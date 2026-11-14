from __future__ import annotations

import logging
import threading
import time
from collections import defaultdict, deque
from http import HTTPStatus
from typing import Any

from fastapi import Depends, Header, HTTPException, Request

from backend.core import db, security, settings, validation

logger = logging.getLogger("boxos.backend")


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
