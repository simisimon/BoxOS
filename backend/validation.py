from __future__ import annotations

import base64
import binascii
import json
import sqlite3
from datetime import date, datetime, timedelta
from http import HTTPStatus
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from backend import settings
from backend.security import now_utc, parse_iso

class ApiError(Exception):
    def __init__(self, status: HTTPStatus, message: str):
        super().__init__(message)
        self.status = status
        self.message = message

def normalize_account_type_value(value: Any) -> str:
    account_type = str(value or "").strip().lower()
    if account_type == "owner":
        return "admin"
    return account_type


def normalize_role_value(value: Any) -> str:
    role = str(value or "").strip().lower()
    if role == "box":
        return "admin"
    return role


def require_email(value: Any) -> str:
    email = str(value or "").strip().lower()
    if "@" not in email or "." not in email:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Enter a valid email.")
    return email


def require_password(value: Any, *, label: str = "Password") -> str:
    password = str(value or "")
    if len(password) < 8:
        raise ApiError(HTTPStatus.BAD_REQUEST, f"{label} must be at least 8 characters.")
    return password


def require_token(value: Any, *, label: str) -> str:
    token = str(value or "").strip()
    if not token:
        raise ApiError(HTTPStatus.BAD_REQUEST, f"{label} is required.")
    return token


def require_display_name(value: Any) -> str:
    display_name = str(value or "").strip()
    if not display_name:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Display name is required.")
    if len(display_name) > 50:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Display name must be 50 characters or fewer.")
    return display_name


def require_nickname(value: Any) -> str:
    nickname = str(value or "").strip()
    if len(nickname) > 30:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Nickname must be 30 characters or fewer.")
    return nickname


def require_platform(value: Any) -> str:
    platform = str(value or "").strip()
    if not platform:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Platform is required.")
    if len(platform) > 30:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Platform must be 30 characters or fewer.")
    return platform


def require_notification_preferences(body: dict[str, Any]) -> dict[str, bool]:
    required_keys = (
        "booking_confirmations",
        "waitlist_promotions",
        "payment_issues",
        "wod_posted",
        "pr_achievements",
        "announcement_activity",
    )
    preferences: dict[str, bool] = {}
    for key in required_keys:
        if key not in body:
            raise ApiError(
                HTTPStatus.BAD_REQUEST,
                f"{key.replace('_', ' ').capitalize()} is required.",
            )
        value = body[key]
        if not isinstance(value, bool):
            raise ApiError(
                HTTPStatus.BAD_REQUEST,
                f"{key.replace('_', ' ').capitalize()} must be true or false.",
            )
        preferences[key] = value
    return preferences


def role_user_payload(row: sqlite3.Row) -> dict[str, Any]:
    return {
        "id": row["id"],
        "email": row["email"],
        "role": row["role"],
        "available_roles": decode_roles(row["roles_json"]),
        "display_name": row["display_name"],
        "nickname": row["nickname"],
    }


def role_managed_member_payload(row: sqlite3.Row) -> dict[str, Any]:
    role = row["active_role"]
    available_roles = decode_roles(row["roles_json"])
    can_edit_role = role != "admin"
    if can_edit_role:
        available_roles = [
            managed_role
            for managed_role in available_roles
            if managed_role in {"athlete", "trainer"}
        ]
        if not available_roles:
            available_roles = ["athlete"]
    return {
        "id": row["user_id"],
        "membership_id": row["id"],
        "email": row["email"],
        "role": role,
        "available_roles": available_roles,
        "display_name": row["display_name"],
        "nickname": row["nickname"],
        "can_edit_role": can_edit_role,
    }


def profile_payload(row: sqlite3.Row) -> dict[str, Any]:
    connection = get_connection()
    active_membership = get_active_membership(connection, row["id"]) if "id" in row.keys() else None
    memberships = (
        list_user_memberships(connection, row["id"])
        if "id" in row.keys()
        else []
    )
    connection.close()
    return {
        "email": row["email"],
        "role": row["role"],
        "available_roles": decode_roles(row["roles_json"]),
        "display_name": row["display_name"],
        "nickname": row["nickname"],
        "account_type": row["account_type"],
        "active_gym": active_gym_payload(active_membership),
        "memberships": [membership_payload(membership) for membership in memberships],
    }


def require_user_id(value: Any) -> int:
    try:
        user_id = int(value)
    except (TypeError, ValueError):
        raise ApiError(HTTPStatus.BAD_REQUEST, "User id is required.")
    if user_id <= 0:
        raise ApiError(HTTPStatus.BAD_REQUEST, "User id is required.")
    return user_id


def require_optional_user_id(value: Any) -> int | None:
    if value is None:
        return None
    trimmed = str(value).strip()
    if not trimmed:
        return None
    return require_user_id(trimmed)


def require_account_type(value: Any) -> str:
    account_type = normalize_account_type_value(value)
    if account_type not in settings.ALLOWED_ACCOUNT_TYPES:
        raise ApiError(
            HTTPStatus.BAD_REQUEST,
            "Account type must be athlete or admin.",
        )
    return account_type


def require_gym_name(value: Any) -> str:
    name = str(value or "").strip()
    if not name:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Gym name is required.")
    if len(name) > 80:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Gym name must be 80 characters or fewer.")
    return name


def require_logo_url(value: Any) -> str:
    logo_url = str(value or "").strip()
    if not logo_url:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Gym logo URL is required.")
    if len(logo_url) > 300:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Gym logo URL must be 300 characters or fewer.")
    return logo_url


def require_upload_filename(value: Any) -> str:
    filename = Path(str(value or "upload").strip()).name
    if not filename:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Filename is required.")
    if len(filename) > 120:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Filename is too long.")
    return filename


def require_announcement_image_content_type(value: Any) -> str:
    content_type = str(value or "").strip().lower()
    if content_type not in settings.ALLOWED_ANNOUNCEMENT_IMAGE_CONTENT_TYPES:
        raise ApiError(
            HTTPStatus.BAD_REQUEST,
            "Announcement images must be JPEG, PNG, or WEBP.",
        )
    return content_type


def require_gym_logo_content_type(value: Any) -> str:
    content_type = str(value or "").strip().lower()
    if content_type not in settings.ALLOWED_GYM_LOGO_CONTENT_TYPES:
        raise ApiError(
            HTTPStatus.BAD_REQUEST,
            "Gym logos must be JPEG, PNG, or WEBP.",
        )
    return content_type


def require_base64_bytes(value: Any, *, label: str, max_bytes: int) -> bytes:
    data = str(value or "").strip()
    if not data:
        raise ApiError(HTTPStatus.BAD_REQUEST, f"{label} is required.")
    try:
        decoded = base64.b64decode(data, validate=True)
    except (ValueError, binascii.Error) as error:
        raise ApiError(HTTPStatus.BAD_REQUEST, f"{label} must be valid base64.") from error
    if not decoded:
        raise ApiError(HTTPStatus.BAD_REQUEST, f"{label} is required.")
    if len(decoded) > max_bytes:
        raise ApiError(HTTPStatus.BAD_REQUEST, f"{label} is too large.")
    return decoded


def require_announcement_title(value: Any) -> str:
    title = str(value or "").strip()
    if not title:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Announcement title is required.")
    if len(title) > 120:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Announcement title must be 120 characters or fewer.")
    return title


def require_announcement_description(value: Any) -> str:
    description = str(value or "").strip()
    if not description:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Announcement description is required.")
    if len(description) > 5000:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Announcement description must be 5000 characters or fewer.")
    return description


def require_announcement_comment_body(value: Any) -> str:
    body = str(value or "").strip()
    if not body:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Comment is required.")
    if len(body) > 1500:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Comment must be 1500 characters or fewer.")
    return body


def require_optional_image_url(value: Any) -> str | None:
    if value is None:
        return None
    image_url = str(value).strip()
    if not image_url:
        return None
    if len(image_url) > 500:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Announcement image URL must be 500 characters or fewer.")
    return image_url


def require_timezone(value: Any) -> str:
    timezone = str(value or "").strip()
    if not timezone:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Timezone is required.")
    if len(timezone) > 100:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Timezone must be 100 characters or fewer.")
    return timezone


def require_schedule_title(value: Any) -> str:
    title = str(value or "").strip()
    if not title:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Class title is required.")
    if len(title) > 80:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Class title must be 80 characters or fewer.")
    return title


def require_class_type(value: Any) -> str:
    class_type = str(value or "").strip()
    allowed_types = {"WOD", "Open Gym", "Specialty", "PT"}
    if class_type not in allowed_types:
        raise ApiError(
            HTTPStatus.BAD_REQUEST,
            "Class type must be WOD, Open Gym, Specialty, or PT.",
        )
    return class_type


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


def recurrence_delta_for(frequency: str) -> timedelta:
    if frequency == "daily":
        return timedelta(days=1)
    if frequency == "weekly":
        return timedelta(days=7)
    if frequency == "monthly":
        return timedelta(days=28)
    return timedelta(days=0)


def recurrence_occurrence_limit_for(frequency: str) -> int:
    if frequency == "none":
        return 1
    return settings.RECURRENCE_OCCURRENCE_LIMITS.get(frequency, settings.MAX_RECURRENCE_OCCURRENCES)


def build_recurrence_start_times(
    start_time: datetime,
    *,
    recurrence_frequency: str,
    occurrence_count: int,
    gym_timezone: str,
) -> list[datetime]:
    if recurrence_frequency == "none":
        return [start_time]
    recurrence_delta = recurrence_delta_for(recurrence_frequency)
    timezone = timezone_for_name(gym_timezone)
    if timezone is not None:
        local_start_time = start_time.astimezone(timezone)
        local_start_naive = local_start_time.replace(tzinfo=None)
        return [
            (local_start_naive + (recurrence_delta * index))
            .replace(tzinfo=timezone)
            .astimezone(UTC)
            for index in range(occurrence_count)
        ]
    local_start_naive = manual_local_datetime_for_utc(start_time, gym_timezone)
    return [
        manual_utc_datetime_for_local(
            local_start_naive + (recurrence_delta * index),
            gym_timezone,
        )
        for index in range(occurrence_count)
    ]


def timezone_for_name(gym_timezone: str) -> Any | None:
    try:
        return ZoneInfo(gym_timezone)
    except ZoneInfoNotFoundError:
        if dateutil_tz is not None:
            timezone = dateutil_tz.gettz(gym_timezone)
            if timezone is not None:
                return timezone
        if pytz is not None:
            try:
                return pytz.timezone(gym_timezone)
            except pytz.UnknownTimeZoneError:
                pass
        if gym_timezone in {"UTC", "Europe/Berlin", "America/New_York"}:
            return None
        raise ApiError(HTTPStatus.BAD_REQUEST, "Gym timezone is invalid.")


def manual_local_datetime_for_utc(utc_datetime: datetime, gym_timezone: str) -> datetime:
    utc_naive = utc_datetime.astimezone(UTC).replace(tzinfo=None)
    return utc_naive + manual_utc_offset_for_utc_datetime(utc_naive, gym_timezone)


def manual_utc_datetime_for_local(local_datetime: datetime, gym_timezone: str) -> datetime:
    offset = manual_utc_offset_for_local_datetime(local_datetime, gym_timezone)
    return (local_datetime - offset).replace(tzinfo=UTC)


def manual_utc_offset_for_utc_datetime(
    utc_datetime: datetime,
    gym_timezone: str,
) -> timedelta:
    if gym_timezone == "UTC":
        return timedelta(0)
    if gym_timezone == "Europe/Berlin":
        dst_start = datetime.combine(last_weekday_of_month(utc_datetime.year, 3, 6), datetime.min.time()) + timedelta(hours=1)
        dst_end = datetime.combine(last_weekday_of_month(utc_datetime.year, 10, 6), datetime.min.time()) + timedelta(hours=1)
        return timedelta(hours=2 if dst_start <= utc_datetime < dst_end else 1)
    if gym_timezone == "America/New_York":
        dst_start = datetime.combine(nth_weekday_of_month(utc_datetime.year, 3, 6, 2), datetime.min.time()) + timedelta(hours=7)
        dst_end = datetime.combine(nth_weekday_of_month(utc_datetime.year, 11, 6, 1), datetime.min.time()) + timedelta(hours=6)
        return timedelta(hours=-4 if dst_start <= utc_datetime < dst_end else -5)
    raise ApiError(HTTPStatus.BAD_REQUEST, "Gym timezone is invalid.")


def manual_utc_offset_for_local_datetime(
    local_datetime: datetime,
    gym_timezone: str,
) -> timedelta:
    if gym_timezone == "UTC":
        return timedelta(0)
    if gym_timezone == "Europe/Berlin":
        dst_start = datetime.combine(last_weekday_of_month(local_datetime.year, 3, 6), datetime.min.time()) + timedelta(hours=2)
        dst_end = datetime.combine(last_weekday_of_month(local_datetime.year, 10, 6), datetime.min.time()) + timedelta(hours=3)
        return timedelta(hours=2 if dst_start <= local_datetime < dst_end else 1)
    if gym_timezone == "America/New_York":
        dst_start = datetime.combine(nth_weekday_of_month(local_datetime.year, 3, 6, 2), datetime.min.time()) + timedelta(hours=2)
        dst_end = datetime.combine(nth_weekday_of_month(local_datetime.year, 11, 6, 1), datetime.min.time()) + timedelta(hours=2)
        return timedelta(hours=-4 if dst_start <= local_datetime < dst_end else -5)
    raise ApiError(HTTPStatus.BAD_REQUEST, "Gym timezone is invalid.")


def nth_weekday_of_month(year: int, month: int, weekday: int, occurrence: int) -> date:
    current = date(year, month, 1)
    while current.weekday() != weekday:
        current += timedelta(days=1)
    return current + timedelta(days=(occurrence - 1) * 7)


def last_weekday_of_month(year: int, month: int, weekday: int) -> date:
    if month == 12:
        current = date(year + 1, 1, 1) - timedelta(days=1)
    else:
        current = date(year, month + 1, 1) - timedelta(days=1)
    while current.weekday() != weekday:
        current -= timedelta(days=1)
    return current


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


def require_wod_description(value: Any) -> str:
    description = str(value or "").strip()
    if len(description) > 2000:
        raise ApiError(
            HTTPStatus.BAD_REQUEST,
            "WOD description must be 2000 characters or fewer.",
        )
    return description


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


def today_utc_date() -> datetime.date:
    return now_utc().date()


def require_admin_analytics_window_days(value: Any) -> int:
    try:
        window_days = int(str(value or "").strip())
    except ValueError as error:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Window days must be a valid integer.") from error
    if window_days not in {7, 14, 30}:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Window days must be one of 7, 14, or 30.")
    return window_days


def parse_programming_date(value: str) -> datetime.date:
    return datetime.fromisoformat(value).date()


def require_programming_date(value: Any) -> str:
    raw = str(value or "").strip()
    if not raw:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Scheduled date is required.")
    try:
        scheduled_date = parse_programming_date(raw)
    except ValueError:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Scheduled date must be a valid ISO-8601 date.")
    if scheduled_date < today_utc_date():
        raise ApiError(HTTPStatus.BAD_REQUEST, "Scheduled date must be today or later.")
    return scheduled_date.isoformat()


def require_programming_title(value: Any) -> str:
    title = str(value or "").strip()
    if not title:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Workout title is required.")
    if len(title) > 80:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Workout title must be 80 characters or fewer.")
    return title


def require_programming_section(value: Any, *, label: str) -> str:
    text_value = str(value or "").strip()
    if len(text_value) > 4000:
        raise ApiError(HTTPStatus.BAD_REQUEST, f"{label} must be 4000 characters or fewer.")
    return text_value


def require_whiteboard_score(score_type_value: Any, score_value_value: Any) -> tuple[str, float, str]:
    score_type = str(score_type_value or "").strip().lower()
    if score_type not in {"time", "reps", "load"}:
        raise ApiError(
            HTTPStatus.BAD_REQUEST,
            "Score type must be time, reps, or load.",
        )
    raw_score_value = str(score_value_value or "").strip()
    if not raw_score_value:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Score value is required.")

    if score_type == "time":
        normalized = raw_score_value.replace(".", ":")
        parts = normalized.split(":")
        if len(parts) not in {2, 3}:
            raise ApiError(
                HTTPStatus.BAD_REQUEST,
                "Time score must be mm:ss or hh:mm:ss.",
            )
        try:
            numbers = [int(part) for part in parts]
        except ValueError:
            raise ApiError(
                HTTPStatus.BAD_REQUEST,
                "Time score must be mm:ss or hh:mm:ss.",
            )
        if any(number < 0 for number in numbers):
            raise ApiError(HTTPStatus.BAD_REQUEST, "Time score must be positive.")
        if len(numbers) == 2:
            minutes, seconds = numbers
            hours = 0
        else:
            hours, minutes, seconds = numbers
        if minutes >= 60 and len(numbers) == 3:
            raise ApiError(HTTPStatus.BAD_REQUEST, "Minutes must be below 60 for hh:mm:ss.")
        if seconds >= 60:
            raise ApiError(HTTPStatus.BAD_REQUEST, "Seconds must be below 60.")
        total_seconds = float(hours * 3600 + minutes * 60 + seconds)
        if total_seconds <= 0:
            raise ApiError(HTTPStatus.BAD_REQUEST, "Time score must be positive.")
        return score_type, total_seconds, raw_score_value

    try:
        score_value = float(raw_score_value)
    except ValueError:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Score value must be numeric.")
    if score_value <= 0:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Score value must be positive.")
    return score_type, score_value, raw_score_value


def require_whiteboard_notes(value: Any) -> str:
    notes = str(value or "").strip()
    if len(notes) > 500:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Notes must be 500 characters or fewer.")
    return notes


def require_personal_workout_title(value: Any) -> str:
    title = str(value or "").strip()
    if not title:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Workout title is required.")
    if len(title) > 120:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Workout title must be 120 characters or fewer.")
    return title


def require_personal_workout_type(value: Any) -> str:
    workout_type = str(value or "").strip().lower()
    allowed_types = {"amrap", "for_time", "emom", "interval", "strength", "custom"}
    if workout_type not in allowed_types:
        raise ApiError(
            HTTPStatus.BAD_REQUEST,
            "Workout type must be amrap, for_time, emom, interval, strength, or custom.",
        )
    return workout_type


def require_personal_workout_structure(value: Any) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ApiError(HTTPStatus.BAD_REQUEST, "Workout structure must be an object.")
    return value


def require_personal_workout_id(value: Any) -> int:
    try:
        workout_id = int(value)
    except (TypeError, ValueError):
        raise ApiError(HTTPStatus.BAD_REQUEST, "Workout id is required.")
    if workout_id <= 0:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Workout id is required.")
    return workout_id


def require_join_request_decision(value: Any) -> str:
    decision = str(value or "").strip().lower()
    if decision not in {"approve", "reject"}:
        raise ApiError(
            HTTPStatus.BAD_REQUEST,
            "Decision must be approve or reject.",
        )
    return decision


def require_role_value(value: Any) -> str:
    role = normalize_role_value(value)
    if role not in settings.ALLOWED_ROLES:
        raise ApiError(
            HTTPStatus.BAD_REQUEST,
            "Role must be athlete, trainer, or admin.",
        )
    return role


def require_role_list(body: dict[str, Any]) -> list[str]:
    if "roles" in body:
        raw_roles = body["roles"]
        if not isinstance(raw_roles, list):
            raise ApiError(HTTPStatus.BAD_REQUEST, "Roles must be a list.")
        return normalize_roles(raw_roles)
    return [require_role_value(body.get("role"))]


def normalize_roles(values: list[Any]) -> list[str]:
    roles = [require_role_value(value) for value in values]
    unique_roles = list(dict.fromkeys(roles))
    if not unique_roles:
        raise ApiError(HTTPStatus.BAD_REQUEST, "At least one role is required.")
    return unique_roles


def encode_roles(roles: list[str]) -> str:
    return json.dumps(roles)


def decode_roles(value: str | None) -> list[str]:
    if not value:
        return ["athlete"]
    try:
        raw_roles = json.loads(value)
    except json.JSONDecodeError:
        return ["athlete"]
    if not isinstance(raw_roles, list):
        return ["athlete"]
    normalized = []
    for role in raw_roles:
        role_value = normalize_role_value(role)
        if role_value in settings.ALLOWED_ROLES and role_value not in normalized:
            normalized.append(role_value)
    return normalized or ["athlete"]
