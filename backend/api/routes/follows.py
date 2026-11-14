from __future__ import annotations

from http import HTTPStatus
from typing import Any

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from backend.api.deps import require_session
from backend.core import db, security, validation
from backend.services import follow_service, results_service

router = APIRouter()


class ResultsPrivacyRequest(BaseModel):
    visibility: str


@router.get("/profile/results-privacy")
def get_results_privacy(session: dict[str, Any] = Depends(require_session)) -> dict[str, str]:
    """Who sees the caller's results: followers (and the gym), the gym, or
    only the caller and their coaches."""
    connection = db.get_connection()
    try:
        row = connection.execute(
            "select results_visibility from users where id = ? and deleted_at is null",
            (session["user_id"],),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Account not found.")
        return {"visibility": row["results_visibility"]}
    finally:
        connection.close()


@router.patch("/profile/results-privacy")
def update_results_privacy(
    body: ResultsPrivacyRequest,
    session: dict[str, Any] = Depends(require_session),
) -> dict[str, str]:
    visibility = body.visibility.strip().lower()
    if visibility not in results_service.RESULTS_VISIBILITY:
        raise validation.ApiError(
            HTTPStatus.BAD_REQUEST, "Choose who sees your results: followers, gym or private."
        )
    connection = db.get_connection()
    try:
        with connection:
            connection.execute(
                "update users set results_visibility = ?, updated_at = ? where id = ? and deleted_at is null",
                (visibility, security.isoformat(security.now_utc()), session["user_id"]),
            )
        return {"visibility": visibility}
    finally:
        connection.close()


class FollowRequest(BaseModel):
    # A member of a gym the caller belongs to, or anyone by invite code.
    user_id: int | None = None
    invite_code: str | None = None


@router.get("/follows")
def list_follows(session: dict[str, Any] = Depends(require_session)) -> dict[str, Any]:
    """Who the caller follows, their followers, open requests and the
    caller's invite code."""
    connection = db.get_connection()
    try:
        with connection:
            return follow_service.overview(connection, user_id=session["user_id"])
    finally:
        connection.close()


@router.get("/follows/search")
def search_follows(
    query: str = "",
    session: dict[str, Any] = Depends(require_session),
) -> dict[str, Any]:
    """Members of the caller's gyms by name, to follow."""
    connection = db.get_connection()
    try:
        return {"people": follow_service.search(connection, user_id=session["user_id"], query=query)}
    finally:
        connection.close()


@router.post("/follows")
def create_follow(body: FollowRequest, session: dict[str, Any] = Depends(require_session)) -> dict[str, Any]:
    """Asks to follow someone; they accept or decline."""
    connection = db.get_connection()
    try:
        with connection:
            return follow_service.request_follow(
                connection,
                user_id=session["user_id"],
                target_id=body.user_id,
                code=(body.invite_code or "").strip() or None,
            )
    finally:
        connection.close()


@router.post("/follows/requests/{follower_id}/accept")
def accept_follow(follower_id: int, session: dict[str, Any] = Depends(require_session)) -> dict[str, Any]:
    connection = db.get_connection()
    try:
        with connection:
            follow_service.accept(connection, user_id=session["user_id"], follower_id=follower_id)
        return {"message": "Request accepted."}
    finally:
        connection.close()


@router.delete("/follows/followers/{follower_id}")
def remove_follower(follower_id: int, session: dict[str, Any] = Depends(require_session)) -> dict[str, Any]:
    """Declines a follow request or removes a follower."""
    connection = db.get_connection()
    try:
        with connection:
            follow_service.remove_follower(connection, user_id=session["user_id"], follower_id=follower_id)
        return {"message": "Follower removed."}
    finally:
        connection.close()


@router.delete("/follows/following/{followee_id}")
def unfollow(followee_id: int, session: dict[str, Any] = Depends(require_session)) -> dict[str, Any]:
    """Stops following someone, or withdraws a request."""
    connection = db.get_connection()
    try:
        with connection:
            follow_service.unfollow(connection, user_id=session["user_id"], followee_id=followee_id)
        return {"message": "Unfollowed."}
    finally:
        connection.close()


@router.get("/feed")
def results_feed(
    offset: int = 0,
    limit: int = 30,
    session: dict[str, Any] = Depends(require_session),
) -> dict[str, Any]:
    """Results of the people the caller follows, newest first."""
    connection = db.get_connection()
    try:
        return follow_service.feed(connection, user_id=session["user_id"], offset=offset, limit=limit)
    finally:
        connection.close()
