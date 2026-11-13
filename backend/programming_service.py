from __future__ import annotations

import json
from http import HTTPStatus
from typing import Any, TYPE_CHECKING

from backend.security import now_utc
from backend.validation import ApiError
from backend import workout_service

if TYPE_CHECKING:
    from backend.db import Row


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
