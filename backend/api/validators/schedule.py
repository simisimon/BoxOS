"""Request validators used only by the schedule routes (see api/routes/schedule.py)."""

from __future__ import annotations

from datetime import datetime
from http import HTTPStatus
from typing import TYPE_CHECKING, Any

from backend.core.security import now_utc, parse_iso

if TYPE_CHECKING:
    pass

from backend.core.validation import BUILTIN_CLASS_TYPES, ApiError, require_user_id
from backend.services.schedule_service import recurrence_occurrence_limit_for


def require_optional_user_id(value: Any) -> int | None:
    if value is None:
        return None
    trimmed = str(value).strip()
    if not trimmed:
        return None
    return require_user_id(trimmed)


def require_schedule_title(value: Any) -> str:
    title = str(value or "").strip()
    if not title:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Class title is required.")
    if len(title) > 80:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Class title must be 80 characters or fewer.")
    return title
CLASS_TYPE_COLORS = {"primary", "info", "success", "warning", "danger", "muted"}


def require_class_type(value: Any, allowed: Any = BUILTIN_CLASS_TYPES) -> str:
    """A class type of the gym: built-in or one its owner added."""
    class_type = str(value or "").strip()
    if class_type not in set(allowed):
        raise ApiError(HTTPStatus.BAD_REQUEST, "Unknown class type.")
    return class_type


def require_new_class_type(raw: dict[str, Any], existing: Any) -> dict[str, Any]:
    name = str(raw.get("name") or "").strip()
    if not 1 <= len(name) <= 30:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Name must be 1 to 30 characters.")
    if name.lower() in {item.lower() for item in existing}:
        raise ApiError(HTTPStatus.CONFLICT, "This class type already exists.")
    color = str(raw.get("color") or "info")
    if color not in CLASS_TYPE_COLORS:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Unknown colour.")
    try:
        capacity = int(raw.get("default_capacity") or 12)
    except (TypeError, ValueError):
        raise ApiError(HTTPStatus.BAD_REQUEST, "Default limit must be a number.") from None
    if not 1 <= capacity <= 200:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Default limit must be 1 to 200.")
    return {"name": name, "color": color, "default_capacity": capacity}


def require_weekdays(value: Any) -> list[int]:
    """ISO weekdays (1 = Monday … 7 = Sunday), deduplicated and sorted."""
    if not isinstance(value, list) or not value:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Select at least one weekday.")
    weekdays: set[int] = set()
    for item in value:
        try:
            weekday = int(item)
        except (TypeError, ValueError):
            raise ApiError(HTTPStatus.BAD_REQUEST, "Weekdays must be numbers from 1 to 7.")
        if weekday < 1 or weekday > 7:
            raise ApiError(HTTPStatus.BAD_REQUEST, "Weekdays must be numbers from 1 to 7.")
        weekdays.add(weekday)
    return sorted(weekdays)


def require_local_time(value: Any) -> str:
    """Wall-clock time in the gym's timezone, normalised to HH:MM."""
    text = str(value or "").strip()
    parts = text.split(":")
    if len(parts) != 2 or not all(part.isdigit() for part in parts):
        raise ApiError(HTTPStatus.BAD_REQUEST, "Start time must use the HH:MM format.")
    hour, minute = int(parts[0]), int(parts[1])
    if hour > 23 or minute > 59:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Start time must use the HH:MM format.")
    return f"{hour:02d}:{minute:02d}"


def require_capacity(value: Any) -> int:
    try:
        capacity = int(value)
    except (TypeError, ValueError):
        raise ApiError(HTTPStatus.BAD_REQUEST, "Capacity is required.")
    if capacity <= 0 or capacity > 200:
        raise ApiError(
            HTTPStatus.BAD_REQUEST,
            "Capacity must be between 1 and 200.",
        )
    return capacity


def require_duration_minutes(value: Any) -> int:
    try:
        duration_minutes = int(value)
    except (TypeError, ValueError):
        raise ApiError(HTTPStatus.BAD_REQUEST, "Duration is required.")
    if duration_minutes <= 0 or duration_minutes > 24 * 60:
        raise ApiError(
            HTTPStatus.BAD_REQUEST,
            "Duration must be between 1 and 1440 minutes.",
        )
    return duration_minutes


def require_recurrence_frequency(value: Any) -> str:
    frequency = str(value or "none").strip().lower()
    allowed = {"none", "daily", "weekly", "monthly"}
    if frequency not in allowed:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Invalid recurrence frequency.")
    return frequency


def require_occurrence_count(value: Any, *, recurrence_frequency: str) -> int:
    if recurrence_frequency == "none":
        return 1
    try:
        occurrence_count = int(value)
    except (TypeError, ValueError):
        raise ApiError(
            HTTPStatus.BAD_REQUEST,
            "Occurrence count must be a whole number.",
        )
    if occurrence_count < 1:
        raise ApiError(
            HTTPStatus.BAD_REQUEST,
            "Occurrence count must be at least 1.",
        )
    max_occurrence_count = recurrence_occurrence_limit_for(recurrence_frequency)
    if occurrence_count > max_occurrence_count:
        if recurrence_frequency == "daily":
            message = (
                f"Occurrence count must be {max_occurrence_count} or fewer."
            )
        else:
            message = (
                "Occurrence count must be "
                f"{max_occurrence_count} or fewer for {recurrence_frequency} recurrence."
            )
        raise ApiError(
            HTTPStatus.BAD_REQUEST,
            message,
        )
    return occurrence_count


def require_schedule_duration_minutes(body: dict[str, Any]) -> int:
    if body.get("duration_minutes") not in (None, ""):
        return require_duration_minutes(body.get("duration_minutes"))

    end_time_value = body.get("end_time")
    if end_time_value in (None, ""):
        raise ApiError(HTTPStatus.BAD_REQUEST, "Duration is required.")

    try:
        start_time = parse_iso(str(body.get("start_time") or "").strip())
        end_time = parse_iso(str(end_time_value).strip())
    except ValueError:
        raise ApiError(
            HTTPStatus.BAD_REQUEST,
            "End time must be a valid ISO-8601 datetime.",
        )

    duration_minutes = int(round((end_time - start_time).total_seconds() / 60))
    return require_duration_minutes(duration_minutes)


def require_attendance_status(value: Any) -> str:
    attendance_status = str(value or "").strip().lower()
    if attendance_status not in {"booked", "attended", "no_show"}:
        raise ApiError(
            HTTPStatus.BAD_REQUEST,
            "Attendance status must be booked, attended, or no_show.",
        )
    return attendance_status


def require_future_datetime(value: Any, *, label: str) -> datetime:
    try:
        parsed = parse_iso(str(value or "").strip())
    except ValueError:
        raise ApiError(
            HTTPStatus.BAD_REQUEST,
            f"{label} must be a valid ISO-8601 datetime.",
        )
    if parsed <= now_utc():
        raise ApiError(
            HTTPStatus.BAD_REQUEST,
            f"{label} must be in the future.",
        )
    return parsed
