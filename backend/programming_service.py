from __future__ import annotations

import json
from http import HTTPStatus
from typing import Any, TYPE_CHECKING

from backend.notifications_core import create_notification
from backend.security import now_utc
from backend.validation import ApiError
from backend import workout_service

if TYPE_CHECKING:
    from backend.db import ManagedConnection, Row


def create_pr_achievement_notification(
    connection: ManagedConnection,
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
workout_log_payload = workout_service.workout_log_payload
exercise_payload = workout_service.exercise_payload
benchmark_workout_payload = workout_service.benchmark_workout_payload
personal_workout_payload = workout_service.personal_workout_payload
get_workout_log_for_user = workout_service.get_workout_log_for_user
refresh_pr_flags_for_workout_title = workout_service.refresh_pr_flags_for_workout_title
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
