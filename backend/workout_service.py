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
        "title": row["title"],
        "description": row["description"],
        "score_type": row["score_type"],
        "kind": row["kind"],
        "exercise_name": row["exercise_name"],
        "set_unit": row["set_unit"],
        "sets": sets,
        "coach_notes": row["coach_notes"],
        "member_notes": row["member_notes"],
    }


def fetch_workout_sections(
    connection: ManagedConnection, daily_workout_id: int
) -> list[dict[str, Any]]:
    rows = connection.execute(
        """
        select title, description, score_type, kind, exercise_name, set_unit,
               sets_json, coach_notes, member_notes
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
    """Replaces all sections for a WOD. ``sections`` is already validated."""
    connection.execute(
        "delete from daily_workout_sections where daily_workout_id = ?",
        (daily_workout_id,),
    )
    for index, section in enumerate(sections):
        connection.execute(
            """
            insert into daily_workout_sections (
              daily_workout_id, position, title, description, score_type,
              kind, exercise_name, set_unit, sets_json, coach_notes, member_notes
            )
            values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                daily_workout_id,
                index,
                section["title"],
                section["description"],
                section["score_type"],
                section.get("kind", "workout"),
                section.get("exercise_name", ""),
                section.get("set_unit", "percent"),
                json.dumps(section.get("sets", [])),
                section.get("coach_notes", ""),
                section.get("member_notes", ""),
            ),
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


