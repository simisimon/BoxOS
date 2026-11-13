from __future__ import annotations

from datetime import timedelta

from backend import db, schedule_service, security, settings, validation
from backend.tests.support import FastApiTestCase


class ScheduleApiTests(FastApiTestCase):
    def test_recurring_schedule_creation_creates_multiple_classes(self) -> None:
        admin_headers, _ = self.create_gym_as_admin("Recurring Box")

        created = self.client.post(
            "/schedule/classes",
            headers=admin_headers,
            json={
                "title": "Lunch WOD",
                "class_type": "WOD",
                "start_time": security.isoformat(security.now_utc() + timedelta(days=1)),
                "duration_minutes": 60,
                "capacity": 12,
                "recurrence_frequency": "daily",
                "occurrence_count": 3,
            },
        )
        self.assertEqual(created.status_code, 201, created.text)
        payload = created.json()
        self.assertEqual(payload["created_count"], 3)
        self.assertEqual(len(payload["classes"]), 3)
        self.assertEqual(payload["classes"][0]["title"], "Lunch WOD")

    def test_cannot_join_waitlist_while_class_has_open_capacity(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("Open Spot Box")
        self.add_active_membership(settings.DEMO_EMAIL, gym_id)

        created = self.client.post(
            "/schedule/classes",
            headers=admin_headers,
            json={
                "title": "Open Gym",
                "class_type": "Open Gym",
                "start_time": security.isoformat(security.now_utc() + timedelta(days=1)),
                "duration_minutes": 60,
                "capacity": 2,
                "recurrence_frequency": "none",
            },
        )
        class_id = created.json()["class"]["id"]

        response = self.client.post(
            "/schedule/waitlist",
            headers=self.auth_headers(settings.DEMO_EMAIL, settings.DEMO_PASSWORD),
            json={"class_id": class_id},
        )
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.json()["detail"], "This class still has open spots.")

    def test_full_class_rejects_duplicate_bookings_and_supports_waitlist_promotion(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("Full Class Box")
        self.add_active_membership(settings.DEMO_EMAIL, gym_id)
        self.create_verified_user("waiter@boxos.app")
        self.add_active_membership("waiter@boxos.app", gym_id)

        created = self.client.post(
            "/schedule/classes",
            headers=admin_headers,
            json={
                "title": "Cap One",
                "class_type": "WOD",
                "start_time": security.isoformat(security.now_utc() + timedelta(days=1)),
                "duration_minutes": 45,
                "capacity": 1,
                "recurrence_frequency": "none",
            },
        )
        class_id = created.json()["class"]["id"]

        athlete_headers = self.auth_headers(settings.DEMO_EMAIL, settings.DEMO_PASSWORD)
        first_booking = self.client.post("/schedule/bookings", headers=athlete_headers, json={"class_id": class_id})
        self.assertEqual(first_booking.status_code, 201, first_booking.text)

        duplicate_booking = self.client.post("/schedule/bookings", headers=athlete_headers, json={"class_id": class_id})
        self.assertEqual(duplicate_booking.status_code, 409)
        self.assertEqual(duplicate_booking.json()["detail"], "You have already booked this class.")

        waiter_headers = self.auth_headers("waiter@boxos.app", "BoxOS123!")
        full_booking = self.client.post("/schedule/bookings", headers=waiter_headers, json={"class_id": class_id})
        self.assertEqual(full_booking.status_code, 409)
        self.assertEqual(full_booking.json()["detail"], "This class is already full.")

        waitlisted = self.client.post("/schedule/waitlist", headers=waiter_headers, json={"class_id": class_id})
        self.assertEqual(waitlisted.status_code, 201, waitlisted.text)

        cancelled = self.client.request("DELETE", "/schedule/bookings", headers=athlete_headers, json={"class_id": class_id})
        self.assertEqual(cancelled.status_code, 200, cancelled.text)

        listed = self.client.get("/schedule/classes", headers=waiter_headers)
        self.assertEqual(listed.status_code, 200)
        promoted_class = listed.json()["classes"][0]
        self.assertTrue(promoted_class["is_booked"])
        self.assertEqual(promoted_class["waitlist_count"], 0)

    def test_owner_removes_a_members_booking_and_promotes_the_waitlist(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("Remove Box")
        athlete_id = self.add_active_membership(settings.DEMO_EMAIL, gym_id)
        self.create_verified_user("next@boxos.app")
        self.add_active_membership("next@boxos.app", gym_id)
        class_id = self.client.post(
            "/schedule/classes",
            headers=admin_headers,
            json={
                "title": "Cap One",
                "class_type": "WOD",
                "start_time": security.isoformat(security.now_utc() + timedelta(days=1)),
                "duration_minutes": 45,
                "capacity": 1,
                "recurrence_frequency": "none",
            },
        ).json()["class"]["id"]
        athlete_headers = self.auth_headers(settings.DEMO_EMAIL, settings.DEMO_PASSWORD)
        next_headers = self.auth_headers("next@boxos.app", "BoxOS123!")
        self.assertEqual(self.client.post("/schedule/bookings", headers=athlete_headers, json={"class_id": class_id}).status_code, 201)
        self.assertEqual(self.client.post("/schedule/waitlist", headers=next_headers, json={"class_id": class_id}).status_code, 201)

        # Members cannot remove someone else.
        refused = self.client.request(
            "DELETE", "/schedule/bookings", headers=next_headers, json={"class_id": class_id, "user_id": athlete_id}
        )
        self.assertEqual(refused.status_code, 403)

        removed = self.client.request(
            "DELETE", "/schedule/bookings", headers=admin_headers, json={"class_id": class_id, "user_id": athlete_id}
        )
        self.assertEqual(removed.status_code, 200, removed.text)
        promoted = self.client.get("/schedule/classes", headers=next_headers).json()["classes"][0]
        self.assertTrue(promoted["is_booked"])

    def test_owner_adds_a_class_type_and_uses_it(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("Types Box")
        self.add_active_membership(settings.DEMO_EMAIL, gym_id)
        athlete_headers = self.auth_headers(settings.DEMO_EMAIL, settings.DEMO_PASSWORD)

        created = self.client.post(
            "/class-types", headers=admin_headers, json={"name": "Hyrox", "color": "danger", "default_capacity": 16}
        )
        self.assertEqual(created.status_code, 201, created.text)
        self.assertEqual(
            [(t["name"], t["color"], t["default_capacity"]) for t in created.json()["class_types"]],
            [("Hyrox", "danger", 16)],
        )
        # Names are unique per gym, built-ins included; members cannot add.
        self.assertEqual(self.client.post("/class-types", headers=admin_headers, json={"name": "hyrox"}).status_code, 409)
        self.assertEqual(self.client.post("/class-types", headers=admin_headers, json={"name": "wod"}).status_code, 409)
        self.assertEqual(self.client.post("/class-types", headers=athlete_headers, json={"name": "Yoga"}).status_code, 403)

        listed = self.client.get("/class-types", headers=athlete_headers)
        self.assertEqual([t["name"] for t in listed.json()["class_types"]], ["Hyrox"])

        class_created = self.client.post(
            "/schedule/classes",
            headers=admin_headers,
            json={
                "title": "Hyrox Prep",
                "class_type": "Hyrox",
                "start_time": security.isoformat(security.now_utc() + timedelta(days=1)),
                "duration_minutes": 60,
                "capacity": 16,
                "recurrence_frequency": "none",
            },
        )
        self.assertEqual(class_created.status_code, 201, class_created.text)
        unknown = self.client.post(
            "/schedule/classes",
            headers=admin_headers,
            json={
                "title": "Mystery",
                "class_type": "Pilates",
                "start_time": security.isoformat(security.now_utc() + timedelta(days=1)),
                "duration_minutes": 60,
                "capacity": 8,
                "recurrence_frequency": "none",
            },
        )
        self.assertEqual(unknown.status_code, 400)

        plan = self.client.post(
            "/membership/plans",
            headers=admin_headers,
            json={
                "name": "Hyrox only",
                "plan_type": "unlimited",
                "price_cents": 5000,
                "billing_period": "monthly",
                "allowed_class_types": ["Hyrox"],
            },
        )
        self.assertEqual(plan.status_code, 201, plan.text)
        self.assertEqual(plan.json()["plan"]["allowed_class_types"], ["Hyrox"])

        type_id = created.json()["class_types"][0]["id"]
        deleted = self.client.request("DELETE", "/class-types", headers=admin_headers, json={"id": type_id})
        self.assertEqual(deleted.status_code, 200, deleted.text)
        self.assertEqual(deleted.json()["class_types"], [])

    def test_cannot_reduce_capacity_below_existing_bookings(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("Capacity Box")
        self.add_active_membership(settings.DEMO_EMAIL, gym_id)
        self.create_verified_user("second-booking@boxos.app")
        self.add_active_membership("second-booking@boxos.app", gym_id)

        created = self.client.post(
            "/schedule/classes",
            headers=admin_headers,
            json={
                "title": "Busy Class",
                "class_type": "WOD",
                "start_time": security.isoformat(security.now_utc() + timedelta(days=1)),
                "duration_minutes": 60,
                "capacity": 2,
                "recurrence_frequency": "none",
            },
        )
        schedule_class = created.json()["class"]
        class_id = schedule_class["id"]

        athlete_headers = self.auth_headers(settings.DEMO_EMAIL, settings.DEMO_PASSWORD)
        booking = self.client.post("/schedule/bookings", headers=athlete_headers, json={"class_id": class_id})
        self.assertEqual(booking.status_code, 201, booking.text)

        second_headers = self.auth_headers("second-booking@boxos.app", "BoxOS123!")
        second_booking = self.client.post("/schedule/bookings", headers=second_headers, json={"class_id": class_id})
        self.assertEqual(second_booking.status_code, 201, second_booking.text)

        updated = self.client.patch(
            "/schedule/classes",
            headers=admin_headers,
            json={
                "id": class_id,
                "title": schedule_class["title"],
                "class_type": schedule_class["class_type"],
                "start_time": schedule_class["start_time"],
                "duration_minutes": schedule_class["duration_minutes"],
                "capacity": 1,
                "trainer_user_id": None if schedule_class["assigned_trainer"] is None else schedule_class["assigned_trainer"]["id"],
            },
        )
        self.assertEqual(updated.status_code, 400)
        self.assertEqual(updated.json()["detail"], "Capacity cannot be lower than the current booking count.")

    def test_attendance_cannot_be_recorded_before_class_starts(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("Attendance Box")
        athlete_user_id = self.add_active_membership(settings.DEMO_EMAIL, gym_id)

        created = self.client.post(
            "/schedule/classes",
            headers=admin_headers,
            json={
                "title": "Evening Class",
                "class_type": "WOD",
                "start_time": security.isoformat(security.now_utc() + timedelta(hours=2)),
                "duration_minutes": 60,
                "capacity": 10,
                "recurrence_frequency": "none",
            },
        )
        class_id = created.json()["class"]["id"]

        athlete_headers = self.auth_headers(settings.DEMO_EMAIL, settings.DEMO_PASSWORD)
        booking = self.client.post("/schedule/bookings", headers=athlete_headers, json={"class_id": class_id})
        self.assertEqual(booking.status_code, 201, booking.text)

        attendance = self.client.patch(
            "/schedule/bookings/attendance",
            headers=admin_headers,
            json={"class_id": class_id, "user_id": athlete_user_id, "attendance_status": "attended"},
        )
        self.assertEqual(attendance.status_code, 400)
        self.assertEqual(attendance.json()["detail"], "Attendance can only be recorded after the class has started.")

    def test_assigning_non_trainer_to_schedule_class_is_rejected(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("Trainer Validation Box")
        athlete_user_id = self.add_active_membership(settings.DEMO_EMAIL, gym_id, roles=["athlete"], active_role="athlete")

        created = self.client.post(
            "/schedule/classes",
            headers=admin_headers,
            json={
                "title": "Coach Needed",
                "class_type": "WOD",
                "start_time": security.isoformat(security.now_utc() + timedelta(days=1)),
                "duration_minutes": 60,
                "capacity": 10,
                "trainer_user_id": athlete_user_id,
                "recurrence_frequency": "none",
            },
        )
        self.assertEqual(created.status_code, 400)
        self.assertEqual(created.json()["detail"], "Selected trainer is not active in this gym.")


class ClassTemplateApiTests(FastApiTestCase):
    def _template_body(self, **overrides: object) -> dict[str, object]:
        body: dict[str, object] = {
            "title": "CrossFit",
            "class_type": "WOD",
            "weekdays": [1, 2, 3, 4, 5, 6, 7],
            "start_time": "23:30",
            "duration_minutes": 60,
            "capacity": 12,
        }
        body.update(overrides)
        return body

    def _sessions_for(self, headers: dict[str, str], template_id: int) -> list[dict[str, object]]:
        response = self.client.get("/schedule/classes", headers=headers)
        self.assertEqual(response.status_code, 200, response.text)
        return [item for item in response.json()["classes"] if item["class_template_id"] == template_id]

    def test_template_generates_sessions_for_rolling_horizon(self) -> None:
        admin_headers, _ = self.create_gym_as_admin("Template Box")

        created = self.client.post("/schedule/templates", headers=admin_headers, json=self._template_body())
        self.assertEqual(created.status_code, 201, created.text)
        template = created.json()["template"]
        self.assertEqual(template["weekdays"], [1, 2, 3, 4, 5, 6, 7])
        self.assertEqual(template["start_time"], "23:30")

        sessions = self._sessions_for(admin_headers, template["id"])
        # Daily for the horizon; today's slot may already have passed.
        self.assertGreaterEqual(len(sessions), schedule_service.TEMPLATE_HORIZON_DAYS)
        self.assertLessEqual(len(sessions), schedule_service.TEMPLATE_HORIZON_DAYS + 1)
        self.assertTrue(all(item["class_type"] == "WOD" for item in sessions))

        # Listing again must not duplicate anything.
        self.assertEqual(len(self._sessions_for(admin_headers, template["id"])), len(sessions))

        listed = self.client.get("/schedule/templates", headers=admin_headers)
        self.assertEqual(listed.status_code, 200, listed.text)
        self.assertEqual([item["id"] for item in listed.json()["templates"]], [template["id"]])

    def test_deleted_template_session_is_not_regenerated(self) -> None:
        admin_headers, _ = self.create_gym_as_admin("Skip Box")
        template = self.client.post("/schedule/templates", headers=admin_headers, json=self._template_body()).json()["template"]
        sessions = self._sessions_for(admin_headers, template["id"])

        deleted = self.client.request("DELETE", "/schedule/classes", headers=admin_headers, json={"id": sessions[0]["id"]})
        self.assertEqual(deleted.status_code, 200, deleted.text)

        self.assertEqual(len(self._sessions_for(admin_headers, template["id"])), len(sessions) - 1)

    def test_editing_template_keeps_booked_sessions_and_replans_the_rest(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("Replan Box")
        self.add_active_membership(settings.DEMO_EMAIL, gym_id)
        template = self.client.post("/schedule/templates", headers=admin_headers, json=self._template_body()).json()["template"]
        booked_session = self._sessions_for(admin_headers, template["id"])[0]

        athlete_headers = self.auth_headers(settings.DEMO_EMAIL, settings.DEMO_PASSWORD)
        booking = self.client.post("/schedule/bookings", headers=athlete_headers, json={"class_id": booked_session["id"]})
        self.assertEqual(booking.status_code, 201, booking.text)

        updated = self.client.patch(
            "/schedule/templates",
            headers=admin_headers,
            json={**self._template_body(start_time="22:00", class_type="Open Gym", title="Open Gym"), "id": template["id"]},
        )
        self.assertEqual(updated.status_code, 200, updated.text)
        self.assertEqual(updated.json()["kept_booked_sessions"], 1)

        sessions = self._sessions_for(admin_headers, template["id"])
        self.assertTrue(sessions)
        self.assertTrue(all(item["class_type"] == "Open Gym" for item in sessions))
        self.assertNotIn(booked_session["id"], [item["id"] for item in sessions])

        all_classes = self.client.get("/schedule/classes", headers=admin_headers).json()["classes"]
        kept = next(item for item in all_classes if item["id"] == booked_session["id"])
        self.assertIsNone(kept["class_template_id"])
        self.assertEqual(kept["start_time"], booked_session["start_time"])
        self.assertEqual(kept["booked_count"], 1)

    def test_deleting_template_removes_unbooked_future_sessions(self) -> None:
        admin_headers, _ = self.create_gym_as_admin("Delete Template Box")
        template = self.client.post("/schedule/templates", headers=admin_headers, json=self._template_body()).json()["template"]
        self.assertTrue(self._sessions_for(admin_headers, template["id"]))

        deleted = self.client.request("DELETE", "/schedule/templates", headers=admin_headers, json={"id": template["id"]})
        self.assertEqual(deleted.status_code, 200, deleted.text)
        self.assertEqual(deleted.json()["kept_booked_sessions"], 0)
        self.assertEqual(self.count_rows("class_schedules"), 0)

    def test_template_rejects_invalid_input_and_athletes(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("Invalid Template Box")
        self.add_active_membership(settings.DEMO_EMAIL, gym_id)

        no_days = self.client.post("/schedule/templates", headers=admin_headers, json=self._template_body(weekdays=[]))
        self.assertEqual(no_days.status_code, 400)
        bad_time = self.client.post("/schedule/templates", headers=admin_headers, json=self._template_body(start_time="25:00"))
        self.assertEqual(bad_time.status_code, 400)
        bad_type = self.client.post("/schedule/templates", headers=admin_headers, json=self._template_body(class_type="Specialty"))
        self.assertEqual(bad_type.status_code, 400)

        athlete_headers = self.auth_headers(settings.DEMO_EMAIL, settings.DEMO_PASSWORD)
        forbidden = self.client.post("/schedule/templates", headers=athlete_headers, json=self._template_body())
        self.assertEqual(forbidden.status_code, 403)

    def test_trainer_cannot_manage_classes_but_can_take_attendance(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("Trainer Rights Box")
        self.add_active_membership(settings.DEMO_EMAIL, gym_id, roles=["athlete", "trainer"], active_role="trainer")
        trainer_headers = self.auth_headers(settings.DEMO_EMAIL, settings.DEMO_PASSWORD)
        class_body = {
            "title": "Evening Class",
            "class_type": "WOD",
            "start_time": security.isoformat(security.now_utc() + timedelta(hours=2)),
            "duration_minutes": 60,
            "capacity": 10,
            "recurrence_frequency": "none",
        }

        forbidden = self.client.post("/schedule/classes", headers=trainer_headers, json=class_body)
        self.assertEqual(forbidden.status_code, 403, forbidden.text)
        template = self.client.post("/schedule/templates", headers=trainer_headers, json=self._template_body())
        self.assertEqual(template.status_code, 403, template.text)

        created = self.client.post("/schedule/classes", headers=admin_headers, json=class_body)
        self.assertEqual(created.status_code, 201, created.text)
        class_id = created.json()["class"]["id"]
        edited = self.client.patch("/schedule/classes", headers=trainer_headers, json={"id": class_id, **class_body})
        self.assertEqual(edited.status_code, 403, edited.text)
        deleted = self.client.request("DELETE", "/schedule/classes", headers=trainer_headers, json={"id": class_id})
        self.assertEqual(deleted.status_code, 403, deleted.text)

        removed = self.client.request(
            "DELETE",
            "/schedule/bookings",
            headers=trainer_headers,
            json={"class_id": class_id, "user_id": self.lookup_user_id(settings.ADMIN_EMAIL)},
        )
        self.assertEqual(removed.status_code, 403, removed.text)

        # Attendance stays open to trainers: the request passes the role check
        # and fails only because the class has not started.
        attendance = self.client.patch(
            "/schedule/bookings/attendance",
            headers=trainer_headers,
            json={"class_id": class_id, "user_id": self.lookup_user_id(settings.DEMO_EMAIL), "attendance_status": "attended"},
        )
        self.assertNotEqual(attendance.status_code, 403, attendance.text)

    def test_my_bookings_lists_upcoming_waitlist_and_cancelled(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("History Box")
        self.add_active_membership(settings.DEMO_EMAIL, gym_id)
        athlete_headers = self.auth_headers(settings.DEMO_EMAIL, settings.DEMO_PASSWORD)

        def create_class(title: str, hours: int, capacity: int = 10) -> int:
            created = self.client.post(
                "/schedule/classes",
                headers=admin_headers,
                json={
                    "title": title,
                    "class_type": "WOD",
                    "start_time": security.isoformat(security.now_utc() + timedelta(hours=hours)),
                    "duration_minutes": 60,
                    "capacity": capacity,
                    "recurrence_frequency": "none",
                },
            )
            self.assertEqual(created.status_code, 201, created.text)
            return created.json()["class"]["id"]

        kept = create_class("Kept", 5)
        cancelled = create_class("Cancelled", 6)
        rebooked = create_class("Rebooked", 7)
        for class_id in (kept, cancelled, rebooked):
            booked = self.client.post("/schedule/bookings", headers=athlete_headers, json={"class_id": class_id})
            self.assertEqual(booked.status_code, 201, booked.text)
        for class_id in (cancelled, rebooked):
            gone = self.client.request("DELETE", "/schedule/bookings", headers=athlete_headers, json={"class_id": class_id})
            self.assertEqual(gone.status_code, 200, gone.text)
        again = self.client.post("/schedule/bookings", headers=athlete_headers, json={"class_id": rebooked})
        self.assertEqual(again.status_code, 201, again.text)

        response = self.client.get("/membership/me/bookings", headers=athlete_headers)
        self.assertEqual(response.status_code, 200, response.text)
        statuses = {row["title"]: row["status"] for row in response.json()["bookings"]}
        # A cancellation disappears once the member booked the class again.
        self.assertEqual(statuses, {"Kept": "booked", "Cancelled": "cancelled", "Rebooked": "booked"})
        cancelled_row = next(row for row in response.json()["bookings"] if row["title"] == "Cancelled")
        self.assertIsNotNone(cancelled_row["cancelled_at"])

        # The owner sees the same history in the member detail.
        user_id = self.lookup_user_id(settings.DEMO_EMAIL)
        owner_view = self.client.get(f"/membership/members/{user_id}/bookings", headers=admin_headers)
        self.assertEqual(owner_view.status_code, 200, owner_view.text)
        self.assertIn("cancelled", {row["status"] for row in owner_view.json()["bookings"]})
