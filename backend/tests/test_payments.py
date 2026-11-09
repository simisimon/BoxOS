from __future__ import annotations

from http import HTTPStatus

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
