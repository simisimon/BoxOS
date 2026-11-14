from __future__ import annotations

from http import HTTPStatus
from typing import Any

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from backend.api.deps import (
    require_active_gym_member_session,
    require_admin_gym_session,
    require_session,
)
from backend.core import db
from backend.services import movement_service, programming_service

router = APIRouter()


@router.get("/exercises")
def list_exercises(
    query: str = "",
    limit: int = 50,
    _: dict[str, Any] = Depends(require_session),
) -> dict[str, Any]:
    normalized_query = (query or "").strip().lower()
    normalized_limit = max(1, min(limit, 100))
    connection = db.get_connection()
    try:
        if normalized_query:
            rows = connection.execute(
                """
                select id, name, category, equipment, level,
                       primary_muscles, secondary_muscles
                from exercises
                where search like ?
                order by name
                limit ?
                """,
                (f"%{normalized_query}%", normalized_limit),
            ).fetchall()
        else:
            rows = connection.execute(
                """
                select id, name, category, equipment, level,
                       primary_muscles, secondary_muscles
                from exercises
                order by name
                limit ?
                """,
                (normalized_limit,),
            ).fetchall()
        return {"exercises": [programming_service.exercise_payload(row) for row in rows]}
    finally:
        connection.close()


@router.get("/movements")
def list_movements(
    query: str = "",
    limit: int = 20,
    session: dict[str, Any] = Depends(require_active_gym_member_session),
) -> dict[str, Any]:
    """The gym's movements (bundled CrossFit list plus its own) for the block
    editor's exercise picker; result history matches on these."""
    connection = db.get_connection()
    try:
        movements = movement_service.search_movements(
            connection,
            gym_id=session["active_gym_id"],
            query=query,
            limit=max(1, min(limit, 100)),
        )
        return {"movements": movements}
    finally:
        connection.close()


@router.get("/movements/{movement_id}")
def get_movement(
    movement_id: int,
    session: dict[str, Any] = Depends(require_active_gym_member_session),
) -> dict[str, Any]:
    """One movement with instructions and muscles from the exercise library
    (empty when the movement has no library entry)."""
    connection = db.get_connection()
    try:
        movement = movement_service.movement_detail(
            connection, gym_id=session["active_gym_id"], movement_id=movement_id
        )
        if movement is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Movement not found.")
        return {"movement": movement}
    finally:
        connection.close()


@router.get("/gym-movements")
def list_gym_movements(session: dict[str, Any] = Depends(require_admin_gym_session)) -> dict[str, Any]:
    """Settings > Movements: the gym's own movements with their usage."""
    connection = db.get_connection()
    try:
        return {"movements": movement_service.gym_movements(connection, gym_id=session["active_gym_id"])}
    finally:
        connection.close()


class MovementUpdateRequest(BaseModel):
    name: str | None = None
    archived: bool | None = None


@router.patch("/movements/{movement_id}")
def update_movement(
    movement_id: int,
    body: MovementUpdateRequest,
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, Any]:
    connection = db.get_connection()
    try:
        with connection:
            movement = movement_service.update_movement(
                connection,
                gym_id=session["active_gym_id"],
                movement_id=movement_id,
                name=body.name,
                archived=body.archived,
            )
        return {"movement": movement}
    finally:
        connection.close()


class MovementMergeRequest(BaseModel):
    into_id: int


@router.post("/movements/{movement_id}/merge")
def merge_movement(
    movement_id: int,
    body: MovementMergeRequest,
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, Any]:
    """Merge a duplicate into another movement: its WOD blocks and results
    move there, so history and PRs see them as one."""
    connection = db.get_connection()
    try:
        with connection:
            movement = movement_service.merge_movement(
                connection,
                gym_id=session["active_gym_id"],
                movement_id=movement_id,
                into_id=body.into_id,
            )
        return {"movement": movement}
    finally:
        connection.close()


@router.get("/workout-names")
def list_workout_names(
    query: str = "",
    limit: int = 10,
    session: dict[str, Any] = Depends(require_active_gym_member_session),
) -> dict[str, Any]:
    """Suggestions for a workout block's name: the benchmark catalog plus
    names this gym has used before."""
    wanted = " ".join(query.strip().lower().split())
    connection = db.get_connection()
    try:
        benchmarks = [
            row["name"]
            for row in connection.execute(
                "select name from benchmark_workouts order by sort_order"
            ).fetchall()
        ]
        used = [
            row["workout_name"]
            for row in connection.execute(
                """
                select distinct s.workout_name
                from daily_workout_sections s
                join daily_workouts w on w.id = s.daily_workout_id
                where w.gym_id = ? and s.workout_name <> ''
                order by s.workout_name
                """,
                (session["active_gym_id"],),
            ).fetchall()
        ]
        names: list[str] = []
        seen: set[str] = set()
        for name in [*used, *benchmarks]:
            key = name.lower()
            if key in seen or (wanted and wanted not in key):
                continue
            seen.add(key)
            names.append(name)
        names.sort(key=lambda n: (not n.lower().startswith(wanted), n.lower()))
        return {"workout_names": names[: max(1, min(limit, 50))]}
    finally:
        connection.close()
