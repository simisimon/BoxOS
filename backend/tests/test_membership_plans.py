from __future__ import annotations

from datetime import date, datetime, time, timedelta
from zoneinfo import ZoneInfo

from backend import settings
from backend.tests.support import FastApiTestCase

BERLIN = ZoneInfo("Europe/Berlin")

UNLIMITED = {"name": "Unlimited", "plan_type": "unlimited", "price_cents": 12900, "billing_period": "monthly"}
TWELVE_A_MONTH = {
    "name": "12 tokens / month",
    "plan_type": "tokens",
    "price_cents": 8900,
    "billing_period": "monthly",
    "token_count": 12,
    "token_period": "month",
}
TEN_PACK = {
    "name": "10-token pack",
    "plan_type": "token_pack",
    "price_cents": 18000,
    "billing_period": "one_time",
    "token_count": 10,
    "validity_days": 90,
}


class MembershipPlanTests(FastApiTestCase):
    def setUp(self) -> None:
        super().setUp()
        self.admin_headers, self.gym_id = self.create_gym_as_admin("Plan Box")
        self.athlete_id = self.add_active_membership(settings.DEMO_EMAIL, self.gym_id)
        self.athlete_headers = self.auth_headers(settings.DEMO_EMAIL, settings.DEMO_PASSWORD)

    # --- helpers --------------------------------------------------------------

    def create_plan(self, payload: dict) -> dict:
        response = self.client.post("/membership/plans", headers=self.admin_headers, json=payload)
        self.assertEqual(response.status_code, 201, response.text)
        return response.json()["plan"]

    def assign(self, plan_id: int, user_id: int | None = None, **extra) -> dict:
        response = self.client.post(
            "/membership/assignments",
            headers=self.admin_headers,
            json={"user_id": user_id or self.athlete_id, "plan_id": plan_id, **extra},
        )
        self.assertEqual(response.status_code, 201, response.text)
        return response.json()["plan"]

    def enforce(self, enabled: bool = True) -> None:
        response = self.client.patch(
            "/membership/settings", headers=self.admin_headers, json={"require_plan_for_booking": enabled}
        )
        self.assertEqual(response.status_code, 200, response.text)

    def next_week_day(self, weekday: int) -> date:
        """A day (0 = Monday) in a week that lies fully in the future."""
        today = datetime.now(BERLIN).date()
        monday = today + timedelta(days=7 - today.weekday())
        return monday + timedelta(days=weekday)

    def create_class(self, day: date, *, class_type: str = "WOD", capacity: int = 10, hour: int = 10) -> int:
        start = datetime.combine(day, time(hour, 0), tzinfo=BERLIN).astimezone(ZoneInfo("UTC"))
        response = self.client.post(
            "/schedule/classes",
            headers=self.admin_headers,
            json={
                "title": f"{class_type} {day.isoformat()} {hour}",
                "class_type": class_type,
                "start_time": start.isoformat(),
                "duration_minutes": 60,
                "capacity": capacity,
                "recurrence_frequency": "none",
            },
        )
        self.assertEqual(response.status_code, 201, response.text)
        return response.json()["class"]["id"]

    def book(self, class_id: int, headers: dict | None = None):
        return self.client.post("/schedule/bookings", headers=headers or self.athlete_headers, json={"class_id": class_id})

    # --- plan definition ------------------------------------------------------

    def test_owner_creates_edits_and_archives_plans(self) -> None:
        unlimited = self.create_plan(UNLIMITED)
        weekly = self.create_plan(TWELVE_A_MONTH)
        card = self.create_plan({**TEN_PACK, "allowed_class_types": ["WOD", "Open Gym"]})

        self.assertEqual(unlimited["currency"], "EUR")
        self.assertEqual(weekly["token_count"], 12)
        self.assertEqual(weekly["token_period"], "month")
        self.assertEqual(card["token_count"], 10)
        self.assertIsNone(card["token_period"])
        self.assertEqual(card["validity_days"], 90)
        self.assertEqual(card["allowed_class_types"], ["WOD", "Open Gym"])

        edited = self.client.patch(
            "/membership/plans",
            headers=self.admin_headers,
            json={**UNLIMITED, "plan_id": unlimited["id"], "price_cents": 13900, "name": "Unlimited+"},
        )
        self.assertEqual(edited.status_code, 200, edited.text)
        self.assertEqual(edited.json()["plan"]["price_cents"], 13900)

        archived = self.client.patch(
            "/membership/plans/archive", headers=self.admin_headers, json={"plan_id": card["id"], "archived": True}
        )
        self.assertEqual(archived.status_code, 200, archived.text)

        athlete_view = self.client.get("/membership/plans", headers=self.athlete_headers).json()
        self.assertEqual([plan["name"] for plan in athlete_view["plans"]], ["12 tokens / month", "Unlimited+"])
        owner_view = self.client.get("/membership/plans?include_archived=true", headers=self.admin_headers).json()
        self.assertEqual(len(owner_view["plans"]), 3)

    def test_plan_validation_and_permissions(self) -> None:
        missing_tokens = self.client.post(
            "/membership/plans", headers=self.admin_headers, json={**TWELVE_A_MONTH, "token_count": None}
        )
        self.assertEqual(missing_tokens.status_code, 400)
        bad_period = self.client.post(
            "/membership/plans", headers=self.admin_headers, json={**TWELVE_A_MONTH, "token_period": "day"}
        )
        self.assertEqual(bad_period.status_code, 400)
        bad_type = self.client.post(
            "/membership/plans", headers=self.admin_headers, json={**UNLIMITED, "plan_type": "family"}
        )
        self.assertEqual(bad_type.status_code, 400)
        bad_class_type = self.client.post(
            "/membership/plans", headers=self.admin_headers, json={**UNLIMITED, "allowed_class_types": ["Yoga"]}
        )
        self.assertEqual(bad_class_type.status_code, 400)
        negative = self.client.post("/membership/plans", headers=self.admin_headers, json={**UNLIMITED, "price_cents": -1})
        self.assertEqual(negative.status_code, 400)

        athlete_create = self.client.post("/membership/plans", headers=self.athlete_headers, json=UNLIMITED)
        self.assertEqual(athlete_create.status_code, 403)

    # --- requests and assignment ---------------------------------------------

    def test_member_requests_plan_and_owner_approves(self) -> None:
        plan = self.create_plan(TWELVE_A_MONTH)

        requested = self.client.post("/membership/requests", headers=self.athlete_headers, json={"plan_id": plan["id"]})
        self.assertEqual(requested.status_code, 201, requested.text)
        self.assertEqual(requested.json()["plan"]["state"], "requested")

        members = self.client.get("/roles/users", headers=self.admin_headers).json()["users"]
        athlete = next(user for user in members if user["id"] == self.athlete_id)
        self.assertTrue(athlete["has_plan_request"])
        self.assertIsNone(athlete["plan"])

        requests = self.client.get("/membership/requests", headers=self.admin_headers).json()["requests"]
        self.assertEqual(len(requests), 1)
        self.assertEqual(requests[0]["member"]["id"], self.athlete_id)

        approved = self.client.patch(
            "/membership/requests",
            headers=self.admin_headers,
            json={"request_id": requests[0]["id"], "decision": "approve", "price_cents": 7900},
        )
        self.assertEqual(approved.status_code, 200, approved.text)
        self.assertEqual(approved.json()["plan"]["state"], "current")
        self.assertEqual(approved.json()["plan"]["price_cents"], 7900)
        self.assertEqual(approved.json()["plan"]["payment_status"], "due")

        mine = self.client.get("/membership/me", headers=self.athlete_headers).json()
        self.assertEqual(mine["plans"][0]["plan_name"], "12 tokens / month")
        self.assertEqual(mine["plans"][0]["tokens_remaining"], 12)
        self.assertEqual(mine["plans"][0]["period_starts_on"], mine["plans"][0]["starts_on"])
        self.assertEqual(
            self.count_rows("notifications", "user_id = ? and type = 'membership_plan'", (self.athlete_id,)), 1
        )

        paid = self.client.patch(
            "/membership/assignments",
            headers=self.admin_headers,
            json={"member_plan_id": requests[0]["id"], "payment_status": "paid"},
        )
        self.assertEqual(paid.status_code, 200, paid.text)
        members = self.client.get("/roles/users", headers=self.admin_headers).json()["users"]
        athlete = next(user for user in members if user["id"] == self.athlete_id)
        self.assertEqual(athlete["plan"]["payment_status"], "paid")
        self.assertFalse(athlete["has_plan_request"])

    def test_new_request_replaces_open_one_and_can_be_withdrawn_or_rejected(self) -> None:
        first = self.create_plan(UNLIMITED)
        second = self.create_plan(TWELVE_A_MONTH)
        self.client.post("/membership/requests", headers=self.athlete_headers, json={"plan_id": first["id"]})
        self.client.post("/membership/requests", headers=self.athlete_headers, json={"plan_id": second["id"]})
        requests = self.client.get("/membership/requests", headers=self.admin_headers).json()["requests"]
        self.assertEqual([item["plan_name"] for item in requests], ["12 tokens / month"])

        withdrawn = self.client.delete("/membership/requests", headers=self.athlete_headers)
        self.assertEqual(withdrawn.status_code, 200, withdrawn.text)
        self.assertEqual(self.client.get("/membership/requests", headers=self.admin_headers).json()["requests"], [])

        self.client.post("/membership/requests", headers=self.athlete_headers, json={"plan_id": first["id"]})
        request_id = self.client.get("/membership/requests", headers=self.admin_headers).json()["requests"][0]["id"]
        rejected = self.client.patch(
            "/membership/requests", headers=self.admin_headers, json={"request_id": request_id, "decision": "reject"}
        )
        self.assertEqual(rejected.status_code, 200, rejected.text)
        self.assertEqual(rejected.json()["plan"]["state"], "rejected")

    def test_assigning_a_plan_replaces_the_current_one(self) -> None:
        unlimited = self.create_plan(UNLIMITED)
        weekly = self.create_plan(TWELVE_A_MONTH)
        first = self.assign(unlimited["id"])
        self.assertEqual(first["state"], "current")

        future_start = (datetime.now(BERLIN).date() + timedelta(days=10)).isoformat()
        switched = self.assign(weekly["id"], starts_on=future_start)
        self.assertEqual(switched["state"], "upcoming")

        plans = self.client.get(f"/membership/members/{self.athlete_id}", headers=self.admin_headers).json()["plans"]
        by_name = {plan["plan_name"]: plan for plan in plans}
        self.assertEqual(by_name["Unlimited"]["state"], "current")
        self.assertEqual(
            by_name["Unlimited"]["ends_on"],
            (date.fromisoformat(future_start) - timedelta(days=1)).isoformat(),
        )

        ended = self.client.post(
            "/membership/assignments/end", headers=self.admin_headers, json={"member_plan_id": first["id"]}
        )
        self.assertEqual(ended.status_code, 200, ended.text)
        self.assertEqual(ended.json()["plan"]["state"], "ended")

    def test_join_request_can_carry_a_plan_choice(self) -> None:
        plan = self.create_plan(TEN_PACK)
        self.create_verified_user("newbie@boxos.app")
        newbie_headers = self.auth_headers("newbie@boxos.app", "BoxOS123!")

        offered = self.client.get(f"/gyms/{self.gym_id}/plans", headers=newbie_headers)
        self.assertEqual(offered.status_code, 200, offered.text)
        self.assertEqual([item["name"] for item in offered.json()["plans"]], ["10-token pack"])

        joined = self.client.post(
            "/gyms/join-requests", headers=newbie_headers, json={"gym_id": self.gym_id, "plan_id": plan["id"]}
        )
        self.assertEqual(joined.status_code, 201, joined.text)
        join_requests = self.client.get("/gyms/join-requests", headers=self.admin_headers).json()["requests"]
        self.assertEqual(join_requests[0]["requested_plan_name"], "10-token pack")
        # Not a member yet: the plan request waits for the join approval.
        self.assertEqual(self.client.get("/membership/requests", headers=self.admin_headers).json()["requests"], [])

        approved = self.client.patch(
            "/gyms/join-requests",
            headers=self.admin_headers,
            json={"request_id": join_requests[0]["id"], "decision": "approve"},
        )
        self.assertEqual(approved.status_code, 200, approved.text)
        plan_requests = self.client.get("/membership/requests", headers=self.admin_headers).json()["requests"]
        self.assertEqual([item["plan_name"] for item in plan_requests], ["10-token pack"])

    # --- booking gate ---------------------------------------------------------

    def test_booking_is_open_without_plan_until_the_box_enforces_plans(self) -> None:
        class_id = self.create_class(self.next_week_day(1))
        other_class_id = self.create_class(self.next_week_day(2))
        self.assertEqual(self.book(class_id).status_code, 201)

        self.enforce()
        refused = self.book(other_class_id)
        self.assertEqual(refused.status_code, 403)
        self.assertIn("active membership plan", refused.json()["detail"])

        # Owners and trainers are never checked.
        self.assertEqual(self.book(other_class_id, headers=self.admin_headers).status_code, 201)

    def test_token_plan_refills_each_period_from_the_start_date(self) -> None:
        self.enforce()
        plan = self.create_plan({**TWELVE_A_MONTH, "token_count": 1, "token_period": "week"})
        monday = self.next_week_day(0)
        self.assign(plan["id"], starts_on=monday.isoformat())
        tuesday = self.create_class(self.next_week_day(1))
        thursday = self.create_class(self.next_week_day(3))
        following_week = self.create_class(self.next_week_day(8))

        self.assertEqual(self.book(tuesday).status_code, 201)
        refused = self.book(thursday)
        self.assertEqual(refused.status_code, 403)
        self.assertIn("all 1 tokens", refused.json()["detail"])
        self.assertEqual(self.book(following_week).status_code, 201)

        cancelled = self.client.request(
            "DELETE", "/schedule/bookings", headers=self.athlete_headers, json={"class_id": tuesday}
        )
        self.assertEqual(cancelled.status_code, 200, cancelled.text)
        self.assertEqual(self.book(thursday).status_code, 201)

    def test_monthly_tokens_are_counted_per_month_from_the_start_date(self) -> None:
        self.enforce()
        plan = self.create_plan({**TWELVE_A_MONTH, "token_count": 2})
        start = self.next_week_day(0)
        self.assign(plan["id"], starts_on=start.isoformat())
        first = [self.create_class(start + timedelta(days=offset)) for offset in (1, 10, 20)]
        next_month = self.create_class(start + timedelta(days=35))

        self.assertEqual(self.book(first[0]).status_code, 201)
        self.assertEqual(self.book(first[1]).status_code, 201)
        self.assertEqual(self.book(first[2]).status_code, 403)
        self.assertEqual(self.book(next_month).status_code, 201)

    def test_token_pack_counts_bookings_and_cancel_gives_the_token_back(self) -> None:
        self.enforce()
        plan = self.create_plan({**TEN_PACK, "token_count": 2})
        self.assign(plan["id"])
        classes = [self.create_class(self.next_week_day(day)) for day in (0, 1, 2)]

        self.assertEqual(self.book(classes[0]).status_code, 201)
        self.assertEqual(self.book(classes[1]).status_code, 201)
        refused = self.book(classes[2])
        self.assertEqual(refused.status_code, 403)
        self.assertIn("no tokens left", refused.json()["detail"])

        mine = self.client.get("/membership/me", headers=self.athlete_headers).json()["plans"][0]
        self.assertEqual(mine["tokens_used"], 2)
        self.assertEqual(mine["tokens_remaining"], 0)

        self.client.request("DELETE", "/schedule/bookings", headers=self.athlete_headers, json={"class_id": classes[0]})
        self.assertEqual(self.book(classes[2]).status_code, 201)

    def test_token_pack_validity_sets_end_date(self) -> None:
        plan = self.create_plan(TEN_PACK)
        assigned = self.assign(plan["id"])
        start = date.fromisoformat(assigned["starts_on"])
        self.assertEqual(assigned["ends_on"], (start + timedelta(days=89)).isoformat())

    def test_plan_class_types_are_enforced(self) -> None:
        self.enforce()
        plan = self.create_plan({**UNLIMITED, "allowed_class_types": ["WOD"]})
        self.assign(plan["id"])
        wod = self.create_class(self.next_week_day(1), class_type="WOD")
        pt = self.create_class(self.next_week_day(1), class_type="PT", hour=12)

        self.assertEqual(self.book(wod).status_code, 201)
        refused = self.book(pt)
        self.assertEqual(refused.status_code, 403)
        self.assertIn("does not include PT", refused.json()["detail"])

    def test_plan_must_cover_the_class_date(self) -> None:
        self.enforce()
        plan = self.create_plan(UNLIMITED)
        later = self.next_week_day(14)
        self.assign(plan["id"], starts_on=later.isoformat())
        before_start = self.create_class(self.next_week_day(1))
        after_start = self.create_class(later)
        self.assertEqual(self.book(before_start).status_code, 403)
        self.assertEqual(self.book(after_start).status_code, 201)

    def test_waitlist_promotion_skips_athletes_whose_plan_no_longer_covers_the_class(self) -> None:
        self.enforce()
        card = self.create_plan({**TEN_PACK, "token_count": 1})
        unlimited = self.create_plan(UNLIMITED)
        waiter_id = self.create_verified_user("waiter@boxos.app")
        self.add_active_membership("waiter@boxos.app", self.gym_id)
        late_id = self.create_verified_user("late@boxos.app")
        self.add_active_membership("late@boxos.app", self.gym_id)
        waiter_headers = self.auth_headers("waiter@boxos.app", "BoxOS123!")
        late_headers = self.auth_headers("late@boxos.app", "BoxOS123!")
        self.assign(unlimited["id"])
        self.assign(card["id"], user_id=waiter_id)
        self.assign(unlimited["id"], user_id=late_id)

        full_class = self.create_class(self.next_week_day(1), capacity=1)
        other_class = self.create_class(self.next_week_day(2))
        self.assertEqual(self.book(full_class).status_code, 201)
        waitlisted = self.client.post("/schedule/waitlist", headers=waiter_headers, json={"class_id": full_class})
        self.assertEqual(waitlisted.status_code, 201, waitlisted.text)
        self.client.post("/schedule/waitlist", headers=late_headers, json={"class_id": full_class})
        # The waiter spends the only class on their card elsewhere.
        self.assertEqual(self.book(other_class, headers=waiter_headers).status_code, 201)

        self.client.request("DELETE", "/schedule/bookings", headers=self.athlete_headers, json={"class_id": full_class})

        self.assertEqual(
            self.count_rows("class_bookings", "class_schedule_id = ? and user_id = ?", (full_class, late_id)), 1
        )
        self.assertEqual(
            self.count_rows("class_bookings", "class_schedule_id = ? and user_id = ?", (full_class, waiter_id)), 0
        )
        self.assertEqual(self.count_rows("class_waitlist_entries", "class_schedule_id = ?", (full_class,)), 0)
        self.assertEqual(
            self.count_rows("notifications", "user_id = ? and type = 'waitlist_skipped'", (waiter_id,)), 1
        )

    # --- extra tokens ---------------------------------------------------------

    def grant(self, tokens: int, user_id: int | None = None, **extra):
        return self.client.post(
            "/membership/extra-tokens",
            headers=self.admin_headers,
            json={"user_id": user_id or self.athlete_id, "tokens": tokens, **extra},
        )

    def test_owner_sets_extra_token_price(self) -> None:
        settings_view = self.client.get("/membership/settings", headers=self.admin_headers).json()
        self.assertIsNone(settings_view["extra_token_price_cents"])

        updated = self.client.patch(
            "/membership/settings", headers=self.admin_headers, json={"extra_token_price_cents": 1500}
        )
        self.assertEqual(updated.status_code, 200, updated.text)
        self.assertEqual(updated.json()["extra_token_price_cents"], 1500)

        # Leaving the field out keeps the price; null turns it off.
        self.enforce()
        kept = self.client.get("/membership/settings", headers=self.admin_headers).json()
        self.assertEqual(kept["extra_token_price_cents"], 1500)
        cleared = self.client.patch(
            "/membership/settings", headers=self.admin_headers, json={"extra_token_price_cents": None}
        )
        self.assertIsNone(cleared.json()["extra_token_price_cents"])

        negative = self.client.patch(
            "/membership/settings", headers=self.admin_headers, json={"extra_token_price_cents": -5}
        )
        self.assertEqual(negative.status_code, 400)

    def test_granted_tokens_default_to_the_box_price_and_expire_after_a_month(self) -> None:
        self.client.patch("/membership/settings", headers=self.admin_headers, json={"extra_token_price_cents": 1500})
        granted = self.grant(3)
        self.assertEqual(granted.status_code, 201, granted.text)
        extra = granted.json()["extra_tokens"]
        self.assertEqual(extra["tokens_remaining"], 3)
        credit = extra["credits"][0]
        self.assertEqual(credit["price_cents"], 4500)
        self.assertEqual(credit["source"], "manual")
        granted_on = date.fromisoformat(credit["granted_on"])
        valid_until = date.fromisoformat(credit["valid_until"])
        self.assertGreater(valid_until, granted_on + timedelta(days=26))
        self.assertLess(valid_until, granted_on + timedelta(days=31))

        free = self.grant(1, price_cents=0).json()["extra_tokens"]
        self.assertEqual(free["tokens_remaining"], 4)

        mine = self.client.get("/membership/me", headers=self.athlete_headers).json()
        self.assertEqual(mine["extra_tokens"]["tokens_remaining"], 4)
        self.assertEqual(mine["extra_token_price_cents"], 1500)
        self.assertEqual(
            self.count_rows("notifications", "user_id = ? and title = 'Extra tokens added'", (self.athlete_id,)), 2
        )

        self.assertEqual(self.grant(0).status_code, 400)
        self.assertEqual(self.grant(51).status_code, 400)
        athlete_grant = self.client.post(
            "/membership/extra-tokens",
            headers=self.athlete_headers,
            json={"user_id": self.athlete_id, "tokens": 5},
        )
        self.assertEqual(athlete_grant.status_code, 403)

    def test_extra_tokens_cover_classes_the_plan_cannot(self) -> None:
        self.enforce()
        plan = self.create_plan({**TEN_PACK, "token_count": 1, "allowed_class_types": ["WOD"]})
        self.assign(plan["id"])
        self.grant(2)
        wod = self.create_class(self.next_week_day(0))
        second_wod = self.create_class(self.next_week_day(1))
        pt = self.create_class(self.next_week_day(1), class_type="PT", hour=12)
        third_wod = self.create_class(self.next_week_day(2))

        # Plan tokens first, then extra tokens (also for class types the plan leaves out).
        self.assertEqual(self.book(wod).status_code, 201)
        mine = self.client.get("/membership/me", headers=self.athlete_headers).json()
        self.assertEqual(mine["plans"][0]["tokens_remaining"], 0)
        self.assertEqual(mine["extra_tokens"]["tokens_remaining"], 2)
        self.assertEqual(self.book(second_wod).status_code, 201)
        self.assertEqual(self.book(pt).status_code, 201)
        refused = self.book(third_wod)
        self.assertEqual(refused.status_code, 403)
        self.assertIn("no tokens left", refused.json()["detail"])

        mine = self.client.get("/membership/me", headers=self.athlete_headers).json()
        self.assertEqual(mine["plans"][0]["tokens_used"], 1)
        self.assertEqual(mine["extra_tokens"]["tokens_remaining"], 0)

        # Cancelling gives the extra token back.
        self.client.request("DELETE", "/schedule/bookings", headers=self.athlete_headers, json={"class_id": pt})
        self.assertEqual(self.book(third_wod).status_code, 201)

    def test_extra_tokens_work_without_a_plan_but_not_after_they_expire(self) -> None:
        self.enforce()
        self.grant(5)
        soon = self.create_class(self.next_week_day(1))
        too_late = self.create_class(self.next_week_day(1) + timedelta(days=35))

        self.assertEqual(self.book(soon).status_code, 201)
        refused = self.book(too_late)
        self.assertEqual(refused.status_code, 403)
        self.assertIn("active membership plan", refused.json()["detail"])

    def test_extra_tokens_are_not_spent_when_plans_are_not_enforced(self) -> None:
        self.grant(1)
        class_id = self.create_class(self.next_week_day(1))
        self.assertEqual(self.book(class_id).status_code, 201)
        mine = self.client.get("/membership/me", headers=self.athlete_headers).json()
        self.assertEqual(mine["extra_tokens"]["tokens_remaining"], 1)

    def test_owner_sees_and_removes_extra_tokens(self) -> None:
        credit_id = self.grant(2).json()["extra_tokens"]["credits"][0]["id"]

        detail = self.client.get(f"/membership/members/{self.athlete_id}", headers=self.admin_headers).json()
        self.assertEqual(detail["extra_tokens"]["tokens_remaining"], 2)
        roster = self.client.get("/roles/users", headers=self.admin_headers).json()["users"]
        athlete = next(user for user in roster if user["id"] == self.athlete_id)
        self.assertEqual(athlete["extra_tokens_remaining"], 2)

        forbidden = self.client.delete(f"/membership/extra-tokens/{credit_id}", headers=self.athlete_headers)
        self.assertEqual(forbidden.status_code, 403)
        removed = self.client.delete(f"/membership/extra-tokens/{credit_id}", headers=self.admin_headers)
        self.assertEqual(removed.status_code, 200, removed.text)
        self.assertEqual(removed.json()["extra_tokens"]["tokens_remaining"], 0)
        missing = self.client.delete(f"/membership/extra-tokens/{credit_id}", headers=self.admin_headers)
        self.assertEqual(missing.status_code, 404)

    def test_members_do_not_see_payment_status(self) -> None:
        plan = self.create_plan(UNLIMITED)
        assigned = self.assign(plan["id"])
        self.client.patch(
            "/membership/assignments",
            headers=self.admin_headers,
            json={"member_plan_id": assigned["id"], "payment_status": "overdue"},
        )
        mine = self.client.get("/membership/me", headers=self.athlete_headers).json()
        self.assertNotIn("payment_status", mine["plans"][0])
        owner_view = self.client.get(f"/membership/members/{self.athlete_id}", headers=self.admin_headers).json()
        self.assertEqual(owner_view["plans"][0]["payment_status"], "overdue")
