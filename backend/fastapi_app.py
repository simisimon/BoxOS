from __future__ import annotations

import json
from contextlib import asynccontextmanager
from http import HTTPStatus
from pathlib import Path
from typing import Any
import secrets
from datetime import datetime, timedelta


from fastapi import Depends, FastAPI, Header, HTTPException, Request
from fastapi.responses import FileResponse
from pydantic import BaseModel

from backend import announcement_service, audit, auth_service, db, membership_service, notifications_core, programming_service, schedule_service, security, settings, session_auth, validation, workout_service


class LoginRequest(BaseModel):
    email: str
    password: str


class RefreshRequest(BaseModel):
    refresh_token: str


class UpdateProfileRequest(BaseModel):
    display_name: str
    nickname: str


class CreateGymRequest(BaseModel):
    name: str
    logo_url: str
    timezone: str


class ScheduleClassRequest(BaseModel):
    title: str
    class_type: str
    start_time: str
    duration_minutes: int | None = None
    duration: int | None = None
    capacity: int
    trainer_user_id: int | None = None
    wod_description: str | None = None
    recurrence_frequency: str | None = None
    occurrence_count: int | None = None


class UpdateScheduleClassRequest(ScheduleClassRequest):
    id: int


class ClassIdRequest(BaseModel):
    class_id: int


class ScheduleClassDeleteRequest(BaseModel):
    id: int


class UpdateAttendanceRequest(BaseModel):
    class_id: int
    user_id: int
    attendance_status: str


class GymIdRequest(BaseModel):
    gym_id: int


class UpdateActiveRoleRequest(BaseModel):
    role: str


class ReviewJoinRequestBody(BaseModel):
    request_id: int
    decision: str


class AssignRoleRequest(BaseModel):
    user_id: int
    role: str | None = None
    roles: list[str] | None = None


class NotificationPreferencesRequest(BaseModel):
    booking_confirmations: bool
    waitlist_promotions: bool
    payment_issues: bool
    wod_posted: bool
    pr_achievements: bool
    announcement_activity: bool


class AnnouncementRequest(BaseModel):
    title: str
    description: str
    image_url: str | None = None


class AnnouncementUpdateRequest(AnnouncementRequest):
    id: int


class AnnouncementIdRequest(BaseModel):
    announcement_id: int


class EntityIdRequest(BaseModel):
    id: int


class AnnouncementCommentRequest(BaseModel):
    announcement_id: int
    body: str


class AnnouncementCommentUpdateRequest(BaseModel):
    id: int
    body: str


class AnnouncementImageUploadRequest(BaseModel):
    filename: str
    content_type: str
    data_base64: str


class PersonalWorkoutRequest(BaseModel):
    title: str
    type: str
    structure: Any


class PersonalWorkoutDeleteRequest(BaseModel):
    id: int


class DailyWorkoutRequest(BaseModel):
    scheduled_date: str
    title: str
    strength_text: str | None = None
    metcon_text: str | None = None
    notes_text: str | None = None


class DailyWorkoutUpdateRequest(DailyWorkoutRequest):
    id: int


class WhiteboardResultRequest(BaseModel):
    workout_id: int
    score_type: str
    score_value: Any
    notes_text: str | None = None


class WorkoutLogRequest(BaseModel):
    workout_id: int
    class_id: int | None = None
    score_type: str
    score_value: Any
    notes_text: str | None = None


@asynccontextmanager
async def lifespan(_: FastAPI):
    db.init_db()
    yield


app = FastAPI(title="BoxOS Backend", version="0.1.0", lifespan=lifespan)


def raise_http_error(error: validation.ApiError) -> None:
    raise HTTPException(status_code=error.status.value, detail=error.message)


def require_bearer_token(authorization: str | None = Header(default=None)) -> str:
    if authorization is None or not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=HTTPStatus.UNAUTHORIZED.value,
            detail="Missing bearer token.",
        )
    return authorization.removeprefix("Bearer ").strip()


def require_session(access_token: str = Depends(require_bearer_token)) -> dict[str, Any]:
    connection = db.get_connection()
    try:
        session = connection.execute(
            """
            select sessions.*, users.email, users.email_verified,
                   users.role, users.roles_json, users.account_type, users.active_gym_id
            from sessions
            join users on users.id = sessions.user_id
            where sessions.access_token_hash = ? and users.deleted_at is null
            """,
            (security.hash_token(access_token),),
        ).fetchone()
        if session is None or security.parse_iso(session["access_expires_at"]) <= security.now_utc():
            with connection:
                connection.execute(
                    "delete from sessions where access_token_hash = ?",
                    (security.hash_token(access_token),),
                )
            raise HTTPException(
                status_code=HTTPStatus.UNAUTHORIZED.value,
                detail="Session expired.",
            )
        return dict(session)
    finally:
        connection.close()


def require_admin_session(session: dict[str, Any] = Depends(require_session)) -> dict[str, Any]:
    if session["role"] != "admin":
        raise HTTPException(
            status_code=HTTPStatus.FORBIDDEN.value,
            detail="The admin role is required for this action.",
        )
    return session


def require_active_gym_member_session(
    session: dict[str, Any] = Depends(require_session),
) -> dict[str, Any]:
    if session["active_gym_id"] is None:
        raise HTTPException(
            status_code=HTTPStatus.FORBIDDEN.value,
            detail="An active gym context is required.",
        )
    connection = db.get_connection()
    try:
        membership = connection.execute(
            """
            select id from gym_memberships
            where user_id = ? and gym_id = ? and status = 'active'
            """,
            (session["user_id"], session["active_gym_id"]),
        ).fetchone()
    finally:
        connection.close()
    if membership is None:
        raise HTTPException(
            status_code=HTTPStatus.FORBIDDEN.value,
            detail="You are not an active member of the selected gym.",
        )
    return session


def require_schedule_manager_session(
    session: dict[str, Any] = Depends(require_active_gym_member_session),
) -> dict[str, Any]:
    if session["role"] not in {"admin", "trainer"}:
        raise HTTPException(
            status_code=HTTPStatus.FORBIDDEN.value,
            detail="The admin or trainer role is required for this action.",
        )
    return session


def require_admin_gym_session(
    session: dict[str, Any] = Depends(require_session),
) -> dict[str, Any]:
    if session["role"] != "admin":
        raise HTTPException(
            status_code=HTTPStatus.FORBIDDEN.value,
            detail="The admin role is required for this action.",
        )
    if session["active_gym_id"] is None:
        raise HTTPException(
            status_code=HTTPStatus.FORBIDDEN.value,
            detail="An active admin gym context is required.",
        )
    return session


def _signup(body: dict[str, Any], *, account_type: str) -> dict[str, Any]:
    email = validation.require_email(body.get("email"))
    password = validation.require_password(body.get("password"))
    normalized_account_type = validation.require_account_type(account_type)
    connection = db.get_connection()
    try:
        existing = connection.execute(
            "select id from users where email = ? and deleted_at is null",
            (email,),
        ).fetchone()
        if existing is not None:
            raise HTTPException(status_code=HTTPStatus.CONFLICT.value, detail="Email is already registered.")
        timestamp = security.isoformat(security.now_utc())
        with connection:
            cursor = connection.execute(
                """
                insert into users (email, password_hash, email_verified, role, roles_json, account_type, created_at, updated_at)
                values (?, ?, 0, ?, ?, ?, ?, ?)
                """,
                (
                    email,
                    security.hash_password(password),
                    "admin" if normalized_account_type == "admin" else "athlete",
                    validation.encode_roles(["admin"] if normalized_account_type == "admin" else ["athlete"]),
                    normalized_account_type,
                    timestamp,
                    timestamp,
                ),
            )
            user_id = int(cursor.lastrowid)
            token = auth_service.issue_verification_token(connection, user_id)
        print(f"[boxos-backend] Verification token for {email}: {token}")
        return {"message": "Account created. Check the backend log for the verification token."}
    finally:
        connection.close()


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/auth/login")
def login(body: LoginRequest) -> dict[str, str]:
    email = validation.require_email(body.email)
    password = validation.require_password(body.password)
    connection = db.get_connection()
    try:
        user = connection.execute(
            "select * from users where email = ? and deleted_at is null",
            (email,),
        ).fetchone()
        if user is None or not security.verify_password(password, user["password_hash"]):
            raise HTTPException(
                status_code=HTTPStatus.UNAUTHORIZED.value,
                detail="Invalid email or password.",
            )
        if not user["email_verified"]:
            raise HTTPException(
                status_code=HTTPStatus.FORBIDDEN.value,
                detail="Verify your email before signing in.",
            )
        with connection:
            membership_service.sync_user_context(connection, user["id"])
            return auth_service.create_session(connection, user["id"])
    finally:
        connection.close()


@app.post("/auth/refresh")
def refresh(body: RefreshRequest) -> dict[str, str]:
    refresh_token = validation.require_token(body.refresh_token, label="Refresh token")
    connection = db.get_connection()
    try:
        session = connection.execute(
            "select * from sessions where refresh_token_hash = ?",
            (security.hash_token(refresh_token),),
        ).fetchone()
        if session is None or security.parse_iso(session["refresh_expires_at"]) <= security.now_utc():
            with connection:
                connection.execute(
                    "delete from sessions where refresh_token_hash = ?",
                    (security.hash_token(refresh_token),),
                )
            raise HTTPException(
                status_code=HTTPStatus.UNAUTHORIZED.value,
                detail="Session refresh failed.",
            )
        with connection:
            membership_service.sync_user_context(connection, session["user_id"])
            connection.execute("delete from sessions where id = ?", (session["id"],))
            return auth_service.create_session(connection, session["user_id"])
    finally:
        connection.close()


@app.get("/auth/session")
def auth_session(session: dict[str, Any] = Depends(require_session)) -> dict[str, Any]:
    connection = db.get_connection()
    try:
        active_membership = membership_service.get_active_membership(connection, session["user_id"])
        memberships = membership_service.list_user_memberships(connection, session["user_id"])
        return {
            "email": session["email"],
            "email_verified": bool(session["email_verified"]),
            "role": session["role"],
            "available_roles": validation.decode_roles(session["roles_json"]),
            "account_type": session["account_type"],
            "active_gym": membership_service.active_gym_payload(active_membership),
            "memberships": [membership_service.membership_payload(row) for row in memberships],
        }
    finally:
        connection.close()


@app.get("/profile")
def get_profile(session: dict[str, Any] = Depends(require_session)) -> dict[str, Any]:
    connection = db.get_connection()
    try:
        user = connection.execute(
            """
            select id, email, role, roles_json, display_name, nickname, account_type, active_gym_id
            from users
            where id = ? and deleted_at is null
            """,
            (session["user_id"],),
        ).fetchone()
        if user is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Profile not found.")
        return membership_service.profile_payload(user)
    finally:
        connection.close()


@app.patch("/profile")
def update_profile(
    body: UpdateProfileRequest,
    session: dict[str, Any] = Depends(require_session),
) -> dict[str, Any]:
    try:
        display_name = validation.require_display_name(body.display_name)
        nickname = validation.require_nickname(body.nickname)
    except validation.ApiError as error:
        raise_http_error(error)
    connection = db.get_connection()
    try:
        with connection:
            connection.execute(
                """
                update users
                set display_name = ?, nickname = ?, updated_at = ?
                where id = ? and deleted_at is null
                """,
                (display_name, nickname, security.isoformat(security.now_utc()), session["user_id"]),
            )
        user = connection.execute(
            "select id, email, role, roles_json, display_name, nickname, account_type, active_gym_id from users where id = ?",
            (session["user_id"],),
        ).fetchone()
        if user is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Profile not found.")
        return membership_service.profile_payload(user)
    finally:
        connection.close()


@app.patch("/profile/active-role")
def update_active_role(
    body: UpdateActiveRoleRequest,
    session: dict[str, Any] = Depends(require_session),
) -> dict[str, Any]:
    try:
        role = validation.require_role_value(body.role)
    except validation.ApiError as error:
        raise_http_error(error)
    assigned_roles = validation.decode_roles(session["roles_json"])
    if role not in assigned_roles:
        raise HTTPException(
            status_code=HTTPStatus.BAD_REQUEST.value,
            detail="The selected role is not assigned to this user.",
        )
    connection = db.get_connection()
    try:
        with connection:
            membership = membership_service.get_active_membership(connection, session["user_id"])
            if membership is not None:
                connection.execute(
                    "update gym_memberships set active_role = ?, updated_at = ? where id = ?",
                    (role, security.isoformat(security.now_utc()), membership["id"]),
                )
                membership_service.sync_user_context(connection, session["user_id"])
            else:
                connection.execute(
                    "update users set role = ?, updated_at = ? where id = ? and deleted_at is null",
                    (role, security.isoformat(security.now_utc()), session["user_id"]),
                )
        user = connection.execute(
            "select id, email, role, roles_json, display_name, nickname, account_type, active_gym_id from users where id = ?",
            (session["user_id"],),
        ).fetchone()
        if user is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Profile not found.")
        return membership_service.profile_payload(user)
    finally:
        connection.close()


@app.patch("/profile/active-gym")
def update_active_gym(
    body: GymIdRequest,
    session: dict[str, Any] = Depends(require_session),
) -> dict[str, Any]:
    gym_id = body.gym_id
    connection = db.get_connection()
    try:
        membership = connection.execute(
            "select id from gym_memberships where user_id = ? and gym_id = ? and status = 'active'",
            (session["user_id"], gym_id),
        ).fetchone()
        if membership is None:
            raise HTTPException(status_code=HTTPStatus.BAD_REQUEST.value, detail="You are not an active member of that gym.")
        with connection:
            connection.execute(
                "update users set active_gym_id = ?, updated_at = ? where id = ?",
                (gym_id, security.isoformat(security.now_utc()), session["user_id"]),
            )
            membership_service.sync_user_context(connection, session["user_id"])
        user = connection.execute(
            "select id, email, role, roles_json, display_name, nickname, account_type, active_gym_id from users where id = ?",
            (session["user_id"],),
        ).fetchone()
        if user is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Profile not found.")
        return membership_service.profile_payload(user)
    finally:
        connection.close()


@app.get("/profile/notifications")
def get_notification_preferences(
    session: dict[str, Any] = Depends(require_session),
) -> dict[str, bool]:
    connection = db.get_connection()
    try:
        user = connection.execute(
            """
            select notify_booking_confirmations, notify_waitlist_promotions, notify_payment_issues,
                   notify_wod_posted, notify_pr_achievements, notify_announcement_activity
            from users where id = ? and deleted_at is null
            """,
            (session["user_id"],),
        ).fetchone()
        if user is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Notification preferences not found.")
        return notifications_core.notification_preferences_payload(user)
    finally:
        connection.close()


@app.patch("/profile/notifications")
def update_notification_preferences(
    body: NotificationPreferencesRequest,
    session: dict[str, Any] = Depends(require_session),
) -> dict[str, bool]:
    payload = body.model_dump()
    try:
        preferences = validation.require_notification_preferences(payload)
    except validation.ApiError as error:
        raise_http_error(error)
    connection = db.get_connection()
    try:
        with connection:
            connection.execute(
                """
                update users
                set notify_booking_confirmations = ?, notify_waitlist_promotions = ?, notify_payment_issues = ?,
                    notify_wod_posted = ?, notify_pr_achievements = ?, notify_announcement_activity = ?, updated_at = ?
                where id = ? and deleted_at is null
                """,
                (
                    int(preferences["booking_confirmations"]),
                    int(preferences["waitlist_promotions"]),
                    int(preferences["payment_issues"]),
                    int(preferences["wod_posted"]),
                    int(preferences["pr_achievements"]),
                    int(preferences["announcement_activity"]),
                    security.isoformat(security.now_utc()),
                    session["user_id"],
                ),
            )
        user = connection.execute(
            """
            select notify_booking_confirmations, notify_waitlist_promotions, notify_payment_issues,
                   notify_wod_posted, notify_pr_achievements, notify_announcement_activity
            from users where id = ? and deleted_at is null
            """,
            (session["user_id"],),
        ).fetchone()
        if user is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Notification preferences not found.")
        return notifications_core.notification_preferences_payload(user)
    finally:
        connection.close()


@app.get("/notifications")
def list_notifications(
    session: dict[str, Any] = Depends(require_session),
) -> dict[str, Any]:
    connection = db.get_connection()
    try:
        rows = connection.execute(
            "select id, user_id, gym_id, type, title, body, entity_type, entity_id, read_at, created_at from notifications where user_id = ? order by created_at desc, id desc limit 50",
            (session["user_id"],),
        ).fetchall()
        unread_count = connection.execute(
            "select count(*) as count from notifications where user_id = ? and read_at is null",
            (session["user_id"],),
        ).fetchone()["count"]
        return {"unread_count": unread_count, "notifications": [announcement_service.notification_payload(row) for row in rows]}
    finally:
        connection.close()


@app.patch("/notifications/read-all")
def mark_notifications_read(
    session: dict[str, Any] = Depends(require_session),
) -> dict[str, Any]:
    connection = db.get_connection()
    try:
        with connection:
            connection.execute(
                "update notifications set read_at = ? where user_id = ? and read_at is null",
                (security.isoformat(security.now_utc()), session["user_id"]),
            )
        rows = connection.execute(
            "select id, user_id, gym_id, type, title, body, entity_type, entity_id, read_at, created_at from notifications where user_id = ? order by created_at desc, id desc limit 50",
            (session["user_id"],),
        ).fetchall()
        return {"unread_count": 0, "notifications": [announcement_service.notification_payload(row) for row in rows]}
    finally:
        connection.close()


@app.get("/gyms")
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


@app.post("/gyms", status_code=HTTPStatus.CREATED.value)
def create_gym(
    body: CreateGymRequest,
    session: dict[str, Any] = Depends(require_admin_session),
) -> dict[str, Any]:
    try:
        name = validation.require_gym_name(body.name)
        logo_url = validation.require_logo_url(body.logo_url)
        timezone = validation.require_timezone(body.timezone)
    except validation.ApiError as error:
        raise_http_error(error)

    connection = db.get_connection()
    try:
        with connection:
            slug = membership_service.unique_gym_slug(connection, name)
            timestamp = security.isoformat(security.now_utc())
            cursor = connection.execute(
                """
                insert into gyms (name, slug, logo_url, timezone, created_by_user_id, created_at, updated_at)
                values (?, ?, ?, ?, ?, ?, ?)
                """,
                (name, slug, logo_url, timezone, session["user_id"], timestamp, timestamp),
            )
            gym_id = int(cursor.lastrowid)
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


@app.post("/gyms/join-requests", status_code=HTTPStatus.CREATED.value)
def create_join_request(
    body: GymIdRequest,
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
        timestamp = security.isoformat(security.now_utc())
        with connection:
            connection.execute(
                "insert into gym_join_requests (user_id, gym_id, status, created_at, updated_at) values (?, ?, 'pending', ?, ?)",
                (session["user_id"], gym_id, timestamp, timestamp),
            )
        return {"message": "Join request submitted."}
    finally:
        connection.close()


@app.get("/gyms/join-requests")
def list_join_requests(
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, list[dict[str, Any]]]:
    connection = db.get_connection()
    try:
        rows = connection.execute(
            """
            select gym_join_requests.id, gym_join_requests.created_at, users.email, users.display_name, users.nickname
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
                }
                for row in rows
            ]
        }
    finally:
        connection.close()


@app.get("/gyms/my-requests")
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


@app.patch("/gyms/join-requests")
def review_join_request(
    body: ReviewJoinRequestBody,
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, str]:
    try:
        request_id = validation.require_user_id(body.request_id)
        decision = validation.require_join_request_decision(body.decision)
    except validation.ApiError as error:
        raise_http_error(error)
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


@app.get("/roles/users")
def list_role_users(
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, list[dict[str, Any]]]:
    connection = db.get_connection()
    try:
        rows = connection.execute(
            """
            select gym_memberships.id, gym_memberships.user_id, gym_memberships.active_role, gym_memberships.roles_json,
                   users.email, users.display_name, users.nickname
            from gym_memberships
            join users on users.id = gym_memberships.user_id
            where gym_memberships.gym_id = ? and gym_memberships.status = 'active' and users.deleted_at is null
            order by case gym_memberships.active_role when 'admin' then 0 when 'trainer' then 1 else 2 end,
                     lower(coalesce(nullif(users.display_name, ''), users.email)) asc
            """,
            (session["active_gym_id"],),
        ).fetchall()
        return {"users": [membership_service.role_managed_member_payload(row) for row in rows]}
    finally:
        connection.close()


@app.patch("/roles/users")
def assign_role(
    body: AssignRoleRequest,
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, Any]:
    payload = body.model_dump(exclude_none=True)
    try:
        user_id = validation.require_user_id(body.user_id)
        roles = validation.require_role_list(payload)
    except validation.ApiError as error:
        raise_http_error(error)
    managed_roles = [role for role in roles if role in {"athlete", "trainer"}]
    if not managed_roles:
        raise HTTPException(status_code=HTTPStatus.BAD_REQUEST.value, detail="Managed roles must include athlete or trainer.")
    connection = db.get_connection()
    try:
        membership_before = connection.execute(
            "select id, active_role from gym_memberships where user_id = ? and gym_id = ? and status = 'active'",
            (user_id, session["active_gym_id"]),
        ).fetchone()
        if membership_before is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Gym member not found.")
        if membership_before["active_role"] == "admin":
            raise HTTPException(status_code=HTTPStatus.FORBIDDEN.value, detail="Admin memberships cannot be changed from this screen.")
        active_role = membership_before["active_role"] if membership_before["active_role"] in managed_roles else managed_roles[0]
        with connection:
            updated = connection.execute(
                "update gym_memberships set active_role = ?, roles_json = ?, updated_at = ? where id = ?",
                (active_role, validation.encode_roles(managed_roles), security.isoformat(security.now_utc()), membership_before["id"]),
            )
            membership_service.sync_user_context(connection, user_id)
            audit.write_audit_log(
                connection,
                gym_id=session["active_gym_id"],
                actor_user_id=session["user_id"],
                target_user_id=user_id,
                action="gym_member_roles_updated",
                entity_type="gym_membership",
                entity_id=membership_before["id"],
                details={"roles": managed_roles, "active_role": active_role},
            )
        if updated.rowcount == 0:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Gym member not found.")
        user = connection.execute(
            """
            select gym_memberships.id, gym_memberships.user_id, gym_memberships.active_role, gym_memberships.roles_json,
                   users.email, users.display_name, users.nickname
            from gym_memberships
            join users on users.id = gym_memberships.user_id
            where gym_memberships.id = ? and users.deleted_at is null
            """,
            (membership_before["id"],),
        ).fetchone()
        if user is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Gym member not found.")
        return membership_service.role_managed_member_payload(user)
    finally:
        connection.close()


@app.get("/announcements")
def list_announcements(
    session: dict[str, Any] = Depends(require_active_gym_member_session),
) -> dict[str, list[dict[str, Any]]]:
    connection = db.get_connection()
    try:
        rows = connection.execute(
            """
            select announcements.id, announcements.gym_id, announcements.title, announcements.description,
                   announcements.image_url, announcements.created_by_user_id, announcements.created_at, announcements.updated_at,
                   users.display_name as author_display_name, users.nickname as author_nickname, users.email as author_email
            from announcements
            join users on users.id = announcements.created_by_user_id
            where announcements.gym_id = ?
            order by announcements.created_at desc, announcements.id desc
            """,
            (session["active_gym_id"],),
        ).fetchall()
        return {
            "announcements": [
                announcement_service.announcement_payload(
                    connection,
                    row,
                    current_user_id=session["user_id"],
                    session_role=str(session["role"]),
                )
                for row in rows
            ]
        }
    finally:
        connection.close()


@app.post("/announcements", status_code=HTTPStatus.CREATED.value)
def create_announcement(
    body: AnnouncementRequest,
    session: dict[str, Any] = Depends(require_schedule_manager_session),
) -> dict[str, Any]:
    try:
        title = validation.require_announcement_title(body.title)
        description = validation.require_announcement_description(body.description)
        image_url = validation.require_optional_image_url(body.image_url)
    except validation.ApiError as error:
        raise_http_error(error)
    connection = db.get_connection()
    try:
        timestamp = security.isoformat(security.now_utc())
        with connection:
            cursor = connection.execute(
                "insert into announcements (gym_id, title, description, image_url, created_by_user_id, created_at, updated_at) values (?, ?, ?, ?, ?, ?, ?)",
                (session["active_gym_id"], title, description, image_url, session["user_id"], timestamp, timestamp),
            )
            row = announcement_service.get_announcement_row(connection, announcement_id=int(cursor.lastrowid), gym_id=session["active_gym_id"])
            if row is None:
                raise HTTPException(status_code=HTTPStatus.INTERNAL_SERVER_ERROR.value, detail="Announcement creation failed.")
            audit.write_audit_log(
                connection,
                gym_id=session["active_gym_id"],
                actor_user_id=session["user_id"],
                action="announcement_created",
                entity_type="announcement",
                entity_id=int(cursor.lastrowid),
                details={"title": title, "has_image": bool(image_url)},
            )
        return {"announcement": announcement_service.announcement_payload(connection, row, current_user_id=session["user_id"], session_role=str(session["role"]))}
    finally:
        connection.close()


@app.post("/announcements/image", status_code=HTTPStatus.CREATED.value)
def upload_announcement_image(
    body: AnnouncementImageUploadRequest,
    _: dict[str, Any] = Depends(require_schedule_manager_session),
) -> dict[str, str]:
    try:
        filename = validation.require_upload_filename(body.filename)
        content_type = validation.require_announcement_image_content_type(body.content_type)
        raw_bytes = validation.require_base64_bytes(body.data_base64, label="Image data", max_bytes=settings.MAX_ANNOUNCEMENT_IMAGE_BYTES)
    except validation.ApiError as error:
        raise_http_error(error)
    extension = settings.ALLOWED_ANNOUNCEMENT_IMAGE_CONTENT_TYPES[content_type]
    stored_name = f"announcement_{secrets.token_urlsafe(12)}{extension}"
    file_path = settings.ANNOUNCEMENT_UPLOADS_DIR / stored_name
    file_path.write_bytes(raw_bytes)
    return {"filename": filename, "image_url": f"/uploads/announcements/{stored_name}"}


@app.patch("/announcements")
def update_announcement(
    body: AnnouncementUpdateRequest,
    session: dict[str, Any] = Depends(require_schedule_manager_session),
) -> dict[str, Any]:
    try:
        announcement_id = validation.require_user_id(body.id)
        title = validation.require_announcement_title(body.title)
        description = validation.require_announcement_description(body.description)
        image_url = validation.require_optional_image_url(body.image_url)
    except validation.ApiError as error:
        raise_http_error(error)
    connection = db.get_connection()
    try:
        existing = connection.execute(
            "select id, created_by_user_id from announcements where id = ? and gym_id = ?",
            (announcement_id, session["active_gym_id"]),
        ).fetchone()
        if existing is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Announcement not found.")
        try:
            announcement_service.ensure_announcement_manage_permission(existing, session)
        except validation.ApiError as error:
            raise_http_error(error)
        with connection:
            connection.execute(
                "update announcements set title = ?, description = ?, image_url = ?, updated_at = ? where id = ? and gym_id = ?",
                (title, description, image_url, security.isoformat(security.now_utc()), announcement_id, session["active_gym_id"]),
            )
            row = announcement_service.get_announcement_row(connection, announcement_id=announcement_id, gym_id=session["active_gym_id"])
            if row is None:
                raise HTTPException(status_code=HTTPStatus.INTERNAL_SERVER_ERROR.value, detail="Announcement update failed.")
            audit.write_audit_log(connection, gym_id=session["active_gym_id"], actor_user_id=session["user_id"], action="announcement_updated", entity_type="announcement", entity_id=announcement_id, details={"title": title, "has_image": bool(image_url)})
        return {"announcement": announcement_service.announcement_payload(connection, row, current_user_id=session["user_id"], session_role=str(session["role"]))}
    finally:
        connection.close()


@app.delete("/announcements")
def delete_announcement(
    body: EntityIdRequest,
    session: dict[str, Any] = Depends(require_schedule_manager_session),
) -> dict[str, bool]:
    announcement_id = body.id
    connection = db.get_connection()
    try:
        existing = connection.execute(
            "select id, title, created_by_user_id from announcements where id = ? and gym_id = ?",
            (announcement_id, session["active_gym_id"]),
        ).fetchone()
        if existing is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Announcement not found.")
        try:
            announcement_service.ensure_announcement_manage_permission(existing, session)
        except validation.ApiError as error:
            raise_http_error(error)
        with connection:
            connection.execute("delete from announcements where id = ? and gym_id = ?", (announcement_id, session["active_gym_id"]))
            audit.write_audit_log(connection, gym_id=session["active_gym_id"], actor_user_id=session["user_id"], action="announcement_deleted", entity_type="announcement", entity_id=announcement_id, details={"title": existing["title"]})
        return {"deleted": True}
    finally:
        connection.close()


@app.post("/announcements/likes")
def like_announcement(
    body: AnnouncementIdRequest,
    session: dict[str, Any] = Depends(require_active_gym_member_session),
) -> dict[str, Any]:
    announcement_id = body.announcement_id
    connection = db.get_connection()
    try:
        announcement = announcement_service.get_announcement_row(connection, announcement_id=announcement_id, gym_id=session["active_gym_id"])
        if announcement is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Announcement not found.")
        with connection:
            cursor = connection.execute(
                "insert or ignore into announcement_likes (announcement_id, user_id, created_at) values (?, ?, ?)",
                (announcement_id, session["user_id"], security.isoformat(security.now_utc())),
            )
            if cursor.rowcount:
                announcement_service.create_announcement_like_notification(connection, recipient_user_id=int(announcement["created_by_user_id"]), actor_user_id=int(session["user_id"]), gym_id=int(session["active_gym_id"]), announcement_id=announcement_id, announcement_title=str(announcement["title"]))
        refreshed = announcement_service.get_announcement_row(connection, announcement_id=announcement_id, gym_id=session["active_gym_id"])
        return {"announcement": announcement_service.announcement_payload(connection, refreshed, current_user_id=session["user_id"], session_role=str(session["role"]))}
    finally:
        connection.close()


@app.delete("/announcements/likes")
def unlike_announcement(
    body: AnnouncementIdRequest,
    session: dict[str, Any] = Depends(require_active_gym_member_session),
) -> dict[str, Any]:
    announcement_id = body.announcement_id
    connection = db.get_connection()
    try:
        announcement = announcement_service.get_announcement_row(connection, announcement_id=announcement_id, gym_id=session["active_gym_id"])
        if announcement is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Announcement not found.")
        with connection:
            connection.execute("delete from announcement_likes where announcement_id = ? and user_id = ?", (announcement_id, session["user_id"]))
        refreshed = announcement_service.get_announcement_row(connection, announcement_id=announcement_id, gym_id=session["active_gym_id"])
        return {"announcement": announcement_service.announcement_payload(connection, refreshed, current_user_id=session["user_id"], session_role=str(session["role"]))}
    finally:
        connection.close()


@app.post("/announcements/comments", status_code=HTTPStatus.CREATED.value)
def create_announcement_comment(
    body: AnnouncementCommentRequest,
    session: dict[str, Any] = Depends(require_active_gym_member_session),
) -> dict[str, Any]:
    try:
        announcement_id = validation.require_user_id(body.announcement_id)
        comment_body = validation.require_announcement_comment_body(body.body)
    except validation.ApiError as error:
        raise_http_error(error)
    connection = db.get_connection()
    try:
        announcement = announcement_service.get_announcement_row(connection, announcement_id=announcement_id, gym_id=session["active_gym_id"])
        if announcement is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Announcement not found.")
        timestamp = security.isoformat(security.now_utc())
        with connection:
            cursor = connection.execute(
                "insert into announcement_comments (announcement_id, gym_id, user_id, body, created_at, updated_at) values (?, ?, ?, ?, ?, ?)",
                (announcement_id, session["active_gym_id"], session["user_id"], comment_body, timestamp, timestamp),
            )
            comment = announcement_service.get_announcement_comment_row(connection, int(cursor.lastrowid))
            if comment is None:
                raise HTTPException(status_code=HTTPStatus.INTERNAL_SERVER_ERROR.value, detail="Comment creation failed.")
            announcement_service.create_announcement_comment_notification(connection, recipient_user_id=int(announcement["created_by_user_id"]), actor_user_id=int(session["user_id"]), gym_id=int(session["active_gym_id"]), announcement_id=announcement_id, announcement_title=str(announcement["title"]), comment_body=comment_body)
            audit.write_audit_log(connection, gym_id=session["active_gym_id"], actor_user_id=session["user_id"], action="announcement_comment_created", entity_type="announcement_comment", entity_id=int(cursor.lastrowid), details={"announcement_id": announcement_id})
        return {"comment": announcement_service.announcement_comment_payload(comment, current_user_id=session["user_id"], session_role=str(session["role"]))}
    finally:
        connection.close()


@app.patch("/announcements/comments")
def update_announcement_comment(
    body: AnnouncementCommentUpdateRequest,
    session: dict[str, Any] = Depends(require_active_gym_member_session),
) -> dict[str, Any]:
    try:
        comment_id = validation.require_user_id(body.id)
        comment_body = validation.require_announcement_comment_body(body.body)
    except validation.ApiError as error:
        raise_http_error(error)
    connection = db.get_connection()
    try:
        existing = announcement_service.get_announcement_comment_row(connection, comment_id)
        if existing is None or int(existing["gym_id"]) != int(session["active_gym_id"]):
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Comment not found.")
        try:
            announcement_service.ensure_announcement_comment_manage_permission(existing, session)
        except validation.ApiError as error:
            raise_http_error(error)
        with connection:
            connection.execute("update announcement_comments set body = ?, updated_at = ? where id = ?", (comment_body, security.isoformat(security.now_utc()), comment_id))
            comment = announcement_service.get_announcement_comment_row(connection, comment_id)
            if comment is None:
                raise HTTPException(status_code=HTTPStatus.INTERNAL_SERVER_ERROR.value, detail="Comment update failed.")
            audit.write_audit_log(connection, gym_id=session["active_gym_id"], actor_user_id=session["user_id"], action="announcement_comment_updated", entity_type="announcement_comment", entity_id=comment_id, details={"announcement_id": existing["announcement_id"]})
        return {"comment": announcement_service.announcement_comment_payload(comment, current_user_id=session["user_id"], session_role=str(session["role"]))}
    finally:
        connection.close()


@app.delete("/announcements/comments")
def delete_announcement_comment(
    body: EntityIdRequest,
    session: dict[str, Any] = Depends(require_active_gym_member_session),
) -> dict[str, bool]:
    comment_id = body.id
    connection = db.get_connection()
    try:
        existing = announcement_service.get_announcement_comment_row(connection, comment_id)
        if existing is None or int(existing["gym_id"]) != int(session["active_gym_id"]):
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Comment not found.")
        try:
            announcement_service.ensure_announcement_comment_manage_permission(existing, session)
        except validation.ApiError as error:
            raise_http_error(error)
        with connection:
            connection.execute("delete from announcement_comments where id = ?", (comment_id,))
            audit.write_audit_log(connection, gym_id=session["active_gym_id"], actor_user_id=session["user_id"], action="announcement_comment_deleted", entity_type="announcement_comment", entity_id=comment_id, details={"announcement_id": existing["announcement_id"]})
        return {"deleted": True}
    finally:
        connection.close()


@app.get("/schedule/classes")
def list_schedule_classes(
    session: dict[str, Any] = Depends(require_active_gym_member_session),
) -> dict[str, list[dict[str, Any]]]:
    connection = db.get_connection()
    try:
        include_bookings = session["role"] in {"admin", "trainer"}
        rows = connection.execute(
            """
            select
              class_schedules.id,
              class_schedules.gym_id,
              class_schedules.title,
              class_schedules.class_type,
              class_schedules.start_time,
              class_schedules.end_time,
              class_schedules.duration_minutes,
              class_schedules.capacity,
              class_schedules.assigned_trainer_user_id,
              trainer.display_name as assigned_trainer_display_name,
              trainer.nickname as assigned_trainer_nickname,
              class_schedules.wod_description
            from class_schedules
            left join users trainer on trainer.id = class_schedules.assigned_trainer_user_id
            where class_schedules.gym_id = ?
            order by start_time asc
            """,
            (session["active_gym_id"],),
        ).fetchall()
        return {
            "classes": [
                schedule_service.schedule_class_payload(
                    connection,
                    row,
                    current_user_id=session["user_id"],
                    include_bookings=include_bookings,
                )
                for row in rows
            ]
        }
    finally:
        connection.close()


@app.get("/schedule/trainers")
def list_schedule_trainers(
    session: dict[str, Any] = Depends(require_schedule_manager_session),
) -> dict[str, list[dict[str, Any]]]:
    connection = db.get_connection()
    try:
        rows = connection.execute(
            """
            select users.id, users.display_name, users.nickname
            from gym_memberships
            join users on users.id = gym_memberships.user_id
            where gym_memberships.gym_id = ?
              and gym_memberships.status = 'active'
              and gym_memberships.active_role = 'trainer'
              and users.deleted_at is null
            order by lower(coalesce(nullif(users.display_name, ''), users.email)) asc
            """,
            (session["active_gym_id"],),
        ).fetchall()
        return {
            "trainers": [
                {
                    "id": row["id"],
                    "display_name": row["display_name"],
                    "nickname": row["nickname"],
                }
                for row in rows
            ]
        }
    finally:
        connection.close()


@app.post("/schedule/classes", status_code=HTTPStatus.CREATED.value)
def create_schedule_class(
    body: ScheduleClassRequest,
    session: dict[str, Any] = Depends(require_schedule_manager_session),
) -> dict[str, Any]:
    try:
        title = validation.require_schedule_title(body.title)
        class_type = validation.require_class_type(body.class_type)
        start_time = validation.require_future_datetime(body.start_time, label="Start time")
        duration_minutes = validation.require_schedule_duration_minutes(body.model_dump())
        capacity = validation.require_capacity(body.capacity)
        trainer_user_id = validation.require_optional_user_id(body.trainer_user_id)
        wod_description = validation.require_wod_description(body.wod_description)
        recurrence_frequency = validation.require_recurrence_frequency(body.recurrence_frequency)
        occurrence_count = validation.require_occurrence_count(
            body.occurrence_count,
            recurrence_frequency=recurrence_frequency,
        )
    except validation.ApiError as error:
        raise_http_error(error)
    connection = db.get_connection()
    try:
        gym_row = connection.execute(
            "select timezone from gyms where id = ?",
            (session["active_gym_id"],),
        ).fetchone()
        if gym_row is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Active gym not found.")
        try:
            start_times = schedule_service.build_recurrence_start_times(
                start_time,
                recurrence_frequency=recurrence_frequency,
                occurrence_count=occurrence_count,
                gym_timezone=gym_row["timezone"],
            )
        except validation.ApiError as error:
            raise_http_error(error)
        if recurrence_frequency != "none":
            for generated_start_time in start_times:
                if generated_start_time <= security.now_utc():
                    raise HTTPException(
                        status_code=HTTPStatus.BAD_REQUEST.value,
                        detail="Recurring classes must all be scheduled in the future.",
                    )
        if trainer_user_id is not None:
            assigned_trainer = connection.execute(
                """
                select users.id
                from gym_memberships
                join users on users.id = gym_memberships.user_id
                where gym_memberships.gym_id = ?
                  and gym_memberships.user_id = ?
                  and gym_memberships.status = 'active'
                  and gym_memberships.active_role = 'trainer'
                  and users.deleted_at is null
                """,
                (session["active_gym_id"], trainer_user_id),
            ).fetchone()
            if assigned_trainer is None:
                raise HTTPException(status_code=HTTPStatus.BAD_REQUEST.value, detail="Selected trainer is not active in this gym.")
        timestamp = security.isoformat(security.now_utc())
        with connection:
            schedule_ids: list[int] = []
            for generated_start_time in start_times:
                generated_end_time = generated_start_time + timedelta(minutes=duration_minutes)
                cursor = connection.execute(
                    """
                    insert into class_schedules (
                      gym_id, title, class_type, start_time, end_time, duration_minutes, capacity, assigned_trainer_user_id, wod_description,
                      created_by_user_id, updated_by_user_id, created_at, updated_at
                    )
                    values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        session["active_gym_id"],
                        title,
                        class_type,
                        security.isoformat(generated_start_time),
                        security.isoformat(generated_end_time),
                        duration_minutes,
                        capacity,
                        trainer_user_id,
                        wod_description,
                        session["user_id"],
                        session["user_id"],
                        timestamp,
                        timestamp,
                    ),
                )
                schedule_ids.append(int(cursor.lastrowid))
            payloads = []
            for schedule_id in schedule_ids:
                row = schedule_service.get_schedule_class_row(connection, schedule_id)
                if row is None:
                    raise HTTPException(status_code=HTTPStatus.INTERNAL_SERVER_ERROR.value, detail="Schedule class creation failed.")
                payloads.append(
                    schedule_service.schedule_class_payload(
                        connection,
                        row,
                        current_user_id=session["user_id"],
                        include_bookings=session["role"] in {"admin", "trainer"},
                    )
                )
            for schedule_id, generated_start_time in zip(schedule_ids, start_times, strict=True):
                audit.write_audit_log(
                    connection,
                    gym_id=session["active_gym_id"],
                    actor_user_id=session["user_id"],
                    action="schedule_class_created",
                    entity_type="schedule_class",
                    entity_id=schedule_id,
                    details={
                        "title": title,
                        "class_type": class_type,
                        "start_time": security.isoformat(generated_start_time),
                        "duration_minutes": duration_minutes,
                        "capacity": capacity,
                        "trainer_user_id": trainer_user_id,
                        "recurrence_frequency": recurrence_frequency,
                        "occurrence_count": occurrence_count,
                    },
                )
        return {"class": payloads[0], "classes": payloads, "created_count": len(payloads)}
    finally:
        connection.close()


@app.patch("/schedule/classes")
def update_schedule_class(
    body: UpdateScheduleClassRequest,
    session: dict[str, Any] = Depends(require_schedule_manager_session),
) -> dict[str, Any]:
    try:
        schedule_id = validation.require_user_id(body.id)
        title = validation.require_schedule_title(body.title)
        class_type = validation.require_class_type(body.class_type)
        start_time = validation.require_future_datetime(body.start_time, label="Start time")
        duration_minutes = validation.require_schedule_duration_minutes(body.model_dump())
        capacity = validation.require_capacity(body.capacity)
        trainer_user_id = validation.require_optional_user_id(body.trainer_user_id)
        wod_description = validation.require_wod_description(body.wod_description)
    except validation.ApiError as error:
        raise_http_error(error)
    end_time = start_time + timedelta(minutes=duration_minutes)
    connection = db.get_connection()
    try:
        existing = connection.execute(
            "select id, start_time from class_schedules where id = ? and gym_id = ?",
            (schedule_id, session["active_gym_id"]),
        ).fetchone()
        if existing is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Schedule class not found.")
        if security.parse_iso(existing["start_time"]) <= security.now_utc():
            raise HTTPException(status_code=HTTPStatus.BAD_REQUEST.value, detail="Only future classes can be edited.")
        booked_count_row = connection.execute(
            "select count(*) as booked_count from class_bookings where class_schedule_id = ?",
            (schedule_id,),
        ).fetchone()
        booked_count = int(booked_count_row["booked_count"]) if booked_count_row is not None else 0
        if capacity < booked_count:
            raise HTTPException(status_code=HTTPStatus.BAD_REQUEST.value, detail="Capacity cannot be lower than the current booking count.")
        if trainer_user_id is not None:
            assigned_trainer = connection.execute(
                """
                select users.id
                from gym_memberships
                join users on users.id = gym_memberships.user_id
                where gym_memberships.gym_id = ?
                  and gym_memberships.user_id = ?
                  and gym_memberships.status = 'active'
                  and gym_memberships.active_role = 'trainer'
                  and users.deleted_at is null
                """,
                (session["active_gym_id"], trainer_user_id),
            ).fetchone()
            if assigned_trainer is None:
                raise HTTPException(status_code=HTTPStatus.BAD_REQUEST.value, detail="Selected trainer is not active in this gym.")
        affected_user_rows = connection.execute(
            """
            select user_id from class_bookings where class_schedule_id = ?
            union
            select user_id from class_waitlist_entries where class_schedule_id = ?
            """,
            (schedule_id, schedule_id),
        ).fetchall()
        with connection:
            connection.execute(
                """
                update class_schedules
                set title = ?, class_type = ?, start_time = ?, end_time = ?, duration_minutes = ?, capacity = ?,
                    assigned_trainer_user_id = ?, wod_description = ?, updated_by_user_id = ?, updated_at = ?
                where id = ?
                """,
                (
                    title,
                    class_type,
                    security.isoformat(start_time),
                    security.isoformat(end_time),
                    duration_minutes,
                    capacity,
                    trainer_user_id,
                    wod_description,
                    session["user_id"],
                    security.isoformat(security.now_utc()),
                    schedule_id,
                ),
            )
            row = schedule_service.get_schedule_class_row(connection, schedule_id)
            if row is None:
                raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Schedule class not found.")
            payload = schedule_service.schedule_class_payload(
                connection,
                row,
                current_user_id=session["user_id"],
                include_bookings=session["role"] in {"admin", "trainer"},
            )
            audit.write_audit_log(
                connection,
                gym_id=session["active_gym_id"],
                actor_user_id=session["user_id"],
                action="schedule_class_updated",
                entity_type="schedule_class",
                entity_id=schedule_id,
                details={
                    "title": title,
                    "class_type": class_type,
                    "start_time": security.isoformat(start_time),
                    "duration_minutes": duration_minutes,
                    "capacity": capacity,
                    "trainer_user_id": trainer_user_id,
                },
            )
            schedule_service.create_schedule_update_notifications(
                connection,
                gym_id=session["active_gym_id"],
                class_schedule_id=schedule_id,
                user_ids=[int(user["user_id"]) for user in affected_user_rows if int(user["user_id"]) != session["user_id"]],
            )
        return {"class": payload}
    finally:
        connection.close()


@app.delete("/schedule/classes")
def delete_schedule_class(
    body: ScheduleClassDeleteRequest,
    session: dict[str, Any] = Depends(require_schedule_manager_session),
) -> dict[str, bool | str]:
    schedule_id = body.id
    connection = db.get_connection()
    try:
        existing = connection.execute(
            "select id, start_time from class_schedules where id = ? and gym_id = ?",
            (schedule_id, session["active_gym_id"]),
        ).fetchone()
        if existing is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Schedule class not found.")
        if security.parse_iso(existing["start_time"]) <= security.now_utc():
            raise HTTPException(status_code=HTTPStatus.BAD_REQUEST.value, detail="Only future classes can be deleted.")
        with connection:
            connection.execute("delete from class_schedules where id = ?", (schedule_id,))
            audit.write_audit_log(
                connection,
                gym_id=session["active_gym_id"],
                actor_user_id=session["user_id"],
                action="schedule_class_deleted",
                entity_type="schedule_class",
                entity_id=schedule_id,
            )
        return {"message": "Schedule class deleted."}
    finally:
        connection.close()


@app.post("/schedule/bookings", status_code=HTTPStatus.CREATED.value)
def create_class_booking(
    body: ClassIdRequest,
    session: dict[str, Any] = Depends(require_active_gym_member_session),
) -> dict[str, str]:
    schedule_id = body.class_id
    connection = db.get_connection()
    try:
        schedule_row = connection.execute(
            "select id, gym_id, start_time, capacity from class_schedules where id = ? and gym_id = ?",
            (schedule_id, session["active_gym_id"]),
        ).fetchone()
        if schedule_row is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Schedule class not found.")
        if security.parse_iso(schedule_row["start_time"]) <= security.now_utc():
            raise HTTPException(status_code=HTTPStatus.BAD_REQUEST.value, detail="Only future classes can be booked.")
        existing_booking = connection.execute(
            "select id from class_bookings where class_schedule_id = ? and user_id = ?",
            (schedule_id, session["user_id"]),
        ).fetchone()
        if existing_booking is not None:
            raise HTTPException(status_code=HTTPStatus.CONFLICT.value, detail="You have already booked this class.")
        booking_count_row = connection.execute(
            "select count(*) as booked_count from class_bookings where class_schedule_id = ?",
            (schedule_id,),
        ).fetchone()
        booked_count = int(booking_count_row["booked_count"]) if booking_count_row is not None else 0
        if booked_count >= schedule_row["capacity"]:
            raise HTTPException(status_code=HTTPStatus.CONFLICT.value, detail="This class is already full.")
        with connection:
            connection.execute(
                "insert into class_bookings (class_schedule_id, user_id, attendance_status, created_at) values (?, ?, 'booked', ?)",
                (schedule_id, session["user_id"], security.isoformat(security.now_utc())),
            )
            schedule_service.create_booking_confirmation_notification(
                connection,
                user_id=session["user_id"],
                gym_id=schedule_row["gym_id"],
                class_schedule_id=schedule_id,
            )
        return {"message": "Class booked."}
    finally:
        connection.close()


@app.delete("/schedule/bookings")
def delete_class_booking(
    body: ClassIdRequest,
    session: dict[str, Any] = Depends(require_active_gym_member_session),
) -> dict[str, str]:
    schedule_id = body.class_id
    connection = db.get_connection()
    try:
        schedule_row = connection.execute(
            "select id, gym_id, start_time from class_schedules where id = ? and gym_id = ?",
            (schedule_id, session["active_gym_id"]),
        ).fetchone()
        if schedule_row is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Schedule class not found.")
        if security.parse_iso(schedule_row["start_time"]) <= security.now_utc():
            raise HTTPException(status_code=HTTPStatus.BAD_REQUEST.value, detail="Only future classes can be cancelled.")
        existing_booking = connection.execute(
            "select id from class_bookings where class_schedule_id = ? and user_id = ?",
            (schedule_id, session["user_id"]),
        ).fetchone()
        if existing_booking is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="You do not have a booking for this class.")
        with connection:
            connection.execute(
                "delete from class_bookings where class_schedule_id = ? and user_id = ?",
                (schedule_id, session["user_id"]),
            )
            promoted_user_id = schedule_service.promote_next_waitlisted_user(connection, class_schedule_id=schedule_id)
            if promoted_user_id is not None:
                schedule_service.create_waitlist_promotion_notification(
                    connection,
                    user_id=promoted_user_id,
                    gym_id=schedule_row["gym_id"],
                    class_schedule_id=schedule_id,
                )
        return {"message": "Booking cancelled."}
    finally:
        connection.close()


@app.post("/schedule/waitlist", status_code=HTTPStatus.CREATED.value)
def create_class_waitlist(
    body: ClassIdRequest,
    session: dict[str, Any] = Depends(require_active_gym_member_session),
) -> dict[str, str]:
    schedule_id = body.class_id
    connection = db.get_connection()
    try:
        schedule_row = connection.execute(
            "select id, gym_id, start_time, capacity from class_schedules where id = ? and gym_id = ?",
            (schedule_id, session["active_gym_id"]),
        ).fetchone()
        if schedule_row is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Schedule class not found.")
        if security.parse_iso(schedule_row["start_time"]) <= security.now_utc():
            raise HTTPException(status_code=HTTPStatus.BAD_REQUEST.value, detail="Only future classes can be waitlisted.")
        existing_booking = connection.execute(
            "select id from class_bookings where class_schedule_id = ? and user_id = ?",
            (schedule_id, session["user_id"]),
        ).fetchone()
        if existing_booking is not None:
            raise HTTPException(status_code=HTTPStatus.CONFLICT.value, detail="You have already booked this class.")
        existing_waitlist = connection.execute(
            "select id from class_waitlist_entries where class_schedule_id = ? and user_id = ?",
            (schedule_id, session["user_id"]),
        ).fetchone()
        if existing_waitlist is not None:
            raise HTTPException(status_code=HTTPStatus.CONFLICT.value, detail="You are already on the waitlist for this class.")
        booking_count_row = connection.execute(
            "select count(*) as booked_count from class_bookings where class_schedule_id = ?",
            (schedule_id,),
        ).fetchone()
        booked_count = int(booking_count_row["booked_count"]) if booking_count_row is not None else 0
        if booked_count < schedule_row["capacity"]:
            raise HTTPException(status_code=HTTPStatus.CONFLICT.value, detail="This class still has open spots.")
        with connection:
            connection.execute(
                "insert into class_waitlist_entries (class_schedule_id, user_id, created_at) values (?, ?, ?)",
                (schedule_id, session["user_id"], security.isoformat(security.now_utc())),
            )
        return {"message": "Added to waitlist."}
    finally:
        connection.close()


@app.delete("/schedule/waitlist")
def delete_class_waitlist(
    body: ClassIdRequest,
    session: dict[str, Any] = Depends(require_active_gym_member_session),
) -> dict[str, str]:
    schedule_id = body.class_id
    connection = db.get_connection()
    try:
        schedule_row = connection.execute(
            "select id from class_schedules where id = ? and gym_id = ?",
            (schedule_id, session["active_gym_id"]),
        ).fetchone()
        if schedule_row is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Schedule class not found.")
        existing_waitlist = connection.execute(
            "select id from class_waitlist_entries where class_schedule_id = ? and user_id = ?",
            (schedule_id, session["user_id"]),
        ).fetchone()
        if existing_waitlist is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="You are not on the waitlist for this class.")
        with connection:
            connection.execute(
                "delete from class_waitlist_entries where class_schedule_id = ? and user_id = ?",
                (schedule_id, session["user_id"]),
            )
        return {"message": "Removed from waitlist."}
    finally:
        connection.close()


@app.patch("/schedule/bookings/attendance")
def update_class_attendance(
    body: UpdateAttendanceRequest,
    session: dict[str, Any] = Depends(require_schedule_manager_session),
) -> dict[str, Any]:
    try:
        schedule_id = validation.require_user_id(body.class_id)
        user_id = validation.require_user_id(body.user_id)
        attendance_status = validation.require_attendance_status(body.attendance_status)
    except validation.ApiError as error:
        raise_http_error(error)
    connection = db.get_connection()
    try:
        schedule_row = connection.execute(
            "select id, start_time from class_schedules where id = ? and gym_id = ?",
            (schedule_id, session["active_gym_id"]),
        ).fetchone()
        if schedule_row is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Schedule class not found.")
        if security.parse_iso(schedule_row["start_time"]) > security.now_utc():
            raise HTTPException(status_code=HTTPStatus.BAD_REQUEST.value, detail="Attendance can only be recorded after the class has started.")
        booking_row = connection.execute(
            "select id from class_bookings where class_schedule_id = ? and user_id = ?",
            (schedule_id, user_id),
        ).fetchone()
        if booking_row is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="That athlete does not have a booking for this class.")
        with connection:
            connection.execute(
                """
                update class_bookings
                set attendance_status = ?, attendance_marked_at = ?, attendance_marked_by_user_id = ?
                where class_schedule_id = ? and user_id = ?
                """,
                (attendance_status, security.isoformat(security.now_utc()), session["user_id"], schedule_id, user_id),
            )
            row = schedule_service.get_schedule_class_row(connection, schedule_id)
            if row is None:
                raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Schedule class not found.")
            payload = schedule_service.schedule_class_payload(
                connection,
                row,
                current_user_id=session["user_id"],
                include_bookings=True,
            )
        return {"class": payload}
    finally:
        connection.close()


@app.post("/auth/signup")
def signup(body: dict[str, Any]) -> dict[str, Any]:
    return _signup(body, account_type="athlete")


@app.post("/auth/signup-admin")
@app.post("/auth/signup-owner")
def signup_admin(body: dict[str, Any]) -> dict[str, Any]:
    return _signup(body, account_type="admin")


@app.post("/auth/logout")
def logout(session: dict[str, Any] = Depends(require_session)) -> dict[str, Any]:
    connection = db.get_connection()
    try:
        with connection:
            connection.execute("delete from sessions where access_token_hash = ?", (session["access_token_hash"],))
        return {"message": "Signed out."}
    finally:
        connection.close()


@app.post("/auth/logout-all")
def logout_all(session: dict[str, Any] = Depends(require_session)) -> dict[str, Any]:
    connection = db.get_connection()
    try:
        with connection:
            auth_service.delete_sessions(connection, session["user_id"])
            audit.write_audit_log(
                connection,
                gym_id=session["active_gym_id"],
                actor_user_id=session["user_id"],
                target_user_id=session["user_id"],
                action="all_sessions_revoked",
                entity_type="session",
            )
        return {"message": "All sessions revoked."}
    finally:
        connection.close()


@app.post("/auth/request-password-reset")
def request_password_reset(body: dict[str, Any]) -> dict[str, Any]:
    email = validation.require_email(body.get("email"))
    connection = db.get_connection()
    try:
        user = connection.execute(
            "select id from users where email = ? and deleted_at is null",
            (email,),
        ).fetchone()
        if user is not None:
            with connection:
                token = auth_service.issue_password_reset_token(connection, user["id"])
            print(f"[boxos-backend] Password reset token for {email}: {token}")
        return {"message": "If the account exists, a reset token has been issued in the backend log."}
    finally:
        connection.close()


@app.post("/auth/reset-password")
def reset_password(body: dict[str, Any]) -> dict[str, Any]:
    token = validation.require_token(body.get("token"), label="Reset token")
    new_password = validation.require_password(body.get("new_password"))
    logout_other_sessions = bool(body.get("logout_other_sessions", False))
    connection = db.get_connection()
    try:
        reset_row = connection.execute(
            "select * from password_reset_tokens where token_hash = ?",
            (security.hash_token(token),),
        ).fetchone()
        if reset_row is None or security.parse_iso(reset_row["expires_at"]) <= security.now_utc():
            raise HTTPException(status_code=HTTPStatus.BAD_REQUEST.value, detail="Reset token is invalid or expired.")
        with connection:
            connection.execute(
                "update users set password_hash = ?, updated_at = ? where id = ?",
                (security.hash_password(new_password), security.isoformat(security.now_utc()), reset_row["user_id"]),
            )
            connection.execute("delete from password_reset_tokens where user_id = ?", (reset_row["user_id"],))
            if logout_other_sessions:
                auth_service.delete_sessions(connection, reset_row["user_id"])
        return {"message": "Password updated."}
    finally:
        connection.close()


@app.post("/auth/verify-email")
def verify_email(body: dict[str, Any]) -> dict[str, Any]:
    token = validation.require_token(body.get("token"), label="Verification token")
    connection = db.get_connection()
    try:
        verification_row = connection.execute(
            "select * from verification_tokens where token_hash = ?",
            (security.hash_token(token),),
        ).fetchone()
        if verification_row is None or security.parse_iso(verification_row["expires_at"]) <= security.now_utc():
            raise HTTPException(status_code=HTTPStatus.BAD_REQUEST.value, detail="Verification token is invalid or expired.")
        with connection:
            connection.execute(
                "update users set email_verified = 1, updated_at = ? where id = ?",
                (security.isoformat(security.now_utc()), verification_row["user_id"]),
            )
            connection.execute("delete from verification_tokens where user_id = ?", (verification_row["user_id"],))
        return {"message": "Email verified."}
    finally:
        connection.close()


@app.post("/auth/resend-verification")
def resend_verification(body: dict[str, Any]) -> dict[str, Any]:
    email = validation.require_email(body.get("email"))
    connection = db.get_connection()
    try:
        user = connection.execute(
            "select * from users where email = ? and deleted_at is null",
            (email,),
        ).fetchone()
        if user is None:
            return {"message": "If the account exists, a verification token has been issued in the backend log."}
        if user["email_verified"]:
            return {"message": "Email is already verified."}
        with connection:
            token = auth_service.issue_verification_token(connection, user["id"])
        print(f"[boxos-backend] Verification token for {email}: {token}")
        return {"message": "Verification token reissued. Check the backend log."}
    finally:
        connection.close()


@app.post("/auth/change-password")
def change_password(body: dict[str, Any], session: dict[str, Any] = Depends(require_session)) -> dict[str, Any]:
    current_password = validation.require_password(body.get("current_password"), label="Current password")
    new_password = validation.require_password(body.get("new_password"), label="New password")
    logout_other_sessions = bool(body.get("logout_other_sessions", False))
    connection = db.get_connection()
    try:
        user = connection.execute(
            "select * from users where id = ? and deleted_at is null",
            (session["user_id"],),
        ).fetchone()
        if user is None or not security.verify_password(current_password, user["password_hash"]):
            raise HTTPException(status_code=HTTPStatus.UNAUTHORIZED.value, detail="Current password is incorrect.")
        with connection:
            connection.execute(
                "update users set password_hash = ?, updated_at = ? where id = ?",
                (security.hash_password(new_password), security.isoformat(security.now_utc()), user["id"]),
            )
            if logout_other_sessions:
                auth_service.delete_sessions(connection, user["id"], except_access_token_hash=session["access_token_hash"])
            connection.execute("delete from sessions where access_token_hash = ?", (session["access_token_hash"],))
            tokens = auth_service.create_session(connection, user["id"])
        return tokens
    finally:
        connection.close()


@app.delete("/auth/account")
def delete_account(body: dict[str, Any], session: dict[str, Any] = Depends(require_session)) -> dict[str, Any]:
    current_password = validation.require_password(body.get("current_password"), label="Current password")
    connection = db.get_connection()
    try:
        user = connection.execute(
            "select * from users where id = ? and deleted_at is null",
            (session["user_id"],),
        ).fetchone()
        if user is None or not security.verify_password(current_password, user["password_hash"]):
            raise HTTPException(status_code=HTTPStatus.UNAUTHORIZED.value, detail="Current password is incorrect.")
        with connection:
            now = security.now_utc()
            connection.execute(
                """
                update users
                set email = ?, password_hash = ?, deleted_at = ?, purge_after = ?, updated_at = ?, email_verified = 0, display_name = ?, nickname = ?
                where id = ?
                """,
                (
                    f"deleted_{user['id']}@deleted.local",
                    security.hash_password(security.create_token("deleted")),
                    security.isoformat(now),
                    security.isoformat(now + timedelta(days=settings.DELETE_RETENTION_DAYS)),
                    security.isoformat(now),
                    "Deleted User",
                    "",
                    user["id"],
                ),
            )
            connection.execute("delete from sessions where user_id = ?", (user["id"],))
            connection.execute("delete from verification_tokens where user_id = ?", (user["id"],))
            connection.execute("delete from password_reset_tokens where user_id = ?", (user["id"],))
            connection.execute("delete from device_registrations where user_id = ?", (user["id"],))
        return {"message": "Account scheduled for deletion. Personal data has been anonymized and the record will be permanently purged after %s days." % settings.DELETE_RETENTION_DAYS}
    finally:
        connection.close()


@app.post("/devices/register")
def register_device(body: dict[str, Any], session: dict[str, Any] = Depends(require_session)) -> dict[str, Any]:
    device_token = validation.require_token(body.get("device_token"), label="Device token")
    platform = validation.require_platform(body.get("platform"))
    connection = db.get_connection()
    try:
        now = security.isoformat(security.now_utc())
        with connection:
            connection.execute(
                """
                insert into device_registrations (
                    user_id, device_token, platform, created_at, updated_at
                )
                values (?, ?, ?, ?, ?)
                on conflict(device_token) do update set
                    user_id = excluded.user_id,
                    platform = excluded.platform,
                    updated_at = excluded.updated_at
                """,
                (session["user_id"], device_token, platform, now, now),
            )
        return {"message": "Device registered."}
    finally:
        connection.close()


@app.delete("/devices/current")
def unregister_device(body: dict[str, Any], session: dict[str, Any] = Depends(require_session)) -> dict[str, Any]:
    device_token = validation.require_token(body.get("device_token"), label="Device token")
    connection = db.get_connection()
    try:
        with connection:
            connection.execute(
                "delete from device_registrations where user_id = ? and device_token = ?",
                (session["user_id"], device_token),
            )
        return {"message": "Device unregistered."}
    finally:
        connection.close()


@app.get("/programming/workouts")
def list_daily_workouts(session: dict[str, Any] = Depends(require_active_gym_member_session)) -> dict[str, Any]:
    connection = db.get_connection()
    try:
        rows = connection.execute(
            """
            select
              daily_workouts.id,
              daily_workouts.gym_id,
              daily_workouts.scheduled_date,
              daily_workouts.title,
              daily_workouts.strength_text,
              daily_workouts.metcon_text,
              daily_workouts.notes_text,
              daily_workouts.created_at,
              daily_workouts.updated_at
            from daily_workouts
            where daily_workouts.gym_id = ?
            order by daily_workouts.scheduled_date asc
            """,
            (session["active_gym_id"],),
        ).fetchall()
        workouts = [
            programming_service.daily_workout_payload(
                connection,
                row,
                current_user_id=session["user_id"],
                can_edit=session["role"] in {"admin", "trainer"},
            )
            for row in rows
        ]
        return {"workouts": workouts}
    finally:
        connection.close()


@app.post("/programming/workouts")
def create_daily_workout(
    body: DailyWorkoutRequest,
    session: dict[str, Any] = Depends(require_schedule_manager_session),
) -> dict[str, Any]:
    scheduled_date = validation.require_programming_date(body.scheduled_date)
    title = validation.require_programming_title(body.title)
    strength_text = validation.require_programming_section(body.strength_text, label="Strength")
    metcon_text = validation.require_programming_section(body.metcon_text, label="MetCon")
    notes_text = validation.require_programming_section(body.notes_text, label="Notes")
    connection = db.get_connection()
    try:
        existing = connection.execute(
            "select id from daily_workouts where gym_id = ? and scheduled_date = ?",
            (session["active_gym_id"], scheduled_date),
        ).fetchone()
        if existing is not None:
            raise HTTPException(status_code=HTTPStatus.CONFLICT.value, detail="A workout already exists for this date.")
        timestamp = security.isoformat(security.now_utc())
        with connection:
            cursor = connection.execute(
                """
                insert into daily_workouts (
                  gym_id, scheduled_date, title, strength_text, metcon_text, notes_text,
                  created_by_user_id, updated_by_user_id, created_at, updated_at
                )
                values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    session["active_gym_id"],
                    scheduled_date,
                    title,
                    strength_text,
                    metcon_text,
                    notes_text,
                    session["user_id"],
                    session["user_id"],
                    timestamp,
                    timestamp,
                ),
            )
            workout_id = int(cursor.lastrowid)
            row = connection.execute(
                "select id, gym_id, scheduled_date, title, strength_text, metcon_text, notes_text, created_at, updated_at from daily_workouts where id = ?",
                (workout_id,),
            ).fetchone()
            payload = programming_service.daily_workout_payload(connection, row, current_user_id=session["user_id"], can_edit=True)
            notifications_core.create_wod_notifications(connection, gym_id=session["active_gym_id"], workout_id=workout_id, scheduled_date=scheduled_date, title=title, is_update=False)
            audit.write_audit_log(connection, gym_id=session["active_gym_id"], actor_user_id=session["user_id"], action="daily_workout_created", entity_type="daily_workout", entity_id=workout_id, details={"scheduled_date": scheduled_date, "title": title})
        return {"workout": payload}
    finally:
        connection.close()


@app.patch("/programming/workouts")
def update_daily_workout(
    body: DailyWorkoutUpdateRequest,
    session: dict[str, Any] = Depends(require_schedule_manager_session),
) -> dict[str, Any]:
    workout_id = validation.require_user_id(body.id)
    scheduled_date = validation.require_programming_date(body.scheduled_date)
    title = validation.require_programming_title(body.title)
    strength_text = validation.require_programming_section(body.strength_text, label="Strength")
    metcon_text = validation.require_programming_section(body.metcon_text, label="MetCon")
    notes_text = validation.require_programming_section(body.notes_text, label="Notes")
    connection = db.get_connection()
    try:
        existing = connection.execute(
            "select id, scheduled_date from daily_workouts where id = ? and gym_id = ?",
            (workout_id, session["active_gym_id"]),
        ).fetchone()
        if existing is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Workout not found.")
        if validation.parse_programming_date(existing["scheduled_date"]) < programming_service.today_utc_date():
            raise HTTPException(status_code=HTTPStatus.BAD_REQUEST.value, detail="Past workouts cannot be edited.")
        duplicate = connection.execute(
            "select id from daily_workouts where gym_id = ? and scheduled_date = ? and id != ?",
            (session["active_gym_id"], scheduled_date, workout_id),
        ).fetchone()
        if duplicate is not None:
            raise HTTPException(status_code=HTTPStatus.CONFLICT.value, detail="A workout already exists for this date.")
        with connection:
            connection.execute(
                """
                update daily_workouts
                set scheduled_date = ?,
                    title = ?,
                    strength_text = ?,
                    metcon_text = ?,
                    notes_text = ?,
                    updated_by_user_id = ?,
                    updated_at = ?
                where id = ?
                """,
                (scheduled_date, title, strength_text, metcon_text, notes_text, session["user_id"], security.isoformat(security.now_utc()), workout_id),
            )
            row = connection.execute(
                "select id, gym_id, scheduled_date, title, strength_text, metcon_text, notes_text, created_at, updated_at from daily_workouts where id = ?",
                (workout_id,),
            ).fetchone()
            payload = programming_service.daily_workout_payload(connection, row, current_user_id=session["user_id"], can_edit=True)
            notifications_core.create_wod_notifications(connection, gym_id=session["active_gym_id"], workout_id=workout_id, scheduled_date=scheduled_date, title=title, is_update=True)
            audit.write_audit_log(connection, gym_id=session["active_gym_id"], actor_user_id=session["user_id"], action="daily_workout_updated", entity_type="daily_workout", entity_id=workout_id, details={"scheduled_date": scheduled_date, "title": title})
        return {"workout": payload}
    finally:
        connection.close()


@app.post("/programming/whiteboard-results")
def submit_whiteboard_result(
    body: WhiteboardResultRequest,
    session: dict[str, Any] = Depends(require_active_gym_member_session),
) -> dict[str, Any]:
    workout_id = validation.require_user_id(body.workout_id)
    score_type, score_value, score_label = validation.require_whiteboard_score(body.score_type, body.score_value)
    notes_text = validation.require_whiteboard_notes(body.notes_text)
    connection = db.get_connection()
    try:
        workout = connection.execute(
            """
            select id, gym_id, scheduled_date, title, strength_text, metcon_text, notes_text, created_at, updated_at
            from daily_workouts
            where id = ? and gym_id = ?
            """,
            (workout_id, session["active_gym_id"]),
        ).fetchone()
        if workout is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Workout not found.")
        if validation.parse_programming_date(workout["scheduled_date"]) > programming_service.today_utc_date():
            raise HTTPException(status_code=HTTPStatus.BAD_REQUEST.value, detail="Results can only be submitted on or after the workout date.")
        timestamp = security.isoformat(security.now_utc())
        with connection:
            existing = connection.execute(
                "select id from whiteboard_results where daily_workout_id = ? and user_id = ?",
                (workout_id, session["user_id"]),
            ).fetchone()
            action = "whiteboard_result_created" if existing is None else "whiteboard_result_updated"
            if existing is None:
                connection.execute(
                    """
                    insert into whiteboard_results (
                      daily_workout_id, gym_id, user_id, score_type, score_value,
                      score_label, notes_text, created_at, updated_at
                    )
                    values (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (workout_id, session["active_gym_id"], session["user_id"], score_type, score_value, score_label, notes_text, timestamp, timestamp),
                )
            else:
                connection.execute(
                    """
                    update whiteboard_results
                    set score_type = ?, score_value = ?, score_label = ?, notes_text = ?, updated_at = ?
                    where id = ?
                    """,
                    (score_type, score_value, score_label, notes_text, timestamp, existing["id"]),
                )
            payload = programming_service.daily_workout_payload(connection, workout, current_user_id=session["user_id"], can_edit=session["role"] in {"admin", "trainer"})
            audit.write_audit_log(connection, gym_id=session["active_gym_id"], actor_user_id=session["user_id"], target_user_id=session["user_id"], action=action, entity_type="whiteboard_result", entity_id=workout_id, details={"workout_id": workout_id, "score_type": score_type, "score_label": score_label})
        return {"workout": payload}
    finally:
        connection.close()


@app.get("/logbook/entries")
def list_workout_logs(session: dict[str, Any] = Depends(require_active_gym_member_session)) -> dict[str, Any]:
    connection = db.get_connection()
    try:
        rows = connection.execute(
            """
            select
              workout_logs.id,
              workout_logs.daily_workout_id,
              workout_logs.class_schedule_id,
              workout_logs.score_type,
              workout_logs.score_value,
              workout_logs.score_label,
              workout_logs.notes_text,
              workout_logs.created_at,
              workout_logs.updated_at,
              daily_workouts.scheduled_date,
              daily_workouts.title as workout_title,
              class_schedules.title as class_title,
              class_schedules.start_time as class_start_time,
              workout_logs.is_pr,
              workout_logs.pr_rank
            from workout_logs
            join daily_workouts on daily_workouts.id = workout_logs.daily_workout_id
            left join class_schedules on class_schedules.id = workout_logs.class_schedule_id
            where workout_logs.user_id = ? and workout_logs.gym_id = ?
            order by daily_workouts.scheduled_date desc, workout_logs.updated_at desc
            """,
            (session["user_id"], session["active_gym_id"]),
        ).fetchall()
        return {"entries": [programming_service.workout_log_payload(row) for row in rows]}
    finally:
        connection.close()


@app.post("/logbook/entries")
def submit_workout_log(
    body: WorkoutLogRequest,
    session: dict[str, Any] = Depends(require_active_gym_member_session),
) -> dict[str, Any]:
    workout_id = validation.require_user_id(body.workout_id)
    class_id = validation.require_optional_user_id(body.class_id)
    score_type, score_value, score_label = validation.require_whiteboard_score(body.score_type, body.score_value)
    notes_text = validation.require_whiteboard_notes(body.notes_text)
    connection = db.get_connection()
    try:
        workout = connection.execute(
            "select id, gym_id, scheduled_date, title from daily_workouts where id = ? and gym_id = ?",
            (workout_id, session["active_gym_id"]),
        ).fetchone()
        if workout is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Workout not found.")
        if class_id is not None:
            class_row = connection.execute(
                "select id from class_schedules where id = ? and gym_id = ?",
                (class_id, session["active_gym_id"]),
            ).fetchone()
            if class_row is None:
                raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Class not found.")
        timestamp = security.isoformat(security.now_utc())
        with connection:
            existing = connection.execute(
                "select id from workout_logs where user_id = ? and daily_workout_id = ?",
                (session["user_id"], workout_id),
            ).fetchone()
            if existing is None:
                connection.execute(
                    """
                    insert into workout_logs (
                      user_id, gym_id, daily_workout_id, class_schedule_id, score_type,
                      score_value, score_label, notes_text, created_at, updated_at
                    ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (session["user_id"], session["active_gym_id"], workout_id, class_id, score_type, score_value, score_label, notes_text, timestamp, timestamp),
                )
                action = "workout_log_created"
            else:
                connection.execute(
                    """
                    update workout_logs
                    set class_schedule_id = ?, score_type = ?, score_value = ?, score_label = ?, notes_text = ?, updated_at = ?
                    where id = ?
                    """,
                    (class_id, score_type, score_value, score_label, notes_text, timestamp, existing["id"]),
                )
                action = "workout_log_updated"
            programming_service.refresh_pr_flags_for_workout_title(connection, user_id=session["user_id"], gym_id=session["active_gym_id"], workout_title=workout["title"], score_type=score_type)
            row = connection.execute(
                """
                select
                  workout_logs.id,
                  workout_logs.daily_workout_id,
                  workout_logs.class_schedule_id,
                  workout_logs.score_type,
                  workout_logs.score_value,
                  workout_logs.score_label,
                  workout_logs.notes_text,
                  workout_logs.created_at,
                  workout_logs.updated_at,
                  daily_workouts.scheduled_date,
                  daily_workouts.title as workout_title,
                  class_schedules.title as class_title,
                  class_schedules.start_time as class_start_time,
                  workout_logs.is_pr,
                  workout_logs.pr_rank
                from workout_logs
                join daily_workouts on daily_workouts.id = workout_logs.daily_workout_id
                left join class_schedules on class_schedules.id = workout_logs.class_schedule_id
                where workout_logs.user_id = ? and workout_logs.daily_workout_id = ?
                """,
                (session["user_id"], workout_id),
            ).fetchone()
            if row is not None and row["is_pr"]:
                programming_service.create_pr_achievement_notification(connection, user_id=session["user_id"], gym_id=session["active_gym_id"], workout_id=workout_id, workout_title=workout["title"], score_label=score_label)
            audit.write_audit_log(connection, gym_id=session["active_gym_id"], actor_user_id=session["user_id"], target_user_id=session["user_id"], action=action, entity_type="workout_log", entity_id=row["id"] if row is not None else None, details={"workout_id": workout_id, "score_type": score_type, "score_label": score_label})
        if row is None:
            raise HTTPException(status_code=HTTPStatus.INTERNAL_SERVER_ERROR.value, detail="Workout log could not be saved.")
        return {"entry": programming_service.workout_log_payload(row)}
    finally:
        connection.close()


@app.get("/personal-workouts")
def list_personal_workouts(session: dict[str, Any] = Depends(require_session)) -> dict[str, Any]:
    connection = db.get_connection()
    try:
        rows = connection.execute(
            """
            select id, type, title, structure_json, created_at, updated_at
            from personal_workouts
            where user_id = ?
            order by updated_at desc
            """,
            (session["user_id"],),
        ).fetchall()
        return {"workouts": [programming_service.personal_workout_payload(row) for row in rows]}
    finally:
        connection.close()


@app.post("/personal-workouts")
def create_personal_workout(body: PersonalWorkoutRequest, session: dict[str, Any] = Depends(require_session)) -> dict[str, Any]:
    title = validation.require_personal_workout_title(body.title)
    workout_type = validation.require_personal_workout_type(body.type)
    structure = validation.require_personal_workout_structure(body.structure)
    timestamp = security.isoformat(security.now_utc())
    connection = db.get_connection()
    try:
        with connection:
            cursor = connection.execute(
                """
                insert into personal_workouts (
                  user_id, type, title, structure_json, created_at, updated_at
                ) values (?, ?, ?, ?, ?, ?)
                """,
                (
                    session["user_id"],
                    workout_type,
                    title,
                    json.dumps(structure),
                    timestamp,
                    timestamp,
                ),
            )
            row = connection.execute(
                """
                select id, type, title, structure_json, created_at, updated_at
                from personal_workouts
                where id = ?
                """,
                (cursor.lastrowid,),
            ).fetchone()
        return {"workout": programming_service.personal_workout_payload(row)}
    finally:
        connection.close()


@app.delete("/personal-workouts")
def delete_personal_workout(body: PersonalWorkoutDeleteRequest, session: dict[str, Any] = Depends(require_session)) -> dict[str, Any]:
    workout_id = validation.require_personal_workout_id(body.id)
    connection = db.get_connection()
    try:
        with connection:
            existing = connection.execute(
                "select id from personal_workouts where id = ? and user_id = ?",
                (workout_id, session["user_id"]),
            ).fetchone()
            if existing is None:
                raise_http_error(validation.ApiError(HTTPStatus.NOT_FOUND, "Workout not found."))
            connection.execute("delete from personal_workouts where id = ?", (workout_id,))
        return {"deleted": True}
    finally:
        connection.close()


@app.get("/exercises")
def list_exercises(
    query: str = "",
    limit: int = 50,
    _: dict[str, Any] = Depends(require_session),
) -> dict[str, Any]:
    normalized_query = (query or "").strip().lower()
    normalized_limit = max(1, min(limit, 100))
    connection = db.get_connection()
    try:
        if normalized_query:
            rows = connection.execute(
                """
                select id, name, category, equipment, level,
                       primary_muscles, secondary_muscles
                from exercises
                where search like ?
                order by name
                limit ?
                """,
                (f"%{normalized_query}%", normalized_limit),
            ).fetchall()
        else:
            rows = connection.execute(
                """
                select id, name, category, equipment, level,
                       primary_muscles, secondary_muscles
                from exercises
                order by name
                limit ?
                """,
                (normalized_limit,),
            ).fetchall()
        return {"exercises": [programming_service.exercise_payload(row) for row in rows]}
    finally:
        connection.close()


@app.get("/benchmark-workouts")
def list_benchmark_workouts(_: dict[str, Any] = Depends(require_session)) -> dict[str, Any]:
    connection = db.get_connection()
    try:
        rows = connection.execute(
            """
            select id, name, category, structure_json
            from benchmark_workouts
            order by sort_order, name
            """
        ).fetchall()
        return {"workouts": [programming_service.benchmark_workout_payload(row) for row in rows]}
    finally:
        connection.close()


@app.get("/audit-logs")
def list_audit_logs(session: dict[str, Any] = Depends(require_admin_gym_session)) -> dict[str, Any]:
    connection = db.get_connection()
    try:
        rows = connection.execute(
            """
            select
              audit_logs.id,
              audit_logs.action,
              audit_logs.entity_type,
              audit_logs.entity_id,
              audit_logs.details_json,
              audit_logs.created_at,
              actor.email as actor_email,
              actor.display_name as actor_display_name,
              actor.nickname as actor_nickname,
              target.email as target_email,
              target.display_name as target_display_name,
              target.nickname as target_nickname
            from audit_logs
            join users actor on actor.id = audit_logs.actor_user_id
            left join users target on target.id = audit_logs.target_user_id
            where audit_logs.gym_id = ?
            order by audit_logs.created_at desc, audit_logs.id desc
            limit 100
            """,
            (session["active_gym_id"],),
        ).fetchall()
        return {"logs": [programming_service.audit_log_payload(row) for row in rows]}
    finally:
        connection.close()


@app.get("/admin/analytics")
def admin_analytics_overview(
    window_days: int = 14,
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, Any]:
    validated_window_days = programming_service.require_admin_analytics_window_days(window_days)
    connection = db.get_connection()
    try:
        gym_id = session["active_gym_id"]
        today = programming_service.today_utc_date()
        window_start = today - timedelta(days=validated_window_days - 1)
        upcoming_end = today + timedelta(days=6)

        active_memberships = connection.execute(
            """
            select
              gym_memberships.id,
              gym_memberships.user_id,
              gym_memberships.active_role,
              gym_memberships.roles_json,
              gym_memberships.status,
              gym_memberships.created_at,
              users.email,
              users.display_name,
              users.nickname
            from gym_memberships
            join users on users.id = gym_memberships.user_id
            where gym_memberships.gym_id = ?
            order by gym_memberships.created_at desc, gym_memberships.id desc
            """,
            (gym_id,),
        ).fetchall()
        active_members_rows = [row for row in active_memberships if row["status"] == "active"]
        active_members_count = len(active_members_rows)
        trainer_members_count = sum(1 for row in active_members_rows if row["active_role"] == "trainer")
        pending_join_requests_row = connection.execute(
            "select count(*) as count from gym_join_requests where gym_id = ? and status = 'pending'",
            (gym_id,),
        ).fetchone()

        new_members_in_window = 0
        role_mix = {"athlete_only": 0, "trainer_capable": 0, "admin_capable": 0}
        recent_members = []
        for row in active_members_rows:
            created_at = datetime.fromisoformat(row["created_at"])
            if created_at.date() >= window_start:
                new_members_in_window += 1
            available_roles = validation.decode_roles(row["roles_json"])
            if "admin" in available_roles:
                role_mix["admin_capable"] += 1
            elif "trainer" in available_roles:
                role_mix["trainer_capable"] += 1
            else:
                role_mix["athlete_only"] += 1
            if len(recent_members) < 5:
                recent_members.append({
                    "membership_id": int(row["id"]),
                    "user_id": int(row["user_id"]),
                    "email": row["email"],
                    "display_name": row["display_name"],
                    "nickname": row["nickname"],
                    "active_role": row["active_role"],
                    "created_at": row["created_at"],
                })

        attendance_rows = connection.execute(
            """
            select classes_by_day.day, count(*) as classes, coalesce(sum(classes_by_day.capacity), 0) as capacity,
              coalesce(sum(classes_by_day.bookings), 0) as bookings, coalesce(sum(classes_by_day.attended), 0) as attended,
              coalesce(sum(classes_by_day.no_shows), 0) as no_shows
            from (
              select date(class_schedules.start_time) as day, class_schedules.id, class_schedules.capacity as capacity,
                count(class_bookings.id) as bookings,
                coalesce(sum(case when class_bookings.attendance_status = 'attended' then 1 else 0 end), 0) as attended,
                coalesce(sum(case when class_bookings.attendance_status = 'no_show' then 1 else 0 end), 0) as no_shows
              from class_schedules
              left join class_bookings on class_bookings.class_schedule_id = class_schedules.id
              where class_schedules.gym_id = ? and date(class_schedules.start_time) between ? and ?
              group by date(class_schedules.start_time), class_schedules.id, class_schedules.capacity
            ) classes_by_day
            group by classes_by_day.day
            order by classes_by_day.day asc
            """,
            (gym_id, window_start.isoformat(), today.isoformat()),
        ).fetchall()

        upcoming_row = connection.execute(
            """
            select count(*) as classes, coalesce(sum(upcoming_classes.capacity), 0) as capacity,
              coalesce(sum(upcoming_classes.bookings), 0) as bookings, coalesce(sum(upcoming_classes.waitlist_count), 0) as waitlist_spots,
              coalesce(sum(case when upcoming_classes.waitlist_count > 0 then 1 else 0 end), 0) as classes_with_waitlist,
              coalesce(sum(case when upcoming_classes.bookings >= upcoming_classes.capacity then 1 else 0 end), 0) as full_classes
            from (
              select class_schedules.id, class_schedules.title, class_schedules.start_time, class_schedules.capacity as capacity,
                count(distinct class_bookings.id) as bookings, count(distinct class_waitlist_entries.id) as waitlist_count
              from class_schedules
              left join class_bookings on class_bookings.class_schedule_id = class_schedules.id
              left join class_waitlist_entries on class_waitlist_entries.class_schedule_id = class_schedules.id
              where class_schedules.gym_id = ? and date(class_schedules.start_time) between ? and ?
              group by class_schedules.id, class_schedules.title, class_schedules.start_time, class_schedules.capacity
            ) upcoming_classes
            """,
            (gym_id, today.isoformat(), upcoming_end.isoformat()),
        ).fetchone()

        pressure_rows = connection.execute(
            """
            select class_schedules.id, class_schedules.title, class_schedules.start_time, class_schedules.capacity,
              count(distinct class_bookings.id) as bookings, count(distinct class_waitlist_entries.id) as waitlist_count
            from class_schedules
            left join class_bookings on class_bookings.class_schedule_id = class_schedules.id
            left join class_waitlist_entries on class_waitlist_entries.class_schedule_id = class_schedules.id
            where class_schedules.gym_id = ? and date(class_schedules.start_time) between ? and ?
            group by class_schedules.id, class_schedules.title, class_schedules.start_time, class_schedules.capacity
            having count(distinct class_waitlist_entries.id) > 0 or count(distinct class_bookings.id) >= class_schedules.capacity
            order by count(distinct class_waitlist_entries.id) desc,
                     (cast(count(distinct class_bookings.id) as real) / case when class_schedules.capacity <= 0 then 1 else class_schedules.capacity end) desc,
                     class_schedules.start_time asc
            limit 5
            """,
            (gym_id, today.isoformat(), upcoming_end.isoformat()),
        ).fetchall()

        problem_rows = connection.execute(
            """
            select class_schedules.id, class_schedules.title, class_schedules.start_time, class_schedules.capacity,
              count(class_bookings.id) as bookings,
              coalesce(sum(case when class_bookings.attendance_status = 'attended' then 1 else 0 end), 0) as attended,
              coalesce(sum(case when class_bookings.attendance_status = 'no_show' then 1 else 0 end), 0) as no_shows
            from class_schedules
            left join class_bookings on class_bookings.class_schedule_id = class_schedules.id
            where class_schedules.gym_id = ? and date(class_schedules.start_time) between ? and ?
            group by class_schedules.id, class_schedules.title, class_schedules.start_time, class_schedules.capacity
            having count(class_bookings.id) > 0 and (
              cast(count(class_bookings.id) as real) / case when class_schedules.capacity <= 0 then 1 else class_schedules.capacity end < 0.5
              or cast(coalesce(sum(case when class_bookings.attendance_status = 'no_show' then 1 else 0 end), 0) as real) / count(class_bookings.id) >= 0.25
            )
            order by cast(coalesce(sum(case when class_bookings.attendance_status = 'no_show' then 1 else 0 end), 0) as real) / count(class_bookings.id) desc,
                     cast(count(class_bookings.id) as real) / case when class_schedules.capacity <= 0 then 1 else class_schedules.capacity end asc,
                     class_schedules.start_time desc
            limit 5
            """,
            (gym_id, window_start.isoformat(), today.isoformat()),
        ).fetchall()

        totals = {"classes": 0, "capacity": 0, "bookings": 0, "attended": 0, "no_shows": 0}
        daily: list[dict[str, Any]] = []
        rows_by_day = {row["day"]: row for row in attendance_rows}
        current_day = window_start
        while current_day <= today:
            key = current_day.isoformat()
            row = rows_by_day.get(key)
            classes = int(row["classes"]) if row is not None else 0
            capacity = int(row["capacity"]) if row is not None else 0
            bookings = int(row["bookings"]) if row is not None else 0
            attended = int(row["attended"]) if row is not None else 0
            no_shows = int(row["no_shows"]) if row is not None else 0
            totals["classes"] += classes
            totals["capacity"] += capacity
            totals["bookings"] += bookings
            totals["attended"] += attended
            totals["no_shows"] += no_shows
            daily.append({"date": key, "classes": classes, "capacity": capacity, "bookings": bookings, "attended": attended, "no_shows": no_shows, "utilization_rate": 0.0 if capacity <= 0 else round((bookings / capacity) * 100, 1)})
            current_day += timedelta(days=1)

        attendance_rate = 0.0 if totals["bookings"] <= 0 else round((totals["attended"] / totals["bookings"]) * 100, 1)
        no_show_rate = 0.0 if totals["bookings"] <= 0 else round((totals["no_shows"] / totals["bookings"]) * 100, 1)
        utilization_rate = 0.0 if totals["capacity"] <= 0 else round((totals["bookings"] / totals["capacity"]) * 100, 1)

        return {
            "overview": {
                "window_days": validated_window_days,
                "active_members": active_members_count,
                "active_trainers": trainer_members_count,
                "pending_join_requests": int(pending_join_requests_row["count"] if pending_join_requests_row else 0),
                "classes_in_window": totals["classes"],
                "bookings_in_window": totals["bookings"],
                "attended_in_window": totals["attended"],
                "no_shows_in_window": totals["no_shows"],
                "attendance_rate_in_window": attendance_rate,
                "utilization_rate_in_window": utilization_rate,
                "no_show_rate_in_window": no_show_rate,
                "upcoming_classes_next_7_days": int(upcoming_row["classes"] if upcoming_row else 0),
                "upcoming_bookings_next_7_days": int(upcoming_row["bookings"] if upcoming_row else 0),
                "upcoming_capacity_next_7_days": int(upcoming_row["capacity"] if upcoming_row else 0),
                "upcoming_waitlist_spots_next_7_days": int(upcoming_row["waitlist_spots"] if upcoming_row else 0),
                "upcoming_classes_with_waitlist_next_7_days": int(upcoming_row["classes_with_waitlist"] if upcoming_row else 0),
                "upcoming_full_classes_next_7_days": int(upcoming_row["full_classes"] if upcoming_row else 0),
                "new_members_in_window": new_members_in_window,
                "role_mix": role_mix,
            },
            "recent_members": recent_members,
            "daily_attendance": daily,
            "pressure_classes": [
                {"id": int(row["id"]), "title": row["title"], "start_time": row["start_time"], "capacity": int(row["capacity"]), "bookings": int(row["bookings"]), "waitlist_count": int(row["waitlist_count"]), "utilization_rate": 0.0 if int(row["capacity"]) <= 0 else round((int(row["bookings"]) / int(row["capacity"])) * 100, 1)}
                for row in pressure_rows
            ],
            "problem_classes": [
                {"id": int(row["id"]), "title": row["title"], "start_time": row["start_time"], "capacity": int(row["capacity"]), "bookings": int(row["bookings"]), "attended": int(row["attended"]), "no_shows": int(row["no_shows"]), "utilization_rate": 0.0 if int(row["capacity"]) <= 0 else round((int(row["bookings"]) / int(row["capacity"])) * 100, 1), "attendance_rate": 0.0 if int(row["bookings"]) <= 0 else round((int(row["attended"]) / int(row["bookings"])) * 100, 1), "no_show_rate": 0.0 if int(row["bookings"]) <= 0 else round((int(row["no_shows"]) / int(row["bookings"])) * 100, 1)}
                for row in problem_rows
            ],
        }
    finally:
        connection.close()


@app.get("/uploads/{file_path:path}")
def uploaded_file(file_path: str) -> FileResponse:
    candidate = (settings.UPLOADS_ROOT / file_path).resolve()
    uploads_root = settings.UPLOADS_ROOT.resolve()
    if not candidate.is_file() or uploads_root not in candidate.parents:
        raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Uploaded file not found.")
    return FileResponse(candidate)
