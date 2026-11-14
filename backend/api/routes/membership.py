from __future__ import annotations

from datetime import timedelta
from http import HTTPStatus
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel

from backend.api.common import class_type_names
from backend.api.deps import (
    require_active_gym_member_session,
    require_admin_gym_session,
)
from backend.core import audit, db, notifications, security, validation
from backend.services import (
    payment_service,
    plan_service,
    results_service,
    schedule_service,
)

router = APIRouter()


class MembershipPlanRequest(BaseModel):
    name: str
    description: str = ""
    plan_type: str
    price_cents: int
    billing_period: str
    token_count: int | None = None
    token_period: str | None = None
    validity_days: int | None = None
    allowed_class_types: list[str] = []


class UpdateMembershipPlanRequest(MembershipPlanRequest):
    plan_id: int


class ArchiveMembershipPlanRequest(BaseModel):
    plan_id: int
    archived: bool


class MembershipSettingsRequest(BaseModel):
    currency: str | None = None
    require_plan_for_booking: bool | None = None
    # null turns selling extra tokens off; leave the field out to keep it.
    extra_token_price_cents: int | None = None


class GrantExtraTokensRequest(BaseModel):
    user_id: int
    tokens: int
    # Total paid for the tokens; defaults to tokens × the box's token price.
    price_cents: int | None = None


class PlanIdRequest(BaseModel):
    plan_id: int


class ReviewPlanRequestBody(BaseModel):
    request_id: int
    decision: str
    starts_on: str | None = None
    price_cents: int | None = None


class AssignPlanRequest(BaseModel):
    user_id: int
    plan_id: int
    starts_on: str | None = None
    price_cents: int | None = None


class UpdateMemberPlanRequest(BaseModel):
    member_plan_id: int
    payment_status: str | None = None


class MemberPlanIdRequest(BaseModel):
    member_plan_id: int


class EndMemberPlanRequest(BaseModel):
    member_plan_id: int
    # Keep the plan until the end of the current (paid) month and stop the
    # next debit, instead of ending it today.
    at_period_end: bool = False


# --- Membership plans ---------------------------------------------------------
#
# Owners define plans and review plan requests; athletes see the box's plans,
# request one, and see their own plan. Logic lives in backend/services/plan_service.py.


def _is_admin_member(connection: Any, gym_id: int, user_id: int) -> bool:
    row = connection.execute(
        "select roles_json from gym_memberships where user_id = ? and gym_id = ? and status = 'active'",
        (user_id, gym_id),
    ).fetchone()
    return row is not None and "admin" in validation.decode_roles(row["roles_json"])


def _membership_settings_payload(gym: Any) -> dict[str, Any]:
    return {
        "currency": gym["currency"],
        "require_plan_for_booking": bool(gym["require_plan_for_booking"]),
        "currencies": list(plan_service.CURRENCIES),
        "extra_token_price_cents": gym["extra_token_price_cents"],
    }


def _extra_tokens_payload(connection: Any, gym: Any, user_id: int) -> dict[str, Any]:
    return plan_service.extra_tokens_payload(
        connection, gym["id"], user_id, currency=gym["currency"], gym_timezone=gym["timezone"]
    )


def _member_plan_payloads(connection: Any, gym: Any, rows: list[Any]) -> list[dict[str, Any]]:
    return [
        plan_service.member_plan_payload(connection, row, currency=gym["currency"], gym_timezone=gym["timezone"])
        for row in rows
    ]


@router.get("/membership/settings")
def get_membership_settings(
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, Any]:
    connection = db.get_connection()
    try:
        return _membership_settings_payload(plan_service.gym_plan_settings(connection, session["active_gym_id"]))
    finally:
        connection.close()


@router.patch("/membership/settings")
def update_membership_settings(
    body: MembershipSettingsRequest,
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, Any]:
    gym_id = session["active_gym_id"]
    connection = db.get_connection()
    try:
        gym = plan_service.gym_plan_settings(connection, gym_id)
        currency = plan_service.require_currency(body.currency) if body.currency is not None else gym["currency"]
        require_plan = (
            int(body.require_plan_for_booking)
            if body.require_plan_for_booking is not None
            else int(gym["require_plan_for_booking"])
        )
        extra_token_price = (
            plan_service.require_extra_token_price(body.extra_token_price_cents)
            if "extra_token_price_cents" in body.model_fields_set
            else gym["extra_token_price_cents"]
        )
        with connection:
            connection.execute(
                """
                update gyms set currency = ?, require_plan_for_booking = ?, extra_token_price_cents = ?, updated_at = ?
                where id = ?
                """,
                (currency, require_plan, extra_token_price, security.isoformat(security.now_utc()), gym_id),
            )
            audit.write_audit_log(
                connection,
                gym_id=gym_id,
                actor_user_id=session["user_id"],
                action="membership_settings_updated",
                entity_type="gym",
                entity_id=gym_id,
                details={
                    "currency": currency,
                    "require_plan_for_booking": bool(require_plan),
                    "extra_token_price_cents": extra_token_price,
                },
            )
        return _membership_settings_payload(plan_service.gym_plan_settings(connection, gym_id))
    finally:
        connection.close()


# --- Payments (Stripe Connect) -------------------------------------------------
#
# Each box connects its own Stripe account; see backend/services/payment_service.py.


@router.get("/payments/stripe")
def get_stripe_status(
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, Any]:
    connection = db.get_connection()
    try:
        return payment_service.stripe_status_payload(connection, session["active_gym_id"])
    finally:
        connection.close()


@router.post("/payments/stripe/onboarding")
def create_stripe_onboarding_link(
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, Any]:
    """A one-time link to Stripe's sign-up for the box's account (created on
    first use). The app opens it; Stripe sends the owner back to Settings."""
    gym_id = session["active_gym_id"]
    connection = db.get_connection()
    try:
        owner = connection.execute("select email from users where id = ?", (session["user_id"],)).fetchone()
        url = payment_service.onboarding_link(connection, gym_id, owner_email=owner["email"] if owner else "")
        with connection:
            audit.write_audit_log(
                connection,
                gym_id=gym_id,
                actor_user_id=session["user_id"],
                action="stripe_onboarding_started",
                entity_type="gym",
                entity_id=gym_id,
                details={},
            )
        return {"url": url}
    finally:
        connection.close()


@router.post("/membership/me/checkout")
def create_membership_checkout(
    body: MemberPlanIdRequest,
    session: dict[str, Any] = Depends(require_active_gym_member_session),
) -> dict[str, Any]:
    """Member sets up the monthly payment for their plan: a Stripe Checkout
    link on the box's account. The webhook marks the plan paid."""
    connection = db.get_connection()
    try:
        url = payment_service.subscription_checkout_url(
            connection,
            gym_id=session["active_gym_id"],
            user_id=session["user_id"],
            member_plan_id=body.member_plan_id,
        )
        return {"url": url}
    finally:
        connection.close()


@router.post("/stripe/webhook")
async def stripe_webhook(request: Request) -> dict[str, Any]:
    """Events from the boxes' connected Stripe accounts (signed by Stripe).
    Locally: ``stripe listen --forward-connect-to localhost:8081/stripe/webhook``."""
    payload = await request.body()
    event = payment_service.client.construct_event(payload, request.headers.get("stripe-signature"))
    connection = db.get_connection()
    try:
        return {"result": payment_service.handle_event(connection, event)}
    finally:
        connection.close()


@router.get("/membership/plans")
def list_membership_plans(
    include_archived: bool = False,
    session: dict[str, Any] = Depends(require_active_gym_member_session),
) -> dict[str, Any]:
    gym_id = session["active_gym_id"]
    connection = db.get_connection()
    try:
        gym = plan_service.gym_plan_settings(connection, gym_id)
        show_archived = include_archived and _is_admin_member(connection, gym_id, session["user_id"])
        rows = plan_service.list_plan_rows(
            connection, gym_id, gym_timezone=gym["timezone"], include_archived=show_archived
        )
        return {
            "plans": [plan_service.plan_payload(row, currency=gym["currency"]) for row in rows],
            "currency": gym["currency"],
            "require_plan_for_booking": bool(gym["require_plan_for_booking"]),
        }
    finally:
        connection.close()


@router.post("/membership/plans", status_code=HTTPStatus.CREATED.value)
def create_membership_plan(
    body: MembershipPlanRequest,
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, Any]:
    gym_id = session["active_gym_id"]
    fields = plan_service.require_plan_fields(body.model_dump(), class_type_names(session["active_gym_id"]))
    connection = db.get_connection()
    try:
        gym = plan_service.gym_plan_settings(connection, gym_id)
        timestamp = security.isoformat(security.now_utc())
        with connection:
            cursor = connection.execute(
                """
                insert into membership_plans (
                  gym_id, name, description, plan_type, price_cents, billing_period,
                  token_count, token_period, validity_days, allowed_class_types_json,
                  created_by_user_id, created_at, updated_at
                ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                returning id
                """,
                (
                    gym_id,
                    fields["name"],
                    fields["description"],
                    fields["plan_type"],
                    fields["price_cents"],
                    fields["billing_period"],
                    fields["token_count"],
                    fields["token_period"],
                    fields["validity_days"],
                    fields["allowed_class_types_json"],
                    session["user_id"],
                    timestamp,
                    timestamp,
                ),
            )
            plan_id = int(cursor.fetchone()["id"])
            audit.write_audit_log(
                connection,
                gym_id=gym_id,
                actor_user_id=session["user_id"],
                action="membership_plan_created",
                entity_type="membership_plan",
                entity_id=plan_id,
                details={"name": fields["name"], "plan_type": fields["plan_type"], "price_cents": fields["price_cents"]},
            )
        row = plan_service.get_plan_row(connection, gym_id, plan_id)
        return {"plan": plan_service.plan_payload(row, currency=gym["currency"])}
    finally:
        connection.close()


@router.patch("/membership/plans")
def update_membership_plan(
    body: UpdateMembershipPlanRequest,
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, Any]:
    """Edit a plan. Members already on the plan keep the price and limits they
    were given; the change applies to new requests and assignments."""
    gym_id = session["active_gym_id"]
    fields = plan_service.require_plan_fields(body.model_dump(), class_type_names(session["active_gym_id"]))
    connection = db.get_connection()
    try:
        gym = plan_service.gym_plan_settings(connection, gym_id)
        plan_service.get_plan_row(connection, gym_id, body.plan_id)
        with connection:
            connection.execute(
                """
                update membership_plans
                set name = ?, description = ?, plan_type = ?, price_cents = ?, billing_period = ?,
                    token_count = ?, token_period = ?, validity_days = ?, allowed_class_types_json = ?,
                    updated_at = ?
                where id = ? and gym_id = ?
                """,
                (
                    fields["name"],
                    fields["description"],
                    fields["plan_type"],
                    fields["price_cents"],
                    fields["billing_period"],
                    fields["token_count"],
                    fields["token_period"],
                    fields["validity_days"],
                    fields["allowed_class_types_json"],
                    security.isoformat(security.now_utc()),
                    body.plan_id,
                    gym_id,
                ),
            )
            audit.write_audit_log(
                connection,
                gym_id=gym_id,
                actor_user_id=session["user_id"],
                action="membership_plan_updated",
                entity_type="membership_plan",
                entity_id=body.plan_id,
                details={"name": fields["name"], "plan_type": fields["plan_type"], "price_cents": fields["price_cents"]},
            )
        rows = plan_service.list_plan_rows(connection, gym_id, gym_timezone=gym["timezone"], include_archived=True)
        row = next(item for item in rows if item["id"] == body.plan_id)
        return {"plan": plan_service.plan_payload(row, currency=gym["currency"])}
    finally:
        connection.close()


@router.patch("/membership/plans/archive")
def archive_membership_plan(
    body: ArchiveMembershipPlanRequest,
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, Any]:
    """Archive (stop offering) or restore a plan. Archived plans are hidden from
    athletes; members already on them keep them."""
    gym_id = session["active_gym_id"]
    connection = db.get_connection()
    try:
        gym = plan_service.gym_plan_settings(connection, gym_id)
        plan_service.get_plan_row(connection, gym_id, body.plan_id)
        with connection:
            connection.execute(
                "update membership_plans set is_archived = ?, updated_at = ? where id = ? and gym_id = ?",
                (int(body.archived), security.isoformat(security.now_utc()), body.plan_id, gym_id),
            )
            if body.archived:
                # Open requests for a plan that is no longer offered cannot be approved sensibly.
                connection.execute(
                    "update member_plans set status = 'cancelled', updated_at = ? where plan_id = ? and status = 'requested'",
                    (security.isoformat(security.now_utc()), body.plan_id),
                )
            audit.write_audit_log(
                connection,
                gym_id=gym_id,
                actor_user_id=session["user_id"],
                action="membership_plan_archived" if body.archived else "membership_plan_restored",
                entity_type="membership_plan",
                entity_id=body.plan_id,
                details={},
            )
        rows = plan_service.list_plan_rows(connection, gym_id, gym_timezone=gym["timezone"], include_archived=True)
        row = next(item for item in rows if item["id"] == body.plan_id)
        return {"plan": plan_service.plan_payload(row, currency=gym["currency"])}
    finally:
        connection.close()


@router.get("/membership/me")
def get_my_membership(
    session: dict[str, Any] = Depends(require_active_gym_member_session),
) -> dict[str, Any]:
    gym_id = session["active_gym_id"]
    connection = db.get_connection()
    try:
        gym = plan_service.gym_plan_settings(connection, gym_id)
        rows = plan_service.member_plan_rows_for_user(connection, gym_id, session["user_id"])
        plans = _member_plan_payloads(connection, gym, rows)
        for plan in plans:
            # Payment state is the owner's business: members never see "overdue".
            plan.pop("payment_status", None)
        return {
            "plans": plans,
            "currency": gym["currency"],
            "require_plan_for_booking": bool(gym["require_plan_for_booking"]),
            "extra_tokens": _extra_tokens_payload(connection, gym, session["user_id"]),
            "extra_token_price_cents": gym["extra_token_price_cents"],
            "online_payments": payment_service.gym_accepts_payments(connection, gym_id),
        }
    finally:
        connection.close()


@router.post("/membership/requests", status_code=HTTPStatus.CREATED.value)
def request_membership_plan(
    body: PlanIdRequest,
    session: dict[str, Any] = Depends(require_active_gym_member_session),
) -> dict[str, Any]:
    """Ask the owner for a plan. A newer request replaces an open one."""
    gym_id = session["active_gym_id"]
    connection = db.get_connection()
    try:
        gym = plan_service.gym_plan_settings(connection, gym_id)
        plan = plan_service.get_plan_row(connection, gym_id, body.plan_id)
        if plan["is_archived"]:
            raise HTTPException(status_code=HTTPStatus.BAD_REQUEST.value, detail="This plan is no longer offered.")
        with connection:
            plan_service.cancel_open_requests(connection, gym_id=gym_id, user_id=session["user_id"])
            member_plan_id = plan_service.insert_member_plan(
                connection, plan=plan, user_id=session["user_id"], status="requested"
            )
            audit.write_audit_log(
                connection,
                gym_id=gym_id,
                actor_user_id=session["user_id"],
                target_user_id=session["user_id"],
                action="membership_plan_requested",
                entity_type="member_plan",
                entity_id=member_plan_id,
                details={"plan_id": plan["id"], "plan_name": plan["name"]},
            )
        row = plan_service.get_member_plan_row(connection, gym_id, member_plan_id)
        return {"plan": _member_plan_payloads(connection, gym, [row])[0]}
    finally:
        connection.close()


@router.delete("/membership/requests")
def withdraw_membership_plan_request(
    session: dict[str, Any] = Depends(require_active_gym_member_session),
) -> dict[str, str]:
    gym_id = session["active_gym_id"]
    connection = db.get_connection()
    try:
        if plan_service.pending_request_row(connection, gym_id, session["user_id"]) is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="You have no open plan request.")
        with connection:
            plan_service.cancel_open_requests(connection, gym_id=gym_id, user_id=session["user_id"])
        return {"message": "Plan request withdrawn."}
    finally:
        connection.close()


@router.get("/membership/requests")
def list_membership_plan_requests(
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, Any]:
    """Open plan requests from active members (requests sent with a join request
    show up here once the join request is approved)."""
    gym_id = session["active_gym_id"]
    connection = db.get_connection()
    try:
        gym = plan_service.gym_plan_settings(connection, gym_id)
        rows = connection.execute(
            """
            select member_plans.*, users.email, users.display_name, users.nickname, users.profile_image_url
            from member_plans
            join users on users.id = member_plans.user_id
            join gym_memberships on gym_memberships.user_id = member_plans.user_id
              and gym_memberships.gym_id = member_plans.gym_id
              and gym_memberships.status in ('active', 'paused')
            where member_plans.gym_id = ? and member_plans.status = 'requested'
              and users.deleted_at is null
            order by member_plans.requested_at asc, member_plans.id asc
            """,
            (gym_id,),
        ).fetchall()
        requests = []
        for row in rows:
            payload = _member_plan_payloads(connection, gym, [row])[0]
            current = plan_service.plan_for_day(
                connection, gym_id, row["user_id"], schedule_service.local_today(gym["timezone"])
            )
            payload["member"] = {
                "id": row["user_id"],
                "email": row["email"],
                "display_name": row["display_name"],
                "nickname": row["nickname"],
                "profile_image_url": row["profile_image_url"],
            }
            payload["current_plan_name"] = current["plan_name"] if current is not None else None
            requests.append(payload)
        return {"requests": requests}
    finally:
        connection.close()


def _plan_start_date(value: str | None, gym_timezone: str) -> Any:
    today = schedule_service.local_today(gym_timezone)
    if value is None or not str(value).strip():
        return today
    starts_on = plan_service.require_date(value)
    if starts_on < today - timedelta(days=31):
        raise HTTPException(
            status_code=HTTPStatus.BAD_REQUEST.value,
            detail="Start date can be at most a month in the past.",
        )
    return starts_on


def _require_member(connection: Any, gym_id: int, user_id: int) -> None:
    member = connection.execute(
        "select id from gym_memberships where user_id = ? and gym_id = ? and status in ('active', 'paused')",
        (user_id, gym_id),
    ).fetchone()
    if member is None:
        raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Gym member not found.")


@router.patch("/membership/requests")
def review_membership_plan_request(
    body: ReviewPlanRequestBody,
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, Any]:
    """Approve (optionally with a start date and an adjusted price) or reject a plan request."""
    gym_id = session["active_gym_id"]
    decision = validation.require_join_request_decision(body.decision)
    connection = db.get_connection()
    try:
        gym = plan_service.gym_plan_settings(connection, gym_id)
        request_row = plan_service.get_member_plan_row(connection, gym_id, body.request_id)
        if request_row["status"] != "requested":
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Plan request not found.")
        _require_member(connection, gym_id, request_row["user_id"])
        starts_on = _plan_start_date(body.starts_on, gym["timezone"])
        price_cents = plan_service.require_price_cents(body.price_cents) if body.price_cents is not None else None
        timestamp = security.isoformat(security.now_utc())
        with connection:
            if decision == "approve":
                plan_service.activate_member_plan(
                    connection,
                    member_plan=request_row,
                    starts_on=starts_on,
                    price_cents=price_cents,
                    reviewer_user_id=session["user_id"],
                )
                title = "Membership plan approved"
                message = f"{request_row['plan_name']} starts on {starts_on.isoformat()}."
            else:
                connection.execute(
                    """
                    update member_plans
                    set status = 'rejected', reviewed_at = ?, reviewed_by_user_id = ?, updated_at = ?
                    where id = ?
                    """,
                    (timestamp, session["user_id"], timestamp, request_row["id"]),
                )
                title = "Membership plan request declined"
                message = f"Your request for {request_row['plan_name']} was declined. Talk to your box for details."
            notifications.create_notification(
                connection,
                user_id=request_row["user_id"],
                gym_id=gym_id,
                type="membership_plan",
                title=title,
                body=message,
                entity_type="member_plan",
                entity_id=request_row["id"],
            )
            audit.write_audit_log(
                connection,
                gym_id=gym_id,
                actor_user_id=session["user_id"],
                target_user_id=request_row["user_id"],
                action="membership_plan_request_reviewed",
                entity_type="member_plan",
                entity_id=request_row["id"],
                details={
                    "decision": decision,
                    "plan_name": request_row["plan_name"],
                    "starts_on": starts_on.isoformat() if decision == "approve" else None,
                    "price_cents": price_cents,
                },
            )
        row = plan_service.get_member_plan_row(connection, gym_id, request_row["id"])
        return {"plan": _member_plan_payloads(connection, gym, [row])[0]}
    finally:
        connection.close()


@router.get("/membership/members/{user_id}")
def get_member_plans(
    user_id: int,
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, Any]:
    """A member's plan history for the owner's member detail view."""
    gym_id = session["active_gym_id"]
    connection = db.get_connection()
    try:
        gym = plan_service.gym_plan_settings(connection, gym_id)
        _require_member(connection, gym_id, user_id)
        rows = plan_service.member_plan_rows_for_user(connection, gym_id, user_id)
        return {
            "plans": _member_plan_payloads(connection, gym, rows),
            "currency": gym["currency"],
            "extra_tokens": _extra_tokens_payload(connection, gym, user_id),
            "extra_token_price_cents": gym["extra_token_price_cents"],
        }
    finally:
        connection.close()


@router.get("/membership/members/{user_id}/bookings")
def get_member_bookings(
    user_id: int,
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, Any]:
    """A member's class bookings and waitlist entries, newest class first, for
    the Classes tab of the owner's member detail. Read-only."""
    gym_id = session["active_gym_id"]
    connection = db.get_connection()
    try:
        _require_member(connection, gym_id, user_id)
        return {"bookings": _booking_history(connection, gym_id, user_id)}
    finally:
        connection.close()


@router.get("/membership/members/{user_id}/results")
def get_member_results(
    user_id: int,
    movement_id: int | None = None,
    workout_name: str = "",
    limit: int = 200,
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, Any]:
    """A member's results at this gym for the Results tab of the owner's
    member detail; same shape as /results/me."""
    gym_id = session["active_gym_id"]
    connection = db.get_connection()
    try:
        _require_member(connection, gym_id, user_id)
        return results_service.my_results(
            connection,
            user_id=user_id,
            movement_id=movement_id,
            workout_name=workout_name,
            limit=limit,
            gym_id=gym_id,
        )
    finally:
        connection.close()


@router.get("/membership/me/bookings")
def get_my_bookings(
    session: dict[str, Any] = Depends(require_active_gym_member_session),
) -> dict[str, Any]:
    """The signed-in member's bookings, waitlist entries and cancellations at
    the active box, newest class first, for Profile › Bookings."""
    connection = db.get_connection()
    try:
        return {"bookings": _booking_history(connection, session["active_gym_id"], session["user_id"])}
    finally:
        connection.close()


def _booking_history(connection: Any, gym_id: int, user_id: int) -> list[dict[str, Any]]:
    """Bookings (status booked / attended / no_show), waitlist entries
    (`waitlist`) and cancellations (`cancelled`, with `cancelled_at`) of one
    member at one box. A cancellation is left out once the member booked or
    waitlisted the same class again."""
    rows = connection.execute(
        """
        select class_schedules.id as class_id, class_schedules.title, class_schedules.class_type,
               class_schedules.start_time, class_schedules.end_time,
               trainers.display_name as trainer_name, entries.status, entries.cancelled_at
        from (
            select class_schedule_id, attendance_status as status, null as cancelled_at
            from class_bookings where user_id = ?
            union all
            select class_schedule_id, 'waitlist' as status, null as cancelled_at
            from class_waitlist_entries where user_id = ?
            union all
            select class_schedule_id, 'cancelled' as status, max(cancelled_at) as cancelled_at
            from class_booking_cancellations
            where user_id = ?
              and class_schedule_id not in (select class_schedule_id from class_bookings where user_id = ?)
              and class_schedule_id not in (select class_schedule_id from class_waitlist_entries where user_id = ?)
            group by class_schedule_id
        ) entries
        join class_schedules on class_schedules.id = entries.class_schedule_id
        left join users trainers on trainers.id = class_schedules.assigned_trainer_user_id
        where class_schedules.gym_id = ?
        order by class_schedules.start_time desc
        """,
        (user_id, user_id, user_id, user_id, user_id, gym_id),
    ).fetchall()
    return [dict(row) for row in rows]


@router.post("/membership/extra-tokens", status_code=HTTPStatus.CREATED.value)
def grant_extra_tokens(
    body: GrantExtraTokensRequest,
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, Any]:
    """Owner adds extra tokens to a member (e.g. bought in cash). They are valid
    for one month and are spent when the member's plan cannot cover a class."""
    gym_id = session["active_gym_id"]
    connection = db.get_connection()
    try:
        gym = plan_service.gym_plan_settings(connection, gym_id)
        _require_member(connection, gym_id, body.user_id)
        if body.price_cents is not None:
            price_cents = plan_service.require_price_cents(body.price_cents)
        else:
            price_cents = int(gym["extra_token_price_cents"] or 0) * max(int(body.tokens), 0)
        granted_on = schedule_service.local_today(gym["timezone"])
        with connection:
            credit_id = plan_service.grant_token_credit(
                connection,
                gym_id=gym_id,
                user_id=body.user_id,
                tokens=body.tokens,
                price_cents=price_cents,
                granted_on=granted_on,
                created_by_user_id=session["user_id"],
            )
            valid_until = plan_service.extra_token_expiry(granted_on) - timedelta(days=1)
            notifications.create_notification(
                connection,
                user_id=body.user_id,
                gym_id=gym_id,
                type="membership_plan",
                title="Extra tokens added",
                body=f"You got {body.tokens} extra token{'s' if body.tokens != 1 else ''}, valid until {valid_until.isoformat()}.",
                entity_type="token_credit",
                entity_id=credit_id,
            )
            audit.write_audit_log(
                connection,
                gym_id=gym_id,
                actor_user_id=session["user_id"],
                target_user_id=body.user_id,
                action="extra_tokens_granted",
                entity_type="token_credit",
                entity_id=credit_id,
                details={"tokens": body.tokens, "price_cents": price_cents},
            )
        return {"extra_tokens": _extra_tokens_payload(connection, gym, body.user_id)}
    finally:
        connection.close()


@router.delete("/membership/extra-tokens/{credit_id}")
def remove_extra_tokens(
    credit_id: int,
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, Any]:
    """Owner takes back extra tokens added by mistake. Classes already booked on
    them stay booked."""
    gym_id = session["active_gym_id"]
    connection = db.get_connection()
    try:
        gym = plan_service.gym_plan_settings(connection, gym_id)
        row = plan_service.get_token_credit_row(connection, gym_id, credit_id)
        with connection:
            connection.execute("delete from token_credits where id = ?", (credit_id,))
            audit.write_audit_log(
                connection,
                gym_id=gym_id,
                actor_user_id=session["user_id"],
                target_user_id=row["user_id"],
                action="extra_tokens_removed",
                entity_type="token_credit",
                entity_id=credit_id,
                details={"tokens": row["tokens"], "price_cents": row["price_cents"]},
            )
        return {"extra_tokens": _extra_tokens_payload(connection, gym, row["user_id"])}
    finally:
        connection.close()


@router.post("/membership/assignments", status_code=HTTPStatus.CREATED.value)
def assign_membership_plan(
    body: AssignPlanRequest,
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, Any]:
    """Owner gives a member a plan directly. Replaces the member's open request
    and ends or shortens the plan it overlaps."""
    gym_id = session["active_gym_id"]
    connection = db.get_connection()
    try:
        gym = plan_service.gym_plan_settings(connection, gym_id)
        _require_member(connection, gym_id, body.user_id)
        plan = plan_service.get_plan_row(connection, gym_id, body.plan_id)
        if plan["is_archived"]:
            raise HTTPException(status_code=HTTPStatus.BAD_REQUEST.value, detail="This plan is no longer offered.")
        starts_on = _plan_start_date(body.starts_on, gym["timezone"])
        price_cents = plan_service.require_price_cents(body.price_cents) if body.price_cents is not None else None
        with connection:
            plan_service.cancel_open_requests(connection, gym_id=gym_id, user_id=body.user_id)
            member_plan_id = plan_service.insert_member_plan(connection, plan=plan, user_id=body.user_id, status="active")
            plan_service.activate_member_plan(
                connection,
                member_plan=plan_service.get_member_plan_row(connection, gym_id, member_plan_id),
                starts_on=starts_on,
                price_cents=price_cents,
                reviewer_user_id=session["user_id"],
            )
            notifications.create_notification(
                connection,
                user_id=body.user_id,
                gym_id=gym_id,
                type="membership_plan",
                title="New membership plan",
                body=f"You are on {plan['name']} from {starts_on.isoformat()}.",
                entity_type="member_plan",
                entity_id=member_plan_id,
            )
            audit.write_audit_log(
                connection,
                gym_id=gym_id,
                actor_user_id=session["user_id"],
                target_user_id=body.user_id,
                action="membership_plan_assigned",
                entity_type="member_plan",
                entity_id=member_plan_id,
                details={"plan_id": plan["id"], "plan_name": plan["name"], "starts_on": starts_on.isoformat(), "price_cents": price_cents},
            )
        row = plan_service.get_member_plan_row(connection, gym_id, member_plan_id)
        return {"plan": _member_plan_payloads(connection, gym, [row])[0]}
    finally:
        connection.close()


@router.patch("/membership/assignments")
def update_member_plan(
    body: UpdateMemberPlanRequest,
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, Any]:
    """Track payment by hand (paid / due / overdue) until a payment provider exists."""
    gym_id = session["active_gym_id"]
    connection = db.get_connection()
    try:
        gym = plan_service.gym_plan_settings(connection, gym_id)
        row = plan_service.get_member_plan_row(connection, gym_id, body.member_plan_id)
        if row["status"] != "active":
            raise HTTPException(status_code=HTTPStatus.BAD_REQUEST.value, detail="Only active plans can be updated.")
        if body.payment_status is not None:
            payment_status = plan_service.require_payment_status(body.payment_status)
            with connection:
                connection.execute(
                    "update member_plans set payment_status = ?, updated_at = ? where id = ?",
                    (payment_status, security.isoformat(security.now_utc()), row["id"]),
                )
                audit.write_audit_log(
                    connection,
                    gym_id=gym_id,
                    actor_user_id=session["user_id"],
                    target_user_id=row["user_id"],
                    action="member_plan_payment_updated",
                    entity_type="member_plan",
                    entity_id=row["id"],
                    details={"from": row["payment_status"], "to": payment_status},
                )
        row = plan_service.get_member_plan_row(connection, gym_id, body.member_plan_id)
        return {"plan": _member_plan_payloads(connection, gym, [row])[0]}
    finally:
        connection.close()


@router.post("/membership/assignments/end")
def end_member_plan(
    body: EndMemberPlanRequest,
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, Any]:
    gym_id = session["active_gym_id"]
    connection = db.get_connection()
    try:
        gym = plan_service.gym_plan_settings(connection, gym_id)
        row = plan_service.get_member_plan_row(connection, gym_id, body.member_plan_id)
        if row["status"] != "active":
            raise HTTPException(status_code=HTTPStatus.BAD_REQUEST.value, detail="Only active plans can be ended.")
        with connection:
            payment_service.end_subscribed_plan(
                connection, member_plan=row, gym_timezone=gym["timezone"], at_period_end=body.at_period_end
            )
            audit.write_audit_log(
                connection,
                gym_id=gym_id,
                actor_user_id=session["user_id"],
                target_user_id=row["user_id"],
                action="member_plan_ended",
                entity_type="member_plan",
                entity_id=row["id"],
                details={"plan_name": row["plan_name"], "at_period_end": body.at_period_end},
            )
            notifications.create_notification(
                connection,
                user_id=row["user_id"],
                gym_id=gym_id,
                type="membership_plan",
                title="Membership plan ending" if body.at_period_end else "Membership plan ended",
                body=(
                    f"Your box ended {row['plan_name']}. It stays valid until the end of the current month; "
                    "no further payments are taken."
                    if body.at_period_end
                    else f"Your box ended {row['plan_name']} as of today. No further payments are taken."
                ),
                entity_type="member_plan",
                entity_id=row["id"],
            )
        row = plan_service.get_member_plan_row(connection, gym_id, body.member_plan_id)
        return {"plan": _member_plan_payloads(connection, gym, [row])[0]}
    finally:
        connection.close()
