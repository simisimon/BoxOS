from __future__ import annotations

from datetime import timedelta
from http import HTTPStatus
from typing import Any

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from backend.api.common import EntityIdRequest, class_type_names, get_gym_timezone
from backend.api.deps import (
    require_active_gym_member_session,
    require_admin_gym_session,
    require_schedule_manager_session,
)
from backend.api.validators import schedule as validators
from backend.core import audit, db, security, validation
from backend.services import plan_service, schedule_service

router = APIRouter()


class ScheduleClassRequest(BaseModel):
    title: str
    class_type: str
    start_time: str
    duration_minutes: int | None = None
    duration: int | None = None
    capacity: int
    trainer_user_id: int | None = None
    recurrence_frequency: str | None = None
    occurrence_count: int | None = None


class UpdateScheduleClassRequest(ScheduleClassRequest):
    id: int


class ClassTemplateRequest(BaseModel):
    title: str
    class_type: str
    weekdays: list[int]
    start_time: str
    duration_minutes: int
    capacity: int
    trainer_user_id: int | None = None


class UpdateClassTemplateRequest(ClassTemplateRequest):
    id: int


class ClassIdRequest(BaseModel):
    class_id: int


class ScheduleClassDeleteRequest(BaseModel):
    id: int


class UpdateAttendanceRequest(BaseModel):
    class_id: int
    user_id: int
    attendance_status: str


@router.get("/schedule/classes")
def list_schedule_classes(
    session: dict[str, Any] = Depends(require_active_gym_member_session),
) -> dict[str, list[dict[str, Any]]]:
    connection = db.get_connection()
    try:
        include_bookings = session["role"] in {"admin", "trainer"}
        with connection:
            schedule_service.materialize_gym_sessions(
                connection,
                gym_id=session["active_gym_id"],
                gym_timezone=get_gym_timezone(connection, session["active_gym_id"]),
            )
        rows = connection.execute(
            """
            select
              class_schedules.id,
              class_schedules.gym_id,
              class_schedules.title,
              class_schedules.class_type,
              class_schedules.start_time,
              class_schedules.end_time,
              class_schedules.duration_minutes,
              class_schedules.capacity,
              class_schedules.assigned_trainer_user_id,
              class_schedules.class_template_id,
              trainer.display_name as assigned_trainer_display_name,
              trainer.nickname as assigned_trainer_nickname
            from class_schedules
            left join users trainer on trainer.id = class_schedules.assigned_trainer_user_id
            where class_schedules.gym_id = ?
            order by start_time asc
            """,
            (session["active_gym_id"],),
        ).fetchall()
        return {
            "classes": [
                schedule_service.schedule_class_payload(
                    connection,
                    row,
                    current_user_id=session["user_id"],
                    include_bookings=include_bookings,
                )
                for row in rows
            ]
        }
    finally:
        connection.close()


def _require_gym_trainer(connection: Any, gym_id: int, trainer_user_id: int | None) -> None:
    if trainer_user_id is None:
        return
    assigned_trainer = connection.execute(
        """
        select users.id
        from gym_memberships
        join users on users.id = gym_memberships.user_id
        where gym_memberships.gym_id = ?
          and gym_memberships.user_id = ?
          and gym_memberships.status = 'active'
          and gym_memberships.active_role = 'trainer'
          and users.deleted_at is null
        """,
        (gym_id, trainer_user_id),
    ).fetchone()
    if assigned_trainer is None:
        raise HTTPException(status_code=HTTPStatus.BAD_REQUEST.value, detail="Selected trainer is not active in this gym.")


def _class_template_fields(body: ClassTemplateRequest, gym_id: int) -> dict[str, Any]:
    return {
        "title": validators.require_schedule_title(body.title),
        "class_type": validators.require_class_type(body.class_type, class_type_names(gym_id)),
        "weekdays": validators.require_weekdays(body.weekdays),
        "start_local_time": validators.require_local_time(body.start_time),
        "duration_minutes": validators.require_duration_minutes(body.duration_minutes),
        "capacity": validators.require_capacity(body.capacity),
        "trainer_user_id": validators.require_optional_user_id(body.trainer_user_id),
    }


def _class_template_audit_details(fields: dict[str, Any]) -> dict[str, Any]:
    return {
        "title": fields["title"],
        "class_type": fields["class_type"],
        "weekdays": fields["weekdays"],
        "start_time": fields["start_local_time"],
        "duration_minutes": fields["duration_minutes"],
        "capacity": fields["capacity"],
        "trainer_user_id": fields["trainer_user_id"],
    }


@router.get("/schedule/templates")
def list_class_templates(
    session: dict[str, Any] = Depends(require_schedule_manager_session),
) -> dict[str, list[dict[str, Any]]]:
    connection = db.get_connection()
    try:
        rows = schedule_service.list_class_template_rows(connection, session["active_gym_id"])
        return {"templates": [schedule_service.class_template_payload(row) for row in rows]}
    finally:
        connection.close()


@router.post("/schedule/templates", status_code=HTTPStatus.CREATED.value)
def create_class_template(
    body: ClassTemplateRequest,
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, Any]:
    fields = _class_template_fields(body, session["active_gym_id"])
    connection = db.get_connection()
    try:
        gym_timezone = get_gym_timezone(connection, session["active_gym_id"])
        _require_gym_trainer(connection, session["active_gym_id"], fields["trainer_user_id"])
        timestamp = security.isoformat(security.now_utc())
        with connection:
            template_id = int(
                connection.execute(
                    """
                    insert into class_templates (
                      gym_id, title, class_type, weekdays, start_local_time, duration_minutes, capacity,
                      assigned_trainer_user_id, created_by_user_id, updated_by_user_id, created_at, updated_at
                    )
                    values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    returning id
                    """,
                    (
                        session["active_gym_id"],
                        fields["title"],
                        fields["class_type"],
                        schedule_service.encode_weekdays(fields["weekdays"]),
                        fields["start_local_time"],
                        fields["duration_minutes"],
                        fields["capacity"],
                        fields["trainer_user_id"],
                        session["user_id"],
                        session["user_id"],
                        timestamp,
                        timestamp,
                    ),
                ).fetchone()["id"]
            )
            row = schedule_service.get_class_template_row(connection, template_id)
            if row is None:
                raise HTTPException(status_code=HTTPStatus.INTERNAL_SERVER_ERROR.value, detail="Class creation failed.")
            schedule_service.materialize_template_sessions(connection, row, gym_timezone=gym_timezone)
            audit.write_audit_log(
                connection,
                gym_id=session["active_gym_id"],
                actor_user_id=session["user_id"],
                action="class_template_created",
                entity_type="class_template",
                entity_id=template_id,
                details=_class_template_audit_details(fields),
            )
        return {"template": schedule_service.class_template_payload(row)}
    finally:
        connection.close()


@router.patch("/schedule/templates")
def update_class_template(
    body: UpdateClassTemplateRequest,
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, Any]:
    template_id = validation.require_user_id(body.id)
    fields = _class_template_fields(body, session["active_gym_id"])
    connection = db.get_connection()
    try:
        existing = connection.execute(
            "select id from class_templates where id = ? and gym_id = ?",
            (template_id, session["active_gym_id"]),
        ).fetchone()
        if existing is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Class not found.")
        gym_timezone = get_gym_timezone(connection, session["active_gym_id"])
        _require_gym_trainer(connection, session["active_gym_id"], fields["trainer_user_id"])
        with connection:
            connection.execute(
                """
                update class_templates
                set title = ?, class_type = ?, weekdays = ?, start_local_time = ?, duration_minutes = ?,
                    capacity = ?, assigned_trainer_user_id = ?, updated_by_user_id = ?, updated_at = ?
                where id = ?
                """,
                (
                    fields["title"],
                    fields["class_type"],
                    schedule_service.encode_weekdays(fields["weekdays"]),
                    fields["start_local_time"],
                    fields["duration_minutes"],
                    fields["capacity"],
                    fields["trainer_user_id"],
                    session["user_id"],
                    security.isoformat(security.now_utc()),
                    template_id,
                ),
            )
            row = schedule_service.get_class_template_row(connection, template_id)
            if row is None:
                raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Class not found.")
            detached_count = schedule_service.resync_template_sessions(
                connection,
                row,
                gym_timezone=gym_timezone,
                actor_user_id=session["user_id"],
            )
            audit.write_audit_log(
                connection,
                gym_id=session["active_gym_id"],
                actor_user_id=session["user_id"],
                action="class_template_updated",
                entity_type="class_template",
                entity_id=template_id,
                details={**_class_template_audit_details(fields), "detached_booked_sessions": detached_count},
            )
        return {
            "template": schedule_service.class_template_payload(row),
            "kept_booked_sessions": detached_count,
        }
    finally:
        connection.close()


@router.delete("/schedule/templates")
def delete_class_template(
    body: EntityIdRequest,
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, Any]:
    template_id = body.id
    connection = db.get_connection()
    try:
        existing = connection.execute(
            "select id, title from class_templates where id = ? and gym_id = ?",
            (template_id, session["active_gym_id"]),
        ).fetchone()
        if existing is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Class not found.")
        with connection:
            kept_count = schedule_service.remove_template_sessions(connection, template_id)
            connection.execute("delete from class_templates where id = ?", (template_id,))
            audit.write_audit_log(
                connection,
                gym_id=session["active_gym_id"],
                actor_user_id=session["user_id"],
                action="class_template_deleted",
                entity_type="class_template",
                entity_id=template_id,
                details={"title": existing["title"], "kept_booked_sessions": kept_count},
            )
        return {"deleted": True, "kept_booked_sessions": kept_count}
    finally:
        connection.close()


@router.get("/schedule/trainers")
def list_schedule_trainers(
    session: dict[str, Any] = Depends(require_schedule_manager_session),
) -> dict[str, list[dict[str, Any]]]:
    connection = db.get_connection()
    try:
        rows = connection.execute(
            """
            select users.id, users.display_name, users.nickname
            from gym_memberships
            join users on users.id = gym_memberships.user_id
            where gym_memberships.gym_id = ?
              and gym_memberships.status = 'active'
              and gym_memberships.active_role = 'trainer'
              and users.deleted_at is null
            order by lower(coalesce(nullif(users.display_name, ''), users.email)) asc
            """,
            (session["active_gym_id"],),
        ).fetchall()
        return {
            "trainers": [
                {
                    "id": row["id"],
                    "display_name": row["display_name"],
                    "nickname": row["nickname"],
                }
                for row in rows
            ]
        }
    finally:
        connection.close()


@router.post("/schedule/classes", status_code=HTTPStatus.CREATED.value)
def create_schedule_class(
    body: ScheduleClassRequest,
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, Any]:
    title = validators.require_schedule_title(body.title)
    class_type = validators.require_class_type(body.class_type, class_type_names(session["active_gym_id"]))
    start_time = validators.require_future_datetime(body.start_time, label="Start time")
    duration_minutes = validators.require_schedule_duration_minutes(body.model_dump())
    capacity = validators.require_capacity(body.capacity)
    trainer_user_id = validators.require_optional_user_id(body.trainer_user_id)
    recurrence_frequency = validators.require_recurrence_frequency(body.recurrence_frequency)
    occurrence_count = validators.require_occurrence_count(
        body.occurrence_count,
        recurrence_frequency=recurrence_frequency,
    )
    connection = db.get_connection()
    try:
        gym_row = connection.execute(
            "select timezone from gyms where id = ?",
            (session["active_gym_id"],),
        ).fetchone()
        if gym_row is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Active gym not found.")
        start_times = schedule_service.build_recurrence_start_times(
            start_time,
            recurrence_frequency=recurrence_frequency,
            occurrence_count=occurrence_count,
            gym_timezone=gym_row["timezone"],
        )
        if recurrence_frequency != "none":
            for generated_start_time in start_times:
                if generated_start_time <= security.now_utc():
                    raise HTTPException(
                        status_code=HTTPStatus.BAD_REQUEST.value,
                        detail="Recurring classes must all be scheduled in the future.",
                    )
        _require_gym_trainer(connection, session["active_gym_id"], trainer_user_id)
        timestamp = security.isoformat(security.now_utc())
        with connection:
            schedule_ids: list[int] = []
            for generated_start_time in start_times:
                generated_end_time = generated_start_time + timedelta(minutes=duration_minutes)
                cursor = connection.execute(
                    """
                    insert into class_schedules (
                      gym_id, title, class_type, start_time, end_time, duration_minutes, capacity, assigned_trainer_user_id,
                      created_by_user_id, updated_by_user_id, created_at, updated_at
                    )
                    values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    returning id
                    """,
                    (
                        session["active_gym_id"],
                        title,
                        class_type,
                        security.isoformat(generated_start_time),
                        security.isoformat(generated_end_time),
                        duration_minutes,
                        capacity,
                        trainer_user_id,
                        session["user_id"],
                        session["user_id"],
                        timestamp,
                        timestamp,
                    ),
                )
                schedule_id = int(cursor.fetchone()["id"])
                schedule_ids.append(schedule_id)
            payloads = []
            for schedule_id in schedule_ids:
                row = schedule_service.get_schedule_class_row(connection, schedule_id)
                if row is None:
                    raise HTTPException(status_code=HTTPStatus.INTERNAL_SERVER_ERROR.value, detail="Schedule class creation failed.")
                payloads.append(
                    schedule_service.schedule_class_payload(
                        connection,
                        row,
                        current_user_id=session["user_id"],
                        include_bookings=session["role"] in {"admin", "trainer"},
                    )
                )
            for schedule_id, generated_start_time in zip(schedule_ids, start_times, strict=True):
                audit.write_audit_log(
                    connection,
                    gym_id=session["active_gym_id"],
                    actor_user_id=session["user_id"],
                    action="schedule_class_created",
                    entity_type="schedule_class",
                    entity_id=schedule_id,
                    details={
                        "title": title,
                        "class_type": class_type,
                        "start_time": security.isoformat(generated_start_time),
                        "duration_minutes": duration_minutes,
                        "capacity": capacity,
                        "trainer_user_id": trainer_user_id,
                        "recurrence_frequency": recurrence_frequency,
                        "occurrence_count": occurrence_count,
                    },
                )
        return {"class": payloads[0], "classes": payloads, "created_count": len(payloads)}
    finally:
        connection.close()


@router.patch("/schedule/classes")
def update_schedule_class(
    body: UpdateScheduleClassRequest,
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, Any]:
    schedule_id = validation.require_user_id(body.id)
    title = validators.require_schedule_title(body.title)
    class_type = validators.require_class_type(body.class_type, class_type_names(session["active_gym_id"]))
    start_time = validators.require_future_datetime(body.start_time, label="Start time")
    duration_minutes = validators.require_schedule_duration_minutes(body.model_dump())
    capacity = validators.require_capacity(body.capacity)
    trainer_user_id = validators.require_optional_user_id(body.trainer_user_id)
    end_time = start_time + timedelta(minutes=duration_minutes)
    connection = db.get_connection()
    try:
        existing = connection.execute(
            "select id, start_time from class_schedules where id = ? and gym_id = ?",
            (schedule_id, session["active_gym_id"]),
        ).fetchone()
        if existing is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Schedule class not found.")
        if security.parse_iso(existing["start_time"]) <= security.now_utc():
            raise HTTPException(status_code=HTTPStatus.BAD_REQUEST.value, detail="Only future classes can be edited.")
        booked_count_row = connection.execute(
            "select count(*) as booked_count from class_bookings where class_schedule_id = ?",
            (schedule_id,),
        ).fetchone()
        booked_count = int(booked_count_row["booked_count"]) if booked_count_row is not None else 0
        if capacity < booked_count:
            raise HTTPException(status_code=HTTPStatus.BAD_REQUEST.value, detail="Capacity cannot be lower than the current booking count.")
        _require_gym_trainer(connection, session["active_gym_id"], trainer_user_id)
        affected_user_rows = connection.execute(
            """
            select user_id from class_bookings where class_schedule_id = ?
            union
            select user_id from class_waitlist_entries where class_schedule_id = ?
            """,
            (schedule_id, schedule_id),
        ).fetchall()
        with connection:
            connection.execute(
                """
                update class_schedules
                set title = ?, class_type = ?, start_time = ?, end_time = ?, duration_minutes = ?, capacity = ?,
                    assigned_trainer_user_id = ?, updated_by_user_id = ?, updated_at = ?
                where id = ?
                """,
                (
                    title,
                    class_type,
                    security.isoformat(start_time),
                    security.isoformat(end_time),
                    duration_minutes,
                    capacity,
                    trainer_user_id,
                    session["user_id"],
                    security.isoformat(security.now_utc()),
                    schedule_id,
                ),
            )
            row = schedule_service.get_schedule_class_row(connection, schedule_id)
            if row is None:
                raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Schedule class not found.")
            payload = schedule_service.schedule_class_payload(
                connection,
                row,
                current_user_id=session["user_id"],
                include_bookings=session["role"] in {"admin", "trainer"},
            )
            audit.write_audit_log(
                connection,
                gym_id=session["active_gym_id"],
                actor_user_id=session["user_id"],
                action="schedule_class_updated",
                entity_type="schedule_class",
                entity_id=schedule_id,
                details={
                    "title": title,
                    "class_type": class_type,
                    "start_time": security.isoformat(start_time),
                    "duration_minutes": duration_minutes,
                    "capacity": capacity,
                    "trainer_user_id": trainer_user_id,
                },
            )
            schedule_service.create_schedule_update_notifications(
                connection,
                gym_id=session["active_gym_id"],
                class_schedule_id=schedule_id,
                user_ids=[int(user["user_id"]) for user in affected_user_rows if int(user["user_id"]) != session["user_id"]],
            )
        return {"class": payload}
    finally:
        connection.close()


@router.delete("/schedule/classes")
def delete_schedule_class(
    body: ScheduleClassDeleteRequest,
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, bool | str]:
    schedule_id = body.id
    connection = db.get_connection()
    try:
        existing = connection.execute(
            "select id, start_time from class_schedules where id = ? and gym_id = ?",
            (schedule_id, session["active_gym_id"]),
        ).fetchone()
        if existing is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Schedule class not found.")
        if security.parse_iso(existing["start_time"]) <= security.now_utc():
            raise HTTPException(status_code=HTTPStatus.BAD_REQUEST.value, detail="Only future classes can be deleted.")
        with connection:
            connection.execute("delete from class_schedules where id = ?", (schedule_id,))
            audit.write_audit_log(
                connection,
                gym_id=session["active_gym_id"],
                actor_user_id=session["user_id"],
                action="schedule_class_deleted",
                entity_type="schedule_class",
                entity_id=schedule_id,
            )
        return {"message": "Schedule class deleted."}
    finally:
        connection.close()


@router.post("/schedule/bookings", status_code=HTTPStatus.CREATED.value)
def create_class_booking(
    body: ClassIdRequest,
    session: dict[str, Any] = Depends(require_active_gym_member_session),
) -> dict[str, str]:
    schedule_id = body.class_id
    connection = db.get_connection()
    try:
        schedule_row = connection.execute(
            "select id, gym_id, class_type, start_time, capacity from class_schedules where id = ? and gym_id = ?",
            (schedule_id, session["active_gym_id"]),
        ).fetchone()
        if schedule_row is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Schedule class not found.")
        if security.parse_iso(schedule_row["start_time"]) <= security.now_utc():
            raise HTTPException(status_code=HTTPStatus.BAD_REQUEST.value, detail="Only future classes can be booked.")
        existing_booking = connection.execute(
            "select id from class_bookings where class_schedule_id = ? and user_id = ?",
            (schedule_id, session["user_id"]),
        ).fetchone()
        if existing_booking is not None:
            raise HTTPException(status_code=HTTPStatus.CONFLICT.value, detail="You have already booked this class.")
        booking_count_row = connection.execute(
            "select count(*) as booked_count from class_bookings where class_schedule_id = ?",
            (schedule_id,),
        ).fetchone()
        booked_count = int(booking_count_row["booked_count"]) if booking_count_row is not None else 0
        if booked_count >= schedule_row["capacity"]:
            raise HTTPException(status_code=HTTPStatus.CONFLICT.value, detail="This class is already full.")
        check = plan_service.require_booking_allowed(
            connection,
            gym_id=schedule_row["gym_id"],
            user_id=session["user_id"],
            schedule_row=schedule_row,
        )
        with connection:
            connection.execute(
                """
                insert into class_bookings
                  (class_schedule_id, user_id, attendance_status, member_plan_id, token_credit_id, created_at)
                values (?, ?, 'booked', ?, ?, ?)
                """,
                (
                    schedule_id,
                    session["user_id"],
                    check.member_plan_id,
                    check.token_credit_id,
                    security.isoformat(security.now_utc()),
                ),
            )
            schedule_service.create_booking_confirmation_notification(
                connection,
                user_id=session["user_id"],
                gym_id=schedule_row["gym_id"],
                class_schedule_id=schedule_id,
            )
        return {"message": "Class booked."}
    finally:
        connection.close()


class CancelBookingRequest(BaseModel):
    class_id: int
    # The owner removes someone else's booking (e.g. they called to
    # cancel); members always cancel their own.
    user_id: int | None = None


@router.delete("/schedule/bookings")
def delete_class_booking(
    body: CancelBookingRequest,
    session: dict[str, Any] = Depends(require_active_gym_member_session),
) -> dict[str, str]:
    schedule_id = body.class_id
    user_id = session["user_id"] if body.user_id is None else body.user_id
    removing_other = user_id != session["user_id"]
    # Only the owner takes members off a class; trainers keep attendance.
    if removing_other and session["role"] != "admin":
        raise HTTPException(
            status_code=HTTPStatus.FORBIDDEN.value,
            detail="The owner role is required for this action.",
        )
    connection = db.get_connection()
    try:
        schedule_row = connection.execute(
            "select id, gym_id, start_time from class_schedules where id = ? and gym_id = ?",
            (schedule_id, session["active_gym_id"]),
        ).fetchone()
        if schedule_row is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Schedule class not found.")
        if security.parse_iso(schedule_row["start_time"]) <= security.now_utc():
            raise HTTPException(status_code=HTTPStatus.BAD_REQUEST.value, detail="Only future classes can be cancelled.")
        existing_booking = connection.execute(
            "select id from class_bookings where class_schedule_id = ? and user_id = ?",
            (schedule_id, user_id),
        ).fetchone()
        if existing_booking is None:
            raise HTTPException(
                status_code=HTTPStatus.NOT_FOUND.value,
                detail="This member has no booking for this class."
                if removing_other
                else "You do not have a booking for this class.",
            )
        with connection:
            connection.execute(
                "delete from class_bookings where class_schedule_id = ? and user_id = ?",
                (schedule_id, user_id),
            )
            connection.execute(
                """
                insert into class_booking_cancellations (class_schedule_id, user_id, cancelled_at, cancelled_by_user_id)
                values (?, ?, ?, ?)
                """,
                (schedule_id, user_id, security.isoformat(security.now_utc()), session["user_id"]),
            )
            promoted_user_id = plan_service.promote_next_eligible_waitlisted_user(connection, class_schedule_id=schedule_id)
            if promoted_user_id is not None:
                schedule_service.create_waitlist_promotion_notification(
                    connection,
                    user_id=promoted_user_id,
                    gym_id=schedule_row["gym_id"],
                    class_schedule_id=schedule_id,
                )
        return {"message": "Booking cancelled."}
    finally:
        connection.close()


@router.post("/schedule/waitlist", status_code=HTTPStatus.CREATED.value)
def create_class_waitlist(
    body: ClassIdRequest,
    session: dict[str, Any] = Depends(require_active_gym_member_session),
) -> dict[str, str]:
    schedule_id = body.class_id
    connection = db.get_connection()
    try:
        schedule_row = connection.execute(
            "select id, gym_id, class_type, start_time, capacity from class_schedules where id = ? and gym_id = ?",
            (schedule_id, session["active_gym_id"]),
        ).fetchone()
        if schedule_row is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Schedule class not found.")
        if security.parse_iso(schedule_row["start_time"]) <= security.now_utc():
            raise HTTPException(status_code=HTTPStatus.BAD_REQUEST.value, detail="Only future classes can be waitlisted.")
        existing_booking = connection.execute(
            "select id from class_bookings where class_schedule_id = ? and user_id = ?",
            (schedule_id, session["user_id"]),
        ).fetchone()
        if existing_booking is not None:
            raise HTTPException(status_code=HTTPStatus.CONFLICT.value, detail="You have already booked this class.")
        existing_waitlist = connection.execute(
            "select id from class_waitlist_entries where class_schedule_id = ? and user_id = ?",
            (schedule_id, session["user_id"]),
        ).fetchone()
        if existing_waitlist is not None:
            raise HTTPException(status_code=HTTPStatus.CONFLICT.value, detail="You are already on the waitlist for this class.")
        booking_count_row = connection.execute(
            "select count(*) as booked_count from class_bookings where class_schedule_id = ?",
            (schedule_id,),
        ).fetchone()
        booked_count = int(booking_count_row["booked_count"]) if booking_count_row is not None else 0
        if booked_count < schedule_row["capacity"]:
            raise HTTPException(status_code=HTTPStatus.CONFLICT.value, detail="This class still has open spots.")
        plan_service.require_booking_allowed(
            connection,
            gym_id=schedule_row["gym_id"],
            user_id=session["user_id"],
            schedule_row=schedule_row,
        )
        with connection:
            connection.execute(
                "insert into class_waitlist_entries (class_schedule_id, user_id, created_at) values (?, ?, ?)",
                (schedule_id, session["user_id"], security.isoformat(security.now_utc())),
            )
        return {"message": "Added to waitlist."}
    finally:
        connection.close()


@router.delete("/schedule/waitlist")
def delete_class_waitlist(
    body: ClassIdRequest,
    session: dict[str, Any] = Depends(require_active_gym_member_session),
) -> dict[str, str]:
    schedule_id = body.class_id
    connection = db.get_connection()
    try:
        schedule_row = connection.execute(
            "select id from class_schedules where id = ? and gym_id = ?",
            (schedule_id, session["active_gym_id"]),
        ).fetchone()
        if schedule_row is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Schedule class not found.")
        existing_waitlist = connection.execute(
            "select id from class_waitlist_entries where class_schedule_id = ? and user_id = ?",
            (schedule_id, session["user_id"]),
        ).fetchone()
        if existing_waitlist is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="You are not on the waitlist for this class.")
        with connection:
            connection.execute(
                "delete from class_waitlist_entries where class_schedule_id = ? and user_id = ?",
                (schedule_id, session["user_id"]),
            )
        return {"message": "Removed from waitlist."}
    finally:
        connection.close()


@router.patch("/schedule/bookings/attendance")
def update_class_attendance(
    body: UpdateAttendanceRequest,
    session: dict[str, Any] = Depends(require_schedule_manager_session),
) -> dict[str, Any]:
    schedule_id = validation.require_user_id(body.class_id)
    user_id = validation.require_user_id(body.user_id)
    attendance_status = validators.require_attendance_status(body.attendance_status)
    connection = db.get_connection()
    try:
        schedule_row = connection.execute(
            "select id, start_time from class_schedules where id = ? and gym_id = ?",
            (schedule_id, session["active_gym_id"]),
        ).fetchone()
        if schedule_row is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Schedule class not found.")
        if security.parse_iso(schedule_row["start_time"]) > security.now_utc():
            raise HTTPException(status_code=HTTPStatus.BAD_REQUEST.value, detail="Attendance can only be recorded after the class has started.")
        booking_row = connection.execute(
            "select id from class_bookings where class_schedule_id = ? and user_id = ?",
            (schedule_id, user_id),
        ).fetchone()
        if booking_row is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="That athlete does not have a booking for this class.")
        with connection:
            connection.execute(
                """
                update class_bookings
                set attendance_status = ?, attendance_marked_at = ?, attendance_marked_by_user_id = ?
                where class_schedule_id = ? and user_id = ?
                """,
                (attendance_status, security.isoformat(security.now_utc()), session["user_id"], schedule_id, user_id),
            )
            row = schedule_service.get_schedule_class_row(connection, schedule_id)
            if row is None:
                raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Schedule class not found.")
            payload = schedule_service.schedule_class_payload(
                connection,
                row,
                current_user_id=session["user_id"],
                include_bookings=True,
            )
        return {"class": payload}
    finally:
        connection.close()


class NewClassTypeRequest(BaseModel):
    name: str
    color: str = "info"
    default_capacity: int = 12


def _class_type_rows(connection: Any, gym_id: int) -> list[dict[str, Any]]:
    rows = connection.execute(
        "select id, name, color, default_capacity from gym_class_types where gym_id = ? order by created_at, id",
        (gym_id,),
    ).fetchall()
    return [dict(row) for row in rows]


@router.get("/class-types")
def list_class_types(session: dict[str, Any] = Depends(require_active_gym_member_session)) -> dict[str, Any]:
    """The gym's own class types; the four built-ins are fixed in the app."""
    connection = db.get_connection()
    try:
        return {"class_types": _class_type_rows(connection, session["active_gym_id"])}
    finally:
        connection.close()


@router.post("/class-types", status_code=HTTPStatus.CREATED.value)
def create_class_type(
    body: NewClassTypeRequest,
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, Any]:
    gym_id = session["active_gym_id"]
    fields = validators.require_new_class_type(body.model_dump(), class_type_names(gym_id))
    connection = db.get_connection()
    try:
        with connection:
            connection.execute(
                "insert into gym_class_types (gym_id, name, color, default_capacity, created_at) values (?, ?, ?, ?, ?)",
                (gym_id, fields["name"], fields["color"], fields["default_capacity"], security.isoformat(security.now_utc())),
            )
        return {"class_types": _class_type_rows(connection, gym_id)}
    finally:
        connection.close()


class ClassTypeIdRequest(BaseModel):
    id: int


@router.delete("/class-types")
def delete_class_type(
    body: ClassTypeIdRequest,
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, Any]:
    """Removes a custom type from the pickers. Classes and plans that use it
    keep its name."""
    gym_id = session["active_gym_id"]
    connection = db.get_connection()
    try:
        with connection:
            deleted = connection.execute(
                "delete from gym_class_types where id = ? and gym_id = ? returning id",
                (body.id, gym_id),
            ).fetchone()
        if deleted is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Class type not found.")
        return {"class_types": _class_type_rows(connection, gym_id)}
    finally:
        connection.close()
