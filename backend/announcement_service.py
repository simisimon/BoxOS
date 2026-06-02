from __future__ import annotations

import sqlite3
from http import HTTPStatus
from typing import Any

from backend.notifications_core import create_notification
from backend.validation import ApiError


def notification_payload(row: sqlite3.Row) -> dict[str, Any]:
    return {
        "id": row["id"],
        "type": row["type"],
        "title": row["title"],
        "body": row["body"],
        "entity_type": row["entity_type"],
        "entity_id": row["entity_id"],
        "read_at": row["read_at"],
        "created_at": row["created_at"],
    }


def preferred_user_name(
    row: sqlite3.Row,
    *,
    display_name_key: str = "display_name",
    nickname_key: str = "nickname",
    email_key: str = "email",
) -> str:
    return str(row[display_name_key] or "").strip() or str(row[nickname_key] or "").strip() or str(row[email_key] or "").strip()


def announcement_comment_payload(row: sqlite3.Row, *, current_user_id: int, session_role: str) -> dict[str, Any]:
    author_name = preferred_user_name(
        row,
        display_name_key="author_display_name",
        nickname_key="author_nickname",
        email_key="author_email",
    )
    return {
        "id": row["id"],
        "announcement_id": row["announcement_id"],
        "author_name": author_name,
        "body": row["body"],
        "created_at": row["created_at"],
        "updated_at": row["updated_at"],
        "can_manage": session_role == "admin" or int(row["user_id"]) == int(current_user_id),
    }


def list_announcement_comments(connection: sqlite3.Connection, *, announcement_id: int, current_user_id: int, session_role: str) -> list[dict[str, Any]]:
    rows = connection.execute(
        """
        select announcement_comments.id, announcement_comments.announcement_id, announcement_comments.user_id,
               announcement_comments.body, announcement_comments.created_at, announcement_comments.updated_at,
               users.display_name as author_display_name, users.nickname as author_nickname, users.email as author_email
        from announcement_comments
        join users on users.id = announcement_comments.user_id
        where announcement_comments.announcement_id = ?
        order by announcement_comments.created_at asc, announcement_comments.id asc
        """,
        (announcement_id,),
    ).fetchall()
    return [announcement_comment_payload(row, current_user_id=current_user_id, session_role=session_role) for row in rows]


def announcement_payload(connection: sqlite3.Connection, row: sqlite3.Row, *, current_user_id: int, session_role: str) -> dict[str, Any]:
    author_name = preferred_user_name(
        row,
        display_name_key="author_display_name",
        nickname_key="author_nickname",
        email_key="author_email",
    )
    like_count = int(connection.execute("select count(*) from announcement_likes where announcement_id = ?", (row["id"],)).fetchone()[0])
    liked_by_me = connection.execute(
        "select 1 from announcement_likes where announcement_id = ? and user_id = ?",
        (row["id"], current_user_id),
    ).fetchone() is not None
    comments = list_announcement_comments(connection, announcement_id=int(row["id"]), current_user_id=current_user_id, session_role=session_role)
    return {
        "id": row["id"],
        "gym_id": row["gym_id"],
        "title": row["title"],
        "description": row["description"],
        "image_url": row["image_url"],
        "author_name": author_name,
        "created_at": row["created_at"],
        "updated_at": row["updated_at"],
        "like_count": like_count,
        "liked_by_me": liked_by_me,
        "comment_count": len(comments),
        "comments": comments,
        "can_manage": session_role == "admin" or int(row["created_by_user_id"]) == int(current_user_id),
    }


def get_announcement_row(connection: sqlite3.Connection, *, announcement_id: int, gym_id: int) -> sqlite3.Row | None:
    return connection.execute(
        """
        select announcements.id, announcements.gym_id, announcements.title, announcements.description,
               announcements.image_url, announcements.created_by_user_id, announcements.created_at, announcements.updated_at,
               users.display_name as author_display_name, users.nickname as author_nickname, users.email as author_email
        from announcements
        join users on users.id = announcements.created_by_user_id
        where announcements.id = ? and announcements.gym_id = ?
        """,
        (announcement_id, gym_id),
    ).fetchone()


def get_announcement_comment_row(connection: sqlite3.Connection, comment_id: int) -> sqlite3.Row | None:
    return connection.execute(
        """
        select announcement_comments.id, announcement_comments.announcement_id, announcement_comments.gym_id,
               announcement_comments.user_id, announcement_comments.body, announcement_comments.created_at,
               announcement_comments.updated_at, users.display_name as author_display_name,
               users.nickname as author_nickname, users.email as author_email
        from announcement_comments
        join users on users.id = announcement_comments.user_id
        where announcement_comments.id = ?
        """,
        (comment_id,),
    ).fetchone()


def ensure_announcement_manage_permission(announcement: sqlite3.Row, session: sqlite3.Row | dict[str, Any]) -> None:
    if session["role"] == "admin":
        return
    if int(announcement["created_by_user_id"]) == int(session["user_id"]):
        return
        raise ApiError(HTTPStatus.FORBIDDEN, "Only the announcement author or an admin can modify this announcement.")


def ensure_announcement_comment_manage_permission(comment: sqlite3.Row, session: sqlite3.Row | dict[str, Any]) -> None:
    if session["role"] == "admin":
        return
    if int(comment["user_id"]) == int(session["user_id"]):
        return
        raise ApiError(HTTPStatus.FORBIDDEN, "Only the comment author or an admin can modify this comment.")


def create_announcement_like_notification(connection: sqlite3.Connection, *, recipient_user_id: int, actor_user_id: int, gym_id: int, announcement_id: int, announcement_title: str) -> None:
    if recipient_user_id == actor_user_id:
        return
    recipient = connection.execute("select notify_announcement_activity from users where id = ? and deleted_at is null", (recipient_user_id,)).fetchone()
    actor = connection.execute("select display_name, nickname, email from users where id = ? and deleted_at is null", (actor_user_id,)).fetchone()
    if recipient is None or actor is None or not bool(recipient["notify_announcement_activity"]):
        return
    actor_name = preferred_user_name(actor)
    create_notification(connection, user_id=recipient_user_id, gym_id=gym_id, type="announcement_liked", title="New like on your announcement", body=f'{actor_name} liked "{announcement_title}".', entity_type="announcement", entity_id=announcement_id)


def create_announcement_comment_notification(connection: sqlite3.Connection, *, recipient_user_id: int, actor_user_id: int, gym_id: int, announcement_id: int, announcement_title: str, comment_body: str) -> None:
    if recipient_user_id == actor_user_id:
        return
    recipient = connection.execute("select notify_announcement_activity from users where id = ? and deleted_at is null", (recipient_user_id,)).fetchone()
    actor = connection.execute("select display_name, nickname, email from users where id = ? and deleted_at is null", (actor_user_id,)).fetchone()
    if recipient is None or actor is None or not bool(recipient["notify_announcement_activity"]):
        return
    actor_name = preferred_user_name(actor)
    snippet = comment_body.strip()
    if len(snippet) > 80:
        snippet = f"{snippet[:77].rstrip()}..."
    create_notification(connection, user_id=recipient_user_id, gym_id=gym_id, type="announcement_commented", title="New comment on your announcement", body=f'{actor_name} commented on "{announcement_title}": {snippet}', entity_type="announcement", entity_id=announcement_id)
