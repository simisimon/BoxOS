from __future__ import annotations

import json
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


def daily_workout_payload(connection: ManagedConnection, row: Row, *, current_user_id: int, can_edit: bool) -> dict[str, Any]:
    return {
        "id": row["id"],
        "gym_id": row["gym_id"],
        "scheduled_date": row["scheduled_date"],
        "title": row["title"],
        # Coach notes are for coaches; members only get the member notes.
        "sections": [
            section if can_edit else {**section, "coach_notes": ""}
            for section in fetch_workout_sections(connection, row["id"])
        ],
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


