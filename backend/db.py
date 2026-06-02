from __future__ import annotations

import json
import sqlite3
from typing import Any

from backend import settings
from backend.security import hash_password, isoformat, now_utc
from backend.validation import normalize_account_type_value, normalize_role_value, encode_roles

class ManagedConnection(sqlite3.Connection):
    def __del__(self) -> None:
        try:
            self.close()
        except sqlite3.Error:
            pass


def get_connection() -> sqlite3.Connection:
    connection = sqlite3.connect(settings.DB_PATH, factory=ManagedConnection)
    connection.row_factory = sqlite3.Row
    return connection

def init_db() -> None:
    settings.ANNOUNCEMENT_UPLOADS_DIR.mkdir(parents=True, exist_ok=True)
    connection = get_connection()
    with connection:
      connection.executescript(
          """
          create table if not exists users (
            id integer primary key autoincrement,
            email text not null unique,
            password_hash text not null,
            email_verified integer not null default 0,
            role text not null default 'athlete',
            roles_json text not null default '["athlete"]',
            display_name text not null default '',
            nickname text not null default '',
            notify_booking_confirmations integer not null default 1,
            notify_waitlist_promotions integer not null default 1,
            notify_payment_issues integer not null default 1,
            notify_wod_posted integer not null default 1,
            notify_pr_achievements integer not null default 1,
            notify_announcement_activity integer not null default 1,
            created_at text not null,
            updated_at text not null,
            deleted_at text,
            purge_after text
          );

          create table if not exists sessions (
            id integer primary key autoincrement,
            user_id integer not null references users(id) on delete cascade,
            access_token_hash text not null unique,
            refresh_token_hash text not null unique,
            access_expires_at text not null,
            refresh_expires_at text not null,
            created_at text not null
          );

          create table if not exists verification_tokens (
            id integer primary key autoincrement,
            user_id integer not null references users(id) on delete cascade,
            token_hash text not null unique,
            type text not null,
            expires_at text not null,
            created_at text not null
          );

          create table if not exists password_reset_tokens (
            id integer primary key autoincrement,
            user_id integer not null references users(id) on delete cascade,
            token_hash text not null unique,
            expires_at text not null,
            created_at text not null
          );

          create table if not exists device_registrations (
            id integer primary key autoincrement,
            user_id integer not null references users(id) on delete cascade,
            device_token text not null unique,
            platform text not null,
            created_at text not null,
            updated_at text not null
          );

          create table if not exists gyms (
            id integer primary key autoincrement,
            name text not null,
            slug text not null unique,
            logo_url text not null,
            timezone text not null,
            created_by_user_id integer not null references users(id) on delete cascade,
            created_at text not null,
            updated_at text not null
          );

          create table if not exists gym_memberships (
            id integer primary key autoincrement,
            user_id integer not null references users(id) on delete cascade,
            gym_id integer not null references gyms(id) on delete cascade,
            active_role text not null default 'athlete',
            roles_json text not null default '["athlete"]',
            status text not null default 'active',
            created_at text not null,
            updated_at text not null,
            unique(user_id, gym_id)
          );

          create table if not exists gym_join_requests (
            id integer primary key autoincrement,
            user_id integer not null references users(id) on delete cascade,
            gym_id integer not null references gyms(id) on delete cascade,
            status text not null default 'pending',
            created_at text not null,
            updated_at text not null,
            reviewed_at text,
            reviewed_by_user_id integer references users(id) on delete set null
          );

          create table if not exists class_schedules (
            id integer primary key autoincrement,
            gym_id integer not null references gyms(id) on delete cascade,
            title text not null,
            class_type text not null,
            start_time text not null,
            end_time text not null,
            duration_minutes integer not null default 60,
            capacity integer not null,
            assigned_trainer_user_id integer references users(id) on delete set null,
            wod_description text not null default '',
            created_by_user_id integer not null references users(id) on delete cascade,
            updated_by_user_id integer not null references users(id) on delete cascade,
            created_at text not null,
            updated_at text not null
          );

          create table if not exists class_bookings (
            id integer primary key autoincrement,
            class_schedule_id integer not null references class_schedules(id) on delete cascade,
            user_id integer not null references users(id) on delete cascade,
            attendance_status text not null default 'booked',
            attendance_marked_at text,
            attendance_marked_by_user_id integer references users(id) on delete set null,
            created_at text not null,
            unique(class_schedule_id, user_id)
          );

          create table if not exists class_waitlist_entries (
            id integer primary key autoincrement,
            class_schedule_id integer not null references class_schedules(id) on delete cascade,
            user_id integer not null references users(id) on delete cascade,
            created_at text not null,
            unique(class_schedule_id, user_id)
          );

          create table if not exists daily_workouts (
            id integer primary key autoincrement,
            gym_id integer not null references gyms(id) on delete cascade,
            scheduled_date text not null,
            title text not null,
            strength_text text not null default '',
            metcon_text text not null default '',
            notes_text text not null default '',
            created_by_user_id integer not null references users(id) on delete cascade,
            updated_by_user_id integer not null references users(id) on delete cascade,
            created_at text not null,
            updated_at text not null,
            unique(gym_id, scheduled_date)
          );

          create table if not exists whiteboard_results (
            id integer primary key autoincrement,
            daily_workout_id integer not null references daily_workouts(id) on delete cascade,
            gym_id integer not null references gyms(id) on delete cascade,
            user_id integer not null references users(id) on delete cascade,
            score_type text not null,
            score_value real not null,
            score_label text not null,
            notes_text text not null default '',
            created_at text not null,
            updated_at text not null,
            unique(daily_workout_id, user_id)
          );

          create table if not exists audit_logs (
            id integer primary key autoincrement,
            gym_id integer references gyms(id) on delete cascade,
            actor_user_id integer not null references users(id) on delete cascade,
            target_user_id integer references users(id) on delete set null,
            action text not null,
            entity_type text not null,
            entity_id integer,
            details_json text not null default '{}',
            created_at text not null
          );

          create table if not exists workout_logs (
            id integer primary key autoincrement,
            user_id integer not null references users(id) on delete cascade,
            gym_id integer not null references gyms(id) on delete cascade,
            daily_workout_id integer not null references daily_workouts(id) on delete cascade,
            class_schedule_id integer references class_schedules(id) on delete set null,
            score_type text not null,
            score_value real not null,
            score_label text not null,
            notes_text text not null default '',
            is_pr integer not null default 0,
            pr_rank integer,
            created_at text not null,
            updated_at text not null,
            unique(user_id, daily_workout_id)
          );

          create table if not exists notifications (
            id integer primary key autoincrement,
            user_id integer not null references users(id) on delete cascade,
            gym_id integer references gyms(id) on delete cascade,
            type text not null,
            title text not null,
            body text not null,
            entity_type text,
            entity_id integer,
            read_at text,
            created_at text not null
          );

          create table if not exists announcements (
            id integer primary key autoincrement,
            gym_id integer not null references gyms(id) on delete cascade,
            title text not null,
            description text not null,
            image_url text,
            created_by_user_id integer not null references users(id) on delete cascade,
            created_at text not null,
            updated_at text not null
          );

          create table if not exists announcement_likes (
            announcement_id integer not null references announcements(id) on delete cascade,
            user_id integer not null references users(id) on delete cascade,
            created_at text not null,
            primary key (announcement_id, user_id)
          );

          create table if not exists announcement_comments (
            id integer primary key autoincrement,
            announcement_id integer not null references announcements(id) on delete cascade,
            gym_id integer not null references gyms(id) on delete cascade,
            user_id integer not null references users(id) on delete cascade,
            body text not null,
            created_at text not null,
            updated_at text not null
          );

          create table if not exists personal_workouts (
            id integer primary key autoincrement,
            user_id integer not null references users(id) on delete cascade,
            type text not null,
            title text not null,
            structure_json text not null default '{}',
            created_at text not null,
            updated_at text not null
          );

          create table if not exists exercises (
            id text primary key,
            name text not null,
            category text not null default '',
            equipment text not null default '',
            level text not null default '',
            force text not null default '',
            mechanic text not null default '',
            primary_muscles text not null default '[]',
            secondary_muscles text not null default '[]',
            instructions text not null default '[]',
            search text not null default ''
          );

          create table if not exists benchmark_workouts (
            id text primary key,
            name text not null,
            category text not null default '',
            structure_json text not null default '{}',
            sort_order integer not null default 0
          );
          """
      )
      ensure_user_columns(connection)
      ensure_class_schedule_columns(connection)
      ensure_class_booking_columns(connection)
      ensure_class_waitlist_tables(connection)
      ensure_workout_log_columns(connection)
      seed_exercises(connection)
      seed_benchmark_workouts(connection)
      migrate_legacy_auth_terms(connection)
      purge_deleted_users(connection)
    connection.close()
    seed_default_users()


def ensure_user_columns(connection: sqlite3.Connection) -> None:
    columns = {
        row["name"] for row in connection.execute("pragma table_info(users)").fetchall()
    }
    if "display_name" not in columns:
        connection.execute(
            "alter table users add column display_name text not null default ''"
        )
    if "role" not in columns:
        connection.execute(
            "alter table users add column role text not null default 'athlete'"
        )
    if "roles_json" not in columns:
        connection.execute(
            "alter table users add column roles_json text not null default '[\"athlete\"]'"
        )
        connection.execute(
            "update users set roles_json = json_array(role)"
        )
    if "nickname" not in columns:
        connection.execute(
            "alter table users add column nickname text not null default ''"
        )
    if "purge_after" not in columns:
        connection.execute(
            "alter table users add column purge_after text"
        )
    if "notify_booking_confirmations" not in columns:
        connection.execute(
            "alter table users add column notify_booking_confirmations integer not null default 1"
        )
    if "notify_waitlist_promotions" not in columns:
        connection.execute(
            "alter table users add column notify_waitlist_promotions integer not null default 1"
        )
    if "notify_payment_issues" not in columns:
        connection.execute(
            "alter table users add column notify_payment_issues integer not null default 1"
        )
    if "notify_wod_posted" not in columns:
        connection.execute(
            "alter table users add column notify_wod_posted integer not null default 1"
        )
    if "notify_pr_achievements" not in columns:
        connection.execute(
            "alter table users add column notify_pr_achievements integer not null default 1"
        )
    if "notify_announcement_activity" not in columns:
        connection.execute(
            "alter table users add column notify_announcement_activity integer not null default 1"
        )
    if "account_type" not in columns:
        connection.execute(
            "alter table users add column account_type text not null default 'athlete'"
        )
    if "active_gym_id" not in columns:
        connection.execute(
            "alter table users add column active_gym_id integer references gyms(id) on delete set null"
        )


def normalize_account_type_value(value: Any) -> str:
    account_type = str(value or "").strip().lower()
    if account_type == "owner":
        return "admin"
    return account_type


def normalize_role_value(value: Any) -> str:
    role = str(value or "").strip().lower()
    if role == "box":
        return "admin"
    return role


def ensure_class_booking_columns(connection: sqlite3.Connection) -> None:
    tables = {
        row["name"]
        for row in connection.execute(
            "select name from sqlite_master where type = 'table'"
        ).fetchall()
    }
    if "class_bookings" not in tables:
        return
    columns = {
        row["name"] for row in connection.execute("pragma table_info(class_bookings)").fetchall()
    }
    if "attendance_status" not in columns:
        connection.execute(
            "alter table class_bookings add column attendance_status text not null default 'booked'"
        )
    if "attendance_marked_at" not in columns:
        connection.execute(
            "alter table class_bookings add column attendance_marked_at text"
        )
    if "attendance_marked_by_user_id" not in columns:
        connection.execute(
            "alter table class_bookings add column attendance_marked_by_user_id integer references users(id) on delete set null"
        )


def ensure_class_schedule_columns(connection: sqlite3.Connection) -> None:
    tables = {
        row["name"]
        for row in connection.execute(
            "select name from sqlite_master where type = 'table'"
        ).fetchall()
    }
    if "class_schedules" not in tables:
        return
    columns = {
        row["name"] for row in connection.execute("pragma table_info(class_schedules)").fetchall()
    }
    if "duration_minutes" not in columns:
        connection.execute(
            "alter table class_schedules add column duration_minutes integer not null default 60"
        )
        connection.execute(
            """
            update class_schedules
            set duration_minutes = cast(
              round((julianday(end_time) - julianday(start_time)) * 24 * 60)
              as integer
            )
            where duration_minutes <= 0
            """
        )
    if "wod_description" not in columns:
        connection.execute(
            "alter table class_schedules add column wod_description text not null default ''"
        )
    if "assigned_trainer_user_id" not in columns:
        connection.execute(
            "alter table class_schedules add column assigned_trainer_user_id integer references users(id) on delete set null"
        )


def ensure_class_waitlist_tables(connection: sqlite3.Connection) -> None:
    connection.execute(
        """
        create table if not exists class_waitlist_entries (
          id integer primary key autoincrement,
          class_schedule_id integer not null references class_schedules(id) on delete cascade,
          user_id integer not null references users(id) on delete cascade,
          created_at text not null,
          unique(class_schedule_id, user_id)
        )
        """
    )


def ensure_workout_log_columns(connection: sqlite3.Connection) -> None:
    tables = {
        row["name"]
        for row in connection.execute(
            "select name from sqlite_master where type = 'table'"
        ).fetchall()
    }
    if "workout_logs" not in tables:
        return
    columns = {
        row["name"] for row in connection.execute("pragma table_info(workout_logs)").fetchall()
    }
    if "is_pr" not in columns:
        connection.execute(
            "alter table workout_logs add column is_pr integer not null default 0"
        )
    if "pr_rank" not in columns:
        connection.execute(
            "alter table workout_logs add column pr_rank integer"
        )


def seed_exercises(connection: sqlite3.Connection) -> None:
    """Load the bundled free-exercise-db dataset once into the exercises table.

    No-op if the table is already populated or the seed file is missing, so it
    stays cheap on every startup and harmless in environments without the data.
    """
    existing = connection.execute(
        "select count(*) as count from exercises"
    ).fetchone()
    if existing["count"] > 0:
        return
    if not settings.EXERCISES_SEED_PATH.exists():
        return
    with open(settings.EXERCISES_SEED_PATH, encoding="utf-8") as handle:
        data = json.load(handle)
    rows = []
    for item in data:
        name = str(item.get("name") or "").strip()
        if not name:
            continue
        primary = item.get("primaryMuscles") or []
        secondary = item.get("secondaryMuscles") or []
        category = str(item.get("category") or "")
        equipment = str(item.get("equipment") or "")
        search = " ".join(
            [name, " ".join(primary), " ".join(secondary), equipment, category]
        ).lower()
        rows.append(
            (
                str(item.get("id") or name),
                name,
                category,
                equipment,
                str(item.get("level") or ""),
                str(item.get("force") or ""),
                str(item.get("mechanic") or ""),
                json.dumps(primary),
                json.dumps(secondary),
                json.dumps(item.get("instructions") or []),
                search,
            )
        )
    connection.executemany(
        """
        insert or ignore into exercises (
          id, name, category, equipment, level, force, mechanic,
          primary_muscles, secondary_muscles, instructions, search
        ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        rows,
    )


def seed_benchmark_workouts(connection: sqlite3.Connection) -> None:
    """Load the bundled CrossFit benchmark catalog once. No-op if already
    populated or the seed file is missing."""
    existing = connection.execute(
        "select count(*) as count from benchmark_workouts"
    ).fetchone()
    if existing["count"] > 0:
        return
    if not settings.BENCHMARKS_SEED_PATH.exists():
        return
    with open(settings.BENCHMARKS_SEED_PATH, encoding="utf-8") as handle:
        data = json.load(handle)
    rows = []
    for index, item in enumerate(data):
        name = str(item.get("name") or "").strip()
        if not name:
            continue
        rows.append(
            (
                str(item.get("id") or name).lower(),
                name,
                str(item.get("category") or ""),
                json.dumps(item.get("structure") or {}),
                index,
            )
        )
    connection.executemany(
        """
        insert or ignore into benchmark_workouts (
          id, name, category, structure_json, sort_order
        ) values (?, ?, ?, ?, ?)
        """,
        rows,
    )


def migrate_legacy_auth_terms(connection: sqlite3.Connection) -> None:
    connection.execute(
        "update users set account_type = 'admin' where account_type = 'owner'"
    )
    connection.execute("update users set role = 'admin' where role = 'box'")
    connection.execute(
        """
        update users
        set roles_json = replace(roles_json, '\"box\"', '\"admin\"')
        where roles_json like '%"box"%'
        """
    )
    connection.execute(
        "update gym_memberships set active_role = 'admin' where active_role = 'box'"
    )
    connection.execute(
        """
        update gym_memberships
        set roles_json = replace(roles_json, '\"box\"', '\"admin\"')
        where roles_json like '%"box"%'
        """
    )


def purge_deleted_users(connection: sqlite3.Connection) -> None:
    connection.execute(
        """
        delete from gym_memberships
        where user_id in (
          select id from users
          where deleted_at is not null
            and purge_after is not null
            and purge_after <= ?
        )
        """,
        (isoformat(now_utc()),),
    )
    connection.execute(
        """
        delete from gym_join_requests
        where user_id in (
          select id from users
          where deleted_at is not null
            and purge_after is not null
            and purge_after <= ?
        )
        """,
        (isoformat(now_utc()),),
    )
    connection.execute(
        """
        delete from users
        where deleted_at is not null
          and purge_after is not null
          and purge_after <= ?
        """,
        (isoformat(now_utc()),),
    )


def seed_default_users() -> None:
    seed_user(
        email=settings.DEMO_EMAIL,
        password=settings.DEMO_PASSWORD,
        role="athlete",
        display_name="Demo Athlete",
        nickname="demo",
    )
    seed_user(
        email=settings.TRAINER_EMAIL,
        password=settings.TRAINER_PASSWORD,
        role="trainer",
        display_name="Demo Trainer",
        nickname="trainer",
    )
    seed_user(
        email=settings.ADMIN_EMAIL,
        password=settings.ADMIN_PASSWORD,
        role="admin",
        display_name="Demo Admin",
        nickname="admin",
        account_type="admin",
    )


def seed_user(
    *,
    email: str,
    password: str,
    role: str,
    roles: list[str] | None = None,
    display_name: str,
    nickname: str,
    account_type: str = "athlete",
) -> None:
    assigned_roles = normalize_roles(roles or [role])
    normalized_account_type = require_account_type(account_type)
    connection = get_connection()
    try:
        with connection:
            existing = connection.execute(
                "select id, deleted_at from users where email = ?",
                (email.lower(),),
            ).fetchone()
            if existing is not None:
                connection.execute(
                    """
                    update users
                    set password_hash = ?, email_verified = 1, role = ?, roles_json = ?, deleted_at = null, purge_after = null, updated_at = ?, display_name = ?, nickname = ?, account_type = ?
                    where id = ?
                    """,
                    (
                        hash_password(password),
                        role,
                        encode_roles(assigned_roles),
                        isoformat(now_utc()),
                        display_name,
                        nickname,
                        normalized_account_type,
                        existing["id"],
                    ),
                )
                sync_user_context(connection, existing["id"])
                return

            timestamp = isoformat(now_utc())
            connection.execute(
                """
                insert into users (email, password_hash, email_verified, role, roles_json, display_name, nickname, account_type, created_at, updated_at)
                values (?, ?, 1, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    email.lower(),
                    hash_password(password),
                    role,
                    encode_roles(assigned_roles),
                    display_name,
                    nickname,
                    normalized_account_type,
                    timestamp,
                    timestamp,
                ),
            )
    finally:
        connection.close()


