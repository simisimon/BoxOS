from __future__ import annotations

import json
import sqlite3
from typing import Any


def workout_log_payload(row: sqlite3.Row) -> dict[str, Any]:
    return {
        "id": row["id"],
        "daily_workout_id": row["daily_workout_id"],
        "class_schedule_id": row["class_schedule_id"],
        "scheduled_date": row["scheduled_date"],
        "workout_title": row["workout_title"],
        "class_title": row["class_title"],
        "class_start_time": row["class_start_time"],
        "score_type": row["score_type"],
        "score_value": row["score_value"],
        "score_label": row["score_label"],
        "notes_text": row["notes_text"],
        "updated_at": row["updated_at"],
        "is_pr": bool(row["is_pr"]) if "is_pr" in row.keys() else False,
        "pr_rank": row["pr_rank"] if "pr_rank" in row.keys() else None,
    }


def get_workout_log_for_user(connection: sqlite3.Connection, workout_id: int, user_id: int) -> dict[str, Any] | None:
    row = connection.execute(
        """
        select workout_logs.id, workout_logs.daily_workout_id, workout_logs.class_schedule_id, workout_logs.score_type,
               workout_logs.score_value, workout_logs.score_label, workout_logs.notes_text, workout_logs.created_at,
               workout_logs.updated_at, daily_workouts.scheduled_date, daily_workouts.title as workout_title,
               class_schedules.title as class_title, class_schedules.start_time as class_start_time,
               workout_logs.is_pr, workout_logs.pr_rank
        from workout_logs
        join daily_workouts on daily_workouts.id = workout_logs.daily_workout_id
        left join class_schedules on class_schedules.id = workout_logs.class_schedule_id
        where workout_logs.daily_workout_id = ? and workout_logs.user_id = ?
        """,
        (workout_id, user_id),
    ).fetchone()
    if row is None:
        return None
    return workout_log_payload(row)


def refresh_pr_flags_for_workout_title(
    connection: sqlite3.Connection,
    *,
    user_id: int,
    gym_id: int,
    workout_title: str,
    score_type: str,
) -> None:
    rows = connection.execute(
        """
        select workout_logs.id, workout_logs.score_value, daily_workouts.scheduled_date, workout_logs.updated_at
        from workout_logs
        join daily_workouts on daily_workouts.id = workout_logs.daily_workout_id
        where workout_logs.user_id = ?
          and workout_logs.gym_id = ?
          and daily_workouts.title = ?
          and workout_logs.score_type = ?
        order by
          case when ? = 'time' then workout_logs.score_value end asc,
          case when ? in ('reps', 'load') then workout_logs.score_value end desc,
          daily_workouts.scheduled_date asc,
          workout_logs.updated_at asc,
          workout_logs.id asc
        """,
        (user_id, gym_id, workout_title, score_type, score_type, score_type),
    ).fetchall()
    if not rows:
        return

    best_id = rows[0]["id"]
    updates: list[tuple[int, int, int]] = []
    for index, row in enumerate(rows, start=1):
        updates.append((1 if row["id"] == best_id else 0, index, row["id"]))

    connection.executemany(
        "update workout_logs set is_pr = ?, pr_rank = ? where id = ?",
        updates,
    )


def list_whiteboard_results(connection: sqlite3.Connection, workout_id: int) -> list[dict[str, Any]]:
    rows = connection.execute(
        """
        select whiteboard_results.id, whiteboard_results.user_id, whiteboard_results.score_type,
               whiteboard_results.score_value, whiteboard_results.score_label, whiteboard_results.notes_text,
               whiteboard_results.created_at, whiteboard_results.updated_at, users.display_name, users.nickname
        from whiteboard_results
        join users on users.id = whiteboard_results.user_id
        where whiteboard_results.daily_workout_id = ?
        order by
          case whiteboard_results.score_type when 'time' then 0 when 'reps' then 1 when 'load' then 2 else 3 end asc,
          case when whiteboard_results.score_type = 'time' then whiteboard_results.score_value end asc,
          case when whiteboard_results.score_type in ('reps', 'load') then whiteboard_results.score_value end desc,
          whiteboard_results.updated_at asc
        """,
        (workout_id,),
    ).fetchall()
    return [
        {
            "id": row["id"],
            "user_id": row["user_id"],
            "athlete_name": row["display_name"] or row["nickname"] or "Member",
            "score_type": row["score_type"],
            "score_value": row["score_value"],
            "score_label": row["score_label"],
            "notes_text": row["notes_text"],
            "rank": index + 1,
        }
        for index, row in enumerate(rows)
    ]


def get_whiteboard_result_for_user(connection: sqlite3.Connection, workout_id: int, user_id: int) -> dict[str, Any] | None:
    row = connection.execute(
        "select id, user_id, score_type, score_value, score_label, notes_text from whiteboard_results where daily_workout_id = ? and user_id = ?",
        (workout_id, user_id),
    ).fetchone()
    if row is None:
        return None
    return {
        "id": row["id"],
        "user_id": row["user_id"],
        "score_type": row["score_type"],
        "score_value": row["score_value"],
        "score_label": row["score_label"],
        "notes_text": row["notes_text"],
    }


def daily_workout_payload(connection: sqlite3.Connection, row: sqlite3.Row, *, current_user_id: int, can_edit: bool) -> dict[str, Any]:
    return {
        "id": row["id"],
        "gym_id": row["gym_id"],
        "scheduled_date": row["scheduled_date"],
        "title": row["title"],
        "strength_text": row["strength_text"],
        "metcon_text": row["metcon_text"],
        "notes_text": row["notes_text"],
        "can_edit": can_edit,
        "whiteboard_results": list_whiteboard_results(connection, row["id"]),
        "my_whiteboard_result": get_whiteboard_result_for_user(connection, row["id"], current_user_id),
        "my_workout_log": get_workout_log_for_user(connection, row["id"], current_user_id),
    }


def exercise_payload(row: sqlite3.Row) -> dict[str, Any]:
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


def benchmark_workout_payload(row: sqlite3.Row) -> dict[str, Any]:
    try:
        structure = json.loads(row["structure_json"] or "{}")
    except (TypeError, ValueError):
        structure = {}
    return {"id": row["id"], "name": row["name"], "category": row["category"], "structure": structure}


def personal_workout_payload(row: sqlite3.Row) -> dict[str, Any]:
    try:
        structure = json.loads(row["structure_json"] or "{}")
    except (TypeError, ValueError):
        structure = {}
    return {
        "id": row["id"],
        "type": row["type"],
        "title": row["title"],
        "structure": structure,
        "created_at": row["created_at"],
        "updated_at": row["updated_at"],
    }
