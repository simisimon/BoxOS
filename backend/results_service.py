"""WOD results: an athlete's score on one scored block of a published WOD.

One result per athlete per block. The block's identity (movement, named
workout, title, score type) is copied into the result, so history and PRs
still work after the coach edits or removes the block.
"""

from __future__ import annotations

import json
from datetime import datetime
from http import HTTPStatus
from typing import Any, TYPE_CHECKING

from backend import schedule_service, security
from backend.validation import ApiError

if TYPE_CHECKING:
    from backend.db import ManagedConnection, Row

DIVISIONS = {"rx", "scaled"}
MAX_NOTES = 500
MAX_RESULT_SETS = 30

RESULT_COLUMNS = (
    "id, user_id, gym_id, section_id, daily_workout_id, performed_on, class_schedule_id, "
    "movement_id, workout_name, section_title, score_type, score_value, score_label, "
    "division, time_capped, sets_json, notes, created_at, updated_at"
)


def _number(value: float) -> str:
    return f"{value:g}"


def _whole(raw: Any, label: str, *, maximum: int = 100_000) -> int:
    try:
        number = int(str(raw).strip())
    except (TypeError, ValueError):
        raise ApiError(HTTPStatus.BAD_REQUEST, f"{label} must be a whole number.") from None
    if not 0 < number <= maximum:
        raise ApiError(HTTPStatus.BAD_REQUEST, f"{label} must be between 1 and {maximum}.")
    return number


def _decimal(raw: Any, label: str, *, maximum: float) -> float:
    try:
        number = float(str(raw).strip().replace(",", "."))
    except (TypeError, ValueError):
        raise ApiError(HTTPStatus.BAD_REQUEST, f"{label} must be a number.") from None
    if not 0 < number <= maximum:
        raise ApiError(HTTPStatus.BAD_REQUEST, f"{label} must be between 0 and {_number(maximum)}.")
    return round(number, 2)


def parse_time(raw: Any) -> int:
    """``mm:ss`` or ``h:mm:ss`` to seconds."""
    parts = str(raw or "").strip().replace(".", ":").split(":")
    try:
        numbers = [int(part) for part in parts]
    except ValueError:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Time must be mm:ss or h:mm:ss.") from None
    if len(numbers) == 2:
        hours, (minutes, seconds) = 0, numbers
    elif len(numbers) == 3:
        hours, minutes, seconds = numbers
        if minutes >= 60:
            raise ApiError(HTTPStatus.BAD_REQUEST, "Minutes must be below 60.")
    else:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Time must be mm:ss or h:mm:ss.")
    if min(numbers) < 0 or seconds >= 60:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Time must be mm:ss or h:mm:ss.")
    total = hours * 3600 + minutes * 60 + seconds
    if not 0 < total <= 24 * 3600:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Time must be between 0:01 and 24:00:00.")
    return total


def format_time(seconds: int) -> str:
    hours, rest = divmod(int(seconds), 3600)
    minutes, secs = divmod(rest, 60)
    return f"{hours}:{minutes:02d}:{secs:02d}" if hours else f"{minutes}:{secs:02d}"


def parse_score(
    *,
    score_type: str,
    kind: str,
    score: Any,
    time_capped: bool,
    sets: Any,
) -> tuple[float, str, list[dict[str, Any]]]:
    """Validates a result for a block and returns (sortable value, label,
    sets). Sortable values: seconds (or reps when time-capped),
    rounds*1000+reps, reps, kg, calories, metres."""
    if score_type == "none":
        raise ApiError(HTTPStatus.BAD_REQUEST, "This block takes no result.")
    if kind == "exercise":
        if not isinstance(sets, list) or not sets:
            raise ApiError(HTTPStatus.BAD_REQUEST, "Enter the weight of at least one set.")
        if len(sets) > MAX_RESULT_SETS:
            raise ApiError(HTTPStatus.BAD_REQUEST, f"At most {MAX_RESULT_SETS} sets.")
        clean = []
        for index, raw in enumerate(sets):
            if not isinstance(raw, dict):
                raise ApiError(HTTPStatus.BAD_REQUEST, f"Set {index + 1} is invalid.")
            reps = _whole(raw.get("reps"), f"Set {index + 1} reps", maximum=999)
            kg_raw = raw.get("kg")
            kg = None if kg_raw in (None, "") else _decimal(kg_raw, f"Set {index + 1} weight", maximum=1000)
            clean.append({"reps": reps, "kg": kg})
        loads = [s["kg"] for s in clean if s["kg"] is not None]
        if not loads:
            raise ApiError(HTTPStatus.BAD_REQUEST, "Enter the weight of at least one set.")
        top = max(loads)
        return top, f"{_number(top)} kg", clean
    if score_type == "time":
        if time_capped:
            reps = _whole(score, "Reps at the cap")
            return float(reps), f"CAP · {reps} reps", []
        seconds = parse_time(score)
        return float(seconds), format_time(seconds), []
    if score_type == "rounds_reps":
        parts = [p for p in str(score or "").replace("+", " ").split() if p]
        if len(parts) not in (1, 2):
            raise ApiError(HTTPStatus.BAD_REQUEST, "Rounds + reps must look like 7+14.")
        try:
            rounds = int(parts[0])
            reps = int(parts[1]) if len(parts) == 2 else 0
        except ValueError:
            raise ApiError(HTTPStatus.BAD_REQUEST, "Rounds + reps must be whole numbers.") from None
        if rounds < 0 or not 0 <= reps < 1000 or rounds + reps == 0 or rounds > 999:
            raise ApiError(HTTPStatus.BAD_REQUEST, "Rounds + reps must look like 7+14.")
        return float(rounds * 1000 + reps), f"{rounds}+{reps}", []
    if score_type == "reps":
        reps = _whole(score, "Reps")
        return float(reps), f"{reps} reps", []
    if score_type == "weight":
        kg = _decimal(score, "Weight", maximum=1000)
        return kg, f"{_number(kg)} kg", []
    if score_type == "calories":
        calories = _whole(score, "Calories", maximum=10_000)
        return float(calories), f"{calories} cal", []
    if score_type == "distance":
        metres = _decimal(score, "Distance", maximum=100_000)
        return metres, f"{_number(metres)} m", []
    raise ApiError(HTTPStatus.BAD_REQUEST, "This block has an unknown score type.")


def require_division(value: Any) -> str:
    division = str(value or "rx").strip().lower()
    if division not in DIVISIONS:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Division must be rx or scaled.")
    return division


def require_notes(value: Any) -> str:
    notes = str(value or "").strip()
    if len(notes) > MAX_NOTES:
        raise ApiError(HTTPStatus.BAD_REQUEST, f"Notes must be {MAX_NOTES} characters or fewer.")
    return notes


def result_payload(row: Row) -> dict[str, Any]:
    try:
        sets = json.loads(row["sets_json"] or "[]")
    except (TypeError, ValueError):
        sets = []
    return {
        "id": row["id"],
        "section_id": row["section_id"],
        "daily_workout_id": row["daily_workout_id"],
        "performed_on": row["performed_on"],
        "section_title": row["section_title"],
        "workout_name": row["workout_name"],
        "movement_id": row["movement_id"],
        "score_type": row["score_type"],
        "score_value": row["score_value"],
        "score_label": row["score_label"],
        "division": row["division"],
        "time_capped": bool(row["time_capped"]),
        "sets": sets,
        "notes": row["notes"],
        "updated_at": row["updated_at"],
    }


def gym_today(connection: ManagedConnection, gym_id: int) -> str:
    row = connection.execute("select timezone from gyms where id = ?", (gym_id,)).fetchone()
    zone = schedule_service.timezone_for_name(row["timezone"]) if row and row["timezone"] else None
    now = datetime.now(zone) if zone is not None else security.now_utc()
    return now.date().isoformat()


def loggable_section(connection: ManagedConnection, *, gym_id: int, section_id: int) -> Row:
    """The block with its WOD, if the athlete may log it: the gym's own,
    published, and dated today or earlier."""
    row = connection.execute(
        """
        select s.id, s.title, s.score_type, s.kind, s.movement_id, s.workout_name,
               w.id as daily_workout_id, w.scheduled_date, w.status
        from daily_workout_sections s
        join daily_workouts w on w.id = s.daily_workout_id
        where s.id = ? and w.gym_id = ?
        """,
        (section_id, gym_id),
    ).fetchone()
    if row is None or row["status"] != "published":
        raise ApiError(HTTPStatus.NOT_FOUND, "Workout block not found.")
    if row["scheduled_date"] > gym_today(connection, gym_id):
        raise ApiError(HTTPStatus.BAD_REQUEST, "Results can be logged from the day of the workout.")
    if row["score_type"] == "none":
        raise ApiError(HTTPStatus.BAD_REQUEST, "This block takes no result.")
    return row


def booked_class_id(connection: ManagedConnection, *, user_id: int, gym_id: int, day: str) -> int | None:
    """The athlete's class on that day, if they booked one (first by time)."""
    row = connection.execute(
        """
        select c.id
        from class_bookings b
        join class_schedules c on c.id = b.class_schedule_id
        where b.user_id = ? and c.gym_id = ? and c.start_time like ?
          and b.attendance_status <> 'no_show'
        order by c.start_time
        limit 1
        """,
        (user_id, gym_id, f"{day}%"),
    ).fetchone()
    return int(row["id"]) if row else None


def save_result(
    connection: ManagedConnection,
    *,
    user_id: int,
    gym_id: int,
    section_id: int,
    body: dict[str, Any],
) -> dict[str, Any]:
    section = loggable_section(connection, gym_id=gym_id, section_id=section_id)
    time_capped = bool(body.get("time_capped")) and section["score_type"] == "time" and section["kind"] != "exercise"
    value, label, sets = parse_score(
        score_type=section["score_type"],
        kind=section["kind"],
        score=body.get("score"),
        time_capped=time_capped,
        sets=body.get("sets"),
    )
    division = require_division(body.get("division"))
    notes = require_notes(body.get("notes"))
    timestamp = security.isoformat(security.now_utc())
    class_id = booked_class_id(connection, user_id=user_id, gym_id=gym_id, day=section["scheduled_date"])
    row = connection.execute(
        f"""
        insert into workout_results (
          user_id, gym_id, section_id, daily_workout_id, performed_on, class_schedule_id,
          movement_id, workout_name, section_title, score_type, score_value, score_label,
          division, time_capped, sets_json, notes, created_at, updated_at
        )
        values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        on conflict (user_id, section_id) do update set
          class_schedule_id = excluded.class_schedule_id,
          movement_id = excluded.movement_id,
          workout_name = excluded.workout_name,
          section_title = excluded.section_title,
          score_type = excluded.score_type,
          score_value = excluded.score_value,
          score_label = excluded.score_label,
          division = excluded.division,
          time_capped = excluded.time_capped,
          sets_json = excluded.sets_json,
          notes = excluded.notes,
          updated_at = excluded.updated_at
        returning {RESULT_COLUMNS}
        """,
        (
            user_id,
            gym_id,
            section_id,
            section["daily_workout_id"],
            section["scheduled_date"],
            class_id,
            section["movement_id"],
            section["workout_name"],
            section["title"],
            section["score_type"],
            value,
            label,
            division,
            1 if time_capped else 0,
            json.dumps(sets),
            notes,
            timestamp,
            timestamp,
        ),
    ).fetchone()
    return result_payload(row)


def delete_result(connection: ManagedConnection, *, user_id: int, gym_id: int, section_id: int) -> None:
    deleted = connection.execute(
        "delete from workout_results where user_id = ? and gym_id = ? and section_id = ? returning id",
        (user_id, gym_id, section_id),
    ).fetchone()
    if deleted is None:
        raise ApiError(HTTPStatus.NOT_FOUND, "Result not found.")


def my_results_by_section(
    connection: ManagedConnection, *, user_id: int, daily_workout_id: int
) -> dict[int, dict[str, Any]]:
    rows = connection.execute(
        f"select {RESULT_COLUMNS} from workout_results where user_id = ? and daily_workout_id = ?",
        (user_id, daily_workout_id),
    ).fetchall()
    return {int(row["section_id"]): result_payload(row) for row in rows if row["section_id"] is not None}


def result_counts_by_section(connection: ManagedConnection, *, daily_workout_id: int) -> dict[int, int]:
    rows = connection.execute(
        """
        select section_id, count(*) as count from workout_results
        where daily_workout_id = ? and section_id is not null
        group by section_id
        """,
        (daily_workout_id,),
    ).fetchall()
    return {int(row["section_id"]): int(row["count"]) for row in rows}
