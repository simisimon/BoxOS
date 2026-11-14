from __future__ import annotations

import secrets
from http import HTTPStatus
from typing import Any

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from backend.api.common import GymIdRequest
from backend.api.deps import (
    require_admin_gym_session,
    require_admin_session,
    require_gym_owner_session,
    require_session,
)
from backend.api.validators import gyms as validators
from backend.core import audit, db, security, settings, validation
from backend.services import membership_service, plan_service, schedule_service

router = APIRouter()


class AddGymOwnerRequest(BaseModel):
    user_id: int


class CreateGymRequest(BaseModel):
    name: str
    logo_url: str
    timezone: str = "UTC"  # Default to UTC if not provided


class UpdateGymRequest(BaseModel):
    # Every field is optional: only the ones sent are changed.
    name: str | None = None
    logo_url: str | None = None
    timezone: str | None = None


class JoinGymRequest(GymIdRequest):
    # Optional plan the athlete would like; becomes a plan request the owner
    # reviews once the join request is approved.
    plan_id: int | None = None


class ReviewJoinRequestBody(BaseModel):
    request_id: int
    decision: str


class GymLogoUploadRequest(BaseModel):
    filename: str
    content_type: str
    data_base64: str


@router.get("/gyms")
def list_gyms() -> dict[str, list[dict[str, Any]]]:
    connection = db.get_connection()
    try:
        rows = connection.execute(
            "select id, name, slug, logo_url, timezone from gyms order by name asc"
        ).fetchall()
        return {
            "gyms": [
                {
                    "id": row["id"],
                    "name": row["name"],
                    "slug": row["slug"],
                    "logo_url": row["logo_url"],
                    "timezone": row["timezone"],
                }
                for row in rows
            ]
        }
    finally:
        connection.close()


@router.post("/gyms", status_code=HTTPStatus.CREATED.value)
def create_gym(
    body: CreateGymRequest,
    session: dict[str, Any] = Depends(require_admin_session),
) -> dict[str, Any]:
    name = validators.require_gym_name(body.name)
    logo_url = body.logo_url.strip() if body.logo_url else ""
    timezone = body.timezone or "UTC"

    connection = db.get_connection()
    try:
        with connection:
            slug = membership_service.unique_gym_slug(connection, name)
            timestamp = security.isoformat(security.now_utc())
            cursor = connection.execute(
                """
                insert into gyms (name, slug, logo_url, timezone, created_by_user_id, created_at, updated_at)
                values (?, ?, ?, ?, ?, ?, ?)
                returning id
                """,
                (name, slug, logo_url, timezone, session["user_id"], timestamp, timestamp),
            )
            gym_id = int(cursor.fetchone()["id"])
            connection.execute(
                """
                insert into gym_memberships (
                  user_id, gym_id, active_role, roles_json, status, created_at, updated_at
                ) values (?, ?, 'admin', ?, 'active', ?, ?)
                """,
                (session["user_id"], gym_id, validation.encode_roles(["admin"]), timestamp, timestamp),
            )
            connection.execute(
                "update users set active_gym_id = ?, updated_at = ? where id = ?",
                (gym_id, timestamp, session["user_id"]),
            )
            membership_service.sync_user_context(connection, session["user_id"])
            audit.write_audit_log(
                connection,
                gym_id=gym_id,
                actor_user_id=session["user_id"],
                action="gym_created",
                entity_type="gym",
                entity_id=gym_id,
                details={"name": name, "slug": slug},
            )
        return {
            "gym": {
                "id": gym_id,
                "name": name,
                "slug": slug,
                "logo_url": logo_url,
                "timezone": timezone,
            }
        }
    finally:
        connection.close()


@router.post("/gyms/logo", status_code=HTTPStatus.CREATED.value)
def upload_gym_logo(
    body: GymLogoUploadRequest,
    _: dict[str, Any] = Depends(require_admin_session),
) -> dict[str, str]:
    filename = validation.require_upload_filename(body.filename)
    content_type = validators.require_gym_logo_content_type(body.content_type)
    raw_bytes = validation.require_base64_bytes(body.data_base64, label="Logo data", max_bytes=settings.MAX_GYM_LOGO_BYTES)
    extension = settings.ALLOWED_GYM_LOGO_CONTENT_TYPES[content_type]
    stored_name = f"gym_logo_{secrets.token_urlsafe(12)}{extension}"
    file_path = settings.GYM_LOGOS_DIR / stored_name
    file_path.write_bytes(raw_bytes)
    return {"filename": filename, "logo_url": f"/uploads/gym_logos/{stored_name}"}


@router.patch("/gyms/current")
def update_current_gym(
    body: UpdateGymRequest,
    session: dict[str, Any] = Depends(require_gym_owner_session),
) -> dict[str, Any]:
    """Edit the active gym's identity (name, logo, timezone).

    The slug stays as created so existing links keep working. A timezone change
    re-plans every class template's future sessions at the same local time in
    the new zone; booked sessions keep their instant and are detached when they
    no longer match (see ``schedule_service.resync_template_sessions``).
    """
    gym_id = int(session["active_gym_id"])
    connection = db.get_connection()
    try:
        gym = connection.execute(
            "select id, name, slug, logo_url, timezone from gyms where id = ?",
            (gym_id,),
        ).fetchone()
        if gym is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Gym not found.")

        updated = {"name": gym["name"], "logo_url": gym["logo_url"], "timezone": gym["timezone"]}
        if body.name is not None:
            updated["name"] = validators.require_gym_name(body.name)
        if body.logo_url is not None:
            logo_url = body.logo_url.strip()
            updated["logo_url"] = validators.require_logo_url(logo_url) if logo_url else ""
        if body.timezone is not None:
            timezone = validators.require_timezone(body.timezone)
            try:
                schedule_service.timezone_for_name(timezone)  # raises ApiError on unknown zones
            except ValueError as error:  # malformed keys such as "../x"
                raise validation.ApiError(HTTPStatus.BAD_REQUEST, "Gym timezone is invalid.") from error
            updated["timezone"] = timezone

        changes = {
            field: {"from": gym[field], "to": value}
            for field, value in updated.items()
            if value != gym[field]
        }
        detached_sessions = 0
        if changes:
            timestamp = security.isoformat(security.now_utc())
            with connection:
                connection.execute(
                    "update gyms set name = ?, logo_url = ?, timezone = ?, updated_at = ? where id = ?",
                    (updated["name"], updated["logo_url"], updated["timezone"], timestamp, gym_id),
                )
                if "timezone" in changes:
                    for template in schedule_service.list_class_template_rows(connection, gym_id):
                        detached_sessions += schedule_service.resync_template_sessions(
                            connection,
                            template,
                            gym_timezone=updated["timezone"],
                            actor_user_id=session["user_id"],
                        )
                audit.write_audit_log(
                    connection,
                    gym_id=gym_id,
                    actor_user_id=session["user_id"],
                    action="gym_updated",
                    entity_type="gym",
                    entity_id=gym_id,
                    details={"changes": changes, "detached_sessions": detached_sessions},
                )
        return {
            "gym": {
                "id": gym_id,
                "name": updated["name"],
                "slug": gym["slug"],
                "logo_url": updated["logo_url"],
                "timezone": updated["timezone"],
            },
            "detached_sessions": detached_sessions,
        }
    finally:
        connection.close()


@router.post("/gyms/join-requests", status_code=HTTPStatus.CREATED.value)
def create_join_request(
    body: JoinGymRequest,
    session: dict[str, Any] = Depends(require_session),
) -> dict[str, str]:
    gym_id = body.gym_id
    connection = db.get_connection()
    try:
        gym = connection.execute("select id from gyms where id = ?", (gym_id,)).fetchone()
        if gym is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Gym not found.")
        existing_membership = connection.execute(
            "select id from gym_memberships where user_id = ? and gym_id = ? and status = 'active'",
            (session["user_id"], gym_id),
        ).fetchone()
        if existing_membership is not None:
            raise HTTPException(status_code=HTTPStatus.CONFLICT.value, detail="You are already a member of this gym.")
        existing_request = connection.execute(
            "select id from gym_join_requests where user_id = ? and gym_id = ? and status = 'pending'",
            (session["user_id"], gym_id),
        ).fetchone()
        if existing_request is not None:
            raise HTTPException(status_code=HTTPStatus.CONFLICT.value, detail="A join request is already pending.")
        plan = None
        if body.plan_id is not None:
            plan = plan_service.get_plan_row(connection, gym_id, body.plan_id)
            if plan["is_archived"]:
                raise HTTPException(status_code=HTTPStatus.BAD_REQUEST.value, detail="This plan is no longer offered.")
        timestamp = security.isoformat(security.now_utc())
        with connection:
            connection.execute(
                "insert into gym_join_requests (user_id, gym_id, status, created_at, updated_at) values (?, ?, 'pending', ?, ?)",
                (session["user_id"], gym_id, timestamp, timestamp),
            )
            if plan is not None:
                plan_service.cancel_open_requests(connection, gym_id=gym_id, user_id=session["user_id"])
                plan_service.insert_member_plan(connection, plan=plan, user_id=session["user_id"], status="requested")
        return {"message": "Join request submitted."}
    finally:
        connection.close()


@router.get("/gyms/join-requests")
def list_join_requests(
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, list[dict[str, Any]]]:
    connection = db.get_connection()
    try:
        rows = connection.execute(
            """
            select gym_join_requests.id, gym_join_requests.created_at, users.email, users.display_name, users.nickname,
                   (
                     select member_plans.plan_name from member_plans
                     where member_plans.gym_id = gym_join_requests.gym_id
                       and member_plans.user_id = gym_join_requests.user_id
                       and member_plans.status = 'requested'
                     order by member_plans.id desc limit 1
                   ) as requested_plan_name
            from gym_join_requests
            join users on users.id = gym_join_requests.user_id
            where gym_join_requests.gym_id = ? and gym_join_requests.status = 'pending'
            order by gym_join_requests.created_at asc
            """,
            (session["active_gym_id"],),
        ).fetchall()
        return {
            "requests": [
                {
                    "id": row["id"],
                    "email": row["email"],
                    "display_name": row["display_name"],
                    "nickname": row["nickname"],
                    "created_at": row["created_at"],
                    "requested_plan_name": row["requested_plan_name"],
                }
                for row in rows
            ]
        }
    finally:
        connection.close()


@router.get("/gyms/my-requests")
def list_my_join_requests(
    session: dict[str, Any] = Depends(require_session),
) -> dict[str, list[dict[str, Any]]]:
    connection = db.get_connection()
    try:
        rows = connection.execute(
            """
            select gym_join_requests.id, gym_join_requests.status, gym_join_requests.created_at, gym_join_requests.reviewed_at,
                   gyms.id as gym_id, gyms.name as gym_name, gyms.slug as gym_slug, gyms.logo_url as gym_logo_url, gyms.timezone as gym_timezone
            from gym_join_requests
            join gyms on gyms.id = gym_join_requests.gym_id
            where gym_join_requests.user_id = ?
            order by gym_join_requests.updated_at desc
            """,
            (session["user_id"],),
        ).fetchall()
        return {
            "requests": [
                {
                    "id": row["id"],
                    "status": row["status"],
                    "created_at": row["created_at"],
                    "reviewed_at": row["reviewed_at"],
                    "gym": {
                        "id": row["gym_id"],
                        "name": row["gym_name"],
                        "slug": row["gym_slug"],
                        "logo_url": row["gym_logo_url"],
                        "timezone": row["gym_timezone"],
                    },
                }
                for row in rows
            ]
        }
    finally:
        connection.close()


@router.patch("/gyms/join-requests")
def review_join_request(
    body: ReviewJoinRequestBody,
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, str]:
    request_id = validation.require_user_id(body.request_id)
    decision = validation.require_join_request_decision(body.decision)
    connection = db.get_connection()
    try:
        join_request = connection.execute(
            "select * from gym_join_requests where id = ? and gym_id = ? and status = 'pending'",
            (request_id, session["active_gym_id"]),
        ).fetchone()
        if join_request is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Join request not found.")
        timestamp = security.isoformat(security.now_utc())
        with connection:
            if decision == "approve":
                connection.execute(
                    """
                    insert into gym_memberships (user_id, gym_id, active_role, roles_json, status, created_at, updated_at)
                    values (?, ?, 'athlete', ?, 'active', ?, ?)
                    on conflict(user_id, gym_id) do update set active_role = excluded.active_role, roles_json = excluded.roles_json,
                      status = excluded.status, updated_at = excluded.updated_at
                    """,
                    (join_request["user_id"], join_request["gym_id"], validation.encode_roles(["athlete"]), timestamp, timestamp),
                )
                member_user = connection.execute(
                    "select active_gym_id from users where id = ?",
                    (join_request["user_id"],),
                ).fetchone()
                if member_user is not None and member_user["active_gym_id"] is None:
                    connection.execute(
                        "update users set active_gym_id = ?, updated_at = ? where id = ?",
                        (join_request["gym_id"], timestamp, join_request["user_id"]),
                    )
                membership_service.sync_user_context(connection, join_request["user_id"])
            else:
                plan_service.cancel_open_requests(
                    connection, gym_id=join_request["gym_id"], user_id=join_request["user_id"], status="rejected"
                )
            connection.execute(
                "update gym_join_requests set status = ?, reviewed_at = ?, reviewed_by_user_id = ?, updated_at = ? where id = ?",
                ("approved" if decision == "approve" else "rejected", timestamp, session["user_id"], timestamp, request_id),
            )
            audit.write_audit_log(
                connection,
                gym_id=session["active_gym_id"],
                actor_user_id=session["user_id"],
                target_user_id=join_request["user_id"],
                action="join_request_reviewed",
                entity_type="gym_join_request",
                entity_id=request_id,
                details={"decision": decision, "join_request_id": request_id},
            )
        return {"message": f"Join request {'approved' if decision == 'approve' else 'rejected'}."}
    finally:
        connection.close()


@router.get("/gyms/{gym_id}/plans")
def list_gym_plans_for_join(
    gym_id: int,
    _: dict[str, Any] = Depends(require_session),
) -> dict[str, Any]:
    """The plans a box offers, for athletes choosing one while sending a join request."""
    connection = db.get_connection()
    try:
        gym = plan_service.gym_plan_settings(connection, gym_id)
        rows = plan_service.list_plan_rows(connection, gym_id, gym_timezone=gym["timezone"], include_archived=False)
        plans = [plan_service.plan_payload(row, currency=gym["currency"]) for row in rows]
        for plan in plans:
            plan.pop("active_member_count", None)
        return {"plans": plans, "currency": gym["currency"]}
    finally:
        connection.close()


@router.post("/gyms/{gym_id}/owners")
def add_gym_owner(
    gym_id: int,
    body: AddGymOwnerRequest,
    session: dict[str, Any] = Depends(require_session),
) -> dict[str, Any]:
    user_id = validation.require_user_id(body.user_id)
    connection = db.get_connection()
    try:
        if not membership_service.is_gym_owner(connection, session["user_id"], gym_id):
            raise HTTPException(status_code=HTTPStatus.FORBIDDEN.value, detail="The owner role is required for this action.")
        if user_id == session["user_id"]:
            raise HTTPException(status_code=HTTPStatus.BAD_REQUEST.value, detail="You are already an owner of this box.")
        with connection:
            if not membership_service.make_gym_owner(connection, gym_id=gym_id, user_id=user_id):
                raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Gym member not found.")
            audit.write_audit_log(
                connection,
                gym_id=gym_id,
                actor_user_id=session["user_id"],
                target_user_id=user_id,
                action="gym_owner_added",
                entity_type="gym",
                entity_id=gym_id,
                details={},
            )
        return {"message": "Owner added."}
    finally:
        connection.close()
