"""WOD results: an athlete's score on one scored block of a published WOD.

One result per athlete per block. The block's identity (movement, named
workout, title, score type) is copied into the result, so history and PRs
still work after the coach edits or removes the block.
"""

from __future__ import annotations

import csv
import io
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
    "division, time_capped, sets_json, notes, photo_url, created_at, updated_at"
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
        "photo_url": row["photo_url"] or "",
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
        "delete from workout_results where user_id = ? and gym_id = ? and section_id = ? returning id, photo_url",
        (user_id, gym_id, section_id),
    ).fetchone()
    if deleted is None:
        raise ApiError(HTTPStatus.NOT_FOUND, "Result not found.")
    if deleted["photo_url"]:
        from backend import result_social_service

        result_social_service._remove_photo_file(deleted["photo_url"])


def my_results_by_section(
    connection: ManagedConnection, *, user_id: int, daily_workout_id: int
) -> dict[int, dict[str, Any]]:
    rows = connection.execute(
        f"select {RESULT_COLUMNS} from workout_results where user_id = ? and daily_workout_id = ?",
        (user_id, daily_workout_id),
    ).fetchall()
    return {int(row["section_id"]): result_payload(row) for row in rows if row["section_id"] is not None}


RESULTS_VISIBILITY = ("gym", "private")

# Leaderboard rows a viewer may see: coaches see everyone, athletes see
# results of people who share them with the gym, plus their own.
_VISIBLE_TO_VIEWER = "(? or u.results_visibility <> 'private' or r.user_id = ?)"


def result_counts_by_section(
    connection: ManagedConnection, *, daily_workout_id: int, viewer_id: int, staff: bool
) -> dict[int, int]:
    rows = connection.execute(
        f"""
        select r.section_id, count(*) as count
        from workout_results r
        join users u on u.id = r.user_id
        where r.daily_workout_id = ? and r.section_id is not null and u.deleted_at is null
          and {_VISIBLE_TO_VIEWER}
        group by r.section_id
        """,
        (daily_workout_id, staff, viewer_id),
    ).fetchall()
    return {int(row["section_id"]): int(row["count"]) for row in rows}


# --- PRs ------------------------------------------------------------------
#
# A result is a PR when it beats every earlier result (by WOD date) of the
# same athlete with the same movement or named workout, the same score type
# and the same division. Exercise blocks compare per rep count: a set of N
# reps is a PR against earlier sets of N or more reps. The first result is
# the baseline, never a PR. Worked out on read, because athletes can log past
# WODs and that changes which result came first.


def identity(row: Row | dict[str, Any]) -> tuple[str, Any] | None:
    """What makes two results "the same exercise or workout"."""
    if row["movement_id"] is not None:
        return ("movement", int(row["movement_id"]))
    name = " ".join(str(row["workout_name"] or "").lower().split())
    if name:
        return ("workout", name)
    return None


def sort_key(row: Row | dict[str, Any]) -> tuple[int, float]:
    """Lower is better: finished times by seconds, then capped times by more
    reps; every other score type by the higher value."""
    if row["score_type"] == "time":
        if row["time_capped"]:
            return (1, -float(row["score_value"]))
        return (0, float(row["score_value"]))
    return (0, -float(row["score_value"]))


def _sets(row: Row | dict[str, Any]) -> list[dict[str, Any]]:
    try:
        return [s for s in json.loads(row["sets_json"] or "[]") if s.get("kg") is not None]
    except (TypeError, ValueError):
        return []


def compute_prs(rows: list[Row]) -> set[int]:
    """Ids of the PR results among one athlete's results."""
    ordered = sorted(rows, key=lambda r: (r["performed_on"], r["id"]))
    best: dict[tuple, tuple[int, float]] = {}
    lifted: dict[tuple, list[tuple[int, float]]] = {}
    prs: set[int] = set()
    for row in ordered:
        key = identity(row)
        if key is None:
            continue
        sets = _sets(row)
        if sets:
            group = (key, row["division"])
            earlier = lifted.setdefault(group, [])
            if earlier and any(
                s["kg"] > max((kg for reps, kg in earlier if reps >= s["reps"]), default=0)
                and any(reps >= s["reps"] for reps, _ in earlier)
                for s in sets
            ):
                prs.add(int(row["id"]))
            earlier.extend((int(s["reps"]), float(s["kg"])) for s in sets)
            continue
        group = (key, row["score_type"], row["division"])
        score = sort_key(row)
        if group in best and score < best[group]:
            prs.add(int(row["id"]))
        if group not in best or score < best[group]:
            best[group] = score
    return prs


def _identity_filter(key: tuple[str, Any]) -> tuple[str, tuple[Any, ...]]:
    if key[0] == "movement":
        return "movement_id = ?", (key[1],)
    return "movement_id is null and lower(workout_name) = ?", (key[1],)


def results_with_identity(
    connection: ManagedConnection, *, user_id: int, key: tuple[str, Any]
) -> list[Row]:
    clause, params = _identity_filter(key)
    return connection.execute(
        f"select {RESULT_COLUMNS} from workout_results where user_id = ? and {clause}",
        (user_id, *params),
    ).fetchall()


def pr_flags(connection: ManagedConnection, rows: list[Row]) -> set[int]:
    """PR result ids among ``rows``, judged against each athlete's history."""
    prs: set[int] = set()
    seen: set[tuple[int, tuple]] = set()
    for row in rows:
        key = identity(row)
        if key is None or (row["user_id"], key) in seen:
            continue
        seen.add((row["user_id"], key))
        prs |= compute_prs(results_with_identity(connection, user_id=row["user_id"], key=key))
    return prs


def is_pr(connection: ManagedConnection, result: dict[str, Any], user_id: int) -> bool:
    row = {**result, "user_id": user_id}
    key = identity(row)
    if key is None:
        return False
    history = results_with_identity(connection, user_id=user_id, key=key)
    return int(result["id"]) in compute_prs(history)


# --- Leaderboard ------------------------------------------------------------


def _display_name(row: Row) -> str:
    name = (row["display_name"] or "").strip() or (row["nickname"] or "").strip()
    return name or str(row["email"]).split("@")[0]


def leaderboard(
    connection: ManagedConnection,
    *,
    daily_workout_id: int,
    viewer_id: int,
    staff: bool,
) -> list[dict[str, Any]]:
    """Ranked results per scored block: Rx before Scaled, then by score.
    Equal scores share a rank. Coaches see everyone and the notes; athletes
    don't see results their owners keep private."""
    rows = connection.execute(
        f"""
        select {", ".join("r." + c.strip() for c in RESULT_COLUMNS.split(","))},
               u.display_name, u.nickname, u.email, u.profile_image_url
        from workout_results r
        join users u on u.id = r.user_id
        where r.daily_workout_id = ? and r.section_id is not null and u.deleted_at is null
          and {_VISIBLE_TO_VIEWER}
        """,
        (daily_workout_id, staff, viewer_id),
    ).fetchall()
    prs = pr_flags(connection, rows)
    from backend import result_social_service

    social = result_social_service.social_counts(
        connection, result_ids=[int(r["id"]) for r in rows], viewer_id=viewer_id
    )
    by_section: dict[int, list[Row]] = {}
    for row in rows:
        by_section.setdefault(int(row["section_id"]), []).append(row)
    sections = []
    for section_id, entries in by_section.items():
        entries.sort(key=lambda r: (r["division"] != "rx", sort_key(r), _display_name(r).lower()))
        ranked = []
        previous = None
        for index, row in enumerate(entries):
            score = (row["division"], sort_key(row))
            rank = ranked[-1]["rank"] if score == previous else index + 1
            previous = score
            ranked.append(
                {
                    "rank": rank,
                    "result_id": row["id"],
                    "user_id": row["user_id"],
                    "photo_url": row["photo_url"] or "",
                    **social[int(row["id"])],
                    "name": _display_name(row),
                    "avatar_url": row["profile_image_url"] or "",
                    "score_label": row["score_label"],
                    "division": row["division"],
                    "time_capped": bool(row["time_capped"]),
                    "is_pr": int(row["id"]) in prs,
                    "is_me": row["user_id"] == viewer_id,
                    "notes": row["notes"] if staff or row["user_id"] == viewer_id else "",
                }
            )
        sections.append({"section_id": section_id, "entries": ranked})
    return sections


# --- History ------------------------------------------------------------------


def history_for_section(
    connection: ManagedConnection, *, user_id: int, gym_id: int, section_id: int, limit: int = 20
) -> dict[str, Any]:
    """The athlete's results for the same movement or named workout as this
    block, newest first, with PRs marked and the best result per division."""
    section = connection.execute(
        """
        select s.id, s.movement_id, s.workout_name, s.score_type
        from daily_workout_sections s
        join daily_workouts w on w.id = s.daily_workout_id
        where s.id = ? and w.gym_id = ?
        """,
        (section_id, gym_id),
    ).fetchone()
    if section is None:
        raise ApiError(HTTPStatus.NOT_FOUND, "Workout block not found.")
    key = identity(section)
    if key is None:
        rows = connection.execute(
            f"select {RESULT_COLUMNS} from workout_results where user_id = ? and section_id = ?",
            (user_id, section_id),
        ).fetchall()
    else:
        rows = results_with_identity(connection, user_id=user_id, key=key)
    return _history_payload(rows, limit=limit)


def _history_payload(rows: list[Row], *, limit: int) -> dict[str, Any]:
    prs = compute_prs(rows)
    ordered = sorted(rows, key=lambda r: (r["performed_on"], r["id"]), reverse=True)
    best: dict[str, Row] = {}
    for row in ordered:
        if _sets(row):
            continue
        current = best.get(row["division"])
        if current is None or (current["score_type"] == row["score_type"] and sort_key(row) < sort_key(current)):
            best[row["division"]] = row
    return {
        "results": [{**result_payload(r), "is_pr": int(r["id"]) in prs} for r in ordered[:limit]],
        "best": {division: result_payload(row)["id"] for division, row in best.items()},
        "best_sets": best_sets(rows),
    }


def best_sets(rows: list[Row]) -> list[dict[str, Any]]:
    """Heaviest kg per rep count across exercise results (Rx and Scaled),
    for the percentage chart."""
    best: dict[int, float] = {}
    for row in rows:
        for s in _sets(row):
            reps = int(s["reps"])
            best[reps] = max(best.get(reps, 0.0), float(s["kg"]))
    return [{"reps": reps, "kg": kg} for reps, kg in sorted(best.items())]


def my_results(
    connection: ManagedConnection,
    *,
    user_id: int,
    movement_id: int | None,
    workout_name: str,
    limit: int,
    gym_id: int | None = None,
) -> dict[str, Any]:
    """All the athlete's results (any gym, or only ``gym_id``'s), newest
    first, with PR marks, optionally narrowed to one movement or named
    workout; plus the filters the athlete has results for."""
    if gym_id is None:
        rows = connection.execute(
            f"select {RESULT_COLUMNS} from workout_results where user_id = ?",
            (user_id,),
        ).fetchall()
    else:
        rows = connection.execute(
            f"select {RESULT_COLUMNS} from workout_results where user_id = ? and gym_id = ?",
            (user_id, gym_id),
        ).fetchall()
    prs: set[int] = set()
    groups: dict[tuple, list[Row]] = {}
    for row in rows:
        key = identity(row)
        if key is not None:
            groups.setdefault(key, []).append(row)
    for group in groups.values():
        prs |= compute_prs(group)
    wanted: tuple[str, Any] | None = None
    if movement_id is not None:
        wanted = ("movement", movement_id)
    elif workout_name.strip():
        wanted = ("workout", " ".join(workout_name.lower().split()))
    shown = groups.get(wanted, []) if wanted else rows
    shown = sorted(shown, key=lambda r: (r["performed_on"], r["id"]), reverse=True)
    movement_names = {
        int(row["id"]): row["name"]
        for row in connection.execute(
            "select id, name from movements where id in (select distinct movement_id from workout_results where user_id = ?)",
            (user_id,),
        ).fetchall()
    }
    filters = []
    for key, group in groups.items():
        if key[0] == "movement":
            label = movement_names.get(key[1], "Movement")
            filters.append({"movement_id": key[1], "workout_name": "", "label": label, "count": len(group)})
        else:
            label = next((r["workout_name"] for r in group if r["workout_name"]), key[1])
            filters.append({"movement_id": None, "workout_name": label, "label": label, "count": len(group)})
    filters.sort(key=lambda f: f["label"].lower())
    payload = {
        "results": [
            {**result_payload(r), "is_pr": int(r["id"]) in prs} for r in shown[: max(1, min(limit, 500))]
        ],
        "filters": filters,
    }
    if wanted:
        payload["best_sets"] = best_sets(shown)
    return payload


# --- Export -------------------------------------------------------------------

CSV_COLUMNS = [
    "date", "gym", "block", "movement", "workout", "score_type",
    "result", "division", "time_capped", "sets", "pr", "notes",
]


def _csv_cell(value: Any) -> str:
    """Text a spreadsheet won't run as a formula."""
    text = str(value)
    return "'" + text if text[:1] in ("=", "+", "-", "@") else text


def my_results_csv(connection: ManagedConnection, *, user_id: int) -> str:
    """Every result of the athlete, oldest first, as CSV for a spreadsheet."""
    rows = connection.execute(
        f"""
        select {", ".join("r." + c.strip() for c in RESULT_COLUMNS.split(","))},
               coalesce(g.name, '') as gym_name, coalesce(m.name, '') as movement_name
        from workout_results r
        left join gyms g on g.id = r.gym_id
        left join movements m on m.id = r.movement_id
        where r.user_id = ?
        order by r.performed_on, r.id
        """,
        (user_id,),
    ).fetchall()
    groups: dict[tuple, list[Row]] = {}
    for row in rows:
        key = identity(row)
        if key is not None:
            groups.setdefault(key, []).append(row)
    prs: set[int] = set()
    for group in groups.values():
        prs |= compute_prs(group)
    buffer = io.StringIO()
    writer = csv.writer(buffer)
    writer.writerow(CSV_COLUMNS)
    for row in rows:
        sets = "; ".join(f"{int(s['reps'])} x {_number(float(s['kg']))} kg" for s in _sets(row))
        writer.writerow(
            [
                _csv_cell(v)
                for v in (
                    row["performed_on"],
                    row["gym_name"],
                    row["section_title"],
                    row["movement_name"],
                    row["workout_name"],
                    row["score_type"],
                    row["score_label"],
                    "Rx" if row["division"] == "rx" else "Scaled",
                    "yes" if row["time_capped"] else "",
                    sets,
                    "yes" if int(row["id"]) in prs else "",
                    row["notes"],
                )
            ]
        )
    return buffer.getvalue()
