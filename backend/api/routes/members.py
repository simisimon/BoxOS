from __future__ import annotations

from http import HTTPStatus
from typing import Any

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from backend.api.common import get_gym_timezone
from backend.api.deps import require_admin_gym_session
from backend.api.validators import members as validators
from backend.core import audit, db, security, validation
from backend.services import membership_service, plan_service

router = APIRouter()


class AssignRoleRequest(BaseModel):
    user_id: int
    role: str | None = None
    roles: list[str] | None = None
    # New roster-edit fields. All optional so the existing call sites that only
    # send `user_id` + `roles` keep working unchanged.
    active_role: str | None = None
    status: str | None = None
    admin_note: str | None = None


def _member_payload_with_plan(row: Any, summaries: dict[int, dict[str, Any]]) -> dict[str, Any]:
    payload = membership_service.role_managed_member_payload(row)
    summary = summaries.get(int(row["user_id"]), {})
    payload["plan"] = summary.get("plan")
    payload["has_plan_request"] = bool(summary.get("has_plan_request"))
    payload["extra_tokens_remaining"] = int(summary.get("extra_tokens_remaining") or 0)
    return payload


@router.get("/roles/users")
def list_role_users(
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, list[dict[str, Any]]]:
    connection = db.get_connection()
    try:
        rows = connection.execute(
            """
            select gym_memberships.id, gym_memberships.user_id, gym_memberships.active_role,
                   gym_memberships.roles_json, gym_memberships.status, gym_memberships.admin_note,
                   gym_memberships.created_at as joined_at,
                   users.email, users.display_name, users.nickname, users.profile_image_url,
                   (
                     select count(*)
                     from class_bookings
                     join class_schedules on class_schedules.id = class_bookings.class_schedule_id
                     where class_bookings.user_id = gym_memberships.user_id
                       and class_schedules.gym_id = gym_memberships.gym_id
                   ) as total_bookings,
                   (
                     select count(*)
                     from class_bookings
                     join class_schedules on class_schedules.id = class_bookings.class_schedule_id
                     where class_bookings.user_id = gym_memberships.user_id
                       and class_schedules.gym_id = gym_memberships.gym_id
                       and class_bookings.attendance_status = 'attended'
                   ) as attended_bookings,
                   (
                     select count(*)
                     from class_bookings
                     join class_schedules on class_schedules.id = class_bookings.class_schedule_id
                     where class_bookings.user_id = gym_memberships.user_id
                       and class_schedules.gym_id = gym_memberships.gym_id
                       and class_bookings.attendance_status = 'no_show'
                   ) as no_show_bookings,
                   (
                     select max(class_bookings.created_at)
                     from class_bookings
                     join class_schedules on class_schedules.id = class_bookings.class_schedule_id
                     where class_bookings.user_id = gym_memberships.user_id
                       and class_schedules.gym_id = gym_memberships.gym_id
                   ) as last_booking_at
            from gym_memberships
            join users on users.id = gym_memberships.user_id
            where gym_memberships.gym_id = ?
              and gym_memberships.status in ('active', 'paused')
              and users.deleted_at is null
            order by case gym_memberships.active_role when 'admin' then 0 when 'trainer' then 1 else 2 end,
                     lower(coalesce(nullif(users.display_name, ''), users.email)) asc
            """,
            (session["active_gym_id"],),
        ).fetchall()
        summaries = plan_service.plan_summaries_for_gym(
            connection, session["active_gym_id"], get_gym_timezone(connection, session["active_gym_id"])
        )
        return {"users": [_member_payload_with_plan(row, summaries) for row in rows]}
    finally:
        connection.close()


@router.patch("/roles/users")
def assign_role(
    body: AssignRoleRequest,
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, Any]:
    payload = body.model_dump(exclude_none=True)
    user_id = validation.require_user_id(body.user_id)
    roles = validators.require_role_list(payload)
    managed_roles = [role for role in roles if role in {"athlete", "trainer"}]
    if not managed_roles:
        raise HTTPException(status_code=HTTPStatus.BAD_REQUEST.value, detail="Managed roles must include athlete or trainer.")

    # Optional roster-edit fields. Validate up front so we never partially apply.
    desired_active_role: str | None = None
    if body.active_role is not None:
        candidate = validation.normalize_role_value(body.active_role)
        if candidate not in managed_roles:
            raise HTTPException(
                status_code=HTTPStatus.BAD_REQUEST.value,
                detail="Active role must be one of the assigned roles.",
            )
        desired_active_role = candidate
    desired_status: str | None = (
        validators.require_membership_status(body.status) if body.status is not None else None
    )
    desired_note: str | None = (
        validators.require_admin_note(body.admin_note) if body.admin_note is not None else None
    )

    connection = db.get_connection()
    try:
        membership_before = connection.execute(
            "select id, active_role, status, admin_note from gym_memberships where user_id = ? and gym_id = ? and status in ('active', 'paused')",
            (user_id, session["active_gym_id"]),
        ).fetchone()
        if membership_before is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Gym member not found.")
        if membership_before["active_role"] == "admin":
            raise HTTPException(status_code=HTTPStatus.FORBIDDEN.value, detail="Owner memberships cannot be changed from this screen.")

        # Active role precedence: explicit choice from the request wins, else
        # keep the existing one if still valid, else fall back to the first
        # managed role so we never leave the membership inconsistent.
        if desired_active_role is not None:
            active_role = desired_active_role
        elif membership_before["active_role"] in managed_roles:
            active_role = membership_before["active_role"]
        else:
            active_role = managed_roles[0]

        next_status = desired_status if desired_status is not None else membership_before["status"]
        next_note = desired_note if desired_note is not None else membership_before["admin_note"]

        with connection:
            updated = connection.execute(
                """
                update gym_memberships
                set active_role = ?, roles_json = ?, status = ?, admin_note = ?, updated_at = ?
                where id = ?
                """,
                (
                    active_role,
                    validation.encode_roles(managed_roles),
                    next_status,
                    next_note,
                    security.isoformat(security.now_utc()),
                    membership_before["id"],
                ),
            )
            membership_service.sync_user_context(connection, user_id)
            audit_details: dict[str, Any] = {"roles": managed_roles, "active_role": active_role}
            if desired_status is not None:
                audit_details["status"] = next_status
            if desired_note is not None:
                audit_details["admin_note_set"] = bool(next_note)
            audit.write_audit_log(
                connection,
                gym_id=session["active_gym_id"],
                actor_user_id=session["user_id"],
                target_user_id=user_id,
                action="gym_member_roles_updated",
                entity_type="gym_membership",
                entity_id=membership_before["id"],
                details=audit_details,
            )
        if updated.rowcount == 0:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Gym member not found.")
        user = connection.execute(
            """
            select gym_memberships.id, gym_memberships.user_id, gym_memberships.active_role,
                   gym_memberships.roles_json, gym_memberships.status, gym_memberships.admin_note,
                   gym_memberships.created_at as joined_at,
                   users.email, users.display_name, users.nickname, users.profile_image_url,
                   (
                     select count(*)
                     from class_bookings
                     join class_schedules on class_schedules.id = class_bookings.class_schedule_id
                     where class_bookings.user_id = gym_memberships.user_id
                       and class_schedules.gym_id = gym_memberships.gym_id
                   ) as total_bookings,
                   (
                     select count(*)
                     from class_bookings
                     join class_schedules on class_schedules.id = class_bookings.class_schedule_id
                     where class_bookings.user_id = gym_memberships.user_id
                       and class_schedules.gym_id = gym_memberships.gym_id
                       and class_bookings.attendance_status = 'attended'
                   ) as attended_bookings,
                   (
                     select count(*)
                     from class_bookings
                     join class_schedules on class_schedules.id = class_bookings.class_schedule_id
                     where class_bookings.user_id = gym_memberships.user_id
                       and class_schedules.gym_id = gym_memberships.gym_id
                       and class_bookings.attendance_status = 'no_show'
                   ) as no_show_bookings,
                   (
                     select max(class_bookings.created_at)
                     from class_bookings
                     join class_schedules on class_schedules.id = class_bookings.class_schedule_id
                     where class_bookings.user_id = gym_memberships.user_id
                       and class_schedules.gym_id = gym_memberships.gym_id
                   ) as last_booking_at
            from gym_memberships
            join users on users.id = gym_memberships.user_id
            where gym_memberships.id = ? and users.deleted_at is null
            """,
            (membership_before["id"],),
        ).fetchone()
        if user is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Gym member not found.")
        summaries = plan_service.plan_summaries_for_gym(
            connection, session["active_gym_id"], get_gym_timezone(connection, session["active_gym_id"])
        )
        return _member_payload_with_plan(user, summaries)
    finally:
        connection.close()
