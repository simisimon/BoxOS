"""Payments through Stripe Connect.

Each box links its own Stripe account (an Accounts v2 merchant account with
the full Stripe dashboard, owned by the box owner): members pay the box directly, the box pays Stripe's fees, and BoxOS
only keeps the account ID on ``gyms.stripe_account_id``.

Every Stripe call goes through :data:`client`, so tests swap in a fake and
never reach Stripe. Payments are switched off while
``settings.STRIPE_SECRET_KEY`` is empty.
"""

from __future__ import annotations

from http import HTTPStatus
from typing import Any

from backend import settings
from backend.db import ManagedConnection, Row
from backend.security import isoformat, now_utc
from backend.validation import ApiError


def is_configured() -> bool:
    return bool(settings.STRIPE_SECRET_KEY)


def require_configured() -> None:
    if not is_configured():
        raise ApiError(HTTPStatus.SERVICE_UNAVAILABLE, "Online payments are not set up on this server.")


def _dig(value: Any, *keys: str) -> Any:
    """Nested lookup in a Stripe object; None as soon as a level is missing."""
    for key in keys:
        if value is None:
            return None
        value = value.get(key) if hasattr(value, "get") else getattr(value, key, None)
    return value


class StripeClient:
    """The few Stripe calls BoxOS makes, on the platform's secret key.

    Connected accounts use Stripe's Accounts v2 API (``/v2/core/accounts``),
    which Stripe requires for new Connect platforms: each box gets a merchant
    account with the full Stripe dashboard, and Stripe (not BoxOS) collects
    the fees and covers losses, like a classic Standard account."""

    def _call(self, action: Any) -> Any:
        import stripe

        try:
            return action(stripe.StripeClient(settings.STRIPE_SECRET_KEY))
        except stripe.StripeError as error:
            message = getattr(error, "user_message", None) or str(error) or "Stripe request failed."
            raise ApiError(HTTPStatus.BAD_GATEWAY, f"Stripe: {message}") from error

    def create_account(self, *, email: str, country: str, business_name: str) -> str:
        account = self._call(
            lambda stripe_client: stripe_client.v2.core.accounts.create(
                {
                    "display_name": business_name,
                    "contact_email": email,
                    "identity": {"country": country},
                    "dashboard": "full",
                    "defaults": {
                        "responsibilities": {"fees_collector": "stripe", "losses_collector": "stripe"},
                    },
                    "configuration": {
                        "merchant": {
                            "capabilities": {
                                "card_payments": {"requested": True},
                                "sepa_debit_payments": {"requested": True},
                            },
                        },
                    },
                }
            )
        )
        return str(account.id)

    def account_status(self, account_id: str) -> dict[str, bool]:
        account = self._call(
            lambda stripe_client: stripe_client.v2.core.accounts.retrieve(
                account_id, {"include": ["configuration.merchant", "requirements"]}
            )
        )
        card_status = _dig(account, "configuration", "merchant", "capabilities", "card_payments", "status")
        deadline = _dig(account, "requirements", "summary", "minimum_deadline", "status")
        return {
            "charges_enabled": card_status == "active",
            # Nothing is due now (later requirements may still come).
            "details_submitted": deadline in (None, "eventually_due"),
        }

    def onboarding_link(self, account_id: str, *, refresh_url: str, return_url: str) -> str:
        link = self._call(
            lambda stripe_client: stripe_client.v2.core.account_links.create(
                {
                    "account": account_id,
                    "use_case": {
                        "type": "account_onboarding",
                        "account_onboarding": {"refresh_url": refresh_url, "return_url": return_url},
                    },
                }
            )
        )
        return str(link.url)


client: StripeClient = StripeClient()


def _gym_row(connection: ManagedConnection, gym_id: int) -> Row:
    row = connection.execute(
        """
        select id, name, stripe_account_id, stripe_charges_enabled, stripe_details_submitted
        from gyms where id = ?
        """,
        (gym_id,),
    ).fetchone()
    if row is None:
        raise ApiError(HTTPStatus.NOT_FOUND, "Gym not found.")
    return row


def _store_status(connection: ManagedConnection, gym_id: int, status: dict[str, bool]) -> None:
    connection.execute(
        """
        update gyms set stripe_charges_enabled = ?, stripe_details_submitted = ?, updated_at = ?
        where id = ?
        """,
        (int(status["charges_enabled"]), int(status["details_submitted"]), isoformat(now_utc()), gym_id),
    )


def stripe_status_payload(connection: ManagedConnection, gym_id: int, *, refresh: bool = True) -> dict[str, Any]:
    """``state``: ``unavailable`` (server has no Stripe key), ``not_connected``,
    ``onboarding`` (account created, owner has not finished Stripe's sign-up)
    or ``ready`` (the box can take payments).

    An account that is not ready yet is re-read from Stripe, so the status is
    current when the owner comes back from onboarding."""
    gym = _gym_row(connection, gym_id)
    if not is_configured():
        return {"state": "unavailable", "charges_enabled": False, "details_submitted": False}
    account_id = gym["stripe_account_id"]
    charges_enabled = bool(gym["stripe_charges_enabled"])
    details_submitted = bool(gym["stripe_details_submitted"])
    if account_id and not charges_enabled and refresh:
        try:
            status = client.account_status(account_id)
        except ApiError:
            status = None
        if status is not None:
            with connection:
                _store_status(connection, gym_id, status)
            charges_enabled = status["charges_enabled"]
            details_submitted = status["details_submitted"]
    if not account_id:
        state = "not_connected"
    elif charges_enabled:
        state = "ready"
    else:
        state = "onboarding"
    return {"state": state, "charges_enabled": charges_enabled, "details_submitted": details_submitted}


def onboarding_link(connection: ManagedConnection, gym_id: int, *, owner_email: str) -> str:
    """Create the box's Stripe account on first use, then return a one-time
    link to Stripe's onboarding. Stripe sends the owner back to Settings."""
    require_configured()
    gym = _gym_row(connection, gym_id)
    account_id = gym["stripe_account_id"]
    if not account_id:
        account_id = client.create_account(
            email=owner_email,
            country=settings.STRIPE_ACCOUNT_COUNTRY,
            business_name=gym["name"],
        )
        with connection:
            connection.execute(
                "update gyms set stripe_account_id = ?, updated_at = ? where id = ?",
                (account_id, isoformat(now_utc()), gym_id),
            )
    settings_url = f"{settings.APP_BASE_URL}/#/box-settings"
    return client.onboarding_link(
        account_id,
        refresh_url=f"{settings_url}?stripe=refresh",
        return_url=f"{settings_url}?stripe=return",
    )
