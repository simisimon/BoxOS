"""Request validators used only by the programming routes (see api/routes/programming.py)."""

from __future__ import annotations

from datetime import datetime
from http import HTTPStatus
from typing import TYPE_CHECKING, Any

from backend.core.security import now_utc

if TYPE_CHECKING:
    pass

from backend.core.validation import ApiError


def today_utc_date() -> datetime.date:
    return now_utc().date()


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


# ``none`` marks blocks without a result (warm-up, mobility, accessory).
WORKOUT_SECTION_SCORE_TYPES = {"time", "rounds_reps", "reps", "weight", "calories", "distance", "none"}
MAX_WORKOUT_SECTIONS = 20


def require_workout_section_score_type(value: Any) -> str:
    text = str(value or "").strip().lower()
    if text not in WORKOUT_SECTION_SCORE_TYPES:
        raise ApiError(
            HTTPStatus.BAD_REQUEST,
            "Section score must be one of: " + ", ".join(sorted(WORKOUT_SECTION_SCORE_TYPES)) + ".",
        )
    return text


def require_workout_sections(value: Any) -> list[dict[str, Any]]:
    """Normalize and validate the sections payload for a daily WOD.

    Sections require a non-empty description (max 4000 chars) and a score type
    from ``WORKOUT_SECTION_SCORE_TYPES``. Title is optional (max 80 chars).
    A WOD must have at least one section so athletes have something to read.
    """
    if not isinstance(value, list) or not value:
        raise ApiError(
            HTTPStatus.BAD_REQUEST,
            "A WOD needs at least one section.",
        )
    if len(value) > MAX_WORKOUT_SECTIONS:
        raise ApiError(
            HTTPStatus.BAD_REQUEST,
            f"A WOD can have at most {MAX_WORKOUT_SECTIONS} sections.",
        )
    sections: list[dict[str, Any]] = []
    for index, raw in enumerate(value):
        if not isinstance(raw, dict):
            raise ApiError(
                HTTPStatus.BAD_REQUEST,
                f"Section {index + 1} must be an object.",
            )
        title = str(raw.get("title") or "").strip()
        if len(title) > 80:
            raise ApiError(
                HTTPStatus.BAD_REQUEST,
                f"Section {index + 1} title must be 80 characters or fewer.",
            )
        description = str(raw.get("description") or "").strip()
        if not description:
            raise ApiError(
                HTTPStatus.BAD_REQUEST,
                f"Section {index + 1} needs a description.",
            )
        if len(description) > 4000:
            raise ApiError(
                HTTPStatus.BAD_REQUEST,
                f"Section {index + 1} description must be 4000 characters or fewer.",
            )
        score_type = require_workout_section_score_type(raw.get("score_type"))
        section_id = raw.get("id")
        sections.append(
            {
                "id": section_id if isinstance(section_id, int) and not isinstance(section_id, bool) else None,
                "title": title,
                "description": description,
                "score_type": score_type,
                **_require_block_fields(raw, index),
            }
        )
    return sections


MAX_BLOCK_SETS = 30


def _require_block_fields(raw: dict[str, Any], index: int) -> dict[str, Any]:
    """Optional structured-block fields of a section; older clients omit
    them and get a plain 'workout' block."""
    label = f"Section {index + 1}"
    kind = str(raw.get("kind") or "workout")
    if kind not in {"workout", "exercise"}:
        raise ApiError(HTTPStatus.BAD_REQUEST, f"{label} kind must be 'workout' or 'exercise'.")
    set_unit = str(raw.get("set_unit") or "percent")
    if set_unit not in {"percent", "rpe"}:
        raise ApiError(HTTPStatus.BAD_REQUEST, f"{label} set unit must be 'percent' or 'rpe'.")
    raw_sets = raw.get("sets") or []
    if not isinstance(raw_sets, list) or len(raw_sets) > MAX_BLOCK_SETS:
        raise ApiError(HTTPStatus.BAD_REQUEST, f"{label} can have at most {MAX_BLOCK_SETS} sets.")
    sets = []
    for raw_set in raw_sets:
        try:
            reps = int(raw_set["reps"])
            value = raw_set.get("value")
            value = None if value is None else float(value)
        except (TypeError, ValueError, KeyError):
            raise ApiError(HTTPStatus.BAD_REQUEST, f"{label} has an invalid set.") from None
        if not 1 <= reps <= 999 or (value is not None and not 0 <= value <= 1000):
            raise ApiError(HTTPStatus.BAD_REQUEST, f"{label} has an invalid set.")
        sets.append({"reps": reps, "value": value})
    fields = {
        "kind": kind,
        "exercise_name": str(raw.get("exercise_name") or "").strip(),
        "set_unit": set_unit,
        "sets": sets,
        "coach_notes": str(raw.get("coach_notes") or "").strip(),
        "member_notes": str(raw.get("member_notes") or "").strip(),
        # Named workout (Fran, Murph, a box test) so repeats can be found.
        "workout_name": " ".join(str(raw.get("workout_name") or "").split()),
    }
    if len(fields["workout_name"]) > 80:
        raise ApiError(HTTPStatus.BAD_REQUEST, f"{label} workout name must be 80 characters or fewer.")
    for key in ("exercise_name", "coach_notes", "member_notes"):
        if len(fields[key]) > 2000:
            raise ApiError(HTTPStatus.BAD_REQUEST, f"{label} {key.replace('_', ' ')} is too long.")
    return fields
