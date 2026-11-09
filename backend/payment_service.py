"""Payments through Stripe Connect.

Each box links its own Stripe account (a Standard account owned by the box
owner): members pay the box directly, the box pays Stripe's fees, and BoxOS
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


class StripeClient:
    """The few Stripe calls BoxOS makes, on the platform's secret key."""

    def _stripe(self) -> Any:
        import stripe

        return stripe

    def _call(self, action: Any) -> Any:
        stripe = self._stripe()
        try:
            return action(stripe)
        except stripe.StripeError as error:
            message = getattr(error, "user_message", None) or str(error) or "Stripe request failed."
            raise ApiError(HTTPStatus.BAD_GATEWAY, f"Stripe: {message}") from error

    def create_account(self, *, email: str, country: str, business_name: str) -> str:
        account = self._call(
            lambda stripe: stripe.Account.create(
                api_key=settings.STRIPE_SECRET_KEY,
                type="standard",
                country=country,
                email=email,
                business_profile={"name": business_name},
            )
        )
        return str(account["id"])

    def account_status(self, account_id: str) -> dict[str, bool]:
        account = self._call(
            lambda stripe: stripe.Account.retrieve(account_id, api_key=settings.STRIPE_SECRET_KEY)
        )
        return {
            "charges_enabled": bool(account.get("charges_enabled")),
            "details_submitted": bool(account.get("details_submitted")),
        }

    def onboarding_link(self, account_id: str, *, refresh_url: str, return_url: str) -> str:
        link = self._call(
            lambda stripe: stripe.AccountLink.create(
                api_key=settings.STRIPE_SECRET_KEY,
                account=account_id,
                refresh_url=refresh_url,
                return_url=return_url,
                type="account_onboarding",
            )
        )
        return str(link["url"])


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
