"""Movements: the identity of "the same exercise" across WODs.

The bundled CrossFit list has ``gym_id`` null; a gym adds its own on top,
usually by typing a new exercise name in the block editor. Result history and
PRs match on the movement, so "Back Squat", "back squat" and "BS" are one.
"""

from __future__ import annotations

import json
from typing import Any, TYPE_CHECKING

from backend.security import isoformat, now_utc

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
    }


def _visible_rows(connection: ManagedConnection, gym_id: int) -> list[Row]:
    return connection.execute(
        """
        select id, gym_id, name, category, aliases_json
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
    by_alias = None
    for row in sorted(_visible_rows(connection, gym_id), key=lambda r: r["gym_id"] is None):
        if _normalize(row["name"]) == wanted:
            return row
        if by_alias is None and any(_normalize(alias) == wanted for alias in _aliases(row)):
            by_alias = row
    return by_alias


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
        names = [row["name"], *_aliases(row)]
        normalized = [_normalize(n) for n in names]
        if wanted and not any(wanted in n for n in normalized):
            continue
        starts = 0 if not wanted or any(n.startswith(wanted) for n in normalized) else 1
        matches.append((starts, _normalize(row["name"]), row))
    matches.sort(key=lambda item: (item[0], item[1]))
    return [movement_payload(row) for _, _, row in matches[:limit]]
