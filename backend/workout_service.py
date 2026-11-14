from __future__ import annotations

import json
from http import HTTPStatus
from typing import Any, TYPE_CHECKING

if TYPE_CHECKING:
    from backend.db import ManagedConnection, Row


def workout_section_payload(row: Row) -> dict[str, Any]:
    try:
        sets = json.loads(row["sets_json"] or "[]")
    except (TypeError, ValueError):
        sets = []
    return {
        "id": row["id"],
        "title": row["title"],
        "description": row["description"],
        "score_type": row["score_type"],
        "kind": row["kind"],
        "exercise_name": row["exercise_name"],
        "set_unit": row["set_unit"],
        "sets": sets,
        "coach_notes": row["coach_notes"],
        "member_notes": row["member_notes"],
        "movement_id": row["movement_id"],
        "workout_name": row["workout_name"],
    }


def fetch_workout_sections(
    connection: ManagedConnection, daily_workout_id: int
) -> list[dict[str, Any]]:
    rows = connection.execute(
        """
        select id, title, description, score_type, kind, exercise_name, set_unit,
               sets_json, coach_notes, member_notes, movement_id, workout_name
        from daily_workout_sections
        where daily_workout_id = ?
        order by position asc, id asc
        """,
        (daily_workout_id,),
    ).fetchall()
    return [workout_section_payload(row) for row in rows]


def _refuse_changes_to_logged_blocks(
    connection: ManagedConnection,
    sections: list[dict[str, Any]],
    removed: set[int],
    kept: set[int],
) -> None:
    """Athletes' results hang off a block: it cannot be removed, or switch
    between workout and exercise or to another score type, once logged."""
    from backend.validation import ApiError

    ids = removed | kept
    if not ids:
        return
    placeholders = ", ".join("?" for _ in ids)
    rows = connection.execute(
        f"""
        select s.id, s.title, s.kind, s.score_type, count(r.id) as results
        from daily_workout_sections s
        join workout_results r on r.section_id = s.id
        where s.id in ({placeholders})
        group by s.id, s.title, s.kind, s.score_type
        """,
        tuple(ids),
    ).fetchall()
    incoming = {s.get("id"): s for s in sections if s.get("id") in kept}
    for row in rows:
        name = row["title"] or "A block"
        if row["id"] in removed:
            raise ApiError(
                HTTPStatus.CONFLICT,
                f"{name} has {row['results']} logged results and cannot be removed.",
            )
        new = incoming[row["id"]]
        if new.get("kind", "workout") != row["kind"] or new["score_type"] != row["score_type"]:
            raise ApiError(
                HTTPStatus.CONFLICT,
                f"{name} has {row['results']} logged results; its type and score cannot change.",
            )


def replace_workout_sections(
    connection: ManagedConnection,
    *,
    daily_workout_id: int,
    sections: list[dict[str, Any]],
) -> None:
    """Saves a WOD's blocks in the given order. ``sections`` is already
    validated. A block that carries the ``id`` of one of this WOD's blocks is
    updated in place, so anything attached to it (results) survives the edit;
    blocks without a known id are inserted and blocks left out are deleted.
    Ids from another WOD (duplicate, copy) are treated as new blocks."""
    from backend import movement_service

    gym_id = connection.execute(
        "select gym_id from daily_workouts where id = ?", (daily_workout_id,)
    ).fetchone()["gym_id"]
    existing_ids = {
        int(row["id"])
        for row in connection.execute(
            "select id from daily_workout_sections where daily_workout_id = ?",
            (daily_workout_id,),
        ).fetchall()
    }
    kept: set[int] = set()
    for section in sections:
        section_id = section.get("id")
        if isinstance(section_id, int) and section_id in existing_ids and section_id not in kept:
            kept.add(section_id)
    _refuse_changes_to_logged_blocks(connection, sections, existing_ids - kept, kept)
    for stale_id in existing_ids - kept:
        connection.execute("delete from daily_workout_sections where id = ?", (stale_id,))
    # Move kept rows out of the way of unique(daily_workout_id, position).
    connection.execute(
        "update daily_workout_sections set position = -1 - position where daily_workout_id = ?",
        (daily_workout_id,),
    )
    claimed: set[int] = set()
    for index, section in enumerate(sections):
        kind = section.get("kind", "workout")
        movement_id = (
            movement_service.resolve_movement_id(
                connection, gym_id=gym_id, name=section.get("exercise_name", "")
            )
            if kind == "exercise"
            else None
        )
        values = (
            index,
            section["title"],
            section["description"],
            section["score_type"],
            kind,
            section.get("exercise_name", ""),
            section.get("set_unit", "percent"),
            json.dumps(section.get("sets", [])),
            section.get("coach_notes", ""),
            section.get("member_notes", ""),
            movement_id,
            section.get("workout_name", "") if kind == "workout" else "",
        )
        section_id = section.get("id")
        if section_id in kept and section_id not in claimed:
            claimed.add(section_id)
            connection.execute(
                """
                update daily_workout_sections set
                  position = ?, title = ?, description = ?, score_type = ?,
                  kind = ?, exercise_name = ?, set_unit = ?, sets_json = ?,
                  coach_notes = ?, member_notes = ?, movement_id = ?, workout_name = ?
                where id = ?
                """,
                (*values, section_id),
            )
        else:
            connection.execute(
                """
                insert into daily_workout_sections (
                  position, title, description, score_type,
                  kind, exercise_name, set_unit, sets_json,
                  coach_notes, member_notes, movement_id, workout_name,
                  daily_workout_id
                )
                values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (*values, daily_workout_id),
            )


def _sections_with_results(
    connection: ManagedConnection, daily_workout_id: int, user_id: int, can_edit: bool
) -> list[dict[str, Any]]:
    from backend import results_service

    mine = results_service.my_results_by_section(
        connection, user_id=user_id, daily_workout_id=daily_workout_id
    )
    counts = results_service.result_counts_by_section(
        connection, daily_workout_id=daily_workout_id, viewer_id=user_id, staff=can_edit
    )
    sections = []
    for section in fetch_workout_sections(connection, daily_workout_id):
        # Coach notes are for coaches; members only get the member notes.
        if not can_edit:
            section = {**section, "coach_notes": ""}
        section["my_result"] = mine.get(section["id"])
        section["result_count"] = counts.get(section["id"], 0)
        sections.append(section)
    return sections


def daily_workout_payload(connection: ManagedConnection, row: Row, *, current_user_id: int, can_edit: bool) -> dict[str, Any]:
    return {
        "id": row["id"],
        "gym_id": row["gym_id"],
        "scheduled_date": row["scheduled_date"],
        "title": row["title"],
        "sections": _sections_with_results(connection, row["id"], current_user_id, can_edit),
        "status": row["status"],
        "published_at": row["published_at"],
        "can_edit": can_edit,
    }


DAILY_WORKOUT_COLUMNS = (
    "id, gym_id, scheduled_date, title, "
    "status, published_at, published_by_user_id, created_by_user_id, updated_by_user_id, "
    "created_at, updated_at"
)


def exercise_payload(row: Row) -> dict[str, Any]:
    def _list(value: Any) -> list[Any]:
        try:
            return json.loads(value or "[]")
        except (TypeError, ValueError):
            return []
    return {
        "id": row["id"],
        "name": row["name"],
        "category": row["category"],
        "equipment": row["equipment"],
        "level": row["level"],
        "primary_muscles": _list(row["primary_muscles"]),
        "secondary_muscles": _list(row["secondary_muscles"]),
    }


