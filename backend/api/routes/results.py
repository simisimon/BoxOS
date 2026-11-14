from __future__ import annotations

from http import HTTPStatus
from typing import Any

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel

from backend.api.deps import require_active_gym_member_session, require_session
from backend.core import db
from backend.services import programming_service, results_service

router = APIRouter()


class ResultSetPayload(BaseModel):
    reps: int | str | None = None
    kg: float | str | None = None


class WorkoutResultRequest(BaseModel):
    section_id: int
    # The score as typed: "4:12", "7+14", "120", "62.5". Exercise blocks send
    # sets instead; a time-capped "for time" block sends the reps reached.
    score: str | None = None
    division: str | None = None
    time_capped: bool = False
    sets: list[ResultSetPayload] | None = None
    notes: str | None = None


class WorkoutResultDeleteRequest(BaseModel):
    section_id: int


@router.put("/results")
def save_workout_result(
    body: WorkoutResultRequest,
    session: dict[str, Any] = Depends(require_active_gym_member_session),
) -> dict[str, Any]:
    """Logs or replaces the caller's result on one scored block of a
    published WOD dated today or earlier."""
    payload = body.model_dump()
    payload["sets"] = None if body.sets is None else [s.model_dump() for s in body.sets]
    connection = db.get_connection()
    try:
        with connection:
            result = results_service.save_result(
                connection,
                user_id=session["user_id"],
                gym_id=session["active_gym_id"],
                section_id=body.section_id,
                body=payload,
            )
            result["is_pr"] = results_service.is_pr(connection, result, session["user_id"])
        return {"result": result}
    finally:
        connection.close()


@router.delete("/results")
def delete_workout_result(
    body: WorkoutResultDeleteRequest,
    session: dict[str, Any] = Depends(require_active_gym_member_session),
) -> dict[str, Any]:
    connection = db.get_connection()
    try:
        with connection:
            results_service.delete_result(
                connection,
                user_id=session["user_id"],
                gym_id=session["active_gym_id"],
                section_id=body.section_id,
            )
        return {"message": "Result deleted."}
    finally:
        connection.close()


@router.get("/results/history")
def workout_result_history(
    section_id: int,
    limit: int = 20,
    session: dict[str, Any] = Depends(require_active_gym_member_session),
) -> dict[str, Any]:
    """The caller's earlier results for the same movement or named workout
    as this block ("Last times"), with PRs and the best per division."""
    connection = db.get_connection()
    try:
        return results_service.history_for_section(
            connection,
            user_id=session["user_id"],
            gym_id=session["active_gym_id"],
            section_id=section_id,
            limit=max(1, min(limit, 100)),
        )
    finally:
        connection.close()


@router.get("/results/me")
def my_workout_results(
    movement_id: int | None = None,
    workout_name: str = "",
    limit: int = 200,
    session: dict[str, Any] = Depends(require_session),
) -> dict[str, Any]:
    """All the caller's results for Profile › Results, optionally for one
    movement or named workout."""
    connection = db.get_connection()
    try:
        return results_service.my_results(
            connection,
            user_id=session["user_id"],
            movement_id=movement_id,
            workout_name=workout_name,
            limit=limit,
        )
    finally:
        connection.close()


@router.get("/results/me.csv")
def export_my_workout_results(session: dict[str, Any] = Depends(require_session)) -> Response:
    """All the caller's results as a CSV download."""
    connection = db.get_connection()
    try:
        text = results_service.my_results_csv(connection, user_id=session["user_id"])
    finally:
        connection.close()
    return Response(
        content=text,
        media_type="text/csv; charset=utf-8",
        headers={"Content-Disposition": 'attachment; filename="boxos-results.csv"'},
    )


@router.get("/benchmarks")
def list_benchmarks(session: dict[str, Any] = Depends(require_session)) -> dict[str, Any]:
    """The benchmark catalog (Girls and Heroes) for the personal logbook."""
    connection = db.get_connection()
    try:
        return {"benchmarks": results_service.list_benchmarks(connection)}
    finally:
        connection.close()


class PersonalResultRequest(BaseModel):
    # benchmark (benchmark_id), movement (movement_id or movement_name, logged
    # as sets) or custom (title, description, score_type).
    kind: str
    benchmark_id: str | None = None
    movement_id: int | None = None
    movement_name: str | None = None
    title: str | None = None
    description: str | None = None
    score_type: str | None = None
    performed_on: str
    score: str | None = None
    division: str | None = None
    time_capped: bool = False
    sets: list[ResultSetPayload] | None = None
    notes: str | None = None


def _save_personal(body: PersonalResultRequest, session: dict[str, Any], result_id: int | None) -> dict[str, Any]:
    payload = body.model_dump()
    payload["sets"] = None if body.sets is None else [s.model_dump() for s in body.sets]
    connection = db.get_connection()
    try:
        with connection:
            result = results_service.save_personal_result(
                connection,
                user_id=session["user_id"],
                gym_id=session.get("active_gym_id"),
                body=payload,
                result_id=result_id,
            )
            result["is_pr"] = results_service.is_pr(connection, result, session["user_id"])
        return {"result": result}
    finally:
        connection.close()


@router.post("/results/personal")
def log_personal_result(
    body: PersonalResultRequest,
    session: dict[str, Any] = Depends(require_session),
) -> dict[str, Any]:
    """Logs a result in the caller's own logbook (no gym WOD, no leaderboard)."""
    return _save_personal(body, session, None)


@router.put("/results/personal/{result_id}")
def update_personal_result(
    result_id: int,
    body: PersonalResultRequest,
    session: dict[str, Any] = Depends(require_session),
) -> dict[str, Any]:
    return _save_personal(body, session, result_id)


@router.delete("/results/personal/{result_id}")
def delete_personal_result(
    result_id: int,
    session: dict[str, Any] = Depends(require_session),
) -> dict[str, Any]:
    connection = db.get_connection()
    try:
        with connection:
            results_service.delete_personal_result(
                connection, user_id=session["user_id"], result_id=result_id
            )
        return {"message": "Result deleted."}
    finally:
        connection.close()


@router.get("/programming/workouts/{workout_id}/leaderboard")
def workout_leaderboard(
    workout_id: int,
    session: dict[str, Any] = Depends(require_active_gym_member_session),
) -> dict[str, Any]:
    """Everyone's results on a WOD, ranked per block. Members see it for
    published WODs; owners and trainers also see notes."""
    staff = programming_service.can_view_drafts(session["role"])
    connection = db.get_connection()
    try:
        workout = connection.execute(
            "select id, status from daily_workouts where id = ? and gym_id = ?",
            (workout_id, session["active_gym_id"]),
        ).fetchone()
        if workout is None or (workout["status"] != "published" and not staff):
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Workout not found.")
        return {
            "sections": results_service.leaderboard(
                connection,
                daily_workout_id=workout_id,
                viewer_id=session["user_id"],
                staff=staff,
            )
        }
    finally:
        connection.close()
