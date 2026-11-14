from __future__ import annotations

from datetime import timedelta
from http import HTTPStatus
from typing import Any

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from backend.api.deps import logger, rate_limit, require_session
from backend.core import audit, db, security, settings, validation
from backend.services import auth_service, membership_service

router = APIRouter()


def _log_delivery_token(kind: str, email: str, token: str) -> None:
    """Surface tokens that would normally be emailed. The value is only logged when
    BOXOS_LOG_DELIVERY_TOKENS is enabled (dev default) so it never leaks in production."""
    if settings.LOG_DELIVERY_TOKENS:
        logger.info("%s token for %s: %s", kind, email, token)
    else:
        logger.info("%s token issued for %s (value suppressed).", kind, email)


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


@router.post("/auth/login")
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


@router.post("/auth/refresh")
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


@router.get("/auth/session")
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


@router.post("/auth/signup")
def signup(
    body: SignupRequest,
    _: None = Depends(rate_limit("signup", limit=5, window_seconds=60)),
) -> dict[str, Any]:
    return _signup(body, account_type="athlete")


@router.post("/auth/signup-admin")
@router.post("/auth/signup-owner")
def signup_admin(
    body: SignupRequest,
    _: None = Depends(rate_limit("signup-admin", limit=5, window_seconds=60)),
) -> dict[str, Any]:
    return _signup(body, account_type="admin")


@router.post("/auth/logout")
def logout(session: dict[str, Any] = Depends(require_session)) -> dict[str, Any]:
    connection = db.get_connection()
    try:
        with connection:
            connection.execute("delete from sessions where access_token_hash = ?", (session["access_token_hash"],))
        return {"message": "Signed out."}
    finally:
        connection.close()


@router.post("/auth/logout-all")
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


@router.post("/auth/request-password-reset")
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


@router.post("/auth/reset-password")
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


@router.post("/auth/verify-email")
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


@router.post("/auth/resend-verification")
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


@router.post("/auth/change-password")
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


@router.get("/auth/account/deletion-check")
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


@router.delete("/auth/account")
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
