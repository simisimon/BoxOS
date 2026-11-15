from __future__ import annotations

import json
from datetime import UTC, date, datetime, timedelta
from http import HTTPStatus
from typing import Any, TYPE_CHECKING

from backend.core.security import now_utc
from backend.core.validation import ApiError
from backend.services import workout_service

if TYPE_CHECKING:
    from backend.core.db import Row


def audit_log_payload(row: Row) -> dict[str, Any]:
    return {
        "id": row["id"],
        "action": row["action"],
        "entity_type": row["entity_type"],
        "entity_id": row["entity_id"],
        "details": json.loads(row["details_json"]),
        "created_at": row["created_at"],
        "actor": {
            "email": row["actor_email"],
            "display_name": row["actor_display_name"],
            "nickname": row["actor_nickname"],
        },
        "target": None if row["target_email"] is None else {
            "email": row["target_email"],
            "display_name": row["target_display_name"],
            "nickname": row["target_nickname"],
        },
    }


today_utc_date = lambda: now_utc().date()


def require_admin_analytics_window_days(value: Any) -> int:
    try:
        window_days = int(str(value or "").strip())
    except ValueError as error:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Window days must be a valid integer.") from error
    if window_days not in {7, 14, 30}:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Window days must be one of 7, 14, or 30.")
    return window_days


# re-export workout/programming payload helpers from workout_service

daily_workout_payload = workout_service.daily_workout_payload
exercise_payload = workout_service.exercise_payload
DAILY_WORKOUT_COLUMNS = workout_service.DAILY_WORKOUT_COLUMNS
replace_workout_sections = workout_service.replace_workout_sections
fetch_workout_sections = workout_service.fetch_workout_sections


def can_view_drafts(role: str | None) -> bool:
    return role in {"admin", "trainer"}


def require_workout_status(value: Any) -> str:
    status = str(value or "").strip().lower()
    if status not in {"draft", "published"}:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Status must be draft or published.")
    return status


# --- Scheduled release ----------------------------------------------------------
#
# A gym can set one default release time (Settings › Programming): "20:00 the
# evening before" or "06:00 on the day". Coaches then "Schedule" a WOD instead
# of publishing it. It stays hidden from athletes (status 'scheduled') until
# release_at, when release_due_workouts() publishes it and sends the usual
# "New workout posted" push. Staff see scheduled WODs like drafts.


def require_release_time(value: Any) -> str | None:
    """'HH:MM' (24 h) or None to turn scheduled release off."""
    if value is None or str(value).strip() == "":
        return None
    text = str(value).strip()
    try:
        hours, minutes = (int(part) for part in text.split(":"))
    except ValueError:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Release time must look like 20:00.") from None
    if not (0 <= hours < 24 and 0 <= minutes < 60) or len(text.split(":")[1]) != 2:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Release time must look like 20:00.")
    return f"{hours:02d}:{minutes:02d}"


def gym_release_settings(connection: Any, gym_id: int) -> dict[str, Any]:
    row = connection.execute(
        "select timezone, wod_release_time, wod_release_day_before from gyms where id = ?",
        (gym_id,),
    ).fetchone()
    if row is None:
        raise ApiError(HTTPStatus.NOT_FOUND, "Active gym not found.")
    return {
        "timezone": row["timezone"],
        "release_time": row["wod_release_time"],
        "release_day_before": bool(row["wod_release_day_before"]),
    }


def release_settings_payload(release: dict[str, Any]) -> dict[str, Any]:
    return {
        "release_time": release["release_time"],
        "release_day_before": release["release_day_before"],
    }


def release_moment(scheduled_date: str, release: dict[str, Any]) -> str:
    """UTC timestamp at which a WOD for [scheduled_date] goes live."""
    from backend.services import schedule_service

    hours, minutes = (int(part) for part in release["release_time"].split(":"))
    day = date.fromisoformat(scheduled_date)
    if release["release_day_before"]:
        day -= timedelta(days=1)
    local = datetime(day.year, day.month, day.day, hours, minutes)
    moment = schedule_service.utc_for_local(local, release["timezone"])
    return moment.astimezone(UTC).isoformat(timespec="seconds")


def reschedule_gym_workouts(connection: Any, gym_id: int) -> None:
    """After the gym's release time changed: move every scheduled WOD to the
    new moment, or back to draft when release is turned off."""
    release = gym_release_settings(connection, gym_id)
    rows = connection.execute(
        "select id, scheduled_date from daily_workouts where gym_id = ? and status = 'scheduled'",
        (gym_id,),
    ).fetchall()
    for row in rows:
        if release["release_time"] is None:
            connection.execute(
                "update daily_workouts set status = 'draft', release_at = null where id = ?",
                (row["id"],),
            )
        else:
            connection.execute(
                "update daily_workouts set release_at = ? where id = ?",
                (release_moment(row["scheduled_date"], release), row["id"]),
            )


def release_due_workouts(connection: Any) -> int:
    """Publish every scheduled WOD whose release time has passed and notify
    the gym. The update claims the rows, so two workers never send twice."""
    from backend.core import notifications

    now = now_utc().astimezone(UTC).isoformat(timespec="seconds")
    with connection:
        rows = connection.execute(
            """
            update daily_workouts
            set status = 'published', published_at = release_at, updated_at = ?
            where status = 'scheduled' and release_at <= ?
            returning id, gym_id, scheduled_date, title
            """,
            (now, now),
        ).fetchall()
        for row in rows:
            notifications.create_wod_notifications(
                connection,
                gym_id=row["gym_id"],
                workout_id=row["id"],
                scheduled_date=row["scheduled_date"],
                title=row["title"],
                is_update=False,
            )
    return len(rows)
