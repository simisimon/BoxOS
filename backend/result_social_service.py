"""Fist bumps, comments and a photo on WOD results.

Whoever sees a result can bump it and comment on it: members of the
result's gym, minus results their owners keep private (the owner and the
gym's coaches still see those), and followers of athletes who share with
followers. Comment authors and coaches
delete comments; the owner and coaches remove the photo.
"""

from __future__ import annotations

import secrets
from http import HTTPStatus
from pathlib import Path
from typing import Any, TYPE_CHECKING

from backend import notifications_core, settings
from backend.security import isoformat, now_utc
from backend.validation import ApiError

if TYPE_CHECKING:
    from backend.db import ManagedConnection, Row

MAX_COMMENT = 500
MAX_RESULT_PHOTO_BYTES = 5 * 1024 * 1024
PHOTO_CONTENT_TYPES = {"image/jpeg": ".jpg", "image/png": ".png", "image/webp": ".webp"}


def photos_dir() -> Path:
    return settings.UPLOADS_ROOT / "results"


def _name(row: Row, prefix: str = "") -> str:
    name = (row[prefix + "display_name"] or "").strip() or (row[prefix + "nickname"] or "").strip()
    return name or str(row[prefix + "email"]).split("@")[0]


def viewable_result(
    connection: ManagedConnection, *, result_id: int, viewer_id: int, gym_id: int | None, staff: bool
) -> Row:
    """The result, if the viewer may see it: their own; one at a gym they
    belong to, unless kept private (the gym's coaches still see those); or,
    for followers, any result of someone who shares with followers."""
    row = connection.execute(
        """
        select r.id, r.user_id, r.gym_id, r.section_id, r.daily_workout_id, r.performed_on,
               r.section_title, r.workout_name, r.score_label, r.division, r.time_capped,
               r.notes, r.photo_url,
               u.display_name, u.nickname, u.email, u.profile_image_url, u.results_visibility
        from workout_results r
        join users u on u.id = r.user_id
        where r.id = ? and u.deleted_at is null
        """,
        (result_id,),
    ).fetchone()
    if row is None or not _can_view(connection, row, viewer_id=viewer_id, gym_id=gym_id, staff=staff):
        raise ApiError(HTTPStatus.NOT_FOUND, "Result not found.")
    return row


def coaches_result(connection: ManagedConnection, result: Row, *, viewer_id: int, gym_id: int | None, staff: bool) -> bool:
    """Whether the viewer coaches the gym the result was logged at."""
    from backend import follow_service

    return (
        staff
        and gym_id is not None
        and result["gym_id"] == gym_id
        and gym_id in follow_service.member_gym_ids(connection, viewer_id)
    )


def _can_view(connection: ManagedConnection, row: Row, *, viewer_id: int, gym_id: int | None, staff: bool) -> bool:
    from backend import follow_service

    if row["user_id"] == viewer_id:
        return True
    if coaches_result(connection, row, viewer_id=viewer_id, gym_id=gym_id, staff=staff):
        return True
    visibility = row["results_visibility"]
    if visibility == "private":
        return False
    if row["gym_id"] is not None and row["gym_id"] in follow_service.member_gym_ids(connection, viewer_id):
        return True
    return visibility == "followers" and follow_service.follows(
        connection, follower_id=viewer_id, followee_id=row["user_id"]
    )


def social_counts(
    connection: ManagedConnection, *, result_ids: list[int], viewer_id: int
) -> dict[int, dict[str, Any]]:
    """Bump and comment counts per result, and whether the viewer bumped."""
    if not result_ids:
        return {}
    marks = ", ".join("?" for _ in result_ids)
    counts: dict[int, dict[str, Any]] = {
        rid: {"bump_count": 0, "comment_count": 0, "bumped_by_me": False} for rid in result_ids
    }
    for row in connection.execute(
        f"""
        select result_id, count(*) as count,
               max(case when user_id = ? then 1 else 0 end) as mine
        from result_bumps where result_id in ({marks}) group by result_id
        """,
        (viewer_id, *result_ids),
    ).fetchall():
        counts[int(row["result_id"])]["bump_count"] = int(row["count"])
        counts[int(row["result_id"])]["bumped_by_me"] = bool(row["mine"])
    for row in connection.execute(
        f"select result_id, count(*) as count from result_comments where result_id in ({marks}) group by result_id",
        tuple(result_ids),
    ).fetchall():
        counts[int(row["result_id"])]["comment_count"] = int(row["count"])
    return counts


def _notify(
    connection: ManagedConnection, *, result: Row, actor_id: int, title: str, body: str
) -> None:
    if result["user_id"] == actor_id:
        return
    owner = connection.execute(
        "select notify_result_activity from users where id = ? and deleted_at is null",
        (result["user_id"],),
    ).fetchone()
    if owner is None or not bool(owner["notify_result_activity"]):
        return
    notifications_core.create_notification(
        connection,
        user_id=result["user_id"],
        gym_id=result["gym_id"],
        type="result_activity",
        title=title,
        body=body,
        entity_type="workout_result",
        entity_id=result["id"],
    )


def _actor_name(connection: ManagedConnection, user_id: int) -> str:
    row = connection.execute(
        "select display_name, nickname, email from users where id = ?", (user_id,)
    ).fetchone()
    return _name(row) if row else "Someone"


def _block(result: Row) -> str:
    return result["workout_name"] or result["section_title"] or "your result"


def set_bump(connection: ManagedConnection, *, result: Row, user_id: int, bumped: bool) -> None:
    if not bumped:
        connection.execute(
            "delete from result_bumps where result_id = ? and user_id = ?", (result["id"], user_id)
        )
        return
    inserted = connection.execute(
        """
        insert into result_bumps (result_id, user_id, created_at) values (?, ?, ?)
        on conflict (result_id, user_id) do nothing
        returning result_id
        """,
        (result["id"], user_id, isoformat(now_utc())),
    ).fetchone()
    if inserted is not None:
        _notify(
            connection,
            result=result,
            actor_id=user_id,
            title="Fist bump",
            body=f"{_actor_name(connection, user_id)} gave you a fist bump for {_block(result)} ({result['score_label']}).",
        )


def add_comment(connection: ManagedConnection, *, result: Row, user_id: int, body: str) -> None:
    text = (body or "").strip()
    if not text:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Write a comment first.")
    if len(text) > MAX_COMMENT:
        raise ApiError(HTTPStatus.BAD_REQUEST, f"Comments can be up to {MAX_COMMENT} characters.")
    connection.execute(
        "insert into result_comments (result_id, user_id, body, created_at) values (?, ?, ?, ?)",
        (result["id"], user_id, text, isoformat(now_utc())),
    )
    preview = text if len(text) <= 80 else text[:77] + "..."
    _notify(
        connection,
        result=result,
        actor_id=user_id,
        title="New comment",
        body=f"{_actor_name(connection, user_id)} on {_block(result)}: {preview}",
    )


def delete_comment(
    connection: ManagedConnection, *, comment_id: int, user_id: int, gym_id: int | None, staff: bool
) -> None:
    row = connection.execute(
        "select id, user_id, result_id from result_comments where id = ?",
        (comment_id,),
    ).fetchone()
    if row is None:
        raise ApiError(HTTPStatus.NOT_FOUND, "Comment not found.")
    try:
        result = viewable_result(
            connection, result_id=row["result_id"], viewer_id=user_id, gym_id=gym_id, staff=staff
        )
    except ApiError:
        raise ApiError(HTTPStatus.NOT_FOUND, "Comment not found.") from None
    coach = coaches_result(connection, result, viewer_id=user_id, gym_id=gym_id, staff=staff)
    if row["user_id"] != user_id and not coach:
        raise ApiError(HTTPStatus.FORBIDDEN, "Only the author or a coach can delete this comment.")
    connection.execute("delete from result_comments where id = ?", (comment_id,))


def _remove_photo_file(url: str) -> None:
    name = Path(str(url or "")).name
    if not name:
        return
    root = photos_dir().resolve()
    candidate = (root / name).resolve()
    if root not in candidate.parents:
        return
    try:
        candidate.unlink(missing_ok=True)
    except OSError:
        pass


def set_photo(connection: ManagedConnection, *, result: Row, user_id: int, content_type: str, data: bytes) -> str:
    if result["user_id"] != user_id:
        raise ApiError(HTTPStatus.FORBIDDEN, "Only the athlete can add a photo to this result.")
    extension = PHOTO_CONTENT_TYPES.get(content_type)
    if extension is None:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Photos must be JPEG, PNG, or WEBP.")
    directory = photos_dir()
    directory.mkdir(parents=True, exist_ok=True)
    stored = f"result_{secrets.token_urlsafe(12)}{extension}"
    (directory / stored).write_bytes(data)
    url = f"/uploads/results/{stored}"
    connection.execute(
        "update workout_results set photo_url = ?, updated_at = ? where id = ?",
        (url, isoformat(now_utc()), result["id"]),
    )
    _remove_photo_file(result["photo_url"])
    return url


def remove_photo(connection: ManagedConnection, *, result: Row, user_id: int, staff: bool) -> None:
    if result["user_id"] != user_id and not staff:
        raise ApiError(HTTPStatus.FORBIDDEN, "Only the athlete or a coach can remove this photo.")
    connection.execute(
        "update workout_results set photo_url = '', updated_at = ? where id = ?",
        (isoformat(now_utc()), result["id"]),
    )
    _remove_photo_file(result["photo_url"])


def result_detail(
    connection: ManagedConnection, *, result: Row, viewer_id: int, staff: bool
) -> dict[str, Any]:
    """The result with its photo, who bumped it and its comments."""
    counts = social_counts(connection, result_ids=[result["id"]], viewer_id=viewer_id)[result["id"]]
    bumpers = connection.execute(
        """
        select u.display_name, u.nickname, u.email
        from result_bumps b join users u on u.id = b.user_id
        where b.result_id = ? order by b.created_at
        """,
        (result["id"],),
    ).fetchall()
    comments = connection.execute(
        """
        select c.id, c.user_id, c.body, c.created_at,
               u.display_name, u.nickname, u.email, u.profile_image_url
        from result_comments c join users u on u.id = c.user_id
        where c.result_id = ? and u.deleted_at is null
        order by c.id
        """,
        (result["id"],),
    ).fetchall()
    mine = result["user_id"] == viewer_id
    return {
        "id": result["id"],
        "user_id": result["user_id"],
        "name": _name(result),
        "avatar_url": result["profile_image_url"] or "",
        "performed_on": result["performed_on"],
        "section_title": result["section_title"],
        "workout_name": result["workout_name"],
        "score_label": result["score_label"],
        "division": result["division"],
        "time_capped": bool(result["time_capped"]),
        "notes": result["notes"] if staff or mine else "",
        "photo_url": result["photo_url"] or "",
        "is_me": mine,
        "can_edit_photo": mine,
        "can_remove_photo": bool(result["photo_url"]) and (mine or staff),
        **counts,
        "bumped_by": [_name(row) for row in bumpers],
        "comments": [
            {
                "id": row["id"],
                "name": _name(row),
                "avatar_url": row["profile_image_url"] or "",
                "body": row["body"],
                "created_at": row["created_at"],
                "can_delete": staff or row["user_id"] == viewer_id,
            }
            for row in comments
        ],
    }
