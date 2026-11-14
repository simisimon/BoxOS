from __future__ import annotations

import secrets
from http import HTTPStatus
from pathlib import Path
from typing import Any

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from backend.api.common import GymIdRequest
from backend.api.deps import require_session
from backend.api.validators import profile as validators
from backend.core import db, notifications, security, settings, validation
from backend.services import membership_service

router = APIRouter()


class UpdateProfileRequest(BaseModel):
    display_name: str
    nickname: str


class UpdateActiveRoleRequest(BaseModel):
    role: str


class NotificationPreferencesRequest(BaseModel):
    booking_confirmations: bool
    waitlist_promotions: bool
    payment_issues: bool
    wod_posted: bool
    pr_achievements: bool
    announcement_activity: bool
    # Fist bumps and comments on my results; older clients leave it out.
    result_activity: bool | None = None


class AvatarUploadRequest(BaseModel):
    filename: str
    content_type: str
    data_base64: str


@router.get("/profile")
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


@router.patch("/profile")
def update_profile(
    body: UpdateProfileRequest,
    session: dict[str, Any] = Depends(require_session),
) -> dict[str, Any]:
    display_name = validators.require_display_name(body.display_name)
    nickname = validators.require_nickname(body.nickname)
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


@router.post("/profile/avatar", status_code=HTTPStatus.CREATED.value)
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
    content_type = validators.require_avatar_content_type(body.content_type)
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


@router.delete("/profile/avatar")
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


@router.patch("/profile/active-role")
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


@router.patch("/profile/active-gym")
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


@router.get("/profile/notifications")
def get_notification_preferences(
    session: dict[str, Any] = Depends(require_session),
) -> dict[str, bool]:
    connection = db.get_connection()
    try:
        user = connection.execute(
            """
            select notify_booking_confirmations, notify_waitlist_promotions, notify_payment_issues,
                   notify_wod_posted, notify_pr_achievements, notify_announcement_activity,
                   notify_result_activity
            from users where id = ? and deleted_at is null
            """,
            (session["user_id"],),
        ).fetchone()
        if user is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Notification preferences not found.")
        return notifications.notification_preferences_payload(user)
    finally:
        connection.close()


@router.patch("/profile/notifications")
def update_notification_preferences(
    body: NotificationPreferencesRequest,
    session: dict[str, Any] = Depends(require_session),
) -> dict[str, bool]:
    payload = body.model_dump()
    preferences = validators.require_notification_preferences(payload)
    connection = db.get_connection()
    try:
        with connection:
            connection.execute(
                """
                update users
                set notify_booking_confirmations = ?, notify_waitlist_promotions = ?, notify_payment_issues = ?,
                    notify_wod_posted = ?, notify_pr_achievements = ?, notify_announcement_activity = ?,
                    notify_result_activity = coalesce(?, notify_result_activity), updated_at = ?
                where id = ? and deleted_at is null
                """,
                (
                    int(preferences["booking_confirmations"]),
                    int(preferences["waitlist_promotions"]),
                    int(preferences["payment_issues"]),
                    int(preferences["wod_posted"]),
                    int(preferences["pr_achievements"]),
                    int(preferences["announcement_activity"]),
                    None if body.result_activity is None else int(body.result_activity),
                    security.isoformat(security.now_utc()),
                    session["user_id"],
                ),
            )
        user = connection.execute(
            """
            select notify_booking_confirmations, notify_waitlist_promotions, notify_payment_issues,
                   notify_wod_posted, notify_pr_achievements, notify_announcement_activity,
                   notify_result_activity
            from users where id = ? and deleted_at is null
            """,
            (session["user_id"],),
        ).fetchone()
        if user is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Notification preferences not found.")
        return notifications.notification_preferences_payload(user)
    finally:
        connection.close()
