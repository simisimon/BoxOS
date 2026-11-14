from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from backend.api.deps import require_session
from backend.core import db, validation
from backend.services import programming_service, result_social_service

router = APIRouter()


def _staff(session: dict[str, Any]) -> bool:
    return programming_service.can_view_drafts(session["role"])


def _viewable(connection: Any, result_id: int, session: dict[str, Any]) -> Any:
    return result_social_service.viewable_result(
        connection,
        result_id=result_id,
        viewer_id=session["user_id"],
        gym_id=session.get("active_gym_id"),
        staff=_staff(session),
    )


def _coach(connection: Any, result: Any, session: dict[str, Any]) -> bool:
    """Coaches moderate results logged at their own gym only."""
    return result_social_service.coaches_result(
        connection,
        result,
        viewer_id=session["user_id"],
        gym_id=session.get("active_gym_id"),
        staff=_staff(session),
    )


def _result_detail(connection: Any, result: Any, session: dict[str, Any]) -> dict[str, Any]:
    fresh = _viewable(connection, int(result["id"]), session)
    return {
        "result": result_social_service.result_detail(
            connection, result=fresh, viewer_id=session["user_id"], staff=_coach(connection, fresh, session)
        )
    }


@router.get("/results/{result_id}")
def get_workout_result(
    result_id: int,
    session: dict[str, Any] = Depends(require_session),
) -> dict[str, Any]:
    """One result with its photo, fist bumps and comments."""
    connection = db.get_connection()
    try:
        return _result_detail(connection, _viewable(connection, result_id, session), session)
    finally:
        connection.close()


@router.put("/results/{result_id}/bump")
def bump_workout_result(
    result_id: int,
    session: dict[str, Any] = Depends(require_session),
) -> dict[str, Any]:
    connection = db.get_connection()
    try:
        with connection:
            result = _viewable(connection, result_id, session)
            result_social_service.set_bump(connection, result=result, user_id=session["user_id"], bumped=True)
        return _result_detail(connection, result, session)
    finally:
        connection.close()


@router.delete("/results/{result_id}/bump")
def unbump_workout_result(
    result_id: int,
    session: dict[str, Any] = Depends(require_session),
) -> dict[str, Any]:
    connection = db.get_connection()
    try:
        with connection:
            result = _viewable(connection, result_id, session)
            result_social_service.set_bump(connection, result=result, user_id=session["user_id"], bumped=False)
        return _result_detail(connection, result, session)
    finally:
        connection.close()


class ResultCommentRequest(BaseModel):
    body: str


@router.post("/results/{result_id}/comments")
def comment_on_workout_result(
    result_id: int,
    body: ResultCommentRequest,
    session: dict[str, Any] = Depends(require_session),
) -> dict[str, Any]:
    connection = db.get_connection()
    try:
        with connection:
            result = _viewable(connection, result_id, session)
            result_social_service.add_comment(connection, result=result, user_id=session["user_id"], body=body.body)
        return _result_detail(connection, result, session)
    finally:
        connection.close()


@router.delete("/results/comments/{comment_id}")
def delete_result_comment(
    comment_id: int,
    session: dict[str, Any] = Depends(require_session),
) -> dict[str, Any]:
    """Authors delete their comments; owners and trainers any in their gym."""
    connection = db.get_connection()
    try:
        with connection:
            result_social_service.delete_comment(
                connection,
                comment_id=comment_id,
                user_id=session["user_id"],
                gym_id=session.get("active_gym_id"),
                staff=_staff(session),
            )
        return {"message": "Comment deleted."}
    finally:
        connection.close()


class ResultPhotoRequest(BaseModel):
    filename: str
    content_type: str
    data_base64: str


@router.put("/results/{result_id}/photo")
def upload_result_photo(
    result_id: int,
    body: ResultPhotoRequest,
    session: dict[str, Any] = Depends(require_session),
) -> dict[str, Any]:
    """The athlete's one photo on their result (replaces an earlier one)."""
    validation.require_upload_filename(body.filename)
    data = validation.require_base64_bytes(
        body.data_base64,
        label="Photo data",
        max_bytes=result_social_service.MAX_RESULT_PHOTO_BYTES,
    )
    connection = db.get_connection()
    try:
        with connection:
            result = _viewable(connection, result_id, session)
            result_social_service.set_photo(
                connection,
                result=result,
                user_id=session["user_id"],
                content_type=body.content_type.strip().lower(),
                data=data,
            )
        return _result_detail(connection, result, session)
    finally:
        connection.close()


@router.delete("/results/{result_id}/photo")
def remove_result_photo(
    result_id: int,
    session: dict[str, Any] = Depends(require_session),
) -> dict[str, Any]:
    """The athlete removes their photo; owners and trainers moderate."""
    connection = db.get_connection()
    try:
        with connection:
            result = _viewable(connection, result_id, session)
            result_social_service.remove_photo(
                connection, result=result, user_id=session["user_id"], staff=_coach(connection, result, session)
            )
        return _result_detail(connection, result, session)
    finally:
        connection.close()
