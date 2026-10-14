from __future__ import annotations

import sqlite3
from datetime import UTC, date, datetime, time, timedelta
from http import HTTPStatus
from typing import Any
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from backend import settings
from backend.notifications_core import class_schedule_summary, create_notification
from backend.security import isoformat, now_utc, parse_iso
from backend.validation import ApiError, recurrence_delta_for


def schedule_booking_payload(row: sqlite3.Row, *, current_user_id: int) -> dict[str, Any]:
    return {
        "user_id": row["user_id"],
        "display_name": row["display_name"],
        "nickname": row["nickname"],
        "attendance_status": row["attendance_status"],
        "is_current_user": row["user_id"] == current_user_id,
    }


def schedule_class_payload(
    connection: sqlite3.Connection,
    row: sqlite3.Row,
    *,
    current_user_id: int,
    include_bookings: bool,
) -> dict[str, Any]:
    booking_rows = connection.execute(
        """
        select
          class_bookings.user_id,
          users.display_name,
          users.nickname,
          class_bookings.attendance_status
        from class_bookings
        join users on users.id = class_bookings.user_id
        where class_bookings.class_schedule_id = ?
        order by users.display_name asc, users.email asc
        """,
        (row["id"],),
    ).fetchall()
    booked_count = len(booking_rows)
    current_user_booking = next(
        (booking for booking in booking_rows if booking["user_id"] == current_user_id),
        None,
    )
    waitlist_rows = connection.execute(
        """
        select user_id
        from class_waitlist_entries
        where class_schedule_id = ?
        order by created_at asc, id asc
        """,
        (row["id"],),
    ).fetchall()
    current_user_waitlist = next(
        (entry for entry in waitlist_rows if entry["user_id"] == current_user_id),
        None,
    )
    capacity = row["capacity"]
    return {
        "id": row["id"],
        "gym_id": row["gym_id"],
        "title": row["title"],
        "class_type": row["class_type"],
        "class_template_id": row["class_template_id"],
        "start_time": row["start_time"],
        "end_time": row["end_time"],
        "duration_minutes": row["duration_minutes"],
        "capacity": capacity,
        "assigned_trainer": (
            {
                "id": row["assigned_trainer_user_id"],
                "display_name": row["assigned_trainer_display_name"],
                "nickname": row["assigned_trainer_nickname"],
            }
            if row["assigned_trainer_user_id"] is not None
            else None
        ),
        "booked_count": booked_count,
        "remaining_spots": max(capacity - booked_count, 0),
        "waitlist_count": len(waitlist_rows),
        "is_booked": current_user_booking is not None,
        "is_waitlisted": current_user_waitlist is not None,
        "attendance_status": (
            current_user_booking["attendance_status"] if current_user_booking is not None else None
        ),
        "bookings": [
            schedule_booking_payload(booking, current_user_id=current_user_id)
            for booking in booking_rows
        ] if include_bookings else [],
    }


def create_booking_confirmation_notification(
    connection: sqlite3.Connection,
    *,
    user_id: int,
    gym_id: int,
    class_schedule_id: int,
) -> None:
    user = connection.execute(
        "select notify_booking_confirmations from users where id = ? and deleted_at is null",
        (user_id,),
    ).fetchone()
    schedule_row = class_schedule_summary(connection, class_schedule_id=class_schedule_id)
    if user is None or schedule_row is None or not bool(user["notify_booking_confirmations"]):
        return
    create_notification(
        connection,
        user_id=user_id,
        gym_id=gym_id,
        type="booking_confirmed",
        title="Booking confirmed",
        body=f"{schedule_row['title']} at {schedule_row['start_time']}",
        entity_type="schedule_class",
        entity_id=class_schedule_id,
    )


def promote_next_waitlisted_user(
    connection: sqlite3.Connection,
    *,
    class_schedule_id: int,
) -> int | None:
    next_waitlist_entry = connection.execute(
        """
        select id, user_id
        from class_waitlist_entries
        where class_schedule_id = ?
        order by created_at asc, id asc
        limit 1
        """,
        (class_schedule_id,),
    ).fetchone()
    if next_waitlist_entry is None:
        return None
    connection.execute("delete from class_waitlist_entries where id = ?", (next_waitlist_entry["id"],))
    connection.execute(
        """
        insert into class_bookings (
          class_schedule_id, user_id, attendance_status, created_at
        )
        values (?, ?, 'booked', ?)
        """,
        (class_schedule_id, next_waitlist_entry["user_id"], isoformat(now_utc())),
    )
    return int(next_waitlist_entry["user_id"])


def create_waitlist_promotion_notification(
    connection: sqlite3.Connection,
    *,
    user_id: int,
    gym_id: int,
    class_schedule_id: int,
) -> None:
    user = connection.execute(
        "select notify_waitlist_promotions from users where id = ? and deleted_at is null",
        (user_id,),
    ).fetchone()
    schedule_row = class_schedule_summary(connection, class_schedule_id=class_schedule_id)
    if user is None or schedule_row is None or not bool(user["notify_waitlist_promotions"]):
        return
    create_notification(
        connection,
        user_id=user_id,
        gym_id=gym_id,
        type="waitlist_promoted",
        title="You are in the class",
        body=f"{schedule_row['title']} at {schedule_row['start_time']}",
        entity_type="schedule_class",
        entity_id=class_schedule_id,
    )


def create_schedule_update_notifications(
    connection: sqlite3.Connection,
    *,
    gym_id: int,
    class_schedule_id: int,
    user_ids: list[int],
) -> None:
    schedule_row = class_schedule_summary(connection, class_schedule_id=class_schedule_id)
    if schedule_row is None:
        return
    seen_user_ids: set[int] = set()
    for user_id in user_ids:
        if user_id in seen_user_ids:
            continue
        seen_user_ids.add(user_id)
        user = connection.execute(
            "select notify_booking_confirmations from users where id = ? and deleted_at is null",
            (user_id,),
        ).fetchone()
        if user is None or not bool(user["notify_booking_confirmations"]):
            continue
        create_notification(
            connection,
            user_id=user_id,
            gym_id=gym_id,
            type="schedule_updated",
            title="Class updated",
            body=f"{schedule_row['title']} now starts at {schedule_row['start_time']}",
            entity_type="schedule_class",
            entity_id=class_schedule_id,
        )


def build_recurrence_start_times(
    start_time: datetime,
    *,
    recurrence_frequency: str,
    occurrence_count: int,
    gym_timezone: str,
) -> list[datetime]:
    if recurrence_frequency == "none":
        return [start_time]
    recurrence_delta = recurrence_delta_for(recurrence_frequency)
    timezone = timezone_for_name(gym_timezone)
    if timezone is not None:
        local_start_time = start_time.astimezone(timezone)
        local_start_naive = local_start_time.replace(tzinfo=None)
        return [
            (local_start_naive + (recurrence_delta * index)).replace(tzinfo=timezone).astimezone(UTC)
            for index in range(occurrence_count)
        ]
    local_start_naive = manual_local_datetime_for_utc(start_time, gym_timezone)
    return [manual_utc_datetime_for_local(local_start_naive + (recurrence_delta * index), gym_timezone) for index in range(occurrence_count)]


def timezone_for_name(gym_timezone: str) -> Any | None:
    try:
        return ZoneInfo(gym_timezone)
    except ZoneInfoNotFoundError:
        if settings.dateutil_tz is not None:
            timezone = settings.dateutil_tz.gettz(gym_timezone)
            if timezone is not None:
                return timezone
        if settings.pytz is not None:
            try:
                return settings.pytz.timezone(gym_timezone)
            except settings.pytz.UnknownTimeZoneError:
                pass
        if gym_timezone in {"UTC", "Europe/Berlin", "America/New_York"}:
            return None
        raise ApiError(HTTPStatus.BAD_REQUEST, "Gym timezone is invalid.")


def manual_local_datetime_for_utc(utc_datetime: datetime, gym_timezone: str) -> datetime:
    utc_naive = utc_datetime.astimezone(UTC).replace(tzinfo=None)
    return utc_naive + manual_utc_offset_for_utc_datetime(utc_naive, gym_timezone)


def manual_utc_datetime_for_local(local_datetime: datetime, gym_timezone: str) -> datetime:
    offset = manual_utc_offset_for_local_datetime(local_datetime, gym_timezone)
    return (local_datetime - offset).replace(tzinfo=UTC)


def manual_utc_offset_for_utc_datetime(utc_datetime: datetime, gym_timezone: str) -> timedelta:
    if gym_timezone == "UTC":
        return timedelta(0)
    if gym_timezone == "Europe/Berlin":
        dst_start = datetime.combine(last_weekday_of_month(utc_datetime.year, 3, 6), datetime.min.time()) + timedelta(hours=1)
        dst_end = datetime.combine(last_weekday_of_month(utc_datetime.year, 10, 6), datetime.min.time()) + timedelta(hours=1)
        return timedelta(hours=2 if dst_start <= utc_datetime < dst_end else 1)
    if gym_timezone == "America/New_York":
        dst_start = datetime.combine(nth_weekday_of_month(utc_datetime.year, 3, 6, 2), datetime.min.time()) + timedelta(hours=7)
        dst_end = datetime.combine(nth_weekday_of_month(utc_datetime.year, 11, 6, 1), datetime.min.time()) + timedelta(hours=6)
        return timedelta(hours=-4 if dst_start <= utc_datetime < dst_end else -5)
    raise ApiError(HTTPStatus.BAD_REQUEST, "Gym timezone is invalid.")


def manual_utc_offset_for_local_datetime(local_datetime: datetime, gym_timezone: str) -> timedelta:
    if gym_timezone == "UTC":
        return timedelta(0)
    if gym_timezone == "Europe/Berlin":
        dst_start = datetime.combine(last_weekday_of_month(local_datetime.year, 3, 6), datetime.min.time()) + timedelta(hours=2)
        dst_end = datetime.combine(last_weekday_of_month(local_datetime.year, 10, 6), datetime.min.time()) + timedelta(hours=3)
        return timedelta(hours=2 if dst_start <= local_datetime < dst_end else 1)
    if gym_timezone == "America/New_York":
        dst_start = datetime.combine(nth_weekday_of_month(local_datetime.year, 3, 6, 2), datetime.min.time()) + timedelta(hours=2)
        dst_end = datetime.combine(nth_weekday_of_month(local_datetime.year, 11, 6, 1), datetime.min.time()) + timedelta(hours=2)
        return timedelta(hours=-4 if dst_start <= local_datetime < dst_end else -5)
    raise ApiError(HTTPStatus.BAD_REQUEST, "Gym timezone is invalid.")


def nth_weekday_of_month(year: int, month: int, weekday: int, occurrence: int) -> date:
    current = date(year, month, 1)
    while current.weekday() != weekday:
        current += timedelta(days=1)
    return current + timedelta(days=(occurrence - 1) * 7)


def last_weekday_of_month(year: int, month: int, weekday: int) -> date:
    if month == 12:
        current = date(year + 1, 1, 1) - timedelta(days=1)
    else:
        current = date(year, month + 1, 1) - timedelta(days=1)
    while current.weekday() != weekday:
        current -= timedelta(days=1)
    return current


def get_schedule_class_row(connection: sqlite3.Connection, schedule_id: int) -> sqlite3.Row | None:
    return connection.execute(
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
        where class_schedules.id = ?
        """,
        (schedule_id,),
    ).fetchone()


# --- Weekly class templates ------------------------------------------------
#
# A class template ("CrossFit, Mon–Fri 06:00") is created once; its bookable
# sessions are materialised into class_schedules on demand, a rolling
# TEMPLATE_HORIZON_DAYS ahead. `generated_until` records the last local date
# already materialised, so a session the owner deletes is not re-created.

TEMPLATE_HORIZON_DAYS = 56

CLASS_TEMPLATE_COLUMNS = """
          class_templates.id,
          class_templates.gym_id,
          class_templates.title,
          class_templates.class_type,
          class_templates.weekdays,
          class_templates.start_local_time,
          class_templates.duration_minutes,
          class_templates.capacity,
          class_templates.assigned_trainer_user_id,
          class_templates.generated_until,
          class_templates.updated_by_user_id,
          trainer.display_name as assigned_trainer_display_name,
          trainer.nickname as assigned_trainer_nickname
"""


def encode_weekdays(weekdays: list[int]) -> str:
    return ",".join(str(weekday) for weekday in weekdays)


def decode_weekdays(value: str) -> list[int]:
    return [int(part) for part in str(value or "").split(",") if part.strip()]


def class_template_payload(row: sqlite3.Row) -> dict[str, Any]:
    return {
        "id": row["id"],
        "gym_id": row["gym_id"],
        "title": row["title"],
        "class_type": row["class_type"],
        "weekdays": decode_weekdays(row["weekdays"]),
        "start_time": row["start_local_time"],
        "duration_minutes": row["duration_minutes"],
        "capacity": row["capacity"],
        "assigned_trainer": (
            {
                "id": row["assigned_trainer_user_id"],
                "display_name": row["assigned_trainer_display_name"],
                "nickname": row["assigned_trainer_nickname"],
            }
            if row["assigned_trainer_user_id"] is not None
            else None
        ),
    }


def get_class_template_row(connection: sqlite3.Connection, template_id: int) -> sqlite3.Row | None:
    return connection.execute(
        f"""
        select {CLASS_TEMPLATE_COLUMNS}
        from class_templates
        left join users trainer on trainer.id = class_templates.assigned_trainer_user_id
        where class_templates.id = ?
        """,
        (template_id,),
    ).fetchone()


def list_class_template_rows(connection: sqlite3.Connection, gym_id: int) -> list[sqlite3.Row]:
    return connection.execute(
        f"""
        select {CLASS_TEMPLATE_COLUMNS}
        from class_templates
        left join users trainer on trainer.id = class_templates.assigned_trainer_user_id
        where class_templates.gym_id = ?
        order by class_templates.start_local_time asc, class_templates.id asc
        """,
        (gym_id,),
    ).fetchall()


def local_today(gym_timezone: str) -> date:
    timezone = timezone_for_name(gym_timezone)
    if timezone is not None:
        return now_utc().astimezone(timezone).date()
    return manual_local_datetime_for_utc(now_utc(), gym_timezone).date()


def utc_for_local(local_datetime: datetime, gym_timezone: str) -> datetime:
    timezone = timezone_for_name(gym_timezone)
    if timezone is not None:
        return local_datetime.replace(tzinfo=timezone).astimezone(UTC)
    return manual_utc_datetime_for_local(local_datetime, gym_timezone)


def local_for_utc(utc_datetime: datetime, gym_timezone: str) -> datetime:
    timezone = timezone_for_name(gym_timezone)
    if timezone is not None:
        return utc_datetime.astimezone(timezone).replace(tzinfo=None)
    return manual_local_datetime_for_utc(utc_datetime, gym_timezone)


def _template_local_time(row: sqlite3.Row) -> time:
    hour, minute = (int(part) for part in str(row["start_local_time"]).split(":"))
    return time(hour, minute)


def materialize_template_sessions(
    connection: sqlite3.Connection,
    template: sqlite3.Row,
    *,
    gym_timezone: str,
) -> None:
    """Create the template's sessions up to the rolling horizon. Idempotent.

    Sessions are attributed to whoever last edited the template, not to the
    (possibly athlete) request that happened to trigger generation.
    """
    author_user_id = template["updated_by_user_id"]
    today = local_today(gym_timezone)
    horizon = today + timedelta(days=TEMPLATE_HORIZON_DAYS)
    generated_until = (
        date.fromisoformat(template["generated_until"])
        if template["generated_until"]
        else today - timedelta(days=1)
    )
    current = max(generated_until + timedelta(days=1), today)
    if current > horizon:
        return
    weekdays = set(decode_weekdays(template["weekdays"]))
    start_local_time = _template_local_time(template)
    duration = timedelta(minutes=int(template["duration_minutes"]))
    now = now_utc()
    timestamp = isoformat(now)
    while current <= horizon:
        if current.isoweekday() in weekdays:
            start_time = utc_for_local(datetime.combine(current, start_local_time), gym_timezone)
            if start_time > now:
                connection.execute(
                    """
                    insert into class_schedules (
                      gym_id, title, class_type, start_time, end_time, duration_minutes, capacity,
                      assigned_trainer_user_id, class_template_id, created_by_user_id, updated_by_user_id,
                      created_at, updated_at
                    )
                    values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    on conflict (class_template_id, start_time) do nothing
                    """,
                    (
                        template["gym_id"],
                        template["title"],
                        template["class_type"],
                        isoformat(start_time),
                        isoformat(start_time + duration),
                        template["duration_minutes"],
                        template["capacity"],
                        template["assigned_trainer_user_id"],
                        template["id"],
                        author_user_id,
                        author_user_id,
                        timestamp,
                        timestamp,
                    ),
                )
        current += timedelta(days=1)
    connection.execute(
        "update class_templates set generated_until = ? where id = ?",
        (horizon.isoformat(), template["id"]),
    )


def materialize_gym_sessions(
    connection: sqlite3.Connection,
    *,
    gym_id: int,
    gym_timezone: str,
) -> None:
    horizon = (local_today(gym_timezone) + timedelta(days=TEMPLATE_HORIZON_DAYS)).isoformat()
    for template in list_class_template_rows(connection, gym_id):
        if template["generated_until"] is not None and template["generated_until"] >= horizon:
            continue
        materialize_template_sessions(connection, template, gym_timezone=gym_timezone)


def _future_template_sessions(connection: sqlite3.Connection, template_id: int) -> list[sqlite3.Row]:
    return connection.execute(
        """
        select
          class_schedules.id,
          class_schedules.start_time,
          (
            select count(*) from class_bookings where class_bookings.class_schedule_id = class_schedules.id
          ) + (
            select count(*) from class_waitlist_entries where class_waitlist_entries.class_schedule_id = class_schedules.id
          ) as participant_count,
          (
            select count(*) from class_bookings where class_bookings.class_schedule_id = class_schedules.id
          ) as booked_count
        from class_schedules
        where class_schedules.class_template_id = ?
          and class_schedules.start_time > ?
        """,
        (template_id, isoformat(now_utc())),
    ).fetchall()


def resync_template_sessions(
    connection: sqlite3.Connection,
    template: sqlite3.Row,
    *,
    gym_timezone: str,
    actor_user_id: int,
) -> int:
    """Re-plan a template's future sessions after it was edited.

    Sessions nobody has booked are dropped and regenerated. Booked sessions are
    never moved: if they still match the new plan they take the new title, type,
    trainer, duration and capacity in place; otherwise they are detached and
    kept as one-off sessions. Returns how many booked sessions were detached.
    """
    weekdays = set(decode_weekdays(template["weekdays"]))
    start_local_time = _template_local_time(template)
    detached = 0
    timestamp = isoformat(now_utc())
    for session in _future_template_sessions(connection, int(template["id"])):
        if int(session["participant_count"]) == 0:
            connection.execute("delete from class_schedules where id = ?", (session["id"],))
            continue
        local_start = local_for_utc(parse_iso(session["start_time"]), gym_timezone)
        still_matches = local_start.isoweekday() in weekdays and local_start.time() == start_local_time
        if not still_matches:
            connection.execute(
                "update class_schedules set class_template_id = null, updated_at = ? where id = ?",
                (timestamp, session["id"]),
            )
            detached += 1
            continue
        start_time = parse_iso(session["start_time"])
        connection.execute(
            """
            update class_schedules
            set title = ?, class_type = ?, end_time = ?, duration_minutes = ?, capacity = ?,
                assigned_trainer_user_id = ?, updated_by_user_id = ?, updated_at = ?
            where id = ?
            """,
            (
                template["title"],
                template["class_type"],
                isoformat(start_time + timedelta(minutes=int(template["duration_minutes"]))),
                template["duration_minutes"],
                max(int(template["capacity"]), int(session["booked_count"])),
                template["assigned_trainer_user_id"],
                actor_user_id,
                timestamp,
                session["id"],
            ),
        )
    connection.execute("update class_templates set generated_until = null where id = ?", (template["id"],))
    refreshed = get_class_template_row(connection, int(template["id"]))
    if refreshed is not None:
        materialize_template_sessions(connection, refreshed, gym_timezone=gym_timezone)
    return detached


def remove_template_sessions(connection: sqlite3.Connection, template_id: int) -> int:
    """Drop the template's unbooked future sessions; booked ones stay as one-offs.

    Returns how many booked sessions were kept (they are detached when the
    template row is deleted, via `on delete set null`).
    """
    kept = 0
    for session in _future_template_sessions(connection, template_id):
        if int(session["participant_count"]) == 0:
            connection.execute("delete from class_schedules where id = ?", (session["id"],))
        else:
            kept += 1
    return kept
