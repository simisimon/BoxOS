"""Movements: the identity of "the same exercise" across WODs.

The bundled CrossFit list has ``gym_id`` null; a gym adds its own on top,
usually by typing a new exercise name in the block editor. Result history and
PRs match on the movement, so "Back Squat", "back squat" and "BS" are one.
"""

from __future__ import annotations

import json
from http import HTTPStatus
from typing import Any, TYPE_CHECKING

from backend.security import isoformat, now_utc
from backend.validation import ApiError

if TYPE_CHECKING:
    from backend.db import ManagedConnection, Row

MAX_MOVEMENT_NAME = 80


def _aliases(row: Row) -> list[str]:
    try:
        value = json.loads(row["aliases_json"] or "[]")
    except (TypeError, ValueError):
        return []
    return [str(alias) for alias in value if str(alias).strip()]


def movement_payload(row: Row) -> dict[str, Any]:
    return {
        "id": row["id"],
        "name": row["name"],
        "category": row["category"],
        "aliases": _aliases(row),
        "built_in": row["gym_id"] is None,
        "archived": bool(row["archived_at"]),
    }


def movement_detail(connection: ManagedConnection, *, gym_id: int, movement_id: int) -> dict[str, Any] | None:
    """A movement with the how-to from the exercise library, when linked."""
    row = connection.execute(
        """
        select m.id, m.gym_id, m.name, m.category, m.aliases_json, m.archived_at,
               e.instructions, e.primary_muscles, e.secondary_muscles, e.equipment
        from movements m
        left join exercises e on e.id = m.exercise_id
        where m.id = ? and (m.gym_id is null or m.gym_id = ?)
        """,
        (movement_id, gym_id),
    ).fetchone()
    if row is None:
        return None

    def _list(value: Any) -> list[str]:
        try:
            return [str(item) for item in json.loads(value or "[]") if str(item).strip()]
        except (TypeError, ValueError):
            return []

    return {
        **movement_payload(row),
        "instructions": _list(row["instructions"]),
        "primary_muscles": _list(row["primary_muscles"]),
        "secondary_muscles": _list(row["secondary_muscles"]),
        "equipment": row["equipment"] or "",
    }


def _visible_rows(connection: ManagedConnection, gym_id: int) -> list[Row]:
    return connection.execute(
        """
        select id, gym_id, name, category, aliases_json, archived_at, merged_into_id
        from movements
        where gym_id is null or gym_id = ?
        order by lower(name)
        """,
        (gym_id,),
    ).fetchall()


def _normalize(name: str) -> str:
    return " ".join(name.strip().lower().split())


def find_movement(connection: ManagedConnection, *, gym_id: int, name: str) -> Row | None:
    """The gym's or the built-in movement called ``name`` (or with that alias).
    A gym's own movement wins over a built-in one with the same name."""
    wanted = _normalize(name)
    if not wanted:
        return None
    rows = _visible_rows(connection, gym_id)
    by_id = {row["id"]: row for row in rows}
    by_alias = None
    found = None
    for row in sorted(rows, key=lambda r: r["gym_id"] is None):
        if _normalize(row["name"]) == wanted:
            found = row
            break
        if by_alias is None and any(_normalize(alias) == wanted for alias in _aliases(row)):
            by_alias = row
    found = found or by_alias
    # A merged movement stands for the one it was merged into.
    seen: set[int] = set()
    while found is not None and found["merged_into_id"] is not None and found["id"] not in seen:
        seen.add(found["id"])
        found = by_id.get(found["merged_into_id"], found)
    return found


def resolve_movement_id(connection: ManagedConnection, *, gym_id: int, name: str) -> int | None:
    """The movement for an exercise block's name, created for the gym when
    no movement matches. None for an empty name."""
    name = " ".join(name.strip().split())[:MAX_MOVEMENT_NAME]
    if not name:
        return None
    existing = find_movement(connection, gym_id=gym_id, name=name)
    if existing is not None:
        return int(existing["id"])
    row = connection.execute(
        """
        insert into movements (gym_id, name, category, aliases_json, created_at)
        values (?, ?, '', '[]', ?)
        returning id
        """,
        (gym_id, name, isoformat(now_utc())),
    ).fetchone()
    return int(row["id"])


def search_movements(
    connection: ManagedConnection, *, gym_id: int, query: str, limit: int
) -> list[dict[str, Any]]:
    """Movements whose name or an alias contains ``query``; names that start
    with it come first."""
    wanted = _normalize(query)
    matches: list[tuple[int, str, Row]] = []
    for row in _visible_rows(connection, gym_id):
        if row["archived_at"] or row["merged_into_id"] is not None:
            continue
        names = [row["name"], *_aliases(row)]
        normalized = [_normalize(n) for n in names]
        if wanted and not any(wanted in n for n in normalized):
            continue
        starts = 0 if not wanted or any(n.startswith(wanted) for n in normalized) else 1
        matches.append((starts, _normalize(row["name"]), row))
    matches.sort(key=lambda item: (item[0], item[1]))
    return [movement_payload(row) for _, _, row in matches[:limit]]


# --- Settings > Movements -------------------------------------------------------


def gym_movements(connection: ManagedConnection, *, gym_id: int) -> list[dict[str, Any]]:
    """The gym's own movements (archived ones too, merged ones not), with how
    many WOD blocks and results use each."""
    rows = connection.execute(
        """
        select m.id, m.gym_id, m.name, m.category, m.aliases_json, m.archived_at,
               (select count(*) from daily_workout_sections s where s.movement_id = m.id) as block_count,
               (select count(*) from workout_results r where r.movement_id = m.id) as result_count
        from movements m
        where m.gym_id = ? and m.merged_into_id is null
        order by lower(m.name)
        """,
        (gym_id,),
    ).fetchall()
    return [
        {**movement_payload(row), "block_count": int(row["block_count"]), "result_count": int(row["result_count"])}
        for row in rows
    ]


def _own_movement(connection: ManagedConnection, *, gym_id: int, movement_id: int) -> Row:
    row = connection.execute(
        "select id, gym_id, name, merged_into_id from movements where id = ?",
        (movement_id,),
    ).fetchone()
    if row is None or row["gym_id"] != gym_id or row["merged_into_id"] is not None:
        raise ApiError(HTTPStatus.NOT_FOUND, "Movement not found. Built-in movements can't be changed.")
    return row


def update_movement(
    connection: ManagedConnection,
    *,
    gym_id: int,
    movement_id: int,
    name: str | None,
    archived: bool | None,
) -> dict[str, Any]:
    """Rename or (un)archive one of the gym's own movements."""
    row = _own_movement(connection, gym_id=gym_id, movement_id=movement_id)
    if name is not None:
        name = " ".join(name.strip().split())
        if not name or len(name) > MAX_MOVEMENT_NAME:
            raise ApiError(HTTPStatus.BAD_REQUEST, f"Give the movement a name of up to {MAX_MOVEMENT_NAME} characters.")
        clash = find_movement(connection, gym_id=gym_id, name=name)
        if clash is not None and clash["id"] != row["id"] and _normalize(clash["name"]) == _normalize(name):
            raise ApiError(HTTPStatus.CONFLICT, f"{clash['name']} already exists. Merge into it instead.")
        connection.execute("update movements set name = ? where id = ?", (name, row["id"]))
        # Blocks show the exercise name they were saved with; keep them in step.
        connection.execute(
            "update daily_workout_sections set exercise_name = ? where movement_id = ?",
            (name, row["id"]),
        )
    if archived is not None:
        connection.execute(
            "update movements set archived_at = ? where id = ?",
            (isoformat(now_utc()) if archived else None, row["id"]),
        )
    return _payload_by_id(connection, gym_id=gym_id, movement_id=row["id"])


def merge_movement(
    connection: ManagedConnection, *, gym_id: int, movement_id: int, into_id: int
) -> dict[str, Any]:
    """Move a duplicate's blocks and results to ``into_id`` (the gym's or a
    built-in movement). The duplicate's name keeps resolving to the target."""
    source = _own_movement(connection, gym_id=gym_id, movement_id=movement_id)
    target = connection.execute(
        "select id, gym_id, name, merged_into_id from movements where id = ?",
        (into_id,),
    ).fetchone()
    if (
        target is None
        or target["id"] == source["id"]
        or target["merged_into_id"] is not None
        or target["gym_id"] not in (None, gym_id)
    ):
        raise ApiError(HTTPStatus.BAD_REQUEST, "Pick another movement to merge into.")
    connection.execute(
        "update daily_workout_sections set movement_id = ?, exercise_name = ? where movement_id = ?",
        (target["id"], target["name"], source["id"]),
    )
    connection.execute(
        "update workout_results set movement_id = ? where movement_id = ?",
        (target["id"], source["id"]),
    )
    connection.execute(
        "update movements set merged_into_id = ?, archived_at = coalesce(archived_at, ?) where id = ?",
        (target["id"], isoformat(now_utc()), source["id"]),
    )
    return _payload_by_id(connection, gym_id=gym_id, movement_id=target["id"])


def _payload_by_id(connection: ManagedConnection, *, gym_id: int, movement_id: int) -> dict[str, Any]:
    row = connection.execute(
        """
        select id, gym_id, name, category, aliases_json, archived_at
        from movements where id = ? and (gym_id is null or gym_id = ?)
        """,
        (movement_id, gym_id),
    ).fetchone()
    return movement_payload(row)
