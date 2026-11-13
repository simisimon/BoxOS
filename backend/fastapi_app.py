from __future__ import annotations

import logging
import threading
import time
from collections import defaultdict, deque
from contextlib import asynccontextmanager
from http import HTTPStatus
from pathlib import Path
from typing import Any
import secrets
from datetime import date, datetime, timedelta


from fastapi import Depends, FastAPI, Header, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel

from backend import announcement_service, audit, auth_service, community_service, db, membership_service, notifications_core, payment_service, plan_service, programming_service, schedule_service, security, settings, session_auth, validation

logger = logging.getLogger("boxos.backend")


def _log_delivery_token(kind: str, email: str, token: str) -> None:
    """Surface tokens that would normally be emailed. The value is only logged when
    BOXOS_LOG_DELIVERY_TOKENS is enabled (dev default) so it never leaks in production."""
    if settings.LOG_DELIVERY_TOKENS:
        logger.info("%s token for %s: %s", kind, email, token)
    else:
        logger.info("%s token issued for %s (value suppressed).", kind, email)


_rate_lock = threading.Lock()
_rate_buckets: dict[str, deque[float]] = defaultdict(deque)


def reset_rate_limits() -> None:
    """Clear all in-memory rate-limit state. Intended for test isolation."""
    with _rate_lock:
        _rate_buckets.clear()


def _client_identifier(request: Request) -> str:
    return request.client.host if request.client is not None else "unknown"


def rate_limit(scope: str, *, limit: int, window_seconds: float):
    """Build a dependency that throttles a client (by IP) to `limit` requests per
    rolling `window_seconds` for the given scope. In-memory and per-process, which is
    adequate for a single-instance deployment; swap for a shared store when scaling out."""

    def dependency(request: Request) -> None:
        if not settings.RATE_LIMIT_ENABLED:
            return
        key = f"{scope}:{_client_identifier(request)}"
        now = time.monotonic()
        cutoff = now - window_seconds
        with _rate_lock:
            bucket = _rate_buckets[key]
            while bucket and bucket[0] <= cutoff:
                bucket.popleft()
            if len(bucket) >= limit:
                retry_after = max(1, int(bucket[0] + window_seconds - now) + 1)
                raise HTTPException(
                    status_code=HTTPStatus.TOO_MANY_REQUESTS.value,
                    detail="Too many requests. Please slow down and try again later.",
                    headers={"Retry-After": str(retry_after)},
                )
            bucket.append(now)

    return dependency


class LoginRequest(BaseModel):
    email: str
    password: str


class RefreshRequest(BaseModel):
    refresh_token: str


class SignupRequest(BaseModel):
    email: str
    password: str


class EmailRequest(BaseModel):
    email: str


class VerifyEmailRequest(BaseModel):
    token: str


class ResetPasswordRequest(BaseModel):
    token: str
    new_password: str
    logout_other_sessions: bool = False


class ChangePasswordRequest(BaseModel):
    current_password: str
    new_password: str
    logout_other_sessions: bool = False


class DeleteAccountRequest(BaseModel):
    current_password: str
    # Required to delete boxes the user owns alone and that have no other
    # members; those boxes are deleted together with the account.
    delete_empty_gyms: bool = False


class AddGymOwnerRequest(BaseModel):
    user_id: int


class DeviceRegisterRequest(BaseModel):
    device_token: str
    platform: str


class DeviceTokenRequest(BaseModel):
    device_token: str


class UpdateProfileRequest(BaseModel):
    display_name: str
    nickname: str


class CreateGymRequest(BaseModel):
    name: str
    logo_url: str
    timezone: str = "UTC"  # Default to UTC if not provided


class UpdateGymRequest(BaseModel):
    # Every field is optional: only the ones sent are changed.
    name: str | None = None
    logo_url: str | None = None
    timezone: str | None = None


class ScheduleClassRequest(BaseModel):
    title: str
    class_type: str
    start_time: str
    duration_minutes: int | None = None
    duration: int | None = None
    capacity: int
    trainer_user_id: int | None = None
    recurrence_frequency: str | None = None
    occurrence_count: int | None = None


class UpdateScheduleClassRequest(ScheduleClassRequest):
    id: int


class ClassTemplateRequest(BaseModel):
    title: str
    class_type: str
    weekdays: list[int]
    start_time: str
    duration_minutes: int
    capacity: int
    trainer_user_id: int | None = None


class UpdateClassTemplateRequest(ClassTemplateRequest):
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


class JoinGymRequest(GymIdRequest):
    # Optional plan the athlete would like; becomes a plan request the owner
    # reviews once the join request is approved.
    plan_id: int | None = None


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


class UpdateActiveRoleRequest(BaseModel):
    role: str


class ReviewJoinRequestBody(BaseModel):
    request_id: int
    decision: str


class AssignRoleRequest(BaseModel):
    user_id: int
    role: str | None = None
    roles: list[str] | None = None
    # New roster-edit fields. All optional so the existing call sites that only
    # send `user_id` + `roles` keep working unchanged.
    active_role: str | None = None
    status: str | None = None
    admin_note: str | None = None


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


class GymLogoUploadRequest(BaseModel):
    filename: str
    content_type: str
    data_base64: str


class AvatarUploadRequest(BaseModel):
    filename: str
    content_type: str
    data_base64: str


class DailyWorkoutSetPayload(BaseModel):
    reps: int
    value: float | None = None


class DailyWorkoutSectionPayload(BaseModel):
    title: str | None = None
    description: str
    score_type: str
    # Structured block (docs/admin-ui-reference.md §3.1); all optional.
    kind: str | None = None
    exercise_name: str | None = None
    set_unit: str | None = None
    sets: list[DailyWorkoutSetPayload] | None = None
    coach_notes: str | None = None
    member_notes: str | None = None


class DailyWorkoutRequest(BaseModel):
    scheduled_date: str
    title: str
    sections: list[DailyWorkoutSectionPayload]
    status: str | None = None


class DailyWorkoutUpdateRequest(DailyWorkoutRequest):
    id: int


class DailyWorkoutImportRow(BaseModel):
    scheduled_date: str
    title: str
    status: str | None = None
    sections: list[DailyWorkoutSectionPayload]


class DailyWorkoutImportRequest(BaseModel):
    rows: list[DailyWorkoutImportRow]


class DailyWorkoutPublishRequest(BaseModel):
    id: int


class DailyWorkoutDuplicateRequest(BaseModel):
    source_date: str
    target_date: str


class ChatMessageCreateRequest(BaseModel):
    body: str


@asynccontextmanager
async def lifespan(_: FastAPI):
    db.init_db()
    yield


app = FastAPI(title="BoxOS Backend", version="0.1.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ALLOW_ORIGINS,
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.exception_handler(validation.ApiError)
async def handle_api_error(_: Request, error: validation.ApiError) -> JSONResponse:
    return JSONResponse(status_code=error.status.value, content={"detail": error.message})


@app.exception_handler(Exception)
async def handle_unexpected_error(_: Request, error: Exception) -> JSONResponse:
    logger.exception("Unhandled error while processing request", exc_info=error)
    return JSONResponse(
        status_code=HTTPStatus.INTERNAL_SERVER_ERROR.value,
        content={"detail": "Internal server error."},
    )


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
            detail="The owner role is required for this action.",
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
            detail="The owner or trainer role is required for this action.",
        )
    return session


def require_admin_gym_session(
    session: dict[str, Any] = Depends(require_session),
) -> dict[str, Any]:
    if session["role"] != "admin":
        raise HTTPException(
            status_code=HTTPStatus.FORBIDDEN.value,
            detail="The owner role is required for this action.",
        )
    if session["active_gym_id"] is None:
        raise HTTPException(
            status_code=HTTPStatus.FORBIDDEN.value,
            detail="An active owner gym context is required.",
        )
    return session


def _signup(body: SignupRequest, *, account_type: str) -> dict[str, Any]:
    if not settings.SIGNUP_ENABLED:
        raise HTTPException(
            status_code=HTTPStatus.FORBIDDEN.value,
            detail="Sign-up is closed. Ask the BoxOS team for an account.",
        )
    email = validation.require_email(body.email)
    password = validation.require_password(body.password)
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
                returning id
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
            user_id = int(cursor.fetchone()["id"])
            token = auth_service.issue_verification_token(connection, user_id)
        _log_delivery_token("Verification", email, token)
        return {"message": "Account created. Check the backend log for the verification token."}
    finally:
        connection.close()


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/auth/login")
def login(
    body: LoginRequest,
    _: None = Depends(rate_limit("login", limit=10, window_seconds=60)),
) -> dict[str, str]:
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
            select id, email, role, roles_json, display_name, nickname, account_type, active_gym_id, profile_image_url
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
    display_name = validation.require_display_name(body.display_name)
    nickname = validation.require_nickname(body.nickname)
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
            "select id, email, role, roles_json, display_name, nickname, account_type, active_gym_id, profile_image_url from users where id = ?",
            (session["user_id"],),
        ).fetchone()
        if user is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Profile not found.")
        return membership_service.profile_payload(user)
    finally:
        connection.close()


@app.post("/profile/avatar", status_code=HTTPStatus.CREATED.value)
def upload_avatar(
    body: AvatarUploadRequest,
    session: dict[str, Any] = Depends(require_session),
) -> dict[str, Any]:
    """Upload a new profile photo and persist its URL on the user.

    Mirrors the announcement/gym-logo upload contract: base64 body so this
    works the same way from web + mobile clients without juggling multipart.
    The previous on-disk file (if any) is removed best-effort so an athlete
    cycling through avatars doesn't leave orphans in the uploads directory.
    """
    validation.require_upload_filename(body.filename)
    content_type = validation.require_avatar_content_type(body.content_type)
    raw_bytes = validation.require_base64_bytes(
        body.data_base64,
        label="Avatar data",
        max_bytes=settings.MAX_AVATAR_BYTES,
    )
    extension = settings.ALLOWED_AVATAR_CONTENT_TYPES[content_type]
    stored_name = f"avatar_{secrets.token_urlsafe(12)}{extension}"
    file_path = settings.AVATARS_DIR / stored_name
    file_path.write_bytes(raw_bytes)
    new_url = f"/uploads/avatars/{stored_name}"
    connection = db.get_connection()
    try:
        with connection:
            previous = connection.execute(
                "select profile_image_url from users where id = ? and deleted_at is null",
                (session["user_id"],),
            ).fetchone()
            connection.execute(
                "update users set profile_image_url = ?, updated_at = ? where id = ? and deleted_at is null",
                (new_url, security.isoformat(security.now_utc()), session["user_id"]),
            )
        if previous is not None:
            _remove_previous_avatar(previous["profile_image_url"])
        user = connection.execute(
            "select id, email, role, roles_json, display_name, nickname, account_type, active_gym_id, profile_image_url from users where id = ?",
            (session["user_id"],),
        ).fetchone()
        if user is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Profile not found.")
        return membership_service.profile_payload(user)
    finally:
        connection.close()


@app.delete("/profile/avatar")
def delete_avatar(session: dict[str, Any] = Depends(require_session)) -> dict[str, Any]:
    connection = db.get_connection()
    try:
        with connection:
            previous = connection.execute(
                "select profile_image_url from users where id = ? and deleted_at is null",
                (session["user_id"],),
            ).fetchone()
            connection.execute(
                "update users set profile_image_url = '', updated_at = ? where id = ? and deleted_at is null",
                (security.isoformat(security.now_utc()), session["user_id"]),
            )
        if previous is not None:
            _remove_previous_avatar(previous["profile_image_url"])
        user = connection.execute(
            "select id, email, role, roles_json, display_name, nickname, account_type, active_gym_id, profile_image_url from users where id = ?",
            (session["user_id"],),
        ).fetchone()
        if user is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Profile not found.")
        return membership_service.profile_payload(user)
    finally:
        connection.close()


def _remove_previous_avatar(stored_url: str | None) -> None:
    """Best-effort cleanup of a previous avatar file. Silently no-ops on a
    missing file so a race or manual cleanup never breaks the upload itself."""
    if not stored_url:
        return
    name = Path(str(stored_url)).name
    if not name:
        return
    candidate = (settings.AVATARS_DIR / name).resolve()
    avatars_root = settings.AVATARS_DIR.resolve()
    if avatars_root not in candidate.parents:
        return
    try:
        candidate.unlink(missing_ok=True)
    except OSError:
        pass


@app.patch("/profile/active-role")
def update_active_role(
    body: UpdateActiveRoleRequest,
    session: dict[str, Any] = Depends(require_session),
) -> dict[str, Any]:
    role = validation.require_role_value(body.role)
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
            "select id, email, role, roles_json, display_name, nickname, account_type, active_gym_id, profile_image_url from users where id = ?",
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
            "select id, email, role, roles_json, display_name, nickname, account_type, active_gym_id, profile_image_url from users where id = ?",
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
    preferences = validation.require_notification_preferences(payload)
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
    name = validation.require_gym_name(body.name)
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


@app.post("/gyms/logo", status_code=HTTPStatus.CREATED.value)
def upload_gym_logo(
    body: GymLogoUploadRequest,
    _: dict[str, Any] = Depends(require_admin_session),
) -> dict[str, str]:
    filename = validation.require_upload_filename(body.filename)
    content_type = validation.require_gym_logo_content_type(body.content_type)
    raw_bytes = validation.require_base64_bytes(body.data_base64, label="Logo data", max_bytes=settings.MAX_GYM_LOGO_BYTES)
    extension = settings.ALLOWED_GYM_LOGO_CONTENT_TYPES[content_type]
    stored_name = f"gym_logo_{secrets.token_urlsafe(12)}{extension}"
    file_path = settings.GYM_LOGOS_DIR / stored_name
    file_path.write_bytes(raw_bytes)
    return {"filename": filename, "logo_url": f"/uploads/gym_logos/{stored_name}"}


def require_gym_owner_session(
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, Any]:
    """Owner of the active gym: an active membership there that holds the admin role."""
    connection = db.get_connection()
    try:
        membership = connection.execute(
            """
            select roles_json from gym_memberships
            where user_id = ? and gym_id = ? and status = 'active'
            """,
            (session["user_id"], session["active_gym_id"]),
        ).fetchone()
    finally:
        connection.close()
    if membership is None or "admin" not in validation.decode_roles(membership["roles_json"]):
        raise HTTPException(
            status_code=HTTPStatus.FORBIDDEN.value,
            detail="Only the box owner can edit the box identity.",
        )
    return session


@app.patch("/gyms/current")
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
            updated["name"] = validation.require_gym_name(body.name)
        if body.logo_url is not None:
            logo_url = body.logo_url.strip()
            updated["logo_url"] = validation.require_logo_url(logo_url) if logo_url else ""
        if body.timezone is not None:
            timezone = validation.require_timezone(body.timezone)
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


@app.post("/gyms/join-requests", status_code=HTTPStatus.CREATED.value)
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


@app.get("/gyms/join-requests")
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


def _member_payload_with_plan(row: Any, summaries: dict[int, dict[str, Any]]) -> dict[str, Any]:
    payload = membership_service.role_managed_member_payload(row)
    summary = summaries.get(int(row["user_id"]), {})
    payload["plan"] = summary.get("plan")
    payload["has_plan_request"] = bool(summary.get("has_plan_request"))
    payload["extra_tokens_remaining"] = int(summary.get("extra_tokens_remaining") or 0)
    return payload


@app.get("/roles/users")
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
            connection, session["active_gym_id"], _gym_timezone(connection, session["active_gym_id"])
        )
        return {"users": [_member_payload_with_plan(row, summaries) for row in rows]}
    finally:
        connection.close()


@app.patch("/roles/users")
def assign_role(
    body: AssignRoleRequest,
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, Any]:
    payload = body.model_dump(exclude_none=True)
    user_id = validation.require_user_id(body.user_id)
    roles = validation.require_role_list(payload)
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
        validation.require_membership_status(body.status) if body.status is not None else None
    )
    desired_note: str | None = (
        validation.require_admin_note(body.admin_note) if body.admin_note is not None else None
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
            connection, session["active_gym_id"], _gym_timezone(connection, session["active_gym_id"])
        )
        return _member_payload_with_plan(user, summaries)
    finally:
        connection.close()


# --- Membership plans ---------------------------------------------------------
#
# Owners define plans and review plan requests; athletes see the box's plans,
# request one, and see their own plan. Logic lives in backend/plan_service.py.


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


@app.get("/membership/settings")
def get_membership_settings(
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, Any]:
    connection = db.get_connection()
    try:
        return _membership_settings_payload(plan_service.gym_plan_settings(connection, session["active_gym_id"]))
    finally:
        connection.close()


@app.patch("/membership/settings")
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
# Each box connects its own Stripe account; see backend/payment_service.py.


@app.get("/payments/stripe")
def get_stripe_status(
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, Any]:
    connection = db.get_connection()
    try:
        return payment_service.stripe_status_payload(connection, session["active_gym_id"])
    finally:
        connection.close()


@app.post("/payments/stripe/onboarding")
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


@app.post("/membership/me/checkout")
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


@app.post("/stripe/webhook")
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


@app.get("/membership/plans")
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


@app.get("/gyms/{gym_id}/plans")
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


@app.post("/membership/plans", status_code=HTTPStatus.CREATED.value)
def create_membership_plan(
    body: MembershipPlanRequest,
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, Any]:
    gym_id = session["active_gym_id"]
    fields = plan_service.require_plan_fields(body.model_dump(), _class_type_names(session["active_gym_id"]))
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


@app.patch("/membership/plans")
def update_membership_plan(
    body: UpdateMembershipPlanRequest,
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, Any]:
    """Edit a plan. Members already on the plan keep the price and limits they
    were given; the change applies to new requests and assignments."""
    gym_id = session["active_gym_id"]
    fields = plan_service.require_plan_fields(body.model_dump(), _class_type_names(session["active_gym_id"]))
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


@app.patch("/membership/plans/archive")
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


@app.get("/membership/me")
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


@app.post("/membership/requests", status_code=HTTPStatus.CREATED.value)
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


@app.delete("/membership/requests")
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


@app.get("/membership/requests")
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


@app.patch("/membership/requests")
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
            notifications_core.create_notification(
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


@app.get("/membership/members/{user_id}")
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


@app.get("/membership/members/{user_id}/bookings")
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


@app.get("/membership/me/bookings")
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


@app.post("/membership/extra-tokens", status_code=HTTPStatus.CREATED.value)
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
            notifications_core.create_notification(
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


@app.delete("/membership/extra-tokens/{credit_id}")
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


@app.post("/membership/assignments", status_code=HTTPStatus.CREATED.value)
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
            notifications_core.create_notification(
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


@app.patch("/membership/assignments")
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


@app.post("/membership/assignments/end")
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
            notifications_core.create_notification(
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
    title = validation.require_announcement_title(body.title)
    description = validation.require_announcement_description(body.description)
    image_url = validation.require_optional_image_url(body.image_url)
    connection = db.get_connection()
    try:
        timestamp = security.isoformat(security.now_utc())
        with connection:
            cursor = connection.execute(
                "insert into announcements (gym_id, title, description, image_url, created_by_user_id, created_at, updated_at) values (?, ?, ?, ?, ?, ?, ?) returning id",
                (session["active_gym_id"], title, description, image_url, session["user_id"], timestamp, timestamp),
            )
            new_announcement_id = int(cursor.fetchone()["id"])
            row = announcement_service.get_announcement_row(connection, announcement_id=new_announcement_id, gym_id=session["active_gym_id"])
            if row is None:
                raise HTTPException(status_code=HTTPStatus.INTERNAL_SERVER_ERROR.value, detail="Announcement creation failed.")
            audit.write_audit_log(
                connection,
                gym_id=session["active_gym_id"],
                actor_user_id=session["user_id"],
                action="announcement_created",
                entity_type="announcement",
                entity_id=new_announcement_id,
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
    filename = validation.require_upload_filename(body.filename)
    content_type = validation.require_announcement_image_content_type(body.content_type)
    raw_bytes = validation.require_base64_bytes(body.data_base64, label="Image data", max_bytes=settings.MAX_ANNOUNCEMENT_IMAGE_BYTES)
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
    announcement_id = validation.require_user_id(body.id)
    title = validation.require_announcement_title(body.title)
    description = validation.require_announcement_description(body.description)
    image_url = validation.require_optional_image_url(body.image_url)
    connection = db.get_connection()
    try:
        existing = connection.execute(
            "select id, created_by_user_id from announcements where id = ? and gym_id = ?",
            (announcement_id, session["active_gym_id"]),
        ).fetchone()
        if existing is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Announcement not found.")
        announcement_service.ensure_announcement_manage_permission(existing, session)
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
        announcement_service.ensure_announcement_manage_permission(existing, session)
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
                "insert into announcement_likes (announcement_id, user_id, created_at) values (?, ?, ?) on conflict do nothing",
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
    announcement_id = validation.require_user_id(body.announcement_id)
    comment_body = validation.require_announcement_comment_body(body.body)
    connection = db.get_connection()
    try:
        announcement = announcement_service.get_announcement_row(connection, announcement_id=announcement_id, gym_id=session["active_gym_id"])
        if announcement is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Announcement not found.")
        timestamp = security.isoformat(security.now_utc())
        with connection:
            cursor = connection.execute(
                "insert into announcement_comments (announcement_id, gym_id, user_id, body, created_at, updated_at) values (?, ?, ?, ?, ?, ?) returning id",
                (announcement_id, session["active_gym_id"], session["user_id"], comment_body, timestamp, timestamp),
            )
            new_comment_id = int(cursor.fetchone()["id"])
            comment = announcement_service.get_announcement_comment_row(connection, new_comment_id)
            if comment is None:
                raise HTTPException(status_code=HTTPStatus.INTERNAL_SERVER_ERROR.value, detail="Comment creation failed.")
            announcement_service.create_announcement_comment_notification(connection, recipient_user_id=int(announcement["created_by_user_id"]), actor_user_id=int(session["user_id"]), gym_id=int(session["active_gym_id"]), announcement_id=announcement_id, announcement_title=str(announcement["title"]), comment_body=comment_body)
            audit.write_audit_log(connection, gym_id=session["active_gym_id"], actor_user_id=session["user_id"], action="announcement_comment_created", entity_type="announcement_comment", entity_id=new_comment_id, details={"announcement_id": announcement_id})
        return {"comment": announcement_service.announcement_comment_payload(comment, current_user_id=session["user_id"], session_role=str(session["role"]))}
    finally:
        connection.close()


@app.patch("/announcements/comments")
def update_announcement_comment(
    body: AnnouncementCommentUpdateRequest,
    session: dict[str, Any] = Depends(require_active_gym_member_session),
) -> dict[str, Any]:
    comment_id = validation.require_user_id(body.id)
    comment_body = validation.require_announcement_comment_body(body.body)
    connection = db.get_connection()
    try:
        existing = announcement_service.get_announcement_comment_row(connection, comment_id)
        if existing is None or int(existing["gym_id"]) != int(session["active_gym_id"]):
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Comment not found.")
        announcement_service.ensure_announcement_comment_manage_permission(existing, session)
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
        announcement_service.ensure_announcement_comment_manage_permission(existing, session)
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
        with connection:
            schedule_service.materialize_gym_sessions(
                connection,
                gym_id=session["active_gym_id"],
                gym_timezone=_gym_timezone(connection, session["active_gym_id"]),
            )
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
              class_schedules.class_template_id,
              trainer.display_name as assigned_trainer_display_name,
              trainer.nickname as assigned_trainer_nickname
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


def _gym_timezone(connection: Any, gym_id: int) -> str:
    gym_row = connection.execute("select timezone from gyms where id = ?", (gym_id,)).fetchone()
    if gym_row is None:
        raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Active gym not found.")
    return str(gym_row["timezone"])


def _require_gym_trainer(connection: Any, gym_id: int, trainer_user_id: int | None) -> None:
    if trainer_user_id is None:
        return
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
        (gym_id, trainer_user_id),
    ).fetchone()
    if assigned_trainer is None:
        raise HTTPException(status_code=HTTPStatus.BAD_REQUEST.value, detail="Selected trainer is not active in this gym.")


def _class_type_names(gym_id: int) -> list[str]:
    """Built-in class types plus the ones the gym's owner added."""
    connection = db.get_connection()
    try:
        rows = connection.execute(
            "select name from gym_class_types where gym_id = ? order by created_at, id",
            (gym_id,),
        ).fetchall()
    finally:
        connection.close()
    return [*validation.BUILTIN_CLASS_TYPES, *(row["name"] for row in rows)]


def _class_template_fields(body: ClassTemplateRequest, gym_id: int) -> dict[str, Any]:
    return {
        "title": validation.require_schedule_title(body.title),
        "class_type": validation.require_class_type(body.class_type, _class_type_names(gym_id)),
        "weekdays": validation.require_weekdays(body.weekdays),
        "start_local_time": validation.require_local_time(body.start_time),
        "duration_minutes": validation.require_duration_minutes(body.duration_minutes),
        "capacity": validation.require_capacity(body.capacity),
        "trainer_user_id": validation.require_optional_user_id(body.trainer_user_id),
    }


def _class_template_audit_details(fields: dict[str, Any]) -> dict[str, Any]:
    return {
        "title": fields["title"],
        "class_type": fields["class_type"],
        "weekdays": fields["weekdays"],
        "start_time": fields["start_local_time"],
        "duration_minutes": fields["duration_minutes"],
        "capacity": fields["capacity"],
        "trainer_user_id": fields["trainer_user_id"],
    }


@app.get("/schedule/templates")
def list_class_templates(
    session: dict[str, Any] = Depends(require_schedule_manager_session),
) -> dict[str, list[dict[str, Any]]]:
    connection = db.get_connection()
    try:
        rows = schedule_service.list_class_template_rows(connection, session["active_gym_id"])
        return {"templates": [schedule_service.class_template_payload(row) for row in rows]}
    finally:
        connection.close()


@app.post("/schedule/templates", status_code=HTTPStatus.CREATED.value)
def create_class_template(
    body: ClassTemplateRequest,
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, Any]:
    fields = _class_template_fields(body, session["active_gym_id"])
    connection = db.get_connection()
    try:
        gym_timezone = _gym_timezone(connection, session["active_gym_id"])
        _require_gym_trainer(connection, session["active_gym_id"], fields["trainer_user_id"])
        timestamp = security.isoformat(security.now_utc())
        with connection:
            template_id = int(
                connection.execute(
                    """
                    insert into class_templates (
                      gym_id, title, class_type, weekdays, start_local_time, duration_minutes, capacity,
                      assigned_trainer_user_id, created_by_user_id, updated_by_user_id, created_at, updated_at
                    )
                    values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    returning id
                    """,
                    (
                        session["active_gym_id"],
                        fields["title"],
                        fields["class_type"],
                        schedule_service.encode_weekdays(fields["weekdays"]),
                        fields["start_local_time"],
                        fields["duration_minutes"],
                        fields["capacity"],
                        fields["trainer_user_id"],
                        session["user_id"],
                        session["user_id"],
                        timestamp,
                        timestamp,
                    ),
                ).fetchone()["id"]
            )
            row = schedule_service.get_class_template_row(connection, template_id)
            if row is None:
                raise HTTPException(status_code=HTTPStatus.INTERNAL_SERVER_ERROR.value, detail="Class creation failed.")
            schedule_service.materialize_template_sessions(connection, row, gym_timezone=gym_timezone)
            audit.write_audit_log(
                connection,
                gym_id=session["active_gym_id"],
                actor_user_id=session["user_id"],
                action="class_template_created",
                entity_type="class_template",
                entity_id=template_id,
                details=_class_template_audit_details(fields),
            )
        return {"template": schedule_service.class_template_payload(row)}
    finally:
        connection.close()


@app.patch("/schedule/templates")
def update_class_template(
    body: UpdateClassTemplateRequest,
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, Any]:
    template_id = validation.require_user_id(body.id)
    fields = _class_template_fields(body, session["active_gym_id"])
    connection = db.get_connection()
    try:
        existing = connection.execute(
            "select id from class_templates where id = ? and gym_id = ?",
            (template_id, session["active_gym_id"]),
        ).fetchone()
        if existing is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Class not found.")
        gym_timezone = _gym_timezone(connection, session["active_gym_id"])
        _require_gym_trainer(connection, session["active_gym_id"], fields["trainer_user_id"])
        with connection:
            connection.execute(
                """
                update class_templates
                set title = ?, class_type = ?, weekdays = ?, start_local_time = ?, duration_minutes = ?,
                    capacity = ?, assigned_trainer_user_id = ?, updated_by_user_id = ?, updated_at = ?
                where id = ?
                """,
                (
                    fields["title"],
                    fields["class_type"],
                    schedule_service.encode_weekdays(fields["weekdays"]),
                    fields["start_local_time"],
                    fields["duration_minutes"],
                    fields["capacity"],
                    fields["trainer_user_id"],
                    session["user_id"],
                    security.isoformat(security.now_utc()),
                    template_id,
                ),
            )
            row = schedule_service.get_class_template_row(connection, template_id)
            if row is None:
                raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Class not found.")
            detached_count = schedule_service.resync_template_sessions(
                connection,
                row,
                gym_timezone=gym_timezone,
                actor_user_id=session["user_id"],
            )
            audit.write_audit_log(
                connection,
                gym_id=session["active_gym_id"],
                actor_user_id=session["user_id"],
                action="class_template_updated",
                entity_type="class_template",
                entity_id=template_id,
                details={**_class_template_audit_details(fields), "detached_booked_sessions": detached_count},
            )
        return {
            "template": schedule_service.class_template_payload(row),
            "kept_booked_sessions": detached_count,
        }
    finally:
        connection.close()


@app.delete("/schedule/templates")
def delete_class_template(
    body: EntityIdRequest,
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, Any]:
    template_id = body.id
    connection = db.get_connection()
    try:
        existing = connection.execute(
            "select id, title from class_templates where id = ? and gym_id = ?",
            (template_id, session["active_gym_id"]),
        ).fetchone()
        if existing is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Class not found.")
        with connection:
            kept_count = schedule_service.remove_template_sessions(connection, template_id)
            connection.execute("delete from class_templates where id = ?", (template_id,))
            audit.write_audit_log(
                connection,
                gym_id=session["active_gym_id"],
                actor_user_id=session["user_id"],
                action="class_template_deleted",
                entity_type="class_template",
                entity_id=template_id,
                details={"title": existing["title"], "kept_booked_sessions": kept_count},
            )
        return {"deleted": True, "kept_booked_sessions": kept_count}
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
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, Any]:
    title = validation.require_schedule_title(body.title)
    class_type = validation.require_class_type(body.class_type, _class_type_names(session["active_gym_id"]))
    start_time = validation.require_future_datetime(body.start_time, label="Start time")
    duration_minutes = validation.require_schedule_duration_minutes(body.model_dump())
    capacity = validation.require_capacity(body.capacity)
    trainer_user_id = validation.require_optional_user_id(body.trainer_user_id)
    recurrence_frequency = validation.require_recurrence_frequency(body.recurrence_frequency)
    occurrence_count = validation.require_occurrence_count(
        body.occurrence_count,
        recurrence_frequency=recurrence_frequency,
    )
    connection = db.get_connection()
    try:
        gym_row = connection.execute(
            "select timezone from gyms where id = ?",
            (session["active_gym_id"],),
        ).fetchone()
        if gym_row is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Active gym not found.")
        start_times = schedule_service.build_recurrence_start_times(
            start_time,
            recurrence_frequency=recurrence_frequency,
            occurrence_count=occurrence_count,
            gym_timezone=gym_row["timezone"],
        )
        if recurrence_frequency != "none":
            for generated_start_time in start_times:
                if generated_start_time <= security.now_utc():
                    raise HTTPException(
                        status_code=HTTPStatus.BAD_REQUEST.value,
                        detail="Recurring classes must all be scheduled in the future.",
                    )
        _require_gym_trainer(connection, session["active_gym_id"], trainer_user_id)
        timestamp = security.isoformat(security.now_utc())
        with connection:
            schedule_ids: list[int] = []
            for generated_start_time in start_times:
                generated_end_time = generated_start_time + timedelta(minutes=duration_minutes)
                cursor = connection.execute(
                    """
                    insert into class_schedules (
                      gym_id, title, class_type, start_time, end_time, duration_minutes, capacity, assigned_trainer_user_id,
                      created_by_user_id, updated_by_user_id, created_at, updated_at
                    )
                    values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    returning id
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
                        session["user_id"],
                        session["user_id"],
                        timestamp,
                        timestamp,
                    ),
                )
                schedule_id = int(cursor.fetchone()["id"])
                schedule_ids.append(schedule_id)
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
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, Any]:
    schedule_id = validation.require_user_id(body.id)
    title = validation.require_schedule_title(body.title)
    class_type = validation.require_class_type(body.class_type, _class_type_names(session["active_gym_id"]))
    start_time = validation.require_future_datetime(body.start_time, label="Start time")
    duration_minutes = validation.require_schedule_duration_minutes(body.model_dump())
    capacity = validation.require_capacity(body.capacity)
    trainer_user_id = validation.require_optional_user_id(body.trainer_user_id)
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
        _require_gym_trainer(connection, session["active_gym_id"], trainer_user_id)
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
                    assigned_trainer_user_id = ?, updated_by_user_id = ?, updated_at = ?
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
    session: dict[str, Any] = Depends(require_admin_gym_session),
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
            "select id, gym_id, class_type, start_time, capacity from class_schedules where id = ? and gym_id = ?",
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
        check = plan_service.require_booking_allowed(
            connection,
            gym_id=schedule_row["gym_id"],
            user_id=session["user_id"],
            schedule_row=schedule_row,
        )
        with connection:
            connection.execute(
                """
                insert into class_bookings
                  (class_schedule_id, user_id, attendance_status, member_plan_id, token_credit_id, created_at)
                values (?, ?, 'booked', ?, ?, ?)
                """,
                (
                    schedule_id,
                    session["user_id"],
                    check.member_plan_id,
                    check.token_credit_id,
                    security.isoformat(security.now_utc()),
                ),
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


class CancelBookingRequest(BaseModel):
    class_id: int
    # The owner removes someone else's booking (e.g. they called to
    # cancel); members always cancel their own.
    user_id: int | None = None


@app.delete("/schedule/bookings")
def delete_class_booking(
    body: CancelBookingRequest,
    session: dict[str, Any] = Depends(require_active_gym_member_session),
) -> dict[str, str]:
    schedule_id = body.class_id
    user_id = session["user_id"] if body.user_id is None else body.user_id
    removing_other = user_id != session["user_id"]
    # Only the owner takes members off a class; trainers keep attendance.
    if removing_other and session["role"] != "admin":
        raise HTTPException(
            status_code=HTTPStatus.FORBIDDEN.value,
            detail="The owner role is required for this action.",
        )
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
            (schedule_id, user_id),
        ).fetchone()
        if existing_booking is None:
            raise HTTPException(
                status_code=HTTPStatus.NOT_FOUND.value,
                detail="This member has no booking for this class."
                if removing_other
                else "You do not have a booking for this class.",
            )
        with connection:
            connection.execute(
                "delete from class_bookings where class_schedule_id = ? and user_id = ?",
                (schedule_id, user_id),
            )
            connection.execute(
                """
                insert into class_booking_cancellations (class_schedule_id, user_id, cancelled_at, cancelled_by_user_id)
                values (?, ?, ?, ?)
                """,
                (schedule_id, user_id, security.isoformat(security.now_utc()), session["user_id"]),
            )
            promoted_user_id = plan_service.promote_next_eligible_waitlisted_user(connection, class_schedule_id=schedule_id)
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
            "select id, gym_id, class_type, start_time, capacity from class_schedules where id = ? and gym_id = ?",
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
        plan_service.require_booking_allowed(
            connection,
            gym_id=schedule_row["gym_id"],
            user_id=session["user_id"],
            schedule_row=schedule_row,
        )
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
    schedule_id = validation.require_user_id(body.class_id)
    user_id = validation.require_user_id(body.user_id)
    attendance_status = validation.require_attendance_status(body.attendance_status)
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
def signup(
    body: SignupRequest,
    _: None = Depends(rate_limit("signup", limit=5, window_seconds=60)),
) -> dict[str, Any]:
    return _signup(body, account_type="athlete")


@app.post("/auth/signup-admin")
@app.post("/auth/signup-owner")
def signup_admin(
    body: SignupRequest,
    _: None = Depends(rate_limit("signup-admin", limit=5, window_seconds=60)),
) -> dict[str, Any]:
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
def request_password_reset(
    body: EmailRequest,
    _: None = Depends(rate_limit("password-reset-request", limit=5, window_seconds=60)),
) -> dict[str, Any]:
    email = validation.require_email(body.email)
    connection = db.get_connection()
    try:
        user = connection.execute(
            "select id from users where email = ? and deleted_at is null",
            (email,),
        ).fetchone()
        if user is not None:
            with connection:
                token = auth_service.issue_password_reset_token(connection, user["id"])
            _log_delivery_token("Password reset", email, token)
        return {"message": "If the account exists, a reset token has been issued in the backend log."}
    finally:
        connection.close()


@app.post("/auth/reset-password")
def reset_password(
    body: ResetPasswordRequest,
    _: None = Depends(rate_limit("password-reset", limit=5, window_seconds=60)),
) -> dict[str, Any]:
    token = validation.require_token(body.token, label="Reset token")
    new_password = validation.require_password(body.new_password)
    logout_other_sessions = body.logout_other_sessions
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
def verify_email(
    body: VerifyEmailRequest,
    _: None = Depends(rate_limit("verify-email", limit=10, window_seconds=60)),
) -> dict[str, Any]:
    token = validation.require_token(body.token, label="Verification token")
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
def resend_verification(
    body: EmailRequest,
    _: None = Depends(rate_limit("resend-verification", limit=5, window_seconds=60)),
) -> dict[str, Any]:
    email = validation.require_email(body.email)
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
        _log_delivery_token("Verification", email, token)
        return {"message": "Verification token reissued. Check the backend log."}
    finally:
        connection.close()


@app.post("/auth/change-password")
def change_password(body: ChangePasswordRequest, session: dict[str, Any] = Depends(require_session)) -> dict[str, Any]:
    current_password = validation.require_password(body.current_password, label="Current password")
    new_password = validation.require_password(body.new_password, label="New password")
    logout_other_sessions = body.logout_other_sessions
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


@app.get("/auth/account/deletion-check")
def account_deletion_check(session: dict[str, Any] = Depends(require_session)) -> dict[str, Any]:
    """List what blocks deleting the account.

    ``gyms_needing_owner`` are boxes the user owns alone that still have other
    members: one of them must be made owner first. ``empty_gyms`` are boxes the
    user owns alone with no other members: they are deleted with the account.
    """
    connection = db.get_connection()
    try:
        gyms = membership_service.sole_owned_gyms(connection, session["user_id"])
        return {
            "gyms_needing_owner": [gym for gym in gyms if gym["members"]],
            "empty_gyms": [{"id": gym["id"], "name": gym["name"]} for gym in gyms if not gym["members"]],
        }
    finally:
        connection.close()


@app.post("/gyms/{gym_id}/owners")
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


@app.delete("/auth/account")
def delete_account(body: DeleteAccountRequest, session: dict[str, Any] = Depends(require_session)) -> dict[str, Any]:
    current_password = validation.require_password(body.current_password, label="Current password")
    connection = db.get_connection()
    try:
        user = connection.execute(
            "select * from users where id = ? and deleted_at is null",
            (session["user_id"],),
        ).fetchone()
        if user is None or not security.verify_password(current_password, user["password_hash"]):
            raise HTTPException(status_code=HTTPStatus.UNAUTHORIZED.value, detail="Current password is incorrect.")
        sole_owned = membership_service.sole_owned_gyms(connection, user["id"])
        gyms_needing_owner = [gym for gym in sole_owned if gym["members"]]
        if gyms_needing_owner:
            names = ", ".join(gym["name"] for gym in gyms_needing_owner)
            raise HTTPException(
                status_code=HTTPStatus.CONFLICT.value,
                detail=f"You are the only owner of {names}. Make another member owner before deleting your account.",
            )
        empty_gyms = [gym for gym in sole_owned if not gym["members"]]
        if empty_gyms and not body.delete_empty_gyms:
            names = ", ".join(gym["name"] for gym in empty_gyms)
            raise HTTPException(
                status_code=HTTPStatus.CONFLICT.value,
                detail=f"{names} has no other members and will be deleted with your account. Confirm to continue.",
            )
        with connection:
            now = security.now_utc()
            for gym in empty_gyms:
                connection.execute("delete from gyms where id = ?", (gym["id"],))
            # gyms.created_by_user_id cascades on delete, so the purge of this
            # user would take the boxes they created with it. Hand the
            # reference to a remaining owner.
            connection.execute(
                """
                update gyms
                set created_by_user_id = (
                  select gym_memberships.user_id
                  from gym_memberships
                  join users on users.id = gym_memberships.user_id
                  where gym_memberships.gym_id = gyms.id
                    and gym_memberships.user_id <> gyms.created_by_user_id
                    and gym_memberships.status = 'active'
                    and users.deleted_at is null
                    and gym_memberships.roles_json like '%"admin"%'
                  order by gym_memberships.created_at asc, gym_memberships.id asc
                  limit 1
                ), updated_at = ?
                where created_by_user_id = ?
                  and exists (
                    select 1
                    from gym_memberships
                    join users on users.id = gym_memberships.user_id
                    where gym_memberships.gym_id = gyms.id
                      and gym_memberships.user_id <> gyms.created_by_user_id
                      and gym_memberships.status = 'active'
                      and users.deleted_at is null
                      and gym_memberships.roles_json like '%"admin"%'
                  )
                """,
                (security.isoformat(now), user["id"]),
            )
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
def register_device(body: DeviceRegisterRequest, session: dict[str, Any] = Depends(require_session)) -> dict[str, Any]:
    device_token = validation.require_token(body.device_token, label="Device token")
    platform = validation.require_platform(body.platform)
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
def unregister_device(body: DeviceTokenRequest, session: dict[str, Any] = Depends(require_session)) -> dict[str, Any]:
    device_token = validation.require_token(body.device_token, label="Device token")
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
        can_manage = programming_service.can_view_drafts(session["role"])
        if can_manage:
            rows = connection.execute(
                f"""
                select {programming_service.DAILY_WORKOUT_COLUMNS}
                from daily_workouts
                where daily_workouts.gym_id = ?
                order by daily_workouts.scheduled_date asc
                """,
                (session["active_gym_id"],),
            ).fetchall()
        else:
            rows = connection.execute(
                f"""
                select {programming_service.DAILY_WORKOUT_COLUMNS}
                from daily_workouts
                where daily_workouts.gym_id = ? and daily_workouts.status = 'published'
                order by daily_workouts.scheduled_date asc
                """,
                (session["active_gym_id"],),
            ).fetchall()
        workouts = [
            programming_service.daily_workout_payload(
                connection,
                row,
                current_user_id=session["user_id"],
                can_edit=can_manage,
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
    sections = validation.require_workout_sections(
        [section.model_dump() for section in body.sections]
    )
    status = programming_service.require_workout_status(body.status or "draft")
    connection = db.get_connection()
    try:
        existing = connection.execute(
            "select id from daily_workouts where gym_id = ? and scheduled_date = ?",
            (session["active_gym_id"], scheduled_date),
        ).fetchone()
        if existing is not None:
            raise HTTPException(status_code=HTTPStatus.CONFLICT.value, detail="A workout already exists for this date.")
        timestamp = security.isoformat(security.now_utc())
        published_at = timestamp if status == "published" else None
        published_by = session["user_id"] if status == "published" else None
        with connection:
            cursor = connection.execute(
                """
                insert into daily_workouts (
                  gym_id, scheduled_date, title,
                  status, published_at, published_by_user_id,
                  created_by_user_id, updated_by_user_id, created_at, updated_at
                )
                values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                returning id
                """,
                (
                    session["active_gym_id"],
                    scheduled_date,
                    title,
                    status,
                    published_at,
                    published_by,
                    session["user_id"],
                    session["user_id"],
                    timestamp,
                    timestamp,
                ),
            )
            workout_id = int(cursor.fetchone()["id"])
            programming_service.replace_workout_sections(
                connection,
                daily_workout_id=workout_id,
                sections=sections,
            )
            row = connection.execute(
                f"select {programming_service.DAILY_WORKOUT_COLUMNS} from daily_workouts where id = ?",
                (workout_id,),
            ).fetchone()
            payload = programming_service.daily_workout_payload(connection, row, current_user_id=session["user_id"], can_edit=True)
            if status == "published":
                notifications_core.create_wod_notifications(connection, gym_id=session["active_gym_id"], workout_id=workout_id, scheduled_date=scheduled_date, title=title, is_update=False)
            audit.write_audit_log(connection, gym_id=session["active_gym_id"], actor_user_id=session["user_id"], action="daily_workout_created", entity_type="daily_workout", entity_id=workout_id, details={"scheduled_date": scheduled_date, "title": title, "status": status})
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
    sections = validation.require_workout_sections(
        [section.model_dump() for section in body.sections]
    )
    connection = db.get_connection()
    try:
        existing = connection.execute(
            "select id, scheduled_date, status from daily_workouts where id = ? and gym_id = ?",
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
                    updated_by_user_id = ?,
                    updated_at = ?
                where id = ?
                """,
                (
                    scheduled_date,
                    title,
                    session["user_id"],
                    security.isoformat(security.now_utc()),
                    workout_id,
                ),
            )
            programming_service.replace_workout_sections(
                connection,
                daily_workout_id=workout_id,
                sections=sections,
            )
            row = connection.execute(
                f"select {programming_service.DAILY_WORKOUT_COLUMNS} from daily_workouts where id = ?",
                (workout_id,),
            ).fetchone()
            payload = programming_service.daily_workout_payload(connection, row, current_user_id=session["user_id"], can_edit=True)
            if existing["status"] == "published":
                notifications_core.create_wod_notifications(connection, gym_id=session["active_gym_id"], workout_id=workout_id, scheduled_date=scheduled_date, title=title, is_update=True)
            audit.write_audit_log(connection, gym_id=session["active_gym_id"], actor_user_id=session["user_id"], action="daily_workout_updated", entity_type="daily_workout", entity_id=workout_id, details={"scheduled_date": scheduled_date, "title": title})
        return {"workout": payload}
    finally:
        connection.close()


@app.post("/programming/workouts/publish")
def publish_daily_workout(
    body: DailyWorkoutPublishRequest,
    session: dict[str, Any] = Depends(require_schedule_manager_session),
) -> dict[str, Any]:
    workout_id = validation.require_user_id(body.id)
    connection = db.get_connection()
    try:
        existing = connection.execute(
            "select id, scheduled_date, title, status from daily_workouts where id = ? and gym_id = ?",
            (workout_id, session["active_gym_id"]),
        ).fetchone()
        if existing is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Workout not found.")
        already_published = existing["status"] == "published"
        timestamp = security.isoformat(security.now_utc())
        with connection:
            connection.execute(
                """
                update daily_workouts
                set status = 'published',
                    published_at = ?,
                    published_by_user_id = ?,
                    updated_by_user_id = ?,
                    updated_at = ?
                where id = ?
                """,
                (timestamp, session["user_id"], session["user_id"], timestamp, workout_id),
            )
            row = connection.execute(
                f"select {programming_service.DAILY_WORKOUT_COLUMNS} from daily_workouts where id = ?",
                (workout_id,),
            ).fetchone()
            payload = programming_service.daily_workout_payload(connection, row, current_user_id=session["user_id"], can_edit=True)
            if not already_published:
                notifications_core.create_wod_notifications(connection, gym_id=session["active_gym_id"], workout_id=workout_id, scheduled_date=existing["scheduled_date"], title=existing["title"], is_update=False)
            audit.write_audit_log(connection, gym_id=session["active_gym_id"], actor_user_id=session["user_id"], action="daily_workout_published", entity_type="daily_workout", entity_id=workout_id, details={"scheduled_date": existing["scheduled_date"]})
        return {"workout": payload}
    finally:
        connection.close()


@app.post("/programming/workouts/unpublish")
def unpublish_daily_workout(
    body: DailyWorkoutPublishRequest,
    session: dict[str, Any] = Depends(require_schedule_manager_session),
) -> dict[str, Any]:
    workout_id = validation.require_user_id(body.id)
    connection = db.get_connection()
    try:
        existing = connection.execute(
            "select id, scheduled_date from daily_workouts where id = ? and gym_id = ?",
            (workout_id, session["active_gym_id"]),
        ).fetchone()
        if existing is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Workout not found.")
        timestamp = security.isoformat(security.now_utc())
        with connection:
            connection.execute(
                """
                update daily_workouts
                set status = 'draft',
                    published_at = null,
                    published_by_user_id = null,
                    updated_by_user_id = ?,
                    updated_at = ?
                where id = ?
                """,
                (session["user_id"], timestamp, workout_id),
            )
            row = connection.execute(
                f"select {programming_service.DAILY_WORKOUT_COLUMNS} from daily_workouts where id = ?",
                (workout_id,),
            ).fetchone()
            payload = programming_service.daily_workout_payload(connection, row, current_user_id=session["user_id"], can_edit=True)
            audit.write_audit_log(connection, gym_id=session["active_gym_id"], actor_user_id=session["user_id"], action="daily_workout_unpublished", entity_type="daily_workout", entity_id=workout_id, details={"scheduled_date": existing["scheduled_date"]})
        return {"workout": payload}
    finally:
        connection.close()


@app.post("/programming/workouts/duplicate")
def duplicate_daily_workout(
    body: DailyWorkoutDuplicateRequest,
    session: dict[str, Any] = Depends(require_schedule_manager_session),
) -> dict[str, Any]:
    target_date = validation.require_programming_date(body.target_date)
    source_raw = str(body.source_date or "").strip()
    if not source_raw:
        raise HTTPException(status_code=HTTPStatus.BAD_REQUEST.value, detail="Source date is required.")
    try:
        validation.parse_programming_date(source_raw)
    except ValueError as error:
        raise HTTPException(status_code=HTTPStatus.BAD_REQUEST.value, detail="Source date must be a valid ISO-8601 date.") from error
    if source_raw == target_date:
        raise HTTPException(status_code=HTTPStatus.BAD_REQUEST.value, detail="Source and target dates must differ.")
    connection = db.get_connection()
    try:
        source = connection.execute(
            f"""
            select {programming_service.DAILY_WORKOUT_COLUMNS}
            from daily_workouts
            where gym_id = ? and scheduled_date = ?
            """,
            (session["active_gym_id"], source_raw),
        ).fetchone()
        if source is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Source workout not found.")
        clash = connection.execute(
            "select id from daily_workouts where gym_id = ? and scheduled_date = ?",
            (session["active_gym_id"], target_date),
        ).fetchone()
        if clash is not None:
            raise HTTPException(status_code=HTTPStatus.CONFLICT.value, detail="A workout already exists for this date.")
        source_sections = programming_service.fetch_workout_sections(connection, source["id"])
        timestamp = security.isoformat(security.now_utc())
        with connection:
            cursor = connection.execute(
                """
                insert into daily_workouts (
                  gym_id, scheduled_date, title,
                  status, published_at, published_by_user_id,
                  created_by_user_id, updated_by_user_id, created_at, updated_at
                )
                values (?, ?, ?, 'draft', null, null, ?, ?, ?, ?)
                returning id
                """,
                (
                    session["active_gym_id"],
                    target_date,
                    source["title"],
                    session["user_id"],
                    session["user_id"],
                    timestamp,
                    timestamp,
                ),
            )
            workout_id = int(cursor.fetchone()["id"])
            programming_service.replace_workout_sections(
                connection,
                daily_workout_id=workout_id,
                sections=source_sections,
            )
            row = connection.execute(
                f"select {programming_service.DAILY_WORKOUT_COLUMNS} from daily_workouts where id = ?",
                (workout_id,),
            ).fetchone()
            payload = programming_service.daily_workout_payload(connection, row, current_user_id=session["user_id"], can_edit=True)
            audit.write_audit_log(connection, gym_id=session["active_gym_id"], actor_user_id=session["user_id"], action="daily_workout_duplicated", entity_type="daily_workout", entity_id=workout_id, details={"source_date": source_raw, "target_date": target_date})
        return {"workout": payload}
    finally:
        connection.close()


@app.post("/programming/workouts/import")
def import_daily_workouts(
    body: DailyWorkoutImportRequest,
    session: dict[str, Any] = Depends(require_schedule_manager_session),
) -> Any:
    if not body.rows:
        raise HTTPException(
            status_code=HTTPStatus.BAD_REQUEST.value,
            detail="No rows to import.",
        )
    if len(body.rows) > 500:
        raise HTTPException(
            status_code=HTTPStatus.BAD_REQUEST.value,
            detail="Too many rows to import (max 500).",
        )
    connection = db.get_connection()
    try:
        # Phase 1 — validate every row read-only. The import is atomic: if any
        # row is invalid nothing is created and all errors are reported at once.
        resolved: list[dict[str, Any]] = []
        errors: list[dict[str, Any]] = []
        seen_dates: dict[str, int] = {}
        for index, row in enumerate(body.rows):
            try:
                scheduled_date = validation.require_programming_date(
                    row.scheduled_date
                )
                if scheduled_date in seen_dates:
                    raise validation.ApiError(
                        HTTPStatus.BAD_REQUEST,
                        f"Date {scheduled_date} appears in row {seen_dates[scheduled_date]} already; only one WOD per date.",
                    )
                seen_dates[scheduled_date] = index + 1
                clash = connection.execute(
                    "select id from daily_workouts where gym_id = ? and scheduled_date = ?",
                    (session["active_gym_id"], scheduled_date),
                ).fetchone()
                if clash is not None:
                    raise validation.ApiError(
                        HTTPStatus.CONFLICT,
                        f"A workout already exists for {scheduled_date}.",
                    )
                title = validation.require_programming_title(row.title)
                status = programming_service.require_workout_status(
                    row.status or "draft"
                )
                sections = validation.require_workout_sections(
                    [section.model_dump() for section in row.sections]
                )
                resolved.append(
                    {
                        "scheduled_date": scheduled_date,
                        "title": title,
                        "status": status,
                        "sections": sections,
                    }
                )
            except validation.ApiError as error:
                errors.append({"row": index + 1, "message": error.message})

        if errors:
            return JSONResponse(
                status_code=HTTPStatus.UNPROCESSABLE_ENTITY.value,
                content={"errors": errors, "created_count": 0},
            )

        # Phase 2 — insert everything in a single transaction. The whole batch
        # rolls back if any insert fails.
        timestamp = security.isoformat(security.now_utc())
        created_count = 0
        with connection:
            for item in resolved:
                published_at = timestamp if item["status"] == "published" else None
                published_by = (
                    session["user_id"] if item["status"] == "published" else None
                )
                cursor = connection.execute(
                    """
                    insert into daily_workouts (
                      gym_id, scheduled_date, title,
                      status, published_at, published_by_user_id,
                      created_by_user_id, updated_by_user_id, created_at, updated_at
                    )
                    values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    returning id
                    """,
                    (
                        session["active_gym_id"],
                        item["scheduled_date"],
                        item["title"],
                        item["status"],
                        published_at,
                        published_by,
                        session["user_id"],
                        session["user_id"],
                        timestamp,
                        timestamp,
                    ),
                )
                workout_id = int(cursor.fetchone()["id"])
                programming_service.replace_workout_sections(
                    connection,
                    daily_workout_id=workout_id,
                    sections=item["sections"],
                )
                if item["status"] == "published":
                    notifications_core.create_wod_notifications(
                        connection,
                        gym_id=session["active_gym_id"],
                        workout_id=workout_id,
                        scheduled_date=item["scheduled_date"],
                        title=item["title"],
                        is_update=False,
                    )
                audit.write_audit_log(
                    connection,
                    gym_id=session["active_gym_id"],
                    actor_user_id=session["user_id"],
                    action="daily_workout_created",
                    entity_type="daily_workout",
                    entity_id=workout_id,
                    details={
                        "scheduled_date": item["scheduled_date"],
                        "title": item["title"],
                        "status": item["status"],
                        "source": "import",
                    },
                )
                created_count += 1
        return {"created_count": created_count, "row_count": len(resolved)}
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
              select substr(class_schedules.start_time, 1, 10) as day, class_schedules.id, class_schedules.capacity as capacity,
                count(class_bookings.id) as bookings,
                coalesce(sum(case when class_bookings.attendance_status = 'attended' then 1 else 0 end), 0) as attended,
                coalesce(sum(case when class_bookings.attendance_status = 'no_show' then 1 else 0 end), 0) as no_shows
              from class_schedules
              left join class_bookings on class_bookings.class_schedule_id = class_schedules.id
              where class_schedules.gym_id = ? and substr(class_schedules.start_time, 1, 10) between ? and ?
              group by substr(class_schedules.start_time, 1, 10), class_schedules.id, class_schedules.capacity
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
              where class_schedules.gym_id = ? and substr(class_schedules.start_time, 1, 10) between ? and ?
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
            where class_schedules.gym_id = ? and substr(class_schedules.start_time, 1, 10) between ? and ?
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
            where class_schedules.gym_id = ? and substr(class_schedules.start_time, 1, 10) between ? and ?
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


AT_RISK_DAYS = 21
EXPIRING_DAYS = 14


@app.get("/admin/dashboard")
def admin_dashboard(session: dict[str, Any] = Depends(require_admin_gym_session)) -> dict[str, Any]:
    """Owner dashboard (docs/admin-ui-reference.md §1): headline member counts
    and month-by-month series for the last six calendar months. Read-only."""
    gym_id = session["active_gym_id"]
    connection = db.get_connection()
    # shortcut: months are cut at the gym's local "today", but rows are
    # bucketed by their UTC timestamp, so a class in the first hours of a
    # month can count for the previous one; convert in SQL if that matters.
    today = schedule_service.local_today(_gym_timezone(connection, gym_id))
    # First day of the month five months back, then six month keys "YYYY-MM".
    first = date(today.year, today.month, 1)
    months = []
    for _ in range(6):
        months.insert(0, first)
        first = date(first.year - (first.month == 1), (first.month - 2) % 12 + 1, 1)
    keys = [month.isoformat()[:7] for month in months]
    since = months[0].isoformat()
    at_risk_cutoff = (today - timedelta(days=AT_RISK_DAYS)).isoformat()
    now = security.isoformat(security.now_utc())
    try:
        at_risk = connection.execute(
            """
            select count(*) as count from gym_memberships
            where gym_id = ? and status = 'active' and active_role = 'athlete'
              and substr(created_at, 1, 10) < ?
              and not exists (
                select 1 from class_bookings
                join class_schedules on class_schedules.id = class_bookings.class_schedule_id
                where class_bookings.user_id = gym_memberships.user_id and class_schedules.gym_id = ?
                  and substr(class_schedules.start_time, 1, 10) >= ?
                  -- Only classes that happened and that they showed up for.
                  and class_schedules.start_time <= ? and class_bookings.attendance_status <> 'no_show'
              )
            """,
            (gym_id, at_risk_cutoff, gym_id, at_risk_cutoff, now),
        ).fetchone()["count"]
        expiring = connection.execute(
            """
            select count(*) as count from member_plans
            where gym_id = ? and status = 'active' and ends_on between ? and ?
            """,
            (gym_id, today.isoformat(), (today + timedelta(days=EXPIRING_DAYS)).isoformat()),
        ).fetchone()["count"]

        def per_month(sql: str, params: tuple) -> dict[str, dict[str, Any]]:
            return {row["month"]: dict(row) for row in connection.execute(sql, params).fetchall()}

        churned = per_month(
            """
            select substr(updated_at, 1, 7) as month, count(*) as count from gym_memberships
            where gym_id = ? and status = 'removed' and substr(updated_at, 1, 10) >= ?
            group by substr(updated_at, 1, 7)
            """,
            (gym_id, since),
        )
        new_members = per_month(
            """
            select substr(created_at, 1, 7) as month, count(*) as count from gym_memberships
            where gym_id = ? and active_role = 'athlete' and substr(created_at, 1, 10) >= ?
            group by substr(created_at, 1, 7)
            """,
            (gym_id, since),
        )
        new_memberships = per_month(
            """
            select substr(starts_on, 1, 7) as month, count(*) as count from member_plans
            where gym_id = ? and status in ('active', 'ended') and starts_on >= ?
            group by substr(starts_on, 1, 7)
            """,
            (gym_id, since),
        )
        classes = per_month(
            """
            select per_class.month, coalesce(sum(per_class.capacity), 0) as capacity,
              coalesce(sum(per_class.bookings), 0) as bookings, coalesce(sum(per_class.attended), 0) as attended
            from (
              select substr(class_schedules.start_time, 1, 7) as month, class_schedules.capacity as capacity,
                count(class_bookings.id) as bookings,
                coalesce(sum(case when class_bookings.attendance_status = 'attended' then 1 else 0 end), 0) as attended
              from class_schedules
              left join class_bookings on class_bookings.class_schedule_id = class_schedules.id
              where class_schedules.gym_id = ? and substr(class_schedules.start_time, 1, 10) between ? and ?
              group by class_schedules.id, substr(class_schedules.start_time, 1, 7), class_schedules.capacity
            ) per_class
            group by per_class.month
            """,
            (gym_id, since, today.isoformat()),
        )
        series = []
        for key in keys:
            month_classes = classes.get(key, {})
            capacity = int(month_classes.get("capacity") or 0)
            bookings = int(month_classes.get("bookings") or 0)
            series.append({
                "month": key,
                "new_members": int(new_members.get(key, {}).get("count") or 0),
                "new_memberships": int(new_memberships.get(key, {}).get("count") or 0),
                "churned_members": int(churned.get(key, {}).get("count") or 0),
                "registrations": bookings,
                "attended": int(month_classes.get("attended") or 0),
                # Percent of booked seats over offered seats, 0–100.
                "utilization_percent": 0.0 if capacity <= 0 else round(bookings * 100 / capacity, 1),
            })
        return {
            "members_at_risk": int(at_risk),
            "at_risk_days": AT_RISK_DAYS,
            "expiring_memberships": int(expiring),
            "expiring_days": EXPIRING_DAYS,
            "months": series,
        }
    finally:
        connection.close()


class NewClassTypeRequest(BaseModel):
    name: str
    color: str = "info"
    default_capacity: int = 12


def _class_type_rows(connection: Any, gym_id: int) -> list[dict[str, Any]]:
    rows = connection.execute(
        "select id, name, color, default_capacity from gym_class_types where gym_id = ? order by created_at, id",
        (gym_id,),
    ).fetchall()
    return [dict(row) for row in rows]


@app.get("/class-types")
def list_class_types(session: dict[str, Any] = Depends(require_active_gym_member_session)) -> dict[str, Any]:
    """The gym's own class types; the four built-ins are fixed in the app."""
    connection = db.get_connection()
    try:
        return {"class_types": _class_type_rows(connection, session["active_gym_id"])}
    finally:
        connection.close()


@app.post("/class-types", status_code=HTTPStatus.CREATED.value)
def create_class_type(
    body: NewClassTypeRequest,
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, Any]:
    gym_id = session["active_gym_id"]
    fields = validation.require_new_class_type(body.model_dump(), _class_type_names(gym_id))
    connection = db.get_connection()
    try:
        with connection:
            connection.execute(
                "insert into gym_class_types (gym_id, name, color, default_capacity, created_at) values (?, ?, ?, ?, ?)",
                (gym_id, fields["name"], fields["color"], fields["default_capacity"], security.isoformat(security.now_utc())),
            )
        return {"class_types": _class_type_rows(connection, gym_id)}
    finally:
        connection.close()


class ClassTypeIdRequest(BaseModel):
    id: int


@app.delete("/class-types")
def delete_class_type(
    body: ClassTypeIdRequest,
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, Any]:
    """Removes a custom type from the pickers. Classes and plans that use it
    keep its name."""
    gym_id = session["active_gym_id"]
    connection = db.get_connection()
    try:
        with connection:
            deleted = connection.execute(
                "delete from gym_class_types where id = ? and gym_id = ? returning id",
                (body.id, gym_id),
            ).fetchone()
        if deleted is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Class type not found.")
        return {"class_types": _class_type_rows(connection, gym_id)}
    finally:
        connection.close()


@app.get("/community/dashboard")
def get_community_dashboard(
    session: dict[str, Any] = Depends(require_active_gym_member_session),
) -> dict[str, Any]:
    """Return the shared community snapshot for the active gym.

    This endpoint is intentionally available to every active member role
    because the community view is a shared owner/trainer/member space.
    """
    now = security.now_utc()
    seven_days_ago = security.isoformat(now - timedelta(days=7))
    connection = db.get_connection()
    try:
        stats_row = connection.execute(
            """
            select
              count(*) filter (where gym_memberships.status = 'active') as active_members,
              count(*) filter (
                where gym_memberships.status = 'active'
                  and gym_memberships.active_role = 'trainer'
              ) as active_trainers,
              count(*) filter (
                where gym_memberships.status = 'active'
                  and gym_memberships.active_role = 'admin'
              ) as owners
            from gym_memberships
            join users on users.id = gym_memberships.user_id
            where gym_memberships.gym_id = ?
              and users.deleted_at is null
            """,
            (session["active_gym_id"],),
        ).fetchone()
        message_count_row = connection.execute(
            """
            select count(*) as count
            from chat_messages
            where gym_id = ?
              and deleted_at is null
              and created_at >= ?
            """,
            (session["active_gym_id"], seven_days_ago),
        ).fetchone()
        return {
            "stats": {
                "active_members": int(stats_row["active_members"] if stats_row else 0),
                "active_trainers": int(stats_row["active_trainers"] if stats_row else 0),
                "owners": int(stats_row["owners"] if stats_row else 0),
                "messages_last_7_days": int(
                    message_count_row["count"] if message_count_row else 0
                ),
            },
        }
    finally:
        connection.close()


@app.get("/community/messages")
def list_community_messages(
    since_id: int | None = None,
    session: dict[str, Any] = Depends(require_active_gym_member_session),
) -> dict[str, Any]:
    """List chat messages for the user's active gym.

    By default returns the most recent 50 messages (newest last, so the client
    can render them in chronological order). With ``since_id`` returns up to
    200 messages with ``id > since_id`` so the polling loop can pull only what
    changed. Soft-deleted messages are still returned (body blanked) so a
    poller sees deletions and can update its cache.
    """
    connection = db.get_connection()
    try:
        if since_id is not None and since_id > 0:
            rows = connection.execute(
                f"""
                {community_service.CHAT_MESSAGE_SELECT_SQL}
                where chat_messages.gym_id = ? and chat_messages.id > ?
                order by chat_messages.id asc
                limit 200
                """,
                (session["active_gym_id"], since_id),
            ).fetchall()
        else:
            rows = connection.execute(
                f"""
                {community_service.CHAT_MESSAGE_SELECT_SQL}
                where chat_messages.gym_id = ?
                order by chat_messages.id desc
                limit 50
                """,
                (session["active_gym_id"],),
            ).fetchall()
            rows = list(reversed(rows))
        return {
            "messages": [
                community_service.chat_message_payload(row, current_user_id=session["user_id"])
                for row in rows
            ]
        }
    finally:
        connection.close()


@app.post("/community/messages", status_code=HTTPStatus.CREATED.value)
def create_community_message(
    body: ChatMessageCreateRequest,
    session: dict[str, Any] = Depends(require_active_gym_member_session),
) -> dict[str, Any]:
    message_body = validation.require_chat_message_body(body.body)
    timestamp = security.isoformat(security.now_utc())
    connection = db.get_connection()
    try:
        with connection:
            cursor = connection.execute(
                """
                insert into chat_messages (gym_id, user_id, body, created_at, updated_at)
                values (?, ?, ?, ?, ?)
                returning id
                """,
                (
                    session["active_gym_id"],
                    session["user_id"],
                    message_body,
                    timestamp,
                    timestamp,
                ),
            )
            message_id = int(cursor.fetchone()["id"])
            row = connection.execute(
                f"{community_service.CHAT_MESSAGE_SELECT_SQL} where chat_messages.id = ?",
                (message_id,),
            ).fetchone()
            payload = community_service.chat_message_payload(
                row, current_user_id=session["user_id"]
            )
        return {"message": payload}
    finally:
        connection.close()


@app.delete("/community/messages/{message_id}")
def delete_community_message(
    message_id: int,
    session: dict[str, Any] = Depends(require_active_gym_member_session),
) -> dict[str, Any]:
    """Soft-delete a message.

    Members can always delete their own messages. Trainers and admins can
    additionally moderate other members' messages — the soft-delete keeps the
    row so the client poller can transition the bubble to a 'message deleted'
    state without a hard refresh.
    """
    connection = db.get_connection()
    try:
        row = connection.execute(
            "select id, gym_id, user_id, deleted_at from chat_messages where id = ?",
            (message_id,),
        ).fetchone()
        if row is None or row["gym_id"] != session["active_gym_id"]:
            raise HTTPException(
                status_code=HTTPStatus.NOT_FOUND.value, detail="Message not found."
            )
        if row["deleted_at"] is not None:
            return {"message": {"id": int(row["id"]), "deleted": True}}
        is_owner_message = row["user_id"] == session["user_id"]
        is_moderator = session["role"] in {"admin", "trainer"}
        if not is_owner_message and not is_moderator:
            raise HTTPException(
                status_code=HTTPStatus.FORBIDDEN.value,
                detail="You can only delete your own messages.",
            )
        timestamp = security.isoformat(security.now_utc())
        with connection:
            connection.execute(
                """
                update chat_messages
                set deleted_at = ?, updated_at = ?
                where id = ?
                """,
                (timestamp, timestamp, message_id),
            )
            if not is_owner_message:
                audit.write_audit_log(
                    connection,
                    gym_id=session["active_gym_id"],
                    actor_user_id=session["user_id"],
                    action="chat_message_moderated",
                    entity_type="chat_message",
                    entity_id=message_id,
                    details={"target_user_id": row["user_id"]},
                )
        return {"message": {"id": message_id, "deleted": True}}
    finally:
        connection.close()


@app.get("/uploads/{file_path:path}")
def uploaded_file(file_path: str) -> FileResponse:
    candidate = (settings.UPLOADS_ROOT / file_path).resolve()
    uploads_root = settings.UPLOADS_ROOT.resolve()
    if not candidate.is_file() or uploads_root not in candidate.parents:
        raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Uploaded file not found.")
    return FileResponse(candidate)
