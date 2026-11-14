from __future__ import annotations

from http import HTTPStatus
from typing import Any

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from backend.api.deps import (
    require_active_gym_member_session,
    require_schedule_manager_session,
)
from backend.api.validators import programming as validators
from backend.core import audit, db, notifications, security, validation
from backend.services import programming_service

router = APIRouter()


class DailyWorkoutSetPayload(BaseModel):
    reps: int
    value: float | None = None


class DailyWorkoutSectionPayload(BaseModel):
    # Sent back for existing blocks so they are updated in place.
    id: int | None = None
    title: str | None = None
    description: str
    score_type: str
    # Structured block (docs/admin-ui-reference.md §3.1); all optional.
    kind: str | None = None
    exercise_name: str | None = None
    set_unit: str | None = None
    sets: list[DailyWorkoutSetPayload] | None = None
    coach_notes: str | None = None
    member_notes: str | None = None
    workout_name: str | None = None


class DailyWorkoutRequest(BaseModel):
    scheduled_date: str
    title: str
    sections: list[DailyWorkoutSectionPayload]
    status: str | None = None


class DailyWorkoutUpdateRequest(DailyWorkoutRequest):
    id: int


class DailyWorkoutImportRow(BaseModel):
    scheduled_date: str
    title: str
    status: str | None = None
    sections: list[DailyWorkoutSectionPayload]


class DailyWorkoutImportRequest(BaseModel):
    rows: list[DailyWorkoutImportRow]


class DailyWorkoutPublishRequest(BaseModel):
    id: int


class DailyWorkoutDuplicateRequest(BaseModel):
    source_date: str
    target_date: str


@router.get("/programming/workouts")
def list_daily_workouts(session: dict[str, Any] = Depends(require_active_gym_member_session)) -> dict[str, Any]:
    connection = db.get_connection()
    try:
        can_manage = programming_service.can_view_drafts(session["role"])
        if can_manage:
            rows = connection.execute(
                f"""
                select {programming_service.DAILY_WORKOUT_COLUMNS}
                from daily_workouts
                where daily_workouts.gym_id = ?
                order by daily_workouts.scheduled_date asc
                """,
                (session["active_gym_id"],),
            ).fetchall()
        else:
            rows = connection.execute(
                f"""
                select {programming_service.DAILY_WORKOUT_COLUMNS}
                from daily_workouts
                where daily_workouts.gym_id = ? and daily_workouts.status = 'published'
                order by daily_workouts.scheduled_date asc
                """,
                (session["active_gym_id"],),
            ).fetchall()
        workouts = [
            programming_service.daily_workout_payload(
                connection,
                row,
                current_user_id=session["user_id"],
                can_edit=can_manage,
            )
            for row in rows
        ]
        return {"workouts": workouts}
    finally:
        connection.close()


@router.post("/programming/workouts")
def create_daily_workout(
    body: DailyWorkoutRequest,
    session: dict[str, Any] = Depends(require_schedule_manager_session),
) -> dict[str, Any]:
    scheduled_date = validators.require_programming_date(body.scheduled_date)
    title = validators.require_programming_title(body.title)
    sections = validators.require_workout_sections(
        [section.model_dump() for section in body.sections]
    )
    status = programming_service.require_workout_status(body.status or "draft")
    connection = db.get_connection()
    try:
        existing = connection.execute(
            "select id from daily_workouts where gym_id = ? and scheduled_date = ?",
            (session["active_gym_id"], scheduled_date),
        ).fetchone()
        if existing is not None:
            raise HTTPException(status_code=HTTPStatus.CONFLICT.value, detail="A workout already exists for this date.")
        timestamp = security.isoformat(security.now_utc())
        published_at = timestamp if status == "published" else None
        published_by = session["user_id"] if status == "published" else None
        with connection:
            cursor = connection.execute(
                """
                insert into daily_workouts (
                  gym_id, scheduled_date, title,
                  status, published_at, published_by_user_id,
                  created_by_user_id, updated_by_user_id, created_at, updated_at
                )
                values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                returning id
                """,
                (
                    session["active_gym_id"],
                    scheduled_date,
                    title,
                    status,
                    published_at,
                    published_by,
                    session["user_id"],
                    session["user_id"],
                    timestamp,
                    timestamp,
                ),
            )
            workout_id = int(cursor.fetchone()["id"])
            programming_service.replace_workout_sections(
                connection,
                daily_workout_id=workout_id,
                sections=sections,
            )
            row = connection.execute(
                f"select {programming_service.DAILY_WORKOUT_COLUMNS} from daily_workouts where id = ?",
                (workout_id,),
            ).fetchone()
            payload = programming_service.daily_workout_payload(connection, row, current_user_id=session["user_id"], can_edit=True)
            if status == "published":
                notifications.create_wod_notifications(connection, gym_id=session["active_gym_id"], workout_id=workout_id, scheduled_date=scheduled_date, title=title, is_update=False)
            audit.write_audit_log(connection, gym_id=session["active_gym_id"], actor_user_id=session["user_id"], action="daily_workout_created", entity_type="daily_workout", entity_id=workout_id, details={"scheduled_date": scheduled_date, "title": title, "status": status})
        return {"workout": payload}
    finally:
        connection.close()


@router.patch("/programming/workouts")
def update_daily_workout(
    body: DailyWorkoutUpdateRequest,
    session: dict[str, Any] = Depends(require_schedule_manager_session),
) -> dict[str, Any]:
    workout_id = validation.require_user_id(body.id)
    scheduled_date = validators.require_programming_date(body.scheduled_date)
    title = validators.require_programming_title(body.title)
    sections = validators.require_workout_sections(
        [section.model_dump() for section in body.sections]
    )
    connection = db.get_connection()
    try:
        existing = connection.execute(
            "select id, scheduled_date, status from daily_workouts where id = ? and gym_id = ?",
            (workout_id, session["active_gym_id"]),
        ).fetchone()
        if existing is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Workout not found.")
        if validators.parse_programming_date(existing["scheduled_date"]) < programming_service.today_utc_date():
            raise HTTPException(status_code=HTTPStatus.BAD_REQUEST.value, detail="Past workouts cannot be edited.")
        duplicate = connection.execute(
            "select id from daily_workouts where gym_id = ? and scheduled_date = ? and id != ?",
            (session["active_gym_id"], scheduled_date, workout_id),
        ).fetchone()
        if duplicate is not None:
            raise HTTPException(status_code=HTTPStatus.CONFLICT.value, detail="A workout already exists for this date.")
        with connection:
            connection.execute(
                """
                update daily_workouts
                set scheduled_date = ?,
                    title = ?,
                    updated_by_user_id = ?,
                    updated_at = ?
                where id = ?
                """,
                (
                    scheduled_date,
                    title,
                    session["user_id"],
                    security.isoformat(security.now_utc()),
                    workout_id,
                ),
            )
            programming_service.replace_workout_sections(
                connection,
                daily_workout_id=workout_id,
                sections=sections,
            )
            row = connection.execute(
                f"select {programming_service.DAILY_WORKOUT_COLUMNS} from daily_workouts where id = ?",
                (workout_id,),
            ).fetchone()
            payload = programming_service.daily_workout_payload(connection, row, current_user_id=session["user_id"], can_edit=True)
            if existing["status"] == "published":
                notifications.create_wod_notifications(connection, gym_id=session["active_gym_id"], workout_id=workout_id, scheduled_date=scheduled_date, title=title, is_update=True)
            audit.write_audit_log(connection, gym_id=session["active_gym_id"], actor_user_id=session["user_id"], action="daily_workout_updated", entity_type="daily_workout", entity_id=workout_id, details={"scheduled_date": scheduled_date, "title": title})
        return {"workout": payload}
    finally:
        connection.close()


@router.post("/programming/workouts/publish")
def publish_daily_workout(
    body: DailyWorkoutPublishRequest,
    session: dict[str, Any] = Depends(require_schedule_manager_session),
) -> dict[str, Any]:
    workout_id = validation.require_user_id(body.id)
    connection = db.get_connection()
    try:
        existing = connection.execute(
            "select id, scheduled_date, title, status from daily_workouts where id = ? and gym_id = ?",
            (workout_id, session["active_gym_id"]),
        ).fetchone()
        if existing is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Workout not found.")
        already_published = existing["status"] == "published"
        timestamp = security.isoformat(security.now_utc())
        with connection:
            connection.execute(
                """
                update daily_workouts
                set status = 'published',
                    published_at = ?,
                    published_by_user_id = ?,
                    updated_by_user_id = ?,
                    updated_at = ?
                where id = ?
                """,
                (timestamp, session["user_id"], session["user_id"], timestamp, workout_id),
            )
            row = connection.execute(
                f"select {programming_service.DAILY_WORKOUT_COLUMNS} from daily_workouts where id = ?",
                (workout_id,),
            ).fetchone()
            payload = programming_service.daily_workout_payload(connection, row, current_user_id=session["user_id"], can_edit=True)
            if not already_published:
                notifications.create_wod_notifications(connection, gym_id=session["active_gym_id"], workout_id=workout_id, scheduled_date=existing["scheduled_date"], title=existing["title"], is_update=False)
            audit.write_audit_log(connection, gym_id=session["active_gym_id"], actor_user_id=session["user_id"], action="daily_workout_published", entity_type="daily_workout", entity_id=workout_id, details={"scheduled_date": existing["scheduled_date"]})
        return {"workout": payload}
    finally:
        connection.close()


@router.post("/programming/workouts/unpublish")
def unpublish_daily_workout(
    body: DailyWorkoutPublishRequest,
    session: dict[str, Any] = Depends(require_schedule_manager_session),
) -> dict[str, Any]:
    workout_id = validation.require_user_id(body.id)
    connection = db.get_connection()
    try:
        existing = connection.execute(
            "select id, scheduled_date from daily_workouts where id = ? and gym_id = ?",
            (workout_id, session["active_gym_id"]),
        ).fetchone()
        if existing is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Workout not found.")
        timestamp = security.isoformat(security.now_utc())
        with connection:
            connection.execute(
                """
                update daily_workouts
                set status = 'draft',
                    published_at = null,
                    published_by_user_id = null,
                    updated_by_user_id = ?,
                    updated_at = ?
                where id = ?
                """,
                (session["user_id"], timestamp, workout_id),
            )
            row = connection.execute(
                f"select {programming_service.DAILY_WORKOUT_COLUMNS} from daily_workouts where id = ?",
                (workout_id,),
            ).fetchone()
            payload = programming_service.daily_workout_payload(connection, row, current_user_id=session["user_id"], can_edit=True)
            audit.write_audit_log(connection, gym_id=session["active_gym_id"], actor_user_id=session["user_id"], action="daily_workout_unpublished", entity_type="daily_workout", entity_id=workout_id, details={"scheduled_date": existing["scheduled_date"]})
        return {"workout": payload}
    finally:
        connection.close()


@router.post("/programming/workouts/duplicate")
def duplicate_daily_workout(
    body: DailyWorkoutDuplicateRequest,
    session: dict[str, Any] = Depends(require_schedule_manager_session),
) -> dict[str, Any]:
    target_date = validators.require_programming_date(body.target_date)
    source_raw = str(body.source_date or "").strip()
    if not source_raw:
        raise HTTPException(status_code=HTTPStatus.BAD_REQUEST.value, detail="Source date is required.")
    try:
        validators.parse_programming_date(source_raw)
    except ValueError as error:
        raise HTTPException(status_code=HTTPStatus.BAD_REQUEST.value, detail="Source date must be a valid ISO-8601 date.") from error
    if source_raw == target_date:
        raise HTTPException(status_code=HTTPStatus.BAD_REQUEST.value, detail="Source and target dates must differ.")
    connection = db.get_connection()
    try:
        source = connection.execute(
            f"""
            select {programming_service.DAILY_WORKOUT_COLUMNS}
            from daily_workouts
            where gym_id = ? and scheduled_date = ?
            """,
            (session["active_gym_id"], source_raw),
        ).fetchone()
        if source is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Source workout not found.")
        clash = connection.execute(
            "select id from daily_workouts where gym_id = ? and scheduled_date = ?",
            (session["active_gym_id"], target_date),
        ).fetchone()
        if clash is not None:
            raise HTTPException(status_code=HTTPStatus.CONFLICT.value, detail="A workout already exists for this date.")
        source_sections = programming_service.fetch_workout_sections(connection, source["id"])
        timestamp = security.isoformat(security.now_utc())
        with connection:
            cursor = connection.execute(
                """
                insert into daily_workouts (
                  gym_id, scheduled_date, title,
                  status, published_at, published_by_user_id,
                  created_by_user_id, updated_by_user_id, created_at, updated_at
                )
                values (?, ?, ?, 'draft', null, null, ?, ?, ?, ?)
                returning id
                """,
                (
                    session["active_gym_id"],
                    target_date,
                    source["title"],
                    session["user_id"],
                    session["user_id"],
                    timestamp,
                    timestamp,
                ),
            )
            workout_id = int(cursor.fetchone()["id"])
            programming_service.replace_workout_sections(
                connection,
                daily_workout_id=workout_id,
                sections=source_sections,
            )
            row = connection.execute(
                f"select {programming_service.DAILY_WORKOUT_COLUMNS} from daily_workouts where id = ?",
                (workout_id,),
            ).fetchone()
            payload = programming_service.daily_workout_payload(connection, row, current_user_id=session["user_id"], can_edit=True)
            audit.write_audit_log(connection, gym_id=session["active_gym_id"], actor_user_id=session["user_id"], action="daily_workout_duplicated", entity_type="daily_workout", entity_id=workout_id, details={"source_date": source_raw, "target_date": target_date})
        return {"workout": payload}
    finally:
        connection.close()


@router.post("/programming/workouts/import")
def import_daily_workouts(
    body: DailyWorkoutImportRequest,
    session: dict[str, Any] = Depends(require_schedule_manager_session),
) -> Any:
    if not body.rows:
        raise HTTPException(
            status_code=HTTPStatus.BAD_REQUEST.value,
            detail="No rows to import.",
        )
    if len(body.rows) > 500:
        raise HTTPException(
            status_code=HTTPStatus.BAD_REQUEST.value,
            detail="Too many rows to import (max 500).",
        )
    connection = db.get_connection()
    try:
        # Phase 1 — validate every row read-only. The import is atomic: if any
        # row is invalid nothing is created and all errors are reported at once.
        resolved: list[dict[str, Any]] = []
        errors: list[dict[str, Any]] = []
        seen_dates: dict[str, int] = {}
        for index, row in enumerate(body.rows):
            try:
                scheduled_date = validators.require_programming_date(
                    row.scheduled_date
                )
                if scheduled_date in seen_dates:
                    raise validation.ApiError(
                        HTTPStatus.BAD_REQUEST,
                        f"Date {scheduled_date} appears in row {seen_dates[scheduled_date]} already; only one WOD per date.",
                    )
                seen_dates[scheduled_date] = index + 1
                clash = connection.execute(
                    "select id from daily_workouts where gym_id = ? and scheduled_date = ?",
                    (session["active_gym_id"], scheduled_date),
                ).fetchone()
                if clash is not None:
                    raise validation.ApiError(
                        HTTPStatus.CONFLICT,
                        f"A workout already exists for {scheduled_date}.",
                    )
                title = validators.require_programming_title(row.title)
                status = programming_service.require_workout_status(
                    row.status or "draft"
                )
                sections = validators.require_workout_sections(
                    [section.model_dump() for section in row.sections]
                )
                resolved.append(
                    {
                        "scheduled_date": scheduled_date,
                        "title": title,
                        "status": status,
                        "sections": sections,
                    }
                )
            except validation.ApiError as error:
                errors.append({"row": index + 1, "message": error.message})

        if errors:
            return JSONResponse(
                status_code=HTTPStatus.UNPROCESSABLE_ENTITY.value,
                content={"errors": errors, "created_count": 0},
            )

        # Phase 2 — insert everything in a single transaction. The whole batch
        # rolls back if any insert fails.
        timestamp = security.isoformat(security.now_utc())
        created_count = 0
        with connection:
            for item in resolved:
                published_at = timestamp if item["status"] == "published" else None
                published_by = (
                    session["user_id"] if item["status"] == "published" else None
                )
                cursor = connection.execute(
                    """
                    insert into daily_workouts (
                      gym_id, scheduled_date, title,
                      status, published_at, published_by_user_id,
                      created_by_user_id, updated_by_user_id, created_at, updated_at
                    )
                    values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    returning id
                    """,
                    (
                        session["active_gym_id"],
                        item["scheduled_date"],
                        item["title"],
                        item["status"],
                        published_at,
                        published_by,
                        session["user_id"],
                        session["user_id"],
                        timestamp,
                        timestamp,
                    ),
                )
                workout_id = int(cursor.fetchone()["id"])
                programming_service.replace_workout_sections(
                    connection,
                    daily_workout_id=workout_id,
                    sections=item["sections"],
                )
                if item["status"] == "published":
                    notifications.create_wod_notifications(
                        connection,
                        gym_id=session["active_gym_id"],
                        workout_id=workout_id,
                        scheduled_date=item["scheduled_date"],
                        title=item["title"],
                        is_update=False,
                    )
                audit.write_audit_log(
                    connection,
                    gym_id=session["active_gym_id"],
                    actor_user_id=session["user_id"],
                    action="daily_workout_created",
                    entity_type="daily_workout",
                    entity_id=workout_id,
                    details={
                        "scheduled_date": item["scheduled_date"],
                        "title": item["title"],
                        "status": item["status"],
                        "source": "import",
                    },
                )
                created_count += 1
        return {"created_count": created_count, "row_count": len(resolved)}
    finally:
        connection.close()
