from __future__ import annotations

from datetime import date, datetime, timedelta
from typing import Any

from fastapi import APIRouter, Depends

from backend.api.common import get_gym_timezone
from backend.api.deps import require_admin_gym_session
from backend.core import db, security, validation
from backend.services import programming_service, schedule_service

router = APIRouter()


@router.get("/audit-logs")
def list_audit_logs(session: dict[str, Any] = Depends(require_admin_gym_session)) -> dict[str, Any]:
    connection = db.get_connection()
    try:
        rows = connection.execute(
            """
            select
              audit_logs.id,
              audit_logs.action,
              audit_logs.entity_type,
              audit_logs.entity_id,
              audit_logs.details_json,
              audit_logs.created_at,
              actor.email as actor_email,
              actor.display_name as actor_display_name,
              actor.nickname as actor_nickname,
              target.email as target_email,
              target.display_name as target_display_name,
              target.nickname as target_nickname
            from audit_logs
            join users actor on actor.id = audit_logs.actor_user_id
            left join users target on target.id = audit_logs.target_user_id
            where audit_logs.gym_id = ?
            order by audit_logs.created_at desc, audit_logs.id desc
            limit 100
            """,
            (session["active_gym_id"],),
        ).fetchall()
        return {"logs": [programming_service.audit_log_payload(row) for row in rows]}
    finally:
        connection.close()


@router.get("/admin/analytics")
def admin_analytics_overview(
    window_days: int = 14,
    session: dict[str, Any] = Depends(require_admin_gym_session),
) -> dict[str, Any]:
    validated_window_days = programming_service.require_admin_analytics_window_days(window_days)
    connection = db.get_connection()
    try:
        gym_id = session["active_gym_id"]
        today = programming_service.today_utc_date()
        window_start = today - timedelta(days=validated_window_days - 1)
        upcoming_end = today + timedelta(days=6)

        active_memberships = connection.execute(
            """
            select
              gym_memberships.id,
              gym_memberships.user_id,
              gym_memberships.active_role,
              gym_memberships.roles_json,
              gym_memberships.status,
              gym_memberships.created_at,
              users.email,
              users.display_name,
              users.nickname
            from gym_memberships
            join users on users.id = gym_memberships.user_id
            where gym_memberships.gym_id = ?
            order by gym_memberships.created_at desc, gym_memberships.id desc
            """,
            (gym_id,),
        ).fetchall()
        active_members_rows = [row for row in active_memberships if row["status"] == "active"]
        active_members_count = len(active_members_rows)
        trainer_members_count = sum(1 for row in active_members_rows if row["active_role"] == "trainer")
        pending_join_requests_row = connection.execute(
            "select count(*) as count from gym_join_requests where gym_id = ? and status = 'pending'",
            (gym_id,),
        ).fetchone()

        new_members_in_window = 0
        role_mix = {"athlete_only": 0, "trainer_capable": 0, "admin_capable": 0}
        recent_members = []
        for row in active_members_rows:
            created_at = datetime.fromisoformat(row["created_at"])
            if created_at.date() >= window_start:
                new_members_in_window += 1
            available_roles = validation.decode_roles(row["roles_json"])
            if "admin" in available_roles:
                role_mix["admin_capable"] += 1
            elif "trainer" in available_roles:
                role_mix["trainer_capable"] += 1
            else:
                role_mix["athlete_only"] += 1
            if len(recent_members) < 5:
                recent_members.append({
                    "membership_id": int(row["id"]),
                    "user_id": int(row["user_id"]),
                    "email": row["email"],
                    "display_name": row["display_name"],
                    "nickname": row["nickname"],
                    "active_role": row["active_role"],
                    "created_at": row["created_at"],
                })

        attendance_rows = connection.execute(
            """
            select classes_by_day.day, count(*) as classes, coalesce(sum(classes_by_day.capacity), 0) as capacity,
              coalesce(sum(classes_by_day.bookings), 0) as bookings, coalesce(sum(classes_by_day.attended), 0) as attended,
              coalesce(sum(classes_by_day.no_shows), 0) as no_shows
            from (
              select substr(class_schedules.start_time, 1, 10) as day, class_schedules.id, class_schedules.capacity as capacity,
                count(class_bookings.id) as bookings,
                coalesce(sum(case when class_bookings.attendance_status = 'attended' then 1 else 0 end), 0) as attended,
                coalesce(sum(case when class_bookings.attendance_status = 'no_show' then 1 else 0 end), 0) as no_shows
              from class_schedules
              left join class_bookings on class_bookings.class_schedule_id = class_schedules.id
              where class_schedules.gym_id = ? and substr(class_schedules.start_time, 1, 10) between ? and ?
              group by substr(class_schedules.start_time, 1, 10), class_schedules.id, class_schedules.capacity
            ) classes_by_day
            group by classes_by_day.day
            order by classes_by_day.day asc
            """,
            (gym_id, window_start.isoformat(), today.isoformat()),
        ).fetchall()

        upcoming_row = connection.execute(
            """
            select count(*) as classes, coalesce(sum(upcoming_classes.capacity), 0) as capacity,
              coalesce(sum(upcoming_classes.bookings), 0) as bookings, coalesce(sum(upcoming_classes.waitlist_count), 0) as waitlist_spots,
              coalesce(sum(case when upcoming_classes.waitlist_count > 0 then 1 else 0 end), 0) as classes_with_waitlist,
              coalesce(sum(case when upcoming_classes.bookings >= upcoming_classes.capacity then 1 else 0 end), 0) as full_classes
            from (
              select class_schedules.id, class_schedules.title, class_schedules.start_time, class_schedules.capacity as capacity,
                count(distinct class_bookings.id) as bookings, count(distinct class_waitlist_entries.id) as waitlist_count
              from class_schedules
              left join class_bookings on class_bookings.class_schedule_id = class_schedules.id
              left join class_waitlist_entries on class_waitlist_entries.class_schedule_id = class_schedules.id
              where class_schedules.gym_id = ? and substr(class_schedules.start_time, 1, 10) between ? and ?
              group by class_schedules.id, class_schedules.title, class_schedules.start_time, class_schedules.capacity
            ) upcoming_classes
            """,
            (gym_id, today.isoformat(), upcoming_end.isoformat()),
        ).fetchone()

        pressure_rows = connection.execute(
            """
            select class_schedules.id, class_schedules.title, class_schedules.start_time, class_schedules.capacity,
              count(distinct class_bookings.id) as bookings, count(distinct class_waitlist_entries.id) as waitlist_count
            from class_schedules
            left join class_bookings on class_bookings.class_schedule_id = class_schedules.id
            left join class_waitlist_entries on class_waitlist_entries.class_schedule_id = class_schedules.id
            where class_schedules.gym_id = ? and substr(class_schedules.start_time, 1, 10) between ? and ?
            group by class_schedules.id, class_schedules.title, class_schedules.start_time, class_schedules.capacity
            having count(distinct class_waitlist_entries.id) > 0 or count(distinct class_bookings.id) >= class_schedules.capacity
            order by count(distinct class_waitlist_entries.id) desc,
                     (cast(count(distinct class_bookings.id) as real) / case when class_schedules.capacity <= 0 then 1 else class_schedules.capacity end) desc,
                     class_schedules.start_time asc
            limit 5
            """,
            (gym_id, today.isoformat(), upcoming_end.isoformat()),
        ).fetchall()

        problem_rows = connection.execute(
            """
            select class_schedules.id, class_schedules.title, class_schedules.start_time, class_schedules.capacity,
              count(class_bookings.id) as bookings,
              coalesce(sum(case when class_bookings.attendance_status = 'attended' then 1 else 0 end), 0) as attended,
              coalesce(sum(case when class_bookings.attendance_status = 'no_show' then 1 else 0 end), 0) as no_shows
            from class_schedules
            left join class_bookings on class_bookings.class_schedule_id = class_schedules.id
            where class_schedules.gym_id = ? and substr(class_schedules.start_time, 1, 10) between ? and ?
            group by class_schedules.id, class_schedules.title, class_schedules.start_time, class_schedules.capacity
            having count(class_bookings.id) > 0 and (
              cast(count(class_bookings.id) as real) / case when class_schedules.capacity <= 0 then 1 else class_schedules.capacity end < 0.5
              or cast(coalesce(sum(case when class_bookings.attendance_status = 'no_show' then 1 else 0 end), 0) as real) / count(class_bookings.id) >= 0.25
            )
            order by cast(coalesce(sum(case when class_bookings.attendance_status = 'no_show' then 1 else 0 end), 0) as real) / count(class_bookings.id) desc,
                     cast(count(class_bookings.id) as real) / case when class_schedules.capacity <= 0 then 1 else class_schedules.capacity end asc,
                     class_schedules.start_time desc
            limit 5
            """,
            (gym_id, window_start.isoformat(), today.isoformat()),
        ).fetchall()

        totals = {"classes": 0, "capacity": 0, "bookings": 0, "attended": 0, "no_shows": 0}
        daily: list[dict[str, Any]] = []
        rows_by_day = {row["day"]: row for row in attendance_rows}
        current_day = window_start
        while current_day <= today:
            key = current_day.isoformat()
            row = rows_by_day.get(key)
            classes = int(row["classes"]) if row is not None else 0
            capacity = int(row["capacity"]) if row is not None else 0
            bookings = int(row["bookings"]) if row is not None else 0
            attended = int(row["attended"]) if row is not None else 0
            no_shows = int(row["no_shows"]) if row is not None else 0
            totals["classes"] += classes
            totals["capacity"] += capacity
            totals["bookings"] += bookings
            totals["attended"] += attended
            totals["no_shows"] += no_shows
            daily.append({"date": key, "classes": classes, "capacity": capacity, "bookings": bookings, "attended": attended, "no_shows": no_shows, "utilization_rate": 0.0 if capacity <= 0 else round((bookings / capacity) * 100, 1)})
            current_day += timedelta(days=1)

        attendance_rate = 0.0 if totals["bookings"] <= 0 else round((totals["attended"] / totals["bookings"]) * 100, 1)
        no_show_rate = 0.0 if totals["bookings"] <= 0 else round((totals["no_shows"] / totals["bookings"]) * 100, 1)
        utilization_rate = 0.0 if totals["capacity"] <= 0 else round((totals["bookings"] / totals["capacity"]) * 100, 1)

        return {
            "overview": {
                "window_days": validated_window_days,
                "active_members": active_members_count,
                "active_trainers": trainer_members_count,
                "pending_join_requests": int(pending_join_requests_row["count"] if pending_join_requests_row else 0),
                "classes_in_window": totals["classes"],
                "bookings_in_window": totals["bookings"],
                "attended_in_window": totals["attended"],
                "no_shows_in_window": totals["no_shows"],
                "attendance_rate_in_window": attendance_rate,
                "utilization_rate_in_window": utilization_rate,
                "no_show_rate_in_window": no_show_rate,
                "upcoming_classes_next_7_days": int(upcoming_row["classes"] if upcoming_row else 0),
                "upcoming_bookings_next_7_days": int(upcoming_row["bookings"] if upcoming_row else 0),
                "upcoming_capacity_next_7_days": int(upcoming_row["capacity"] if upcoming_row else 0),
                "upcoming_waitlist_spots_next_7_days": int(upcoming_row["waitlist_spots"] if upcoming_row else 0),
                "upcoming_classes_with_waitlist_next_7_days": int(upcoming_row["classes_with_waitlist"] if upcoming_row else 0),
                "upcoming_full_classes_next_7_days": int(upcoming_row["full_classes"] if upcoming_row else 0),
                "new_members_in_window": new_members_in_window,
                "role_mix": role_mix,
            },
            "recent_members": recent_members,
            "daily_attendance": daily,
            "pressure_classes": [
                {"id": int(row["id"]), "title": row["title"], "start_time": row["start_time"], "capacity": int(row["capacity"]), "bookings": int(row["bookings"]), "waitlist_count": int(row["waitlist_count"]), "utilization_rate": 0.0 if int(row["capacity"]) <= 0 else round((int(row["bookings"]) / int(row["capacity"])) * 100, 1)}
                for row in pressure_rows
            ],
            "problem_classes": [
                {"id": int(row["id"]), "title": row["title"], "start_time": row["start_time"], "capacity": int(row["capacity"]), "bookings": int(row["bookings"]), "attended": int(row["attended"]), "no_shows": int(row["no_shows"]), "utilization_rate": 0.0 if int(row["capacity"]) <= 0 else round((int(row["bookings"]) / int(row["capacity"])) * 100, 1), "attendance_rate": 0.0 if int(row["bookings"]) <= 0 else round((int(row["attended"]) / int(row["bookings"])) * 100, 1), "no_show_rate": 0.0 if int(row["bookings"]) <= 0 else round((int(row["no_shows"]) / int(row["bookings"])) * 100, 1)}
                for row in problem_rows
            ],
        }
    finally:
        connection.close()


AT_RISK_DAYS = 21
EXPIRING_DAYS = 14


@router.get("/admin/dashboard")
def admin_dashboard(session: dict[str, Any] = Depends(require_admin_gym_session)) -> dict[str, Any]:
    """Owner dashboard (docs/admin-ui-reference.md §1): headline member counts
    and month-by-month series for the last six calendar months. Read-only."""
    gym_id = session["active_gym_id"]
    connection = db.get_connection()
    # shortcut: months are cut at the gym's local "today", but rows are
    # bucketed by their UTC timestamp, so a class in the first hours of a
    # month can count for the previous one; convert in SQL if that matters.
    today = schedule_service.local_today(get_gym_timezone(connection, gym_id))
    # First day of the month five months back, then six month keys "YYYY-MM".
    first = date(today.year, today.month, 1)
    months = []
    for _ in range(6):
        months.insert(0, first)
        first = date(first.year - (first.month == 1), (first.month - 2) % 12 + 1, 1)
    keys = [month.isoformat()[:7] for month in months]
    since = months[0].isoformat()
    at_risk_cutoff = (today - timedelta(days=AT_RISK_DAYS)).isoformat()
    now = security.isoformat(security.now_utc())
    try:
        at_risk = connection.execute(
            """
            select count(*) as count from gym_memberships
            where gym_id = ? and status = 'active' and active_role = 'athlete'
              and substr(created_at, 1, 10) < ?
              and not exists (
                select 1 from class_bookings
                join class_schedules on class_schedules.id = class_bookings.class_schedule_id
                where class_bookings.user_id = gym_memberships.user_id and class_schedules.gym_id = ?
                  and substr(class_schedules.start_time, 1, 10) >= ?
                  -- Only classes that happened and that they showed up for.
                  and class_schedules.start_time <= ? and class_bookings.attendance_status <> 'no_show'
              )
            """,
            (gym_id, at_risk_cutoff, gym_id, at_risk_cutoff, now),
        ).fetchone()["count"]
        expiring = connection.execute(
            """
            select count(*) as count from member_plans
            where gym_id = ? and status = 'active' and ends_on between ? and ?
            """,
            (gym_id, today.isoformat(), (today + timedelta(days=EXPIRING_DAYS)).isoformat()),
        ).fetchone()["count"]

        def per_month(sql: str, params: tuple) -> dict[str, dict[str, Any]]:
            return {row["month"]: dict(row) for row in connection.execute(sql, params).fetchall()}

        churned = per_month(
            """
            select substr(updated_at, 1, 7) as month, count(*) as count from gym_memberships
            where gym_id = ? and status = 'removed' and substr(updated_at, 1, 10) >= ?
            group by substr(updated_at, 1, 7)
            """,
            (gym_id, since),
        )
        new_members = per_month(
            """
            select substr(created_at, 1, 7) as month, count(*) as count from gym_memberships
            where gym_id = ? and active_role = 'athlete' and substr(created_at, 1, 10) >= ?
            group by substr(created_at, 1, 7)
            """,
            (gym_id, since),
        )
        new_memberships = per_month(
            """
            select substr(starts_on, 1, 7) as month, count(*) as count from member_plans
            where gym_id = ? and status in ('active', 'ended') and starts_on >= ?
            group by substr(starts_on, 1, 7)
            """,
            (gym_id, since),
        )
        classes = per_month(
            """
            select per_class.month, coalesce(sum(per_class.capacity), 0) as capacity,
              coalesce(sum(per_class.bookings), 0) as bookings, coalesce(sum(per_class.attended), 0) as attended
            from (
              select substr(class_schedules.start_time, 1, 7) as month, class_schedules.capacity as capacity,
                count(class_bookings.id) as bookings,
                coalesce(sum(case when class_bookings.attendance_status = 'attended' then 1 else 0 end), 0) as attended
              from class_schedules
              left join class_bookings on class_bookings.class_schedule_id = class_schedules.id
              where class_schedules.gym_id = ? and substr(class_schedules.start_time, 1, 10) between ? and ?
              group by class_schedules.id, substr(class_schedules.start_time, 1, 7), class_schedules.capacity
            ) per_class
            group by per_class.month
            """,
            (gym_id, since, today.isoformat()),
        )
        series = []
        for key in keys:
            month_classes = classes.get(key, {})
            capacity = int(month_classes.get("capacity") or 0)
            bookings = int(month_classes.get("bookings") or 0)
            series.append({
                "month": key,
                "new_members": int(new_members.get(key, {}).get("count") or 0),
                "new_memberships": int(new_memberships.get(key, {}).get("count") or 0),
                "churned_members": int(churned.get(key, {}).get("count") or 0),
                "registrations": bookings,
                "attended": int(month_classes.get("attended") or 0),
                # Percent of booked seats over offered seats, 0–100.
                "utilization_percent": 0.0 if capacity <= 0 else round(bookings * 100 / capacity, 1),
            })
        return {
            "members_at_risk": int(at_risk),
            "at_risk_days": AT_RISK_DAYS,
            "expiring_memberships": int(expiring),
            "expiring_days": EXPIRING_DAYS,
            "months": series,
        }
    finally:
        connection.close()
