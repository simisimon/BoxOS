"""Membership plans: plan definitions, member plans and the booking gate.

Plans are token-based: every booking spends one token, on any class type the
plan includes. A box defines plans (``membership_plans``) of three types:

* ``unlimited``  – unlimited tokens.
* ``tokens``     – ``token_count`` tokens per ``token_period`` (week, month or
                   year). Periods run from the member plan's start date (a plan
                   starting on the 9th refills on the 9th); unused tokens
                   expire at the end of the period. A class spends a token of
                   the period its date falls in.
* ``token_pack`` – ``token_count`` tokens once, optionally valid for
                   ``validity_days`` from the start date.

A member gets a plan through a ``member_plans`` row: the member requests a plan
(status ``requested``) and the owner approves it, or the owner assigns one
directly. Approved rows are ``active`` for ``starts_on``..``ends_on`` (dates in
the box's timezone, ``ends_on`` null = open-ended). Active rows of one member
never overlap: activating a plan ends or shortens the plans it replaces.

Bookings remember the member plan they were made under
(``class_bookings.member_plan_id``), so tokens used are simply the bookings on
that plan (in the period): cancelling or deleting a class gives the token back,
a no-show keeps it spent.

Extra tokens (``token_credits``) sit next to the plan: the owner grants them
(later: the member buys them), each row holds ``tokens`` valid for classes on
``granted_on``..``expires_on`` (exclusive, one month). A booking spends an extra
token only when the plan cannot cover the class (no plan, class type not
included, or no plan tokens left); it then records ``class_bookings.token_credit_id``
instead of ``member_plan_id``, so cancelling gives the extra token back.

Plans are only enforced when the box turns on ``gyms.require_plan_for_booking``.
Owners and trainers are never checked.
"""

from __future__ import annotations

import json
from datetime import date, datetime, time, timedelta
from http import HTTPStatus
from typing import Any

from backend import notifications_core, schedule_service
from backend.db import ManagedConnection, Row
from backend.security import isoformat, now_utc, parse_iso
from backend.validation import ApiError, decode_roles

PLAN_TYPES = ("unlimited", "tokens", "token_pack")
TOKEN_PERIODS = ("week", "month", "year")
# Plans are billed monthly (subscriptions) or once (token packs). ``yearly``
# is no longer offered; older plans and member plans may still carry it.
BILLING_PERIODS = ("monthly", "one_time")
PAYMENT_STATUSES = ("paid", "due", "overdue")
CLASS_TYPES = ("WOD", "Open Gym", "Skill", "PT")
CURRENCIES = ("EUR", "USD", "GBP", "CHF")

MAX_PLAN_NAME_LENGTH = 60
MAX_PLAN_DESCRIPTION_LENGTH = 300
MAX_PRICE_CENTS = 10_000_000


# --- validation ---------------------------------------------------------------


def _int_field(value: Any, label: str, *, minimum: int, maximum: int) -> int:
    if isinstance(value, bool):
        raise ApiError(HTTPStatus.BAD_REQUEST, f"{label} must be a whole number.")
    try:
        number = int(value)
    except (TypeError, ValueError):
        raise ApiError(HTTPStatus.BAD_REQUEST, f"{label} must be a whole number.")
    if isinstance(value, float) and not value.is_integer():
        raise ApiError(HTTPStatus.BAD_REQUEST, f"{label} must be a whole number.")
    if number < minimum or number > maximum:
        raise ApiError(HTTPStatus.BAD_REQUEST, f"{label} must be between {minimum} and {maximum}.")
    return number


def require_price_cents(value: Any) -> int:
    return _int_field(value, "Price", minimum=0, maximum=MAX_PRICE_CENTS)


def require_plan_fields(
    payload: dict[str, Any], class_types: Any = CLASS_TYPES
) -> dict[str, Any]:
    """Validate a full plan definition and return the columns to store."""
    name = str(payload.get("name") or "").strip()
    if not name:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Plan name is required.")
    if len(name) > MAX_PLAN_NAME_LENGTH:
        raise ApiError(HTTPStatus.BAD_REQUEST, f"Plan name must be {MAX_PLAN_NAME_LENGTH} characters or fewer.")
    description = str(payload.get("description") or "").strip()
    if len(description) > MAX_PLAN_DESCRIPTION_LENGTH:
        raise ApiError(
            HTTPStatus.BAD_REQUEST,
            f"Description must be {MAX_PLAN_DESCRIPTION_LENGTH} characters or fewer.",
        )
    plan_type = str(payload.get("plan_type") or "").strip().lower()
    if plan_type not in PLAN_TYPES:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Plan type must be unlimited, tokens, or token_pack.")
    billing_period = str(payload.get("billing_period") or "").strip().lower()
    if billing_period not in BILLING_PERIODS:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Billing period must be monthly or one_time.")
    price_cents = require_price_cents(payload.get("price_cents"))

    token_count = None
    token_period = None
    validity_days = None
    if plan_type == "tokens":
        token_count = _int_field(payload.get("token_count"), "Tokens", minimum=1, maximum=400)
        token_period = str(payload.get("token_period") or "").strip().lower()
        if token_period not in TOKEN_PERIODS:
            raise ApiError(HTTPStatus.BAD_REQUEST, "Token period must be week, month, or year.")
    elif plan_type == "token_pack":
        token_count = _int_field(payload.get("token_count"), "Tokens", minimum=1, maximum=400)
        if payload.get("validity_days") is not None:
            validity_days = _int_field(payload.get("validity_days"), "Validity", minimum=1, maximum=730)

    raw_types = payload.get("allowed_class_types") or []
    if not isinstance(raw_types, list):
        raise ApiError(HTTPStatus.BAD_REQUEST, "Allowed class types must be a list.")
    requested_types = {str(item).strip() for item in raw_types}
    unknown = requested_types - set(class_types)
    if unknown:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Unknown class type.")
    # Canonical order; every type selected is stored as "all" (empty list).
    allowed_class_types = [item for item in class_types if item in requested_types]
    if len(allowed_class_types) == len(class_types):
        allowed_class_types = []

    return {
        "name": name,
        "description": description,
        "plan_type": plan_type,
        "price_cents": price_cents,
        "billing_period": billing_period,
        "token_count": token_count,
        "token_period": token_period,
        "validity_days": validity_days,
        "allowed_class_types_json": json.dumps(allowed_class_types),
    }


def require_payment_status(value: Any) -> str:
    text = str(value or "").strip().lower()
    if text not in PAYMENT_STATUSES:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Payment status must be paid, due, or overdue.")
    return text


def require_currency(value: Any) -> str:
    text = str(value or "").strip().upper()
    if text not in CURRENCIES:
        raise ApiError(HTTPStatus.BAD_REQUEST, f"Currency must be one of {', '.join(CURRENCIES)}.")
    return text


def require_date(value: Any, label: str = "Start date") -> date:
    try:
        return date.fromisoformat(str(value or "").strip())
    except ValueError:
        raise ApiError(HTTPStatus.BAD_REQUEST, f"{label} must be a date (YYYY-MM-DD).")


# --- payloads -----------------------------------------------------------------


def _class_types(row: Row) -> list[str]:
    try:
        decoded = json.loads(row["allowed_class_types_json"] or "[]")
    except (TypeError, ValueError):
        decoded = []
    # Built-ins in their usual order, then the gym's own types.
    return [item for item in CLASS_TYPES if item in decoded] + [
        item for item in decoded if item not in CLASS_TYPES
    ]


def plan_payload(row: Row, *, currency: str) -> dict[str, Any]:
    return {
        "id": row["id"],
        "name": row["name"],
        "description": row["description"],
        "plan_type": row["plan_type"],
        "price_cents": row["price_cents"],
        "currency": currency,
        "billing_period": row["billing_period"],
        "token_count": row["token_count"],
        "token_period": row["token_period"],
        "validity_days": row["validity_days"],
        "allowed_class_types": _class_types(row),
        "is_archived": bool(row["is_archived"]),
        "active_member_count": int(row["active_member_count"]) if "active_member_count" in row.keys() else 0,
    }


def member_plan_state(row: Row, today: date) -> str:
    """requested | upcoming | current | expired | ended | rejected | cancelled"""
    status = row["status"]
    if status != "active":
        return status
    starts_on = date.fromisoformat(row["starts_on"]) if row["starts_on"] else None
    ends_on = date.fromisoformat(row["ends_on"]) if row["ends_on"] else None
    if starts_on is not None and starts_on > today:
        return "upcoming"
    if ends_on is not None and ends_on < today:
        return "expired"
    return "current"


def member_plan_payload(
    connection: ManagedConnection,
    row: Row,
    *,
    currency: str,
    gym_timezone: str,
) -> dict[str, Any]:
    today = schedule_service.local_today(gym_timezone)
    payload: dict[str, Any] = {
        "id": row["id"],
        "user_id": row["user_id"],
        "plan_id": row["plan_id"],
        "status": row["status"],
        "state": member_plan_state(row, today),
        "plan_name": row["plan_name"],
        "plan_type": row["plan_type"],
        "price_cents": row["price_cents"],
        "currency": currency,
        "billing_period": row["billing_period"],
        "token_count": row["token_count"],
        "token_period": row["token_period"],
        "validity_days": row["validity_days"],
        "allowed_class_types": _class_types(row),
        "starts_on": row["starts_on"],
        "ends_on": row["ends_on"],
        "payment_status": row["payment_status"],
        # Paid by a Stripe subscription (monthly debit) rather than by hand.
        "paid_online": bool(row["stripe_subscription_id"]),
        "requested_at": row["requested_at"],
        "reviewed_at": row["reviewed_at"],
        # Token balance: of the current period (or the first one for an
        # upcoming plan); null for unlimited plans and inactive rows.
        "tokens_total": None,
        "tokens_used": None,
        "tokens_remaining": None,
        "period_starts_on": None,
        "period_ends_on": None,
    }
    if row["status"] == "active" and row["plan_type"] in ("tokens", "token_pack"):
        starts_on = date.fromisoformat(row["starts_on"]) if row["starts_on"] else today
        balance = token_balance(connection, row, max(today, starts_on), gym_timezone)
        payload.update(balance)
    return payload


# --- queries ------------------------------------------------------------------


def gym_plan_settings(connection: ManagedConnection, gym_id: int) -> Row:
    row = connection.execute(
        "select id, timezone, currency, require_plan_for_booking, extra_token_price_cents from gyms where id = ?",
        (gym_id,),
    ).fetchone()
    if row is None:
        raise ApiError(HTTPStatus.NOT_FOUND, "Gym not found.")
    return row


def get_plan_row(connection: ManagedConnection, gym_id: int, plan_id: int) -> Row:
    row = connection.execute(
        "select * from membership_plans where id = ? and gym_id = ?",
        (plan_id, gym_id),
    ).fetchone()
    if row is None:
        raise ApiError(HTTPStatus.NOT_FOUND, "Membership plan not found.")
    return row


def list_plan_rows(
    connection: ManagedConnection,
    gym_id: int,
    *,
    gym_timezone: str,
    include_archived: bool,
) -> list[Row]:
    today = schedule_service.local_today(gym_timezone).isoformat()
    return connection.execute(
        f"""
        select membership_plans.*,
               (
                 select count(distinct member_plans.user_id)
                 from member_plans
                 where member_plans.plan_id = membership_plans.id
                   and member_plans.status = 'active'
                   and (member_plans.ends_on is null or member_plans.ends_on >= ?)
               ) as active_member_count
        from membership_plans
        where membership_plans.gym_id = ?
          {'' if include_archived else 'and membership_plans.is_archived = 0'}
        order by membership_plans.is_archived asc, membership_plans.price_cents asc, lower(membership_plans.name) asc
        """,
        (today, gym_id),
    ).fetchall()


def get_member_plan_row(connection: ManagedConnection, gym_id: int, member_plan_id: int) -> Row:
    row = connection.execute(
        "select * from member_plans where id = ? and gym_id = ?",
        (member_plan_id, gym_id),
    ).fetchone()
    if row is None:
        raise ApiError(HTTPStatus.NOT_FOUND, "Member plan not found.")
    return row


def plan_for_day(connection: ManagedConnection, gym_id: int, user_id: int, day: date) -> Row | None:
    """The active member plan covering ``day`` (gym-local date), if any."""
    text = day.isoformat()
    return connection.execute(
        """
        select * from member_plans
        where gym_id = ? and user_id = ? and status = 'active'
          and (starts_on is null or starts_on <= ?)
          and (ends_on is null or ends_on >= ?)
        order by starts_on desc nulls last, id desc
        limit 1
        """,
        (gym_id, user_id, text, text),
    ).fetchone()


def pending_request_row(connection: ManagedConnection, gym_id: int, user_id: int) -> Row | None:
    return connection.execute(
        "select * from member_plans where gym_id = ? and user_id = ? and status = 'requested' order by id desc limit 1",
        (gym_id, user_id),
    ).fetchone()


def member_plan_rows_for_user(connection: ManagedConnection, gym_id: int, user_id: int) -> list[Row]:
    return connection.execute(
        """
        select * from member_plans
        where gym_id = ? and user_id = ?
        order by case status when 'requested' then 0 when 'active' then 1 else 2 end,
                 starts_on desc nulls last, id desc
        limit 20
        """,
        (gym_id, user_id),
    ).fetchall()


def _add_months(day: date, months: int, anchor_day: int) -> date:
    """``day`` moved by ``months``, on ``anchor_day`` (clamped to the month's length)."""
    month_index = day.year * 12 + day.month - 1 + months
    year, month = divmod(month_index, 12)
    month += 1
    next_month = date(year + (month // 12), month % 12 + 1, 1)
    last_day = (next_month - timedelta(days=1)).day
    return date(year, month, min(anchor_day, last_day))


def token_period_bounds(starts_on: date, token_period: str, day: date) -> tuple[date, date]:
    """The token period ``[start, end)`` containing ``day`` for a plan that
    started on ``starts_on``. Periods are anchored on the start date."""
    if token_period == "week":
        index = max((day - starts_on).days, 0) // 7
        start = starts_on + timedelta(days=7 * index)
        return start, start + timedelta(days=7)
    months = 12 if token_period == "year" else 1
    index = 0
    if day > starts_on:
        elapsed = (day.year - starts_on.year) * 12 + (day.month - starts_on.month)
        index = max(elapsed // months - 1, 0)
        while _add_months(starts_on, (index + 1) * months, starts_on.day) <= day:
            index += 1
    start = _add_months(starts_on, index * months, starts_on.day)
    return start, _add_months(starts_on, (index + 1) * months, starts_on.day)


def tokens_used(
    connection: ManagedConnection,
    member_plan_id: int,
    *,
    window: tuple[date, date] | None = None,
    gym_timezone: str = "UTC",
) -> int:
    """Bookings made on the member plan, optionally only for classes whose
    gym-local date falls in ``window`` = ``[start, end)``."""
    if window is None:
        row = connection.execute(
            "select count(*) as count from class_bookings where member_plan_id = ?",
            (member_plan_id,),
        ).fetchone()
        return int(row["count"]) if row is not None else 0
    start_utc = schedule_service.utc_for_local(datetime.combine(window[0], time.min), gym_timezone)
    end_utc = schedule_service.utc_for_local(datetime.combine(window[1], time.min), gym_timezone)
    row = connection.execute(
        """
        select count(*) as count
        from class_bookings
        join class_schedules on class_schedules.id = class_bookings.class_schedule_id
        where class_bookings.member_plan_id = ?
          and cast(class_schedules.start_time as timestamptz) >= cast(? as timestamptz)
          and cast(class_schedules.start_time as timestamptz) < cast(? as timestamptz)
        """,
        (member_plan_id, isoformat(start_utc), isoformat(end_utc)),
    ).fetchone()
    return int(row["count"]) if row is not None else 0


def token_balance(connection: ManagedConnection, member_plan: Row, day: date, gym_timezone: str) -> dict[str, Any]:
    """Tokens of the member plan for the period containing ``day`` (token
    packs: the whole pack)."""
    total = int(member_plan["token_count"] or 0)
    starts_on = date.fromisoformat(member_plan["starts_on"]) if member_plan["starts_on"] else day
    if member_plan["plan_type"] == "tokens":
        period_start, period_end = token_period_bounds(starts_on, member_plan["token_period"] or "month", day)
        used = tokens_used(connection, member_plan["id"], window=(period_start, period_end), gym_timezone=gym_timezone)
        period = (period_start.isoformat(), (period_end - timedelta(days=1)).isoformat())
    else:
        used = tokens_used(connection, member_plan["id"])
        period = (member_plan["starts_on"], member_plan["ends_on"])
    return {
        "tokens_total": total,
        "tokens_used": used,
        "tokens_remaining": max(total - used, 0),
        "period_starts_on": period[0],
        "period_ends_on": period[1],
    }


def plan_summaries_for_gym(connection: ManagedConnection, gym_id: int, gym_timezone: str) -> dict[int, dict[str, Any]]:
    """Per member: the plan shown on the Members tab (current, else upcoming),
    whether a plan request is open, and the extra tokens left."""
    today = schedule_service.local_today(gym_timezone).isoformat()
    rows = connection.execute(
        """
        select * from member_plans
        where gym_id = ?
          and (status = 'requested' or (status = 'active' and (ends_on is null or ends_on >= ?)))
        order by starts_on asc nulls first, id asc
        """,
        (gym_id, today),
    ).fetchall()
    summaries: dict[int, dict[str, Any]] = {}
    for row in rows:
        summary = summaries.setdefault(int(row["user_id"]), {"plan": None, "has_plan_request": False})
        if row["status"] == "requested":
            summary["has_plan_request"] = True
            continue
        # Rows are ordered by start date, so the first active one is the current
        # (or, if none has started yet, the next upcoming) plan.
        if summary["plan"] is None:
            summary["plan"] = {
                "id": row["id"],
                "plan_name": row["plan_name"],
                "plan_type": row["plan_type"],
                "payment_status": row["payment_status"],
                "starts_on": row["starts_on"],
                "ends_on": row["ends_on"],
                "state": "upcoming" if row["starts_on"] and row["starts_on"] > today else "current",
            }
    for user_id, remaining in extra_tokens_remaining_for_gym(connection, gym_id, gym_timezone).items():
        summary = summaries.setdefault(user_id, {"plan": None, "has_plan_request": False})
        summary["extra_tokens_remaining"] = remaining
    return summaries


# --- activation ---------------------------------------------------------------


def _end_date_for(row: Row, starts_on: date) -> date | None:
    if row["plan_type"] == "token_pack" and row["validity_days"]:
        return starts_on + timedelta(days=int(row["validity_days"]) - 1)
    return None


def _supersede_active_plans(
    connection: ManagedConnection,
    *,
    gym_id: int,
    user_id: int,
    starts_on: date,
    exclude_id: int | None,
    timestamp: str,
) -> None:
    """End or shorten every active plan that would overlap a plan starting on ``starts_on``."""
    rows = connection.execute(
        """
        select id, starts_on, ends_on from member_plans
        where gym_id = ? and user_id = ? and status = 'active'
          and (ends_on is null or ends_on >= ?)
        """,
        (gym_id, user_id, starts_on.isoformat()),
    ).fetchall()
    for row in rows:
        if exclude_id is not None and row["id"] == exclude_id:
            continue
        if row["starts_on"] is None or row["starts_on"] >= starts_on.isoformat():
            connection.execute(
                "update member_plans set status = 'ended', updated_at = ? where id = ?",
                (timestamp, row["id"]),
            )
        else:
            connection.execute(
                "update member_plans set ends_on = ?, updated_at = ? where id = ?",
                ((starts_on - timedelta(days=1)).isoformat(), timestamp, row["id"]),
            )


def activate_member_plan(
    connection: ManagedConnection,
    *,
    member_plan: Row,
    starts_on: date,
    price_cents: int | None,
    reviewer_user_id: int,
) -> None:
    timestamp = isoformat(now_utc())
    _supersede_active_plans(
        connection,
        gym_id=member_plan["gym_id"],
        user_id=member_plan["user_id"],
        starts_on=starts_on,
        exclude_id=member_plan["id"],
        timestamp=timestamp,
    )
    ends_on = _end_date_for(member_plan, starts_on)
    connection.execute(
        """
        update member_plans
        set status = 'active', starts_on = ?, ends_on = ?, price_cents = ?,
            payment_status = 'due', reviewed_at = ?, reviewed_by_user_id = ?, updated_at = ?
        where id = ?
        """,
        (
            starts_on.isoformat(),
            ends_on.isoformat() if ends_on else None,
            member_plan["price_cents"] if price_cents is None else price_cents,
            timestamp,
            reviewer_user_id,
            timestamp,
            member_plan["id"],
        ),
    )


def insert_member_plan(
    connection: ManagedConnection,
    *,
    plan: Row,
    user_id: int,
    status: str,
) -> int:
    timestamp = isoformat(now_utc())
    cursor = connection.execute(
        """
        insert into member_plans (
          gym_id, user_id, plan_id, status, plan_name, plan_type, price_cents, billing_period,
          token_count, token_period, validity_days, allowed_class_types_json,
          requested_at, created_at, updated_at
        ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        returning id
        """,
        (
            plan["gym_id"],
            user_id,
            plan["id"],
            status,
            plan["name"],
            plan["plan_type"],
            plan["price_cents"],
            plan["billing_period"],
            plan["token_count"],
            plan["token_period"],
            plan["validity_days"],
            plan["allowed_class_types_json"],
            timestamp if status == "requested" else None,
            timestamp,
            timestamp,
        ),
    )
    return int(cursor.fetchone()["id"])


def end_member_plan(connection: ManagedConnection, *, member_plan: Row, gym_timezone: str) -> None:
    """End a plan as of yesterday so it no longer covers today."""
    today = schedule_service.local_today(gym_timezone)
    timestamp = isoformat(now_utc())
    starts_on = date.fromisoformat(member_plan["starts_on"]) if member_plan["starts_on"] else today
    ends_on = max(starts_on, today - timedelta(days=1))
    connection.execute(
        "update member_plans set status = 'ended', ends_on = ?, updated_at = ? where id = ?",
        (ends_on.isoformat(), timestamp, member_plan["id"]),
    )


def cancel_open_requests(connection: ManagedConnection, *, gym_id: int, user_id: int, status: str = "cancelled") -> None:
    connection.execute(
        "update member_plans set status = ?, updated_at = ? where gym_id = ? and user_id = ? and status = 'requested'",
        (status, isoformat(now_utc()), gym_id, user_id),
    )


# --- booking gate -------------------------------------------------------------


def _is_staff(connection: ManagedConnection, gym_id: int, user_id: int) -> bool:
    row = connection.execute(
        "select roles_json from gym_memberships where gym_id = ? and user_id = ?",
        (gym_id, user_id),
    ).fetchone()
    if row is None:
        return False
    roles = set(decode_roles(row["roles_json"]))
    return bool(roles & {"admin", "trainer"})


class BookingCheck:
    """Outcome of :func:`booking_plan_check`: what the booking counts against
    (a member plan, an extra token, or nothing) or why it is refused."""

    __slots__ = ("member_plan_id", "token_credit_id", "refusal")

    def __init__(
        self,
        member_plan_id: int | None = None,
        token_credit_id: int | None = None,
        refusal: str | None = None,
    ) -> None:
        self.member_plan_id = member_plan_id
        self.token_credit_id = token_credit_id
        self.refusal = refusal


def _plan_refusal(connection: ManagedConnection, plan: Row | None, class_type: str, day: date, gym_timezone: str) -> str | None:
    if plan is None:
        return "You need an active membership plan for this date. Request one under Profile → Membership."
    allowed = _class_types(plan)
    if allowed and class_type not in allowed:
        return f"Your plan {plan['plan_name']} does not include {class_type} classes."
    if plan["plan_type"] in ("tokens", "token_pack"):
        balance = token_balance(connection, plan, day, gym_timezone)
        if balance["tokens_remaining"] <= 0:
            if plan["plan_type"] == "token_pack":
                return "Your token pack has no tokens left."
            return (
                f"You have used all {balance['tokens_total']} tokens for "
                f"{balance['period_starts_on']} – {balance['period_ends_on']}."
            )
    return None


def booking_plan_check(
    connection: ManagedConnection,
    *,
    gym_id: int,
    user_id: int,
    schedule_row: Row,
) -> BookingCheck:
    """Decide whether ``user_id`` may book ``schedule_row``: on the plan when it
    covers the class, else on an extra token, else refused with the plan's
    reason."""
    gym = gym_plan_settings(connection, gym_id)
    if _is_staff(connection, gym_id, user_id):
        return BookingCheck()
    start = parse_iso(schedule_row["start_time"])
    local_day = schedule_service.local_for_utc(start, gym["timezone"]).date()
    plan = plan_for_day(connection, gym_id, user_id, local_day)
    if not gym["require_plan_for_booking"]:
        return BookingCheck(member_plan_id=plan["id"] if plan is not None else None)
    refusal = _plan_refusal(connection, plan, schedule_row["class_type"], local_day, gym["timezone"])
    if refusal is None:
        return BookingCheck(member_plan_id=plan["id"])
    credit_id = usable_token_credit_id(connection, gym_id, user_id, local_day)
    if credit_id is not None:
        return BookingCheck(token_credit_id=credit_id)
    return BookingCheck(refusal=refusal)


def require_booking_allowed(
    connection: ManagedConnection,
    *,
    gym_id: int,
    user_id: int,
    schedule_row: Row,
) -> BookingCheck:
    check = booking_plan_check(connection, gym_id=gym_id, user_id=user_id, schedule_row=schedule_row)
    if check.refusal is not None:
        raise ApiError(HTTPStatus.FORBIDDEN, check.refusal)
    return check


def promote_next_eligible_waitlisted_user(
    connection: ManagedConnection,
    *,
    class_schedule_id: int,
) -> int | None:
    """Move the first waitlisted athlete whose plan still covers the class into
    the freed spot. Athletes whose plan no longer allows the booking are taken
    off the waitlist and told why."""
    schedule_row = connection.execute(
        "select id, gym_id, title, class_type, start_time from class_schedules where id = ?",
        (class_schedule_id,),
    ).fetchone()
    if schedule_row is None:
        return None
    entries = connection.execute(
        """
        select id, user_id from class_waitlist_entries
        where class_schedule_id = ?
        order by created_at asc, id asc
        """,
        (class_schedule_id,),
    ).fetchall()
    for entry in entries:
        check = booking_plan_check(
            connection,
            gym_id=schedule_row["gym_id"],
            user_id=entry["user_id"],
            schedule_row=schedule_row,
        )
        refusal = check.refusal
        connection.execute("delete from class_waitlist_entries where id = ?", (entry["id"],))
        if refusal is not None:
            notifications_core.create_notification(
                connection,
                user_id=entry["user_id"],
                gym_id=schedule_row["gym_id"],
                type="waitlist_skipped",
                title="Removed from waitlist",
                body=f"A spot opened in {schedule_row['title']}, but {refusal[0].lower()}{refusal[1:]}",
                entity_type="schedule_class",
                entity_id=class_schedule_id,
            )
            continue
        connection.execute(
            """
            insert into class_bookings
              (class_schedule_id, user_id, attendance_status, member_plan_id, token_credit_id, created_at)
            values (?, ?, 'booked', ?, ?, ?)
            """,
            (class_schedule_id, entry["user_id"], check.member_plan_id, check.token_credit_id, isoformat(now_utc())),
        )
        return int(entry["user_id"])
    return None


# --- extra tokens -------------------------------------------------------------

EXTRA_TOKEN_VALIDITY_MONTHS = 1
MAX_EXTRA_TOKENS_PER_GRANT = 50


def require_extra_token_price(value: Any) -> int | None:
    """``None`` turns selling extra tokens off."""
    if value is None:
        return None
    return _int_field(value, "Extra token price", minimum=0, maximum=MAX_PRICE_CENTS)


def extra_token_expiry(granted_on: date) -> date:
    return _add_months(granted_on, EXTRA_TOKEN_VALIDITY_MONTHS, granted_on.day)


def _token_credit_rows(connection: ManagedConnection, gym_id: int, user_id: int, *, valid_after: date) -> list[Row]:
    """Credits that are still valid after ``valid_after`` (``expires_on`` is
    exclusive), with the bookings spent on each, oldest expiry first."""
    return connection.execute(
        """
        select token_credits.*,
               (select count(*) from class_bookings where class_bookings.token_credit_id = token_credits.id) as used
        from token_credits
        where token_credits.gym_id = ? and token_credits.user_id = ? and token_credits.expires_on > ?
        order by token_credits.expires_on asc, token_credits.id asc
        """,
        (gym_id, user_id, valid_after.isoformat()),
    ).fetchall()


def usable_token_credit_id(connection: ManagedConnection, gym_id: int, user_id: int, day: date) -> int | None:
    """The extra-token credit a class on ``day`` spends: the one that expires
    first among those valid on that day with tokens left."""
    for row in _token_credit_rows(connection, gym_id, user_id, valid_after=day):
        if row["granted_on"] <= day.isoformat() and int(row["used"]) < int(row["tokens"]):
            return int(row["id"])
    return None


def extra_tokens_payload(
    connection: ManagedConnection, gym_id: int, user_id: int, *, currency: str, gym_timezone: str
) -> dict[str, Any]:
    today = schedule_service.local_today(gym_timezone)
    credits = []
    for row in _token_credit_rows(connection, gym_id, user_id, valid_after=today):
        remaining = max(int(row["tokens"]) - int(row["used"]), 0)
        credits.append(
            {
                "id": row["id"],
                "tokens": row["tokens"],
                "tokens_used": int(row["used"]),
                "tokens_remaining": remaining,
                "price_cents": row["price_cents"],
                "currency": currency,
                "source": row["source"],
                "granted_on": row["granted_on"],
                # Last day the tokens can be used (expires_on is exclusive).
                "valid_until": (date.fromisoformat(row["expires_on"]) - timedelta(days=1)).isoformat(),
            }
        )
    return {
        "tokens_remaining": sum(credit["tokens_remaining"] for credit in credits),
        "credits": credits,
    }


def extra_tokens_remaining_for_gym(connection: ManagedConnection, gym_id: int, gym_timezone: str) -> dict[int, int]:
    """Per member: unexpired extra tokens left, for the Members tab."""
    today = schedule_service.local_today(gym_timezone).isoformat()
    rows = connection.execute(
        """
        select token_credits.user_id,
               sum(greatest(token_credits.tokens - coalesce(spent.used, 0), 0)) as remaining
        from token_credits
        left join (
          select token_credit_id, count(*) as used from class_bookings
          where token_credit_id is not null group by token_credit_id
        ) spent on spent.token_credit_id = token_credits.id
        where token_credits.gym_id = ? and token_credits.expires_on > ?
        group by token_credits.user_id
        """,
        (gym_id, today),
    ).fetchall()
    return {int(row["user_id"]): int(row["remaining"] or 0) for row in rows}


def grant_token_credit(
    connection: ManagedConnection,
    *,
    gym_id: int,
    user_id: int,
    tokens: Any,
    price_cents: int,
    granted_on: date,
    created_by_user_id: int | None,
    source: str = "manual",
) -> int:
    count = _int_field(tokens, "Tokens", minimum=1, maximum=MAX_EXTRA_TOKENS_PER_GRANT)
    row = connection.execute(
        """
        insert into token_credits
          (gym_id, user_id, tokens, price_cents, source, granted_on, expires_on, created_by_user_id, created_at)
        values (?, ?, ?, ?, ?, ?, ?, ?, ?)
        returning id
        """,
        (
            gym_id,
            user_id,
            count,
            price_cents,
            source,
            granted_on.isoformat(),
            extra_token_expiry(granted_on).isoformat(),
            created_by_user_id,
            isoformat(now_utc()),
        ),
    ).fetchone()
    return int(row["id"])


def get_token_credit_row(connection: ManagedConnection, gym_id: int, credit_id: int) -> Row:
    row = connection.execute(
        "select * from token_credits where id = ? and gym_id = ?",
        (credit_id, gym_id),
    ).fetchone()
    if row is None:
        raise ApiError(HTTPStatus.NOT_FOUND, "Extra tokens not found.")
    return row
