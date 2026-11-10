from __future__ import annotations

import json
from datetime import datetime, timedelta
from http import HTTPStatus
from zoneinfo import ZoneInfo

from backend import payment_service, settings
from backend.tests.support import FastApiTestCase
from backend.validation import ApiError


class FakeStripe:
    """Stands in for payment_service.StripeClient; records what BoxOS asked for."""

    def __init__(self) -> None:
        self.created: list[dict] = []
        self.links: list[dict] = []
        self.status = {"charges_enabled": False, "details_submitted": False}
        self.fail = False

    def create_account(self, *, email: str, country: str, business_name: str) -> str:
        self.created.append({"email": email, "country": country, "business_name": business_name})
        return f"acct_test_{len(self.created)}"

    def account_status(self, account_id: str) -> dict[str, bool]:
        if self.fail:
            raise ApiError(HTTPStatus.BAD_GATEWAY, "Stripe: down")
        return dict(self.status)

    def onboarding_link(self, account_id: str, *, refresh_url: str, return_url: str) -> str:
        self.links.append({"account": account_id, "refresh_url": refresh_url, "return_url": return_url})
        return f"https://connect.stripe.test/{account_id}"

    customers: list[dict]
    checkouts: list[dict]
    cancellations: list[dict]

    def create_customer(self, account_id: str, *, email: str, name: str, metadata: dict) -> str:
        self.customers = getattr(self, "customers", [])
        self.customers.append({"account": account_id, "email": email})
        return f"cus_{len(self.customers)}"

    def create_subscription_checkout(self, account_id: str, params: dict) -> dict:
        self.checkouts = getattr(self, "checkouts", [])
        self.checkouts.append({"account": account_id, **params})
        return {"id": f"cs_{len(self.checkouts)}", "url": f"https://checkout.stripe.test/cs_{len(self.checkouts)}"}

    def cancel_subscription(self, account_id: str, subscription_id: str, *, at_period_end: bool) -> None:
        self.cancellations = getattr(self, "cancellations", [])
        self.cancellations.append({"subscription": subscription_id, "at_period_end": at_period_end})

    def construct_event(self, payload: bytes, signature: str | None):
        if signature != "valid":
            raise ApiError(HTTPStatus.BAD_REQUEST, "Invalid Stripe webhook.")
        return json.loads(payload)


class StripeConnectTests(FastApiTestCase):
    def setUp(self) -> None:
        super().setUp()
        self.fake = FakeStripe()
        self._client = payment_service.client
        self._key = settings.STRIPE_SECRET_KEY
        payment_service.client = self.fake
        settings.STRIPE_SECRET_KEY = "sk_test_fake"
        self.admin_headers, self.gym_id = self.create_gym_as_admin("Pay Box")

    def tearDown(self) -> None:
        payment_service.client = self._client
        settings.STRIPE_SECRET_KEY = self._key
        super().tearDown()

    def status(self) -> dict:
        response = self.client.get("/payments/stripe", headers=self.admin_headers)
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()

    def test_payments_are_unavailable_without_a_stripe_key(self) -> None:
        settings.STRIPE_SECRET_KEY = ""
        self.assertEqual(self.status()["state"], "unavailable")
        response = self.client.post("/payments/stripe/onboarding", headers=self.admin_headers)
        self.assertEqual(response.status_code, 503)
        self.assertEqual(self.fake.created, [])

    def test_owner_connects_and_finishes_onboarding(self) -> None:
        self.assertEqual(self.status()["state"], "not_connected")

        first = self.client.post("/payments/stripe/onboarding", headers=self.admin_headers)
        self.assertEqual(first.status_code, 200, first.text)
        self.assertEqual(first.json()["url"], "https://connect.stripe.test/acct_test_1")
        self.assertEqual(self.fake.created[0]["email"], settings.ADMIN_EMAIL)
        self.assertEqual(self.fake.created[0]["business_name"], "Pay Box")
        self.assertTrue(self.fake.links[0]["return_url"].endswith("/#/box-settings?stripe=return"))
        self.assertEqual(self.status()["state"], "onboarding")

        # A second link reuses the account instead of creating another one.
        self.client.post("/payments/stripe/onboarding", headers=self.admin_headers)
        self.assertEqual(len(self.fake.created), 1)
        self.assertEqual(self.fake.links[1]["account"], "acct_test_1")

        self.fake.status = {"charges_enabled": True, "details_submitted": True}
        self.assertEqual(self.status()["state"], "ready")
        # Once ready, the stored status is used even if Stripe is unreachable.
        self.fake.fail = True
        self.assertEqual(self.status()["state"], "ready")

    def test_stripe_errors_keep_the_stored_status(self) -> None:
        self.client.post("/payments/stripe/onboarding", headers=self.admin_headers)
        self.fake.fail = True
        self.assertEqual(self.status()["state"], "onboarding")

    def test_only_owners_manage_payments(self) -> None:
        self.add_active_membership(settings.DEMO_EMAIL, self.gym_id)
        athlete_headers = self.auth_headers(settings.DEMO_EMAIL, settings.DEMO_PASSWORD)
        self.assertEqual(self.client.get("/payments/stripe", headers=athlete_headers).status_code, 403)
        self.assertEqual(self.client.post("/payments/stripe/onboarding", headers=athlete_headers).status_code, 403)


class SubscriptionTests(FastApiTestCase):
    def setUp(self) -> None:
        super().setUp()
        self.fake = FakeStripe()
        self._client = payment_service.client
        self._key = settings.STRIPE_SECRET_KEY
        payment_service.client = self.fake
        settings.STRIPE_SECRET_KEY = "sk_test_fake"
        self.admin_headers, self.gym_id = self.create_gym_as_admin("Sub Box")
        self.athlete_id = self.add_active_membership(settings.DEMO_EMAIL, self.gym_id)
        self.athlete_headers = self.auth_headers(settings.DEMO_EMAIL, settings.DEMO_PASSWORD)
        self.client.post("/payments/stripe/onboarding", headers=self.admin_headers)
        self.fake.status = {"charges_enabled": True, "details_submitted": True}
        self.client.get("/payments/stripe", headers=self.admin_headers)
        plan = self.client.post(
            "/membership/plans",
            headers=self.admin_headers,
            json={"name": "Unlimited", "plan_type": "unlimited", "price_cents": 8900, "billing_period": "monthly"},
        ).json()["plan"]
        self.plan_id = plan["id"]

    def tearDown(self) -> None:
        payment_service.client = self._client
        settings.STRIPE_SECRET_KEY = self._key
        super().tearDown()

    def assign(self, **extra) -> dict:
        response = self.client.post(
            "/membership/assignments",
            headers=self.admin_headers,
            json={"user_id": self.athlete_id, "plan_id": self.plan_id, **extra},
        )
        self.assertEqual(response.status_code, 201, response.text)
        return response.json()["plan"]

    def checkout(self, member_plan_id: int):
        return self.client.post(
            "/membership/me/checkout", headers=self.athlete_headers, json={"member_plan_id": member_plan_id}
        )

    def send(self, event_id: str, event_type: str, data: dict, signature: str = "valid"):
        body = json.dumps({"id": event_id, "type": event_type, "account": "acct_test_1", "data": {"object": data}})
        return self.client.post(
            "/stripe/webhook", content=body, headers={"Stripe-Signature": signature, "Content-Type": "application/json"}
        )

    def owner_plan(self) -> dict:
        plans = self.client.get(f"/membership/members/{self.athlete_id}", headers=self.admin_headers).json()["plans"]
        return plans[0]

    def test_member_pays_plan_by_subscription_and_webhooks_track_payment(self) -> None:
        member_plan = self.assign()
        mine = self.client.get("/membership/me", headers=self.athlete_headers).json()
        self.assertTrue(mine["online_payments"])
        self.assertFalse(mine["plans"][0]["paid_online"])

        response = self.checkout(member_plan["id"])
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()["url"], "https://checkout.stripe.test/cs_1")
        params = self.fake.checkouts[0]
        self.assertEqual(params["account"], "acct_test_1")
        self.assertEqual(params["mode"], "subscription")
        self.assertEqual(params["line_items"][0]["price_data"]["unit_amount"], 8900)
        self.assertEqual(params["line_items"][0]["price_data"]["recurring"], {"interval": "month"})
        self.assertIn("sepa_debit", params["payment_method_types"])
        self.assertEqual(self.fake.customers[0]["email"], settings.DEMO_EMAIL)

        self.send("evt_1", "checkout.session.completed", {
            "mode": "subscription", "subscription": "sub_1",
            "metadata": {"boxos_member_plan_id": str(member_plan["id"])},
        })
        self.assertTrue(self.owner_plan()["paid_online"])
        # Paying twice is refused.
        self.assertEqual(self.checkout(member_plan["id"]).status_code, 409)

        invoice = {"parent": {"subscription_details": {"subscription": "sub_1"}}, "amount_paid": 8900,
                   "amount_due": 8900, "currency": "eur", "number": "ABC-0001"}
        self.send("evt_2", "invoice.paid", invoice)
        self.assertEqual(self.owner_plan()["payment_status"], "paid")
        self.assertEqual(
            self.count_rows("notifications", "user_id = ? and title = 'Payment received'", (self.athlete_id,)), 1
        )
        # A retried event changes nothing.
        self.assertEqual(self.send("evt_2", "invoice.paid", invoice).json()["result"], "duplicate")

        self.send("evt_3", "invoice.finalized", {**invoice, "amount_paid": 0})
        self.assertEqual(self.owner_plan()["payment_status"], "due")
        self.send("evt_4", "invoice.payment_failed", {**invoice, "amount_paid": 0})
        self.assertEqual(self.owner_plan()["payment_status"], "overdue")
        self.assertEqual(
            self.count_rows("notifications", "user_id = ? and title = 'Payment failed'", (self.athlete_id,)), 1
        )
        mine = self.client.get("/membership/me", headers=self.athlete_headers).json()
        self.assertNotIn("payment_status", mine["plans"][0])

        self.send("evt_5", "customer.subscription.deleted", {"id": "sub_1"})
        self.assertEqual(self.owner_plan()["state"], "ended")

    def test_webhook_rejects_bad_signatures(self) -> None:
        self.assertEqual(self.send("evt_x", "invoice.paid", {}, signature="forged").status_code, 400)

    def test_billing_day_follows_the_plan_start(self) -> None:
        today = datetime.now(ZoneInfo("Europe/Berlin")).date()
        later = today + timedelta(days=10)
        member_plan = self.assign(starts_on=later.isoformat())
        self.assertEqual(self.checkout(member_plan["id"]).status_code, 200)
        data = self.fake.checkouts[0]["subscription_data"]
        self.assertEqual(data["proration_behavior"], "none")
        anchor = datetime.fromtimestamp(data["billing_cycle_anchor"], ZoneInfo("UTC")).date()
        self.assertEqual(anchor, later)

    def test_checkout_needs_a_ready_box_and_a_monthly_plan(self) -> None:
        pack = self.client.post(
            "/membership/plans",
            headers=self.admin_headers,
            json={"name": "Pack", "plan_type": "token_pack", "price_cents": 9000, "billing_period": "one_time",
                  "token_count": 10},
        ).json()["plan"]
        response = self.client.post(
            "/membership/assignments", headers=self.admin_headers, json={"user_id": self.athlete_id, "plan_id": pack["id"]}
        )
        self.assertEqual(self.checkout(response.json()["plan"]["id"]).status_code, 400)

        member_plan = self.assign()
        # Only the member can pay their own plan.
        self.assertEqual(
            self.client.post("/membership/me/checkout", headers=self.admin_headers,
                             json={"member_plan_id": member_plan["id"]}).status_code,
            404,
        )
        settings.STRIPE_SECRET_KEY = ""
        self.assertEqual(self.checkout(member_plan["id"]).status_code, 503)

    def test_owner_ends_a_subscribed_plan_now_or_at_month_end(self) -> None:
        member_plan = self.assign()
        self.send("evt_1", "checkout.session.completed", {
            "mode": "subscription", "subscription": "sub_9",
            "metadata": {"boxos_member_plan_id": str(member_plan["id"])},
        })
        response = self.client.post(
            "/membership/assignments/end",
            headers=self.admin_headers,
            json={"member_plan_id": member_plan["id"], "at_period_end": True},
        )
        self.assertEqual(response.status_code, 200, response.text)
        ended = response.json()["plan"]
        self.assertEqual(ended["state"], "current")
        self.assertIsNotNone(ended["ends_on"])
        self.assertEqual(self.fake.cancellations, [{"subscription": "sub_9", "at_period_end": True}])
        self.assertEqual(
            self.count_rows("notifications", "user_id = ? and title = 'Membership plan ending'", (self.athlete_id,)), 1
        )
        # Stripe's deletion at period end does not shorten the plan further.
        self.send("evt_2", "customer.subscription.deleted", {"id": "sub_9"})
        self.assertEqual(self.owner_plan()["ends_on"], ended["ends_on"])

        response = self.client.post(
            "/membership/assignments/end", headers=self.admin_headers, json={"member_plan_id": member_plan["id"]}
        )
        self.assertEqual(response.json()["plan"]["state"], "ended")
        self.assertEqual(self.fake.cancellations[-1], {"subscription": "sub_9", "at_period_end": False})


class YearlyPlanTests(FastApiTestCase):
    def test_new_plans_cannot_be_billed_yearly(self) -> None:
        admin_headers, _ = self.create_gym_as_admin("Plan Box")
        response = self.client.post(
            "/membership/plans",
            headers=admin_headers,
            json={"name": "Year", "plan_type": "unlimited", "price_cents": 99000, "billing_period": "yearly"},
        )
        self.assertEqual(response.status_code, 400)
        self.assertIn("monthly or one_time", response.json()["detail"])
