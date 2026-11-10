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

from datetime import date, datetime, time, timedelta, timezone

from backend import notifications_core, plan_service, schedule_service, settings
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
        except ApiError:
            raise
        except Exception as error:  # e.g. an outdated stripe package
            raise ApiError(HTTPStatus.BAD_GATEWAY, f"Stripe request failed: {error}") from error

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

    # --- calls on a box's connected account (direct charges) ----------------

    def create_customer(self, account_id: str, *, email: str, name: str, metadata: dict[str, str]) -> str:
        customer = self._call(
            lambda stripe_client: stripe_client.v1.customers.create(
                {"email": email, "name": name, "metadata": metadata},
                {"stripe_account": account_id},
            )
        )
        return str(customer.id)

    def create_subscription_checkout(self, account_id: str, params: dict[str, Any]) -> dict[str, str]:
        session = self._call(
            lambda stripe_client: stripe_client.v1.checkout.sessions.create(params, {"stripe_account": account_id})
        )
        return {"id": str(session.id), "url": str(session.url)}

    def cancel_subscription(self, account_id: str, subscription_id: str, *, at_period_end: bool) -> None:
        if at_period_end:
            self._call(
                lambda stripe_client: stripe_client.v1.subscriptions.update(
                    subscription_id, {"cancel_at_period_end": True}, {"stripe_account": account_id}
                )
            )
        else:
            self._call(
                lambda stripe_client: stripe_client.v1.subscriptions.cancel(
                    subscription_id, {}, {"stripe_account": account_id}
                )
            )

    def construct_event(self, payload: bytes, signature: str | None) -> Any:
        """Verify the webhook signature and parse the event."""
        import stripe

        if not settings.STRIPE_WEBHOOK_SECRET:
            raise ApiError(HTTPStatus.SERVICE_UNAVAILABLE, "Stripe webhooks are not set up on this server.")
        try:
            return stripe.Webhook.construct_event(payload, signature, settings.STRIPE_WEBHOOK_SECRET)
        except (ValueError, stripe.SignatureVerificationError) as error:
            raise ApiError(HTTPStatus.BAD_REQUEST, "Invalid Stripe webhook.") from error


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


# --- monthly subscriptions -----------------------------------------------------
#
# A member pays a monthly member plan through Stripe Checkout on the box's
# account. The subscription bills on the plan's start day each month: a plan
# starting later is free until then, a plan that already started charges the
# rest of the current month now (pro rata) and the full price from the next
# start day on. Webhooks (below) keep ``member_plans.payment_status`` in sync.


def gym_accepts_payments(connection: ManagedConnection, gym_id: int) -> bool:
    if not is_configured():
        return False
    gym = _gym_row(connection, gym_id)
    return bool(gym["stripe_account_id"]) and bool(gym["stripe_charges_enabled"])


def can_pay_online(member_plan: Row) -> bool:
    return member_plan["status"] == "active" and member_plan["billing_period"] == "monthly"


def _customer_id(connection: ManagedConnection, gym: Row, user_id: int) -> str:
    row = connection.execute(
        "select customer_id from stripe_customers where gym_id = ? and user_id = ?",
        (gym["id"], user_id),
    ).fetchone()
    if row is not None:
        return str(row["customer_id"])
    user = connection.execute("select email, display_name from users where id = ?", (user_id,)).fetchone()
    customer_id = client.create_customer(
        gym["stripe_account_id"],
        email=user["email"],
        name=user["display_name"] or user["email"],
        metadata={"boxos_user_id": str(user_id), "boxos_gym_id": str(gym["id"])},
    )
    with connection:
        connection.execute(
            "insert into stripe_customers (gym_id, user_id, customer_id, created_at) values (?, ?, ?, ?)",
            (gym["id"], user_id, customer_id, isoformat(now_utc())),
        )
    return customer_id


def _epoch(day: date) -> int:
    """Noon UTC of ``day``: safely on that calendar day in European time zones."""
    return int(datetime.combine(day, time(12, 0), tzinfo=timezone.utc).timestamp())


def billing_schedule(starts_on: date, today: date) -> dict[str, Any]:
    """Checkout ``subscription_data`` that bills on ``starts_on``'s day."""
    if starts_on > today:
        return {"billing_cycle_anchor": _epoch(starts_on), "proration_behavior": "none"}
    period_start, next_start = plan_service.token_period_bounds(starts_on, "month", today)
    if period_start == today:
        return {}
    return {"billing_cycle_anchor": _epoch(next_start), "proration_behavior": "create_prorations"}


def subscription_checkout_url(
    connection: ManagedConnection, *, gym_id: int, user_id: int, member_plan_id: int
) -> str:
    require_configured()
    gym = _gym_row(connection, gym_id)
    if not gym_accepts_payments(connection, gym_id):
        raise ApiError(HTTPStatus.CONFLICT, "Your box does not take online payments yet.")
    member_plan = plan_service.get_member_plan_row(connection, gym_id, member_plan_id)
    if member_plan["user_id"] != user_id:
        raise ApiError(HTTPStatus.NOT_FOUND, "Membership plan not found.")
    gym_settings = plan_service.gym_plan_settings(connection, gym_id)
    today = schedule_service.local_today(gym_settings["timezone"])
    state = plan_service.member_plan_state(member_plan, today)
    if not can_pay_online(member_plan) or state not in ("current", "upcoming"):
        raise ApiError(HTTPStatus.BAD_REQUEST, "Only current or upcoming monthly plans can be paid online.")
    if member_plan["stripe_subscription_id"]:
        raise ApiError(HTTPStatus.CONFLICT, "Payment for this plan is already set up.")
    if member_plan["price_cents"] <= 0:
        raise ApiError(HTTPStatus.BAD_REQUEST, "This plan is free.")
    customer_id = _customer_id(connection, gym, user_id)
    starts_on = date.fromisoformat(member_plan["starts_on"]) if member_plan["starts_on"] else today
    metadata = {"boxos_member_plan_id": str(member_plan["id"]), "boxos_gym_id": str(gym_id)}
    profile_url = f"{settings.APP_BASE_URL}/#/profile"
    session = client.create_subscription_checkout(
        gym["stripe_account_id"],
        {
            "mode": "subscription",
            "customer": customer_id,
            "line_items": [
                {
                    "quantity": 1,
                    "price_data": {
                        "currency": gym_settings["currency"].lower(),
                        "unit_amount": member_plan["price_cents"],
                        "recurring": {"interval": "month"},
                        "product_data": {"name": member_plan["plan_name"]},
                    },
                }
            ],
            "subscription_data": {**billing_schedule(starts_on, today), "metadata": metadata},
            "metadata": metadata,
            "client_reference_id": str(member_plan["id"]),
            "success_url": f"{profile_url}?payment=success",
            "cancel_url": f"{profile_url}?payment=cancelled",
        },
    )
    with connection:
        connection.execute(
            "update member_plans set stripe_checkout_session_id = ?, updated_at = ? where id = ?",
            (session["id"], isoformat(now_utc()), member_plan["id"]),
        )
    return session["url"]


def end_subscribed_plan(
    connection: ManagedConnection, *, member_plan: Row, gym_timezone: str, at_period_end: bool
) -> None:
    """Owner ends a plan. With a Stripe subscription, ``at_period_end`` keeps
    the plan until the end of the paid month and stops the next debit;
    otherwise the plan (and subscription) ends today."""
    gym = _gym_row(connection, member_plan["gym_id"])
    subscription_id = member_plan["stripe_subscription_id"]
    if subscription_id and gym["stripe_account_id"]:
        client.cancel_subscription(gym["stripe_account_id"], subscription_id, at_period_end=at_period_end)
    if not at_period_end:
        plan_service.end_member_plan(connection, member_plan=member_plan, gym_timezone=gym_timezone)
        return
    today = schedule_service.local_today(gym_timezone)
    starts_on = date.fromisoformat(member_plan["starts_on"]) if member_plan["starts_on"] else today
    _, period_end = plan_service.token_period_bounds(starts_on, "month", max(today, starts_on))
    connection.execute(
        "update member_plans set ends_on = ?, updated_at = ? where id = ?",
        ((period_end - timedelta(days=1)).isoformat(), isoformat(now_utc()), member_plan["id"]),
    )


# --- webhooks ------------------------------------------------------------------


def _plan_for_subscription(connection: ManagedConnection, subscription_id: str | None) -> Row | None:
    if not subscription_id:
        return None
    return connection.execute(
        "select * from member_plans where stripe_subscription_id = ? order by id desc limit 1",
        (subscription_id,),
    ).fetchone()


def _invoice_subscription(invoice: Any) -> str | None:
    return _dig(invoice, "parent", "subscription_details", "subscription") or _dig(invoice, "subscription")


def _set_payment_status(connection: ManagedConnection, member_plan: Row, status: str) -> None:
    connection.execute(
        "update member_plans set payment_status = ?, updated_at = ? where id = ?",
        (status, isoformat(now_utc()), member_plan["id"]),
    )


def _money(cents: int, currency: str) -> str:
    symbol = {"eur": "€", "usd": "$", "gbp": "£"}.get(currency.lower(), f"{currency.upper()} ")
    return f"{symbol}{cents / 100:.2f}"


def handle_event(connection: ManagedConnection, event: Any) -> str:
    """Apply one Stripe event. Returns what was done (for logs and tests).
    Events already seen are skipped, so Stripe's retries are harmless."""
    event_id = str(_dig(event, "id"))
    event_type = str(_dig(event, "type"))
    seen = connection.execute("select 1 from stripe_events where id = ?", (event_id,)).fetchone()
    if seen is not None:
        return "duplicate"
    data = _dig(event, "data", "object")
    with connection:
        result = _apply_event(connection, event_type, data)
        connection.execute(
            "insert into stripe_events (id, type, received_at) values (?, ?, ?)",
            (event_id, event_type, isoformat(now_utc())),
        )
    return result


def _apply_event(connection: ManagedConnection, event_type: str, data: Any) -> str:
    if event_type == "checkout.session.completed" and _dig(data, "mode") == "subscription":
        member_plan_id = _dig(data, "metadata", "boxos_member_plan_id") or _dig(data, "client_reference_id")
        subscription_id = _dig(data, "subscription")
        if not member_plan_id or not subscription_id:
            return "ignored"
        connection.execute(
            "update member_plans set stripe_subscription_id = ?, updated_at = ? where id = ?",
            (str(subscription_id), isoformat(now_utc()), int(member_plan_id)),
        )
        return "subscription_linked"

    if event_type in ("invoice.paid", "invoice.payment_failed", "invoice.finalized"):
        member_plan = _plan_for_subscription(connection, _invoice_subscription(data))
        if member_plan is None:
            return "ignored"
        amount = int(_dig(data, "amount_paid") or _dig(data, "amount_due") or 0)
        currency = str(_dig(data, "currency") or "eur")
        number = _dig(data, "number") or ""
        if event_type == "invoice.finalized":
            if amount <= 0 or member_plan["payment_status"] == "overdue":
                return "ignored"
            _set_payment_status(connection, member_plan, "due")
            return "due"
        if event_type == "invoice.paid":
            _set_payment_status(connection, member_plan, "paid")
            if amount > 0:
                notifications_core.create_notification(
                    connection,
                    user_id=member_plan["user_id"],
                    gym_id=member_plan["gym_id"],
                    type="membership_plan",
                    title="Payment received",
                    body=(
                        f"{member_plan['plan_name']}: {_money(amount, currency)} paid"
                        f"{f' (invoice {number})' if number else ''}. Your invoice was sent by email."
                    ),
                    entity_type="member_plan",
                    entity_id=member_plan["id"],
                )
            return "paid"
        _set_payment_status(connection, member_plan, "overdue")
        notifications_core.create_notification(
            connection,
            user_id=member_plan["user_id"],
            gym_id=member_plan["gym_id"],
            type="membership_plan",
            title="Payment failed",
            body=(
                f"The payment for {member_plan['plan_name']} did not go through. "
                "Stripe will try again; you can update your bank details from the email Stripe sent."
            ),
            entity_type="member_plan",
            entity_id=member_plan["id"],
        )
        return "overdue"

    if event_type == "customer.subscription.deleted":
        member_plan = _plan_for_subscription(connection, _dig(data, "id"))
        if member_plan is None or member_plan["status"] != "active" or member_plan["ends_on"]:
            return "ignored"
        gym = plan_service.gym_plan_settings(connection, member_plan["gym_id"])
        plan_service.end_member_plan(connection, member_plan=member_plan, gym_timezone=gym["timezone"])
        return "plan_ended"

    return "ignored"
