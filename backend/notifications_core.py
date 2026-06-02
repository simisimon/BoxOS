from __future__ import annotations

import sqlite3
from typing import Any

from backend.security import isoformat, now_utc

def notification_preferences_payload(row: sqlite3.Row) -> dict[str, bool]:
    return {
        "booking_confirmations": bool(row["notify_booking_confirmations"]),
        "waitlist_promotions": bool(row["notify_waitlist_promotions"]),
        "payment_issues": bool(row["notify_payment_issues"]),
        "wod_posted": bool(row["notify_wod_posted"]),
        "pr_achievements": bool(row["notify_pr_achievements"]),
        "announcement_activity": bool(row["notify_announcement_activity"]),
    }


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
    return (
        str(row[display_name_key] or "").strip()
        or str(row[nickname_key] or "").strip()
        or str(row[email_key] or "").strip()
    )


def announcement_comment_payload(
    row: sqlite3.Row,
    *,
    current_user_id: int,
    session_role: str,
) -> dict[str, Any]:
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


def list_announcement_comments(
    connection: sqlite3.Connection,
    *,
    announcement_id: int,
    current_user_id: int,
    session_role: str,
) -> list[dict[str, Any]]:
    rows = connection.execute(
        """
        select
          announcement_comments.id,
          announcement_comments.announcement_id,
          announcement_comments.user_id,
          announcement_comments.body,
          announcement_comments.created_at,
          announcement_comments.updated_at,
          users.display_name as author_display_name,
          users.nickname as author_nickname,
          users.email as author_email
        from announcement_comments
        join users on users.id = announcement_comments.user_id
        where announcement_comments.announcement_id = ?
        order by announcement_comments.created_at asc, announcement_comments.id asc
        """,
        (announcement_id,),
    ).fetchall()
    return [
        announcement_comment_payload(
            row,
            current_user_id=current_user_id,
            session_role=session_role,
        )
        for row in rows
    ]


def announcement_payload(
    connection: sqlite3.Connection,
    row: sqlite3.Row,
    *,
    current_user_id: int,
    session_role: str,
) -> dict[str, Any]:
    author_name = preferred_user_name(
        row,
        display_name_key="author_display_name",
        nickname_key="author_nickname",
        email_key="author_email",
    )
    like_count = int(
        connection.execute(
            "select count(*) from announcement_likes where announcement_id = ?",
            (row["id"],),
        ).fetchone()[0]
    )
    liked_by_me = connection.execute(
        "select 1 from announcement_likes where announcement_id = ? and user_id = ?",
        (row["id"], current_user_id),
    ).fetchone() is not None
    comments = list_announcement_comments(
        connection,
        announcement_id=int(row["id"]),
        current_user_id=current_user_id,
        session_role=session_role,
    )
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


def get_announcement_row(
    connection: sqlite3.Connection,
    *,
    announcement_id: int,
    gym_id: int,
) -> sqlite3.Row | None:
    return connection.execute(
        """
        select
          announcements.id,
          announcements.gym_id,
          announcements.title,
          announcements.description,
          announcements.image_url,
          announcements.created_by_user_id,
          announcements.created_at,
          announcements.updated_at,
          users.display_name as author_display_name,
          users.nickname as author_nickname,
          users.email as author_email
        from announcements
        join users on users.id = announcements.created_by_user_id
        where announcements.id = ? and announcements.gym_id = ?
        """,
        (announcement_id, gym_id),
    ).fetchone()


def get_announcement_comment_row(
    connection: sqlite3.Connection,
    comment_id: int,
) -> sqlite3.Row | None:
    return connection.execute(
        """
        select
          announcement_comments.id,
          announcement_comments.announcement_id,
          announcement_comments.gym_id,
          announcement_comments.user_id,
          announcement_comments.body,
          announcement_comments.created_at,
          announcement_comments.updated_at,
          users.display_name as author_display_name,
          users.nickname as author_nickname,
          users.email as author_email
        from announcement_comments
        join users on users.id = announcement_comments.user_id
        where announcement_comments.id = ?
        """,
        (comment_id,),
    ).fetchone()


def ensure_announcement_manage_permission(
    announcement: sqlite3.Row,
    session: sqlite3.Row,
) -> None:
    if session["role"] == "admin":
        return
    if int(announcement["created_by_user_id"]) == int(session["user_id"]):
        return
    raise ApiError(
        HTTPStatus.FORBIDDEN,
        "Only the announcement author or an admin can modify this announcement.",
    )


def ensure_announcement_comment_manage_permission(
    comment: sqlite3.Row,
    session: sqlite3.Row,
) -> None:
    if session["role"] == "admin":
        return
    if int(comment["user_id"]) == int(session["user_id"]):
        return
    raise ApiError(
        HTTPStatus.FORBIDDEN,
        "Only the comment author or an admin can modify this comment.",
    )


def create_notification(
    connection: sqlite3.Connection,
    *,
    user_id: int,
    gym_id: int | None,
    type: str,
    title: str,
    body: str,
    entity_type: str | None = None,
    entity_id: int | None = None,
) -> None:
    connection.execute(
        """
        insert into notifications (
          user_id, gym_id, type, title, body, entity_type, entity_id, created_at
        ) values (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (user_id, gym_id, type, title, body, entity_type, entity_id, isoformat(now_utc())),
    )


def class_schedule_summary(
    connection: sqlite3.Connection,
    *,
    class_schedule_id: int,
) -> sqlite3.Row | None:
    return connection.execute(
        """
        select id, gym_id, title, start_time
        from class_schedules
        where id = ?
        """,
        (class_schedule_id,),
    ).fetchone()


def create_booking_confirmation_notification(
    connection: sqlite3.Connection,
    *,
    user_id: int,
    gym_id: int,
    class_schedule_id: int,
) -> None:
    user = connection.execute(
        "select notify_booking_confirmations from users where id = ? and deleted_at is null",
        (user_id,),
    ).fetchone()
    schedule_row = class_schedule_summary(
        connection,
        class_schedule_id=class_schedule_id,
    )
    if user is None or schedule_row is None or not bool(user["notify_booking_confirmations"]):
        return
    create_notification(
        connection,
        user_id=user_id,
        gym_id=gym_id,
        type="booking_confirmed",
        title="Booking confirmed",
        body=f"{schedule_row['title']} at {schedule_row['start_time']}",
        entity_type="schedule_class",
        entity_id=class_schedule_id,
    )


def promote_next_waitlisted_user(
    connection: sqlite3.Connection,
    *,
    class_schedule_id: int,
) -> int | None:
    next_waitlist_entry = connection.execute(
        """
        select id, user_id
        from class_waitlist_entries
        where class_schedule_id = ?
        order by created_at asc, id asc
        limit 1
        """,
        (class_schedule_id,),
    ).fetchone()
    if next_waitlist_entry is None:
        return None
    connection.execute(
        "delete from class_waitlist_entries where id = ?",
        (next_waitlist_entry["id"],),
    )
    connection.execute(
        """
        insert into class_bookings (
          class_schedule_id, user_id, attendance_status, created_at
        )
        values (?, ?, 'booked', ?)
        """,
        (
            class_schedule_id,
            next_waitlist_entry["user_id"],
            isoformat(now_utc()),
        ),
    )
    return int(next_waitlist_entry["user_id"])


def create_waitlist_promotion_notification(
    connection: sqlite3.Connection,
    *,
    user_id: int,
    gym_id: int,
    class_schedule_id: int,
) -> None:
    user = connection.execute(
        "select notify_waitlist_promotions from users where id = ? and deleted_at is null",
        (user_id,),
    ).fetchone()
    schedule_row = class_schedule_summary(
        connection,
        class_schedule_id=class_schedule_id,
    )
    if user is None or schedule_row is None or not bool(user["notify_waitlist_promotions"]):
        return
    create_notification(
        connection,
        user_id=user_id,
        gym_id=gym_id,
        type="waitlist_promoted",
        title="You are in the class",
        body=f"{schedule_row['title']} at {schedule_row['start_time']}",
        entity_type="schedule_class",
        entity_id=class_schedule_id,
    )


def create_schedule_update_notifications(
    connection: sqlite3.Connection,
    *,
    gym_id: int,
    class_schedule_id: int,
    user_ids: list[int],
) -> None:
    schedule_row = class_schedule_summary(
        connection,
        class_schedule_id=class_schedule_id,
    )
    if schedule_row is None:
        return
    seen_user_ids: set[int] = set()
    for user_id in user_ids:
        if user_id in seen_user_ids:
            continue
        seen_user_ids.add(user_id)
        user = connection.execute(
            "select notify_booking_confirmations from users where id = ? and deleted_at is null",
            (user_id,),
        ).fetchone()
        if user is None or not bool(user["notify_booking_confirmations"]):
            continue
        create_notification(
            connection,
            user_id=user_id,
            gym_id=gym_id,
            type="schedule_updated",
            title="Class updated",
            body=f"{schedule_row['title']} now starts at {schedule_row['start_time']}",
            entity_type="schedule_class",
            entity_id=class_schedule_id,
        )


def create_wod_notifications(
    connection: sqlite3.Connection,
    *,
    gym_id: int,
    workout_id: int,
    scheduled_date: str,
    title: str,
    is_update: bool,
) -> None:
    users = connection.execute(
        """
        select users.id
        from gym_memberships
        join users on users.id = gym_memberships.user_id
        where gym_memberships.gym_id = ?
          and gym_memberships.status = 'active'
          and users.deleted_at is null
          and users.notify_wod_posted = 1
        """,
        (gym_id,),
    ).fetchall()
    notification_type = "wod_updated" if is_update else "wod_posted"
    title_text = "Workout updated" if is_update else "New workout posted"
    body_text = f"{scheduled_date}: {title}"
    for user in users:
        create_notification(
            connection,
            user_id=user["id"],
            gym_id=gym_id,
            type=notification_type,
            title=title_text,
            body=body_text,
            entity_type="daily_workout",
            entity_id=workout_id,
        )


def create_pr_achievement_notification(
    connection: sqlite3.Connection,
    *,
    user_id: int,
    gym_id: int,
    workout_id: int,
    workout_title: str,
    score_label: str,
) -> None:
    user = connection.execute(
        "select notify_pr_achievements from users where id = ? and deleted_at is null",
        (user_id,),
    ).fetchone()
    if user is None or not bool(user["notify_pr_achievements"]):
        return
    create_notification(
        connection,
        user_id=user_id,
        gym_id=gym_id,
        type="pr_achieved",
        title="New personal record",
        body=f"{workout_title}: {score_label}",
        entity_type="daily_workout",
        entity_id=workout_id,
    )


def create_announcement_like_notification(
    connection: sqlite3.Connection,
    *,
    recipient_user_id: int,
    actor_user_id: int,
    gym_id: int,
    announcement_id: int,
    announcement_title: str,
) -> None:
    if recipient_user_id == actor_user_id:
        return
    recipient = connection.execute(
        "select notify_announcement_activity from users where id = ? and deleted_at is null",
        (recipient_user_id,),
    ).fetchone()
    actor = connection.execute(
        "select display_name, nickname, email from users where id = ? and deleted_at is null",
        (actor_user_id,),
    ).fetchone()
    if recipient is None or actor is None or not bool(recipient["notify_announcement_activity"]):
        return
    actor_name = preferred_user_name(actor)
    create_notification(
        connection,
        user_id=recipient_user_id,
        gym_id=gym_id,
        type="announcement_liked",
        title="New like on your announcement",
        body=f'{actor_name} liked "{announcement_title}".',
        entity_type="announcement",
        entity_id=announcement_id,
    )


def create_announcement_comment_notification(
    connection: sqlite3.Connection,
    *,
    recipient_user_id: int,
    actor_user_id: int,
    gym_id: int,
    announcement_id: int,
    announcement_title: str,
    comment_body: str,
) -> None:
    if recipient_user_id == actor_user_id:
        return
    recipient = connection.execute(
        "select notify_announcement_activity from users where id = ? and deleted_at is null",
        (recipient_user_id,),
    ).fetchone()
    actor = connection.execute(
        "select display_name, nickname, email from users where id = ? and deleted_at is null",
        (actor_user_id,),
    ).fetchone()
    if recipient is None or actor is None or not bool(recipient["notify_announcement_activity"]):
        return
    actor_name = preferred_user_name(actor)
    snippet = comment_body.strip()
    if len(snippet) > 80:
        snippet = f"{snippet[:77].rstrip()}..."
    create_notification(
        connection,
        user_id=recipient_user_id,
        gym_id=gym_id,
        type="announcement_commented",
        title="New comment on your announcement",
        body=f'{actor_name} commented on "{announcement_title}": {snippet}',
        entity_type="announcement",
        entity_id=announcement_id,
    )


