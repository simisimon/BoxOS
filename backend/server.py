from __future__ import annotations

import hashlib
import hmac
import json
import secrets
import sqlite3
from datetime import UTC, datetime, timedelta
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

DB_PATH = Path(__file__).with_name("boxos_dev.db")
HOST = "127.0.0.1"
PORT = 8080
DELETE_RETENTION_DAYS = 30
ALLOWED_ROLES = {"athlete", "trainer", "admin"}
ALLOWED_ACCOUNT_TYPES = {"athlete", "admin"}

DEMO_EMAIL = "demo@boxos.app"
DEMO_PASSWORD = "BoxOS123!"
TRAINER_EMAIL = "trainer@boxos.app"
TRAINER_PASSWORD = "BoxOS123!"
ADMIN_EMAIL = "admin@boxos.app"
ADMIN_PASSWORD = "BoxOS123!"
ACCESS_TOKEN_TTL_MINUTES = 15
REFRESH_TOKEN_TTL_DAYS = 30


def now_utc() -> datetime:
    return datetime.now(UTC)


def isoformat(value: datetime) -> str:
    return value.isoformat()


def parse_iso(value: str) -> datetime:
    return datetime.fromisoformat(value)


def pbkdf2_hash(password: str, salt: str) -> str:
    digest = hashlib.pbkdf2_hmac(
        "sha256",
        password.encode("utf-8"),
        salt.encode("utf-8"),
        120_000,
    )
    return digest.hex()


def hash_password(password: str) -> str:
    salt = secrets.token_hex(16)
    digest = pbkdf2_hash(password, salt)
    return f"{salt}${digest}"


def verify_password(password: str, encoded: str) -> bool:
    salt, stored_digest = encoded.split("$", 1)
    computed = pbkdf2_hash(password, salt)
    return hmac.compare_digest(computed, stored_digest)


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def create_token(prefix: str) -> str:
    return f"{prefix}_{secrets.token_urlsafe(24)}"


def get_connection() -> sqlite3.Connection:
    connection = sqlite3.connect(DB_PATH)
    connection.row_factory = sqlite3.Row
    return connection


def init_db() -> None:
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
            created_at text not null,
            updated_at text not null,
            unique(user_id, daily_workout_id)
          );
          """
      )
      ensure_user_columns(connection)
      ensure_class_schedule_columns(connection)
      ensure_class_booking_columns(connection)
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
        email=DEMO_EMAIL,
        password=DEMO_PASSWORD,
        role="athlete",
        display_name="Demo Athlete",
        nickname="demo",
    )
    seed_user(
        email=TRAINER_EMAIL,
        password=TRAINER_PASSWORD,
        role="trainer",
        display_name="Demo Trainer",
        nickname="trainer",
    )
    seed_user(
        email=ADMIN_EMAIL,
        password=ADMIN_PASSWORD,
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


def create_session(connection: sqlite3.Connection, user_id: int) -> dict[str, str]:
    access_token = create_token("access")
    refresh_token = create_token("refresh")
    now = now_utc()
    connection.execute(
        """
        insert into sessions (
          user_id,
          access_token_hash,
          refresh_token_hash,
          access_expires_at,
          refresh_expires_at,
          created_at
        )
        values (?, ?, ?, ?, ?, ?)
        """,
        (
            user_id,
            hash_token(access_token),
            hash_token(refresh_token),
            isoformat(now + timedelta(minutes=ACCESS_TOKEN_TTL_MINUTES)),
            isoformat(now + timedelta(days=REFRESH_TOKEN_TTL_DAYS)),
            isoformat(now),
        ),
    )
    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
    }


def delete_sessions(
    connection: sqlite3.Connection,
    user_id: int,
    *,
    except_access_token_hash: str | None = None,
) -> None:
    if except_access_token_hash is None:
        connection.execute("delete from sessions where user_id = ?", (user_id,))
        return

    connection.execute(
        "delete from sessions where user_id = ? and access_token_hash != ?",
        (user_id, except_access_token_hash),
    )


def issue_verification_token(connection: sqlite3.Connection, user_id: int) -> str:
    token = create_token("verify")
    connection.execute("delete from verification_tokens where user_id = ?", (user_id,))
    connection.execute(
        """
        insert into verification_tokens (user_id, token_hash, type, expires_at, created_at)
        values (?, ?, 'signup', ?, ?)
        """,
        (
            user_id,
            hash_token(token),
            isoformat(now_utc() + timedelta(hours=24)),
            isoformat(now_utc()),
        ),
    )
    return token


def issue_password_reset_token(connection: sqlite3.Connection, user_id: int) -> str:
    token = create_token("reset")
    connection.execute("delete from password_reset_tokens where user_id = ?", (user_id,))
    connection.execute(
        """
        insert into password_reset_tokens (user_id, token_hash, expires_at, created_at)
        values (?, ?, ?, ?)
        """,
        (
            user_id,
            hash_token(token),
            isoformat(now_utc() + timedelta(hours=1)),
            isoformat(now_utc()),
        ),
    )
    return token


def slugify(value: str) -> str:
    normalized = [
        character.lower() if character.isalnum() else "-"
        for character in value.strip()
    ]
    slug = "".join(normalized)
    while "--" in slug:
        slug = slug.replace("--", "-")
    return slug.strip("-") or "gym"


def unique_gym_slug(connection: sqlite3.Connection, name: str) -> str:
    base_slug = slugify(name)
    slug = base_slug
    counter = 2
    while connection.execute(
        "select 1 from gyms where slug = ?",
        (slug,),
    ).fetchone() is not None:
        slug = f"{base_slug}-{counter}"
        counter += 1
    return slug


def list_user_memberships(
    connection: sqlite3.Connection,
    user_id: int,
    *,
    status: str = "active",
) -> list[sqlite3.Row]:
    return connection.execute(
        """
        select
          gym_memberships.id,
          gym_memberships.user_id,
          gym_memberships.gym_id,
          gym_memberships.active_role,
          gym_memberships.roles_json,
          gym_memberships.status,
          gyms.name as gym_name,
          gyms.slug as gym_slug,
          gyms.logo_url as gym_logo_url,
          gyms.timezone as gym_timezone
        from gym_memberships
        join gyms on gyms.id = gym_memberships.gym_id
        where gym_memberships.user_id = ?
          and gym_memberships.status = ?
        order by gyms.name asc
        """,
        (user_id, status),
    ).fetchall()


def get_active_membership(
    connection: sqlite3.Connection,
    user_id: int,
) -> sqlite3.Row | None:
    user = connection.execute(
        "select account_type, active_gym_id from users where id = ?",
        (user_id,),
    ).fetchone()
    if user is None:
        return None

    active_gym_id = user["active_gym_id"]
    if active_gym_id is not None:
        membership = connection.execute(
            """
            select
              gym_memberships.id,
              gym_memberships.user_id,
              gym_memberships.gym_id,
              gym_memberships.active_role,
              gym_memberships.roles_json,
              gym_memberships.status,
              gyms.name as gym_name,
              gyms.slug as gym_slug,
              gyms.logo_url as gym_logo_url,
              gyms.timezone as gym_timezone
            from gym_memberships
            join gyms on gyms.id = gym_memberships.gym_id
            where gym_memberships.user_id = ?
              and gym_memberships.gym_id = ?
              and gym_memberships.status = 'active'
            """,
            (user_id, active_gym_id),
        ).fetchone()
        if membership is not None:
            return membership

    memberships = list_user_memberships(connection, user_id)
    return memberships[0] if memberships else None


def membership_payload(row: sqlite3.Row) -> dict[str, Any]:
    return {
        "gym_id": row["gym_id"],
        "gym_name": row["gym_name"],
        "gym_slug": row["gym_slug"],
        "gym_logo_url": row["gym_logo_url"],
        "gym_timezone": row["gym_timezone"],
        "role": row["active_role"],
        "available_roles": decode_roles(row["roles_json"]),
        "status": row["status"],
    }


def active_gym_payload(row: sqlite3.Row | None) -> dict[str, Any] | None:
    if row is None:
        return None
    return {
        "id": row["gym_id"],
        "name": row["gym_name"],
        "slug": row["gym_slug"],
        "logo_url": row["gym_logo_url"],
        "timezone": row["gym_timezone"],
    }


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
    capacity = row["capacity"]
    return {
        "id": row["id"],
        "gym_id": row["gym_id"],
        "title": row["title"],
        "class_type": row["class_type"],
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
        "wod_description": row["wod_description"],
        "booked_count": booked_count,
        "remaining_spots": max(capacity - booked_count, 0),
        "is_booked": current_user_booking is not None,
        "attendance_status": (
            current_user_booking["attendance_status"]
            if current_user_booking is not None
            else None
        ),
        "bookings": [
            schedule_booking_payload(booking, current_user_id=current_user_id)
            for booking in booking_rows
        ]
        if include_bookings
        else [],
    }


def sync_user_context(connection: sqlite3.Connection, user_id: int) -> None:
    user = connection.execute(
        "select account_type, role, roles_json from users where id = ? and deleted_at is null",
        (user_id,),
    ).fetchone()
    if user is None:
        return

    active_membership = get_active_membership(connection, user_id)
    if active_membership is None:
        connection.execute(
            """
            update users
            set active_gym_id = null,
                role = ?,
                roles_json = ?,
                updated_at = ?
            where id = ?
            """,
            (
                user["role"],
                user["roles_json"],
                isoformat(now_utc()),
                user_id,
            ),
        )
        return

    connection.execute(
        """
        update users
        set active_gym_id = ?,
            role = ?,
            roles_json = ?,
            updated_at = ?
        where id = ?
        """,
        (
            active_membership["gym_id"],
            active_membership["active_role"],
            active_membership["roles_json"],
            isoformat(now_utc()),
            user_id,
        ),
    )


def parse_json(handler: BaseHTTPRequestHandler) -> dict[str, Any]:
    content_length = int(handler.headers.get("Content-Length", "0"))
    raw = handler.rfile.read(content_length) if content_length > 0 else b"{}"
    if not raw:
        return {}
    return json.loads(raw.decode("utf-8"))


class ApiError(Exception):
    def __init__(self, status: HTTPStatus, message: str):
        super().__init__(message)
        self.status = status
        self.message = message


class BoxOsHandler(BaseHTTPRequestHandler):
    server_version = "BoxOSDevBackend/1.0"

    def do_GET(self) -> None:
        try:
            self.run_housekeeping()
            path = urlparse(self.path).path
            if path == "/health":
                self.send_json(HTTPStatus.OK, {"status": "ok"})
                return
            if path == "/auth/session":
                session = self.require_session()
                connection = get_connection()
                active_membership = get_active_membership(connection, session["user_id"])
                memberships = list_user_memberships(connection, session["user_id"])
                connection.close()
                self.send_json(
                    HTTPStatus.OK,
                    {
                        "email": session["email"],
                        "email_verified": bool(session["email_verified"]),
                        "role": session["role"],
                        "available_roles": decode_roles(session["roles_json"]),
                        "account_type": session["account_type"],
                        "active_gym": active_gym_payload(active_membership),
                        "memberships": [membership_payload(row) for row in memberships],
                    },
                )
                return
            if path == "/profile":
                self.handle_get_profile()
                return
            if path == "/profile/notifications":
                self.handle_get_notification_preferences()
                return
            if path == "/gyms":
                self.handle_list_gyms()
                return
            if path == "/schedule/classes":
                self.handle_list_schedule_classes()
                return
            if path == "/schedule/trainers":
                self.handle_list_schedule_trainers()
                return
            if path == "/programming/workouts":
                self.handle_list_daily_workouts()
                return
            if path == "/logbook/entries":
                self.handle_list_workout_logs()
                return
            if path == "/gyms/join-requests":
                self.handle_list_join_requests()
                return
            if path == "/audit-logs":
                self.handle_list_audit_logs()
                return
            if path == "/gyms/my-requests":
                self.handle_list_my_join_requests()
                return
            if path == "/roles/users":
                self.handle_list_role_users()
                return
            raise ApiError(HTTPStatus.NOT_FOUND, "Route not found.")
        except ApiError as error:
            self.send_json(error.status, {"message": error.message})

    def do_POST(self) -> None:
        try:
            self.run_housekeeping()
            path = urlparse(self.path).path
            body = parse_json(self)
            if path == "/auth/login":
                self.handle_login(body)
                return
            if path == "/auth/signup":
                self.handle_signup(body)
                return
            if path == "/auth/signup-admin" or path == "/auth/signup-owner":
                self.handle_admin_signup(body)
                return
            if path == "/auth/logout":
                self.handle_logout()
                return
            if path == "/auth/logout-all":
                self.handle_logout_all()
                return
            if path == "/auth/refresh":
                self.handle_refresh(body)
                return
            if path == "/auth/request-password-reset":
                self.handle_request_password_reset(body)
                return
            if path == "/auth/reset-password":
                self.handle_reset_password(body)
                return
            if path == "/auth/verify-email":
                self.handle_verify_email(body)
                return
            if path == "/auth/resend-verification":
                self.handle_resend_verification(body)
                return
            if path == "/auth/change-password":
                self.handle_change_password(body)
                return
            if path == "/devices/register":
                self.handle_register_device(body)
                return
            if path == "/gyms":
                self.handle_create_gym(body)
                return
            if path == "/schedule/classes":
                self.handle_create_schedule_class(body)
                return
            if path == "/schedule/bookings":
                self.handle_create_class_booking(body)
                return
            if path == "/programming/workouts":
                self.handle_create_daily_workout(body)
                return
            if path == "/programming/whiteboard-results":
                self.handle_submit_whiteboard_result(body)
                return
            if path == "/logbook/entries":
                self.handle_submit_workout_log(body)
                return
            if path == "/gyms/join-requests":
                self.handle_create_join_request(body)
                return
            raise ApiError(HTTPStatus.NOT_FOUND, "Route not found.")
        except ApiError as error:
            self.send_json(error.status, {"message": error.message})

    def do_DELETE(self) -> None:
        try:
            self.run_housekeeping()
            path = urlparse(self.path).path
            body = parse_json(self)
            if path == "/auth/account":
                self.handle_delete_account(body)
                return
            if path == "/devices/current":
                self.handle_unregister_device(body)
                return
            if path == "/schedule/classes":
                self.handle_delete_schedule_class(body)
                return
            if path == "/schedule/bookings":
                self.handle_delete_class_booking(body)
                return
            raise ApiError(HTTPStatus.NOT_FOUND, "Route not found.")
        except ApiError as error:
            self.send_json(error.status, {"message": error.message})

    def do_PATCH(self) -> None:
        try:
            self.run_housekeeping()
            path = urlparse(self.path).path
            body = parse_json(self)
            if path == "/profile":
                self.handle_update_profile(body)
                return
            if path == "/profile/notifications":
                self.handle_update_notification_preferences(body)
                return
            if path == "/profile/active-role":
                self.handle_update_active_role(body)
                return
            if path == "/profile/active-gym":
                self.handle_update_active_gym(body)
                return
            if path == "/schedule/classes":
                self.handle_update_schedule_class(body)
                return
            if path == "/schedule/bookings/attendance":
                self.handle_update_class_attendance(body)
                return
            if path == "/programming/workouts":
                self.handle_update_daily_workout(body)
                return
            if path == "/gyms/join-requests":
                self.handle_review_join_request(body)
                return
            if path == "/roles/users":
                self.handle_assign_role(body)
                return
            raise ApiError(HTTPStatus.NOT_FOUND, "Route not found.")
        except ApiError as error:
            self.send_json(error.status, {"message": error.message})

    def run_housekeeping(self) -> None:
        connection = get_connection()
        with connection:
            purge_deleted_users(connection)
        connection.close()

    def handle_login(self, body: dict[str, Any]) -> None:
        email = require_email(body.get("email"))
        password = require_password(body.get("password"))
        connection = get_connection()
        user = connection.execute(
            "select * from users where email = ? and deleted_at is null",
            (email,),
        ).fetchone()
        if user is None or not verify_password(password, user["password_hash"]):
            connection.close()
            raise ApiError(HTTPStatus.UNAUTHORIZED, "Invalid email or password.")
        if not user["email_verified"]:
            connection.close()
            raise ApiError(HTTPStatus.FORBIDDEN, "Verify your email before signing in.")

        with connection:
            sync_user_context(connection, user["id"])
            tokens = create_session(connection, user["id"])
        connection.close()
        self.send_json(HTTPStatus.OK, tokens)

    def handle_signup(self, body: dict[str, Any]) -> None:
        self._handle_signup(body, account_type="athlete")

    def handle_admin_signup(self, body: dict[str, Any]) -> None:
        self._handle_signup(body, account_type="admin")

    def _handle_signup(self, body: dict[str, Any], *, account_type: str) -> None:
        email = require_email(body.get("email"))
        password = require_password(body.get("password"))
        normalized_account_type = require_account_type(account_type)
        connection = get_connection()
        existing = connection.execute(
            "select id from users where email = ? and deleted_at is null",
            (email,),
        ).fetchone()
        if existing is not None:
            connection.close()
            raise ApiError(HTTPStatus.CONFLICT, "Email is already registered.")

        timestamp = isoformat(now_utc())
        with connection:
            cursor = connection.execute(
                """
                insert into users (email, password_hash, email_verified, role, roles_json, account_type, created_at, updated_at)
                values (?, ?, 0, ?, ?, ?, ?, ?)
                """,
                (
                    email,
                    hash_password(password),
                    "admin" if normalized_account_type == "admin" else "athlete",
                    encode_roles(["admin"] if normalized_account_type == "admin" else ["athlete"]),
                    normalized_account_type,
                    timestamp,
                    timestamp,
                ),
            )
            user_id = int(cursor.lastrowid)
            token = issue_verification_token(connection, user_id)
        connection.close()
        print(f"[boxos-backend] Verification token for {email}: {token}")
        self.send_json(HTTPStatus.CREATED, {"message": "Account created. Check the backend log for the verification token."})

    def handle_logout(self) -> None:
        session = self.require_session()
        connection = get_connection()
        with connection:
            connection.execute(
                "delete from sessions where access_token_hash = ?",
                (session["access_token_hash"],),
            )
        connection.close()
        self.send_json(HTTPStatus.OK, {"message": "Signed out."})

    def handle_logout_all(self) -> None:
        session = self.require_session()
        connection = get_connection()
        with connection:
            delete_sessions(connection, session["user_id"])
            write_audit_log(
                connection,
                gym_id=session["active_gym_id"],
                actor_user_id=session["user_id"],
                target_user_id=session["user_id"],
                action="all_sessions_revoked",
                entity_type="session",
            )
        connection.close()
        self.send_json(HTTPStatus.OK, {"message": "All sessions revoked."})

    def handle_refresh(self, body: dict[str, Any]) -> None:
        refresh_token = require_token(body.get("refresh_token"), label="Refresh token")
        connection = get_connection()
        session = connection.execute(
            """
            select * from sessions
            where refresh_token_hash = ?
            """,
            (hash_token(refresh_token),),
        ).fetchone()
        if session is None or parse_iso(session["refresh_expires_at"]) <= now_utc():
            with connection:
                connection.execute(
                    "delete from sessions where refresh_token_hash = ?",
                    (hash_token(refresh_token),),
                )
            connection.close()
            raise ApiError(HTTPStatus.UNAUTHORIZED, "Session refresh failed.")

        with connection:
            sync_user_context(connection, session["user_id"])
            connection.execute("delete from sessions where id = ?", (session["id"],))
            tokens = create_session(connection, session["user_id"])
        connection.close()
        self.send_json(HTTPStatus.OK, tokens)

    def handle_request_password_reset(self, body: dict[str, Any]) -> None:
        email = require_email(body.get("email"))
        connection = get_connection()
        user = connection.execute(
            "select id from users where email = ? and deleted_at is null",
            (email,),
        ).fetchone()
        if user is not None:
            with connection:
                token = issue_password_reset_token(connection, user["id"])
            print(f"[boxos-backend] Password reset token for {email}: {token}")
        connection.close()
        self.send_json(HTTPStatus.OK, {"message": "If the account exists, a reset token has been issued in the backend log."})

    def handle_get_profile(self) -> None:
        session = self.require_session()
        connection = get_connection()
        user = connection.execute(
            """
            select id, email, role, roles_json, display_name, nickname
                , account_type, active_gym_id
            from users
            where id = ? and deleted_at is null
            """,
            (session["user_id"],),
        ).fetchone()
        connection.close()
        if user is None:
            raise ApiError(HTTPStatus.NOT_FOUND, "Profile not found.")
        self.send_json(HTTPStatus.OK, profile_payload(user))

    def handle_update_profile(self, body: dict[str, Any]) -> None:
        session = self.require_session()
        display_name = require_display_name(body.get("display_name"))
        nickname = require_nickname(body.get("nickname"))
        connection = get_connection()
        with connection:
            connection.execute(
                """
                update users
                set display_name = ?, nickname = ?, updated_at = ?
                where id = ? and deleted_at is null
                """,
                (display_name, nickname, isoformat(now_utc()), session["user_id"]),
            )
        user = connection.execute(
            "select id, email, role, roles_json, display_name, nickname, account_type, active_gym_id from users where id = ?",
            (session["user_id"],),
        ).fetchone()
        connection.close()
        if user is None:
            raise ApiError(HTTPStatus.NOT_FOUND, "Profile not found.")
        self.send_json(HTTPStatus.OK, profile_payload(user))

    def handle_get_notification_preferences(self) -> None:
        session = self.require_session()
        connection = get_connection()
        user = connection.execute(
            """
            select
                notify_booking_confirmations,
                notify_waitlist_promotions,
                notify_payment_issues,
                notify_wod_posted,
                notify_pr_achievements
            from users
            where id = ? and deleted_at is null
            """,
            (session["user_id"],),
        ).fetchone()
        connection.close()
        if user is None:
            raise ApiError(HTTPStatus.NOT_FOUND, "Notification preferences not found.")
        self.send_json(HTTPStatus.OK, notification_preferences_payload(user))

    def handle_update_notification_preferences(self, body: dict[str, Any]) -> None:
        session = self.require_session()
        preferences = require_notification_preferences(body)
        connection = get_connection()
        with connection:
            connection.execute(
                """
                update users
                set notify_booking_confirmations = ?,
                    notify_waitlist_promotions = ?,
                    notify_payment_issues = ?,
                    notify_wod_posted = ?,
                    notify_pr_achievements = ?,
                    updated_at = ?
                where id = ? and deleted_at is null
                """,
                (
                    int(preferences["booking_confirmations"]),
                    int(preferences["waitlist_promotions"]),
                    int(preferences["payment_issues"]),
                    int(preferences["wod_posted"]),
                    int(preferences["pr_achievements"]),
                    isoformat(now_utc()),
                    session["user_id"],
                ),
            )
        user = connection.execute(
            """
            select
                notify_booking_confirmations,
                notify_waitlist_promotions,
                notify_payment_issues,
                notify_wod_posted,
                notify_pr_achievements
            from users
            where id = ? and deleted_at is null
            """,
            (session["user_id"],),
        ).fetchone()
        connection.close()
        if user is None:
            raise ApiError(HTTPStatus.NOT_FOUND, "Notification preferences not found.")
        self.send_json(HTTPStatus.OK, notification_preferences_payload(user))

    def handle_update_active_role(self, body: dict[str, Any]) -> None:
        session = self.require_session()
        role = require_role_value(body.get("role"))
        assigned_roles = decode_roles(session["roles_json"])
        if role not in assigned_roles:
            raise ApiError(
                HTTPStatus.BAD_REQUEST,
                "The selected role is not assigned to this user.",
            )
        connection = get_connection()
        with connection:
            membership = get_active_membership(connection, session["user_id"])
            if membership is not None:
                connection.execute(
                    """
                    update gym_memberships
                    set active_role = ?, updated_at = ?
                    where id = ?
                    """,
                    (role, isoformat(now_utc()), membership["id"]),
                )
                sync_user_context(connection, session["user_id"])
            else:
                connection.execute(
                    """
                    update users
                    set role = ?, updated_at = ?
                    where id = ? and deleted_at is null
                    """,
                    (role, isoformat(now_utc()), session["user_id"]),
                )
        user = connection.execute(
            "select id, email, role, roles_json, display_name, nickname, account_type, active_gym_id from users where id = ?",
            (session["user_id"],),
        ).fetchone()
        connection.close()
        if user is None:
            raise ApiError(HTTPStatus.NOT_FOUND, "Profile not found.")
        self.send_json(HTTPStatus.OK, profile_payload(user))

    def handle_update_active_gym(self, body: dict[str, Any]) -> None:
        session = self.require_session()
        gym_id = require_user_id(body.get("gym_id"))
        connection = get_connection()
        membership = connection.execute(
            """
            select id from gym_memberships
            where user_id = ? and gym_id = ? and status = 'active'
            """,
            (session["user_id"], gym_id),
        ).fetchone()
        if membership is None:
            connection.close()
            raise ApiError(HTTPStatus.BAD_REQUEST, "You are not an active member of that gym.")
        with connection:
            connection.execute(
                "update users set active_gym_id = ?, updated_at = ? where id = ?",
                (gym_id, isoformat(now_utc()), session["user_id"]),
            )
            sync_user_context(connection, session["user_id"])
        user = connection.execute(
            "select id, email, role, roles_json, display_name, nickname, account_type, active_gym_id from users where id = ?",
            (session["user_id"],),
        ).fetchone()
        connection.close()
        if user is None:
            raise ApiError(HTTPStatus.NOT_FOUND, "Profile not found.")
        self.send_json(HTTPStatus.OK, profile_payload(user))

    def handle_list_gyms(self) -> None:
        connection = get_connection()
        rows = connection.execute(
            """
            select id, name, slug, logo_url, timezone
            from gyms
            order by name asc
            """
        ).fetchall()
        connection.close()
        self.send_json(
            HTTPStatus.OK,
            {
                "gyms": [
                    {
                        "id": row["id"],
                        "name": row["name"],
                        "slug": row["slug"],
                        "logo_url": row["logo_url"],
                        "timezone": row["timezone"],
                    }
                    for row in rows
                ]
            },
        )

    def handle_list_schedule_classes(self) -> None:
        session = self.require_active_gym_member_session()
        connection = get_connection()
        include_bookings = session["role"] in {"admin", "trainer"}
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
              trainer.display_name as assigned_trainer_display_name,
              trainer.nickname as assigned_trainer_nickname,
              class_schedules.wod_description
            from class_schedules
            left join users trainer on trainer.id = class_schedules.assigned_trainer_user_id
            where class_schedules.gym_id = ?
            order by start_time asc
            """,
            (session["active_gym_id"],),
        ).fetchall()
        payload = [
            schedule_class_payload(
                connection,
                row,
                current_user_id=session["user_id"],
                include_bookings=include_bookings,
            )
            for row in rows
        ]
        connection.close()
        self.send_json(
            HTTPStatus.OK,
            {"classes": payload},
        )

    def handle_list_schedule_trainers(self) -> None:
        session = self.require_schedule_manager_session()
        connection = get_connection()
        rows = connection.execute(
            """
            select
              users.id,
              users.display_name,
              users.nickname
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
        connection.close()
        self.send_json(
            HTTPStatus.OK,
            {
                "trainers": [
                    {
                        "id": row["id"],
                        "display_name": row["display_name"],
                        "nickname": row["nickname"],
                    }
                    for row in rows
                ]
            },
        )

    def handle_create_schedule_class(self, body: dict[str, Any]) -> None:
        session = self.require_schedule_manager_session()
        title = require_schedule_title(body.get("title"))
        class_type = require_class_type(body.get("class_type"))
        start_time = require_future_datetime(body.get("start_time"), label="Start time")
        duration_minutes = require_schedule_duration_minutes(body)
        capacity = require_capacity(body.get("capacity"))
        trainer_user_id = require_optional_user_id(body.get("trainer_user_id"))
        wod_description = require_wod_description(body.get("wod_description"))
        end_time = start_time + timedelta(minutes=duration_minutes)
        timestamp = isoformat(now_utc())
        connection = get_connection()
        if trainer_user_id is not None:
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
            (session["active_gym_id"], trainer_user_id),
        ).fetchone()
            if assigned_trainer is None:
                connection.close()
                raise ApiError(HTTPStatus.BAD_REQUEST, "Selected trainer is not active in this gym.")
        with connection:
            cursor = connection.execute(
                """
                insert into class_schedules (
                  gym_id, title, class_type, start_time, end_time, duration_minutes, capacity, assigned_trainer_user_id, wod_description,
                  created_by_user_id, updated_by_user_id, created_at, updated_at
                )
                values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    session["active_gym_id"],
                    title,
                    class_type,
                    isoformat(start_time),
                    isoformat(end_time),
                    duration_minutes,
                    capacity,
                    trainer_user_id,
                    wod_description,
                    session["user_id"],
                    session["user_id"],
                    timestamp,
                    timestamp,
                ),
            )
            schedule_id = int(cursor.lastrowid)
            row = connection.execute(
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
                  trainer.display_name as assigned_trainer_display_name,
                  trainer.nickname as assigned_trainer_nickname,
                  class_schedules.wod_description
                from class_schedules
                left join users trainer on trainer.id = class_schedules.assigned_trainer_user_id
                where class_schedules.id = ?
                """,
                (schedule_id,),
            ).fetchone()
            if row is None:
                raise ApiError(
                    HTTPStatus.INTERNAL_SERVER_ERROR,
                    "Schedule class creation failed.",
                )
            payload = schedule_class_payload(
                    connection,
                    row,
                    current_user_id=session["user_id"],
                    include_bookings=session["role"] in {"admin", "trainer"},
                )
            write_audit_log(
                connection,
                gym_id=session["active_gym_id"],
                actor_user_id=session["user_id"],
                action="schedule_class_created",
                entity_type="schedule_class",
                entity_id=schedule_id,
                details={
                    "title": title,
                    "class_type": class_type,
                    "start_time": isoformat(start_time),
                    "duration_minutes": duration_minutes,
                    "capacity": capacity,
                    "trainer_user_id": trainer_user_id,
                },
            )
        connection.close()
        self.send_json(HTTPStatus.CREATED, {"class": payload})

    def handle_update_schedule_class(self, body: dict[str, Any]) -> None:
        session = self.require_schedule_manager_session()
        schedule_id = require_user_id(body.get("id"))
        title = require_schedule_title(body.get("title"))
        class_type = require_class_type(body.get("class_type"))
        start_time = require_future_datetime(body.get("start_time"), label="Start time")
        duration_minutes = require_schedule_duration_minutes(body)
        capacity = require_capacity(body.get("capacity"))
        trainer_user_id = require_optional_user_id(body.get("trainer_user_id"))
        wod_description = require_wod_description(body.get("wod_description"))
        end_time = start_time + timedelta(minutes=duration_minutes)
        connection = get_connection()
        existing = connection.execute(
            """
            select id, start_time
            from class_schedules
            where id = ? and gym_id = ?
            """,
            (schedule_id, session["active_gym_id"]),
        ).fetchone()
        if existing is None:
            connection.close()
            raise ApiError(HTTPStatus.NOT_FOUND, "Schedule class not found.")
        if parse_iso(existing["start_time"]) <= now_utc():
            connection.close()
            raise ApiError(
                HTTPStatus.BAD_REQUEST,
                "Only future classes can be edited.",
            )
        booked_count_row = connection.execute(
            """
            select count(*) as booked_count
            from class_bookings
            where class_schedule_id = ?
            """,
            (schedule_id,),
        ).fetchone()
        booked_count = int(booked_count_row["booked_count"]) if booked_count_row is not None else 0
        if capacity < booked_count:
            connection.close()
            raise ApiError(
                HTTPStatus.BAD_REQUEST,
                "Capacity cannot be lower than the current booking count.",
            )
        if trainer_user_id is not None:
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
            (session["active_gym_id"], trainer_user_id),
        ).fetchone()
            if assigned_trainer is None:
                connection.close()
                raise ApiError(HTTPStatus.BAD_REQUEST, "Selected trainer is not active in this gym.")
        with connection:
            connection.execute(
                """
                update class_schedules
                set title = ?,
                    class_type = ?,
                    start_time = ?,
                    end_time = ?,
                    duration_minutes = ?,
                    capacity = ?,
                    assigned_trainer_user_id = ?,
                    wod_description = ?,
                    updated_by_user_id = ?,
                    updated_at = ?
                where id = ?
                """,
                (
                    title,
                    class_type,
                    isoformat(start_time),
                    isoformat(end_time),
                    duration_minutes,
                    capacity,
                    trainer_user_id,
                    wod_description,
                    session["user_id"],
                    isoformat(now_utc()),
                    schedule_id,
                ),
            )
            row = connection.execute(
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
                  trainer.display_name as assigned_trainer_display_name,
                  trainer.nickname as assigned_trainer_nickname,
                  class_schedules.wod_description
                from class_schedules
                left join users trainer on trainer.id = class_schedules.assigned_trainer_user_id
                where class_schedules.id = ?
                """,
                (schedule_id,),
            ).fetchone()
            if row is None:
                raise ApiError(HTTPStatus.NOT_FOUND, "Schedule class not found.")
            payload = schedule_class_payload(
                    connection,
                    row,
                    current_user_id=session["user_id"],
                    include_bookings=session["role"] in {"admin", "trainer"},
                )
            write_audit_log(
                connection,
                gym_id=session["active_gym_id"],
                actor_user_id=session["user_id"],
                action="schedule_class_updated",
                entity_type="schedule_class",
                entity_id=schedule_id,
                details={
                    "title": title,
                    "class_type": class_type,
                    "start_time": isoformat(start_time),
                    "duration_minutes": duration_minutes,
                    "capacity": capacity,
                    "trainer_user_id": trainer_user_id,
                },
            )
        connection.close()
        self.send_json(HTTPStatus.OK, {"class": payload})

    def handle_delete_schedule_class(self, body: dict[str, Any]) -> None:
        session = self.require_schedule_manager_session()
        schedule_id = require_user_id(body.get("id"))
        connection = get_connection()
        existing = connection.execute(
            """
            select id, start_time
            from class_schedules
            where id = ? and gym_id = ?
            """,
            (schedule_id, session["active_gym_id"]),
        ).fetchone()
        if existing is None:
            connection.close()
            raise ApiError(HTTPStatus.NOT_FOUND, "Schedule class not found.")
        if parse_iso(existing["start_time"]) <= now_utc():
            connection.close()
            raise ApiError(
                HTTPStatus.BAD_REQUEST,
                "Only future classes can be deleted.",
            )
        with connection:
            connection.execute(
                "delete from class_schedules where id = ?",
                (schedule_id,),
            )
            write_audit_log(
                connection,
                gym_id=session["active_gym_id"],
                actor_user_id=session["user_id"],
                action="schedule_class_deleted",
                entity_type="schedule_class",
                entity_id=schedule_id,
            )
        connection.close()
        self.send_json(HTTPStatus.OK, {"message": "Schedule class deleted."})

    def handle_create_class_booking(self, body: dict[str, Any]) -> None:
        session = self.require_active_gym_member_session()
        schedule_id = require_user_id(body.get("class_id"))
        connection = get_connection()
        schedule_row = connection.execute(
            """
            select id, gym_id, start_time, capacity
            from class_schedules
            where id = ? and gym_id = ?
            """,
            (schedule_id, session["active_gym_id"]),
        ).fetchone()
        if schedule_row is None:
            connection.close()
            raise ApiError(HTTPStatus.NOT_FOUND, "Schedule class not found.")
        if parse_iso(schedule_row["start_time"]) <= now_utc():
            connection.close()
            raise ApiError(
                HTTPStatus.BAD_REQUEST,
                "Only future classes can be booked.",
            )
        existing_booking = connection.execute(
            """
            select id
            from class_bookings
            where class_schedule_id = ? and user_id = ?
            """,
            (schedule_id, session["user_id"]),
        ).fetchone()
        if existing_booking is not None:
            connection.close()
            raise ApiError(
                HTTPStatus.CONFLICT,
                "You have already booked this class.",
            )
        booking_count_row = connection.execute(
            """
            select count(*) as booked_count
            from class_bookings
            where class_schedule_id = ?
            """,
            (schedule_id,),
        ).fetchone()
        booked_count = (
            int(booking_count_row["booked_count"]) if booking_count_row is not None else 0
        )
        if booked_count >= schedule_row["capacity"]:
            connection.close()
            raise ApiError(
                HTTPStatus.CONFLICT,
                "This class is already full.",
            )
        with connection:
            connection.execute(
                """
                insert into class_bookings (
                  class_schedule_id, user_id, attendance_status, created_at
                )
                values (?, ?, 'booked', ?)
                """,
                (schedule_id, session["user_id"], isoformat(now_utc())),
            )
        connection.close()
        self.send_json(HTTPStatus.CREATED, {"message": "Class booked."})

    def handle_delete_class_booking(self, body: dict[str, Any]) -> None:
        session = self.require_active_gym_member_session()
        schedule_id = require_user_id(body.get("class_id"))
        connection = get_connection()
        schedule_row = connection.execute(
            """
            select id, gym_id, start_time
            from class_schedules
            where id = ? and gym_id = ?
            """,
            (schedule_id, session["active_gym_id"]),
        ).fetchone()
        if schedule_row is None:
            connection.close()
            raise ApiError(HTTPStatus.NOT_FOUND, "Schedule class not found.")
        if parse_iso(schedule_row["start_time"]) <= now_utc():
            connection.close()
            raise ApiError(
                HTTPStatus.BAD_REQUEST,
                "Only future classes can be cancelled.",
            )
        existing_booking = connection.execute(
            """
            select id
            from class_bookings
            where class_schedule_id = ? and user_id = ?
            """,
            (schedule_id, session["user_id"]),
        ).fetchone()
        if existing_booking is None:
            connection.close()
            raise ApiError(
                HTTPStatus.NOT_FOUND,
                "You do not have a booking for this class.",
            )
        with connection:
            connection.execute(
                """
                delete from class_bookings
                where class_schedule_id = ? and user_id = ?
                """,
                (schedule_id, session["user_id"]),
            )
        connection.close()
        self.send_json(HTTPStatus.OK, {"message": "Booking cancelled."})

    def handle_update_class_attendance(self, body: dict[str, Any]) -> None:
        session = self.require_schedule_manager_session()
        schedule_id = require_user_id(body.get("class_id"))
        user_id = require_user_id(body.get("user_id"))
        attendance_status = require_attendance_status(body.get("attendance_status"))
        connection = get_connection()
        schedule_row = connection.execute(
            """
            select id, start_time
            from class_schedules
            where id = ? and gym_id = ?
            """,
            (schedule_id, session["active_gym_id"]),
        ).fetchone()
        if schedule_row is None:
            connection.close()
            raise ApiError(HTTPStatus.NOT_FOUND, "Schedule class not found.")
        if parse_iso(schedule_row["start_time"]) > now_utc():
            connection.close()
            raise ApiError(
                HTTPStatus.BAD_REQUEST,
                "Attendance can only be recorded after the class has started.",
            )
        booking_row = connection.execute(
            """
            select id
            from class_bookings
            where class_schedule_id = ? and user_id = ?
            """,
            (schedule_id, user_id),
        ).fetchone()
        if booking_row is None:
            connection.close()
            raise ApiError(
                HTTPStatus.NOT_FOUND,
                "That athlete does not have a booking for this class.",
            )
        with connection:
            connection.execute(
                """
                update class_bookings
                set attendance_status = ?,
                    attendance_marked_at = ?,
                    attendance_marked_by_user_id = ?
                where class_schedule_id = ? and user_id = ?
                """,
                (
                    attendance_status,
                    isoformat(now_utc()),
                    session["user_id"],
                    schedule_id,
                    user_id,
                ),
            )
            row = connection.execute(
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
                  trainer.display_name as assigned_trainer_display_name,
                  trainer.nickname as assigned_trainer_nickname,
                  class_schedules.wod_description
                from class_schedules
                left join users trainer on trainer.id = class_schedules.assigned_trainer_user_id
                where class_schedules.id = ?
                """,
                (schedule_id,),
            ).fetchone()
            if row is None:
                raise ApiError(HTTPStatus.NOT_FOUND, "Schedule class not found.")
            payload = schedule_class_payload(
                connection,
                row,
                current_user_id=session["user_id"],
                include_bookings=True,
            )
        connection.close()
        self.send_json(HTTPStatus.OK, {"class": payload})

    def handle_list_daily_workouts(self) -> None:
        session = self.require_active_gym_member_session()
        connection = get_connection()
        rows = connection.execute(
            """
            select
              daily_workouts.id,
              daily_workouts.gym_id,
              daily_workouts.scheduled_date,
              daily_workouts.title,
              daily_workouts.strength_text,
              daily_workouts.metcon_text,
              daily_workouts.notes_text,
              daily_workouts.created_at,
              daily_workouts.updated_at
            from daily_workouts
            where daily_workouts.gym_id = ?
            order by daily_workouts.scheduled_date asc
            """,
            (session["active_gym_id"],),
        ).fetchall()
        workouts = [
            daily_workout_payload(
                connection,
                row,
                current_user_id=session["user_id"],
                can_edit=session["role"] in {"admin", "trainer"},
            )
            for row in rows
        ]
        connection.close()
        self.send_json(HTTPStatus.OK, {"workouts": workouts})

    def handle_create_daily_workout(self, body: dict[str, Any]) -> None:
        session = self.require_schedule_manager_session()
        scheduled_date = require_programming_date(body.get("scheduled_date"))
        title = require_programming_title(body.get("title"))
        strength_text = require_programming_section(body.get("strength_text"), label="Strength")
        metcon_text = require_programming_section(body.get("metcon_text"), label="MetCon")
        notes_text = require_programming_section(body.get("notes_text"), label="Notes")
        connection = get_connection()
        existing = connection.execute(
            "select id from daily_workouts where gym_id = ? and scheduled_date = ?",
            (session["active_gym_id"], scheduled_date),
        ).fetchone()
        if existing is not None:
            connection.close()
            raise ApiError(HTTPStatus.CONFLICT, "A workout already exists for this date.")
        timestamp = isoformat(now_utc())
        with connection:
            cursor = connection.execute(
                """
                insert into daily_workouts (
                  gym_id, scheduled_date, title, strength_text, metcon_text, notes_text,
                  created_by_user_id, updated_by_user_id, created_at, updated_at
                )
                values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    session["active_gym_id"],
                    scheduled_date,
                    title,
                    strength_text,
                    metcon_text,
                    notes_text,
                    session["user_id"],
                    session["user_id"],
                    timestamp,
                    timestamp,
                ),
            )
            row = connection.execute(
                "select id, gym_id, scheduled_date, title, strength_text, metcon_text, notes_text, created_at, updated_at from daily_workouts where id = ?",
                (int(cursor.lastrowid),),
            ).fetchone()
            payload = daily_workout_payload(
                connection,
                row,
                current_user_id=session["user_id"],
                can_edit=True,
            )
            write_audit_log(
                connection,
                gym_id=session["active_gym_id"],
                actor_user_id=session["user_id"],
                action="daily_workout_created",
                entity_type="daily_workout",
                entity_id=int(cursor.lastrowid),
                details={
                    "scheduled_date": scheduled_date,
                    "title": title,
                },
            )
        connection.close()
        self.send_json(HTTPStatus.CREATED, {"workout": payload})

    def handle_update_daily_workout(self, body: dict[str, Any]) -> None:
        session = self.require_schedule_manager_session()
        workout_id = require_user_id(body.get("id"))
        scheduled_date = require_programming_date(body.get("scheduled_date"))
        title = require_programming_title(body.get("title"))
        strength_text = require_programming_section(body.get("strength_text"), label="Strength")
        metcon_text = require_programming_section(body.get("metcon_text"), label="MetCon")
        notes_text = require_programming_section(body.get("notes_text"), label="Notes")
        connection = get_connection()
        existing = connection.execute(
            "select id, scheduled_date from daily_workouts where id = ? and gym_id = ?",
            (workout_id, session["active_gym_id"]),
        ).fetchone()
        if existing is None:
            connection.close()
            raise ApiError(HTTPStatus.NOT_FOUND, "Workout not found.")
        if parse_programming_date(existing["scheduled_date"]) < today_utc_date():
            connection.close()
            raise ApiError(HTTPStatus.BAD_REQUEST, "Past workouts cannot be edited.")
        duplicate = connection.execute(
            "select id from daily_workouts where gym_id = ? and scheduled_date = ? and id != ?",
            (session["active_gym_id"], scheduled_date, workout_id),
        ).fetchone()
        if duplicate is not None:
            connection.close()
            raise ApiError(HTTPStatus.CONFLICT, "A workout already exists for this date.")
        with connection:
            connection.execute(
                """
                update daily_workouts
                set scheduled_date = ?,
                    title = ?,
                    strength_text = ?,
                    metcon_text = ?,
                    notes_text = ?,
                    updated_by_user_id = ?,
                    updated_at = ?
                where id = ?
                """,
                (
                    scheduled_date,
                    title,
                    strength_text,
                    metcon_text,
                    notes_text,
                    session["user_id"],
                    isoformat(now_utc()),
                    workout_id,
                ),
            )
            row = connection.execute(
                "select id, gym_id, scheduled_date, title, strength_text, metcon_text, notes_text, created_at, updated_at from daily_workouts where id = ?",
                (workout_id,),
            ).fetchone()
            payload = daily_workout_payload(
                connection,
                row,
                current_user_id=session["user_id"],
                can_edit=True,
            )
            write_audit_log(
                connection,
                gym_id=session["active_gym_id"],
                actor_user_id=session["user_id"],
                action="daily_workout_updated",
                entity_type="daily_workout",
                entity_id=workout_id,
                details={
                    "scheduled_date": scheduled_date,
                    "title": title,
                },
            )
        connection.close()
        self.send_json(HTTPStatus.OK, {"workout": payload})

    def handle_submit_whiteboard_result(self, body: dict[str, Any]) -> None:
        session = self.require_active_gym_member_session()
        workout_id = require_user_id(body.get("workout_id"))
        score_type, score_value, score_label = require_whiteboard_score(
            body.get("score_type"),
            body.get("score_value"),
        )
        notes_text = require_whiteboard_notes(body.get("notes_text"))
        connection = get_connection()
        workout = connection.execute(
            """
            select id, gym_id, scheduled_date, title, strength_text, metcon_text, notes_text, created_at, updated_at
            from daily_workouts
            where id = ? and gym_id = ?
            """,
            (workout_id, session["active_gym_id"]),
        ).fetchone()
        if workout is None:
            connection.close()
            raise ApiError(HTTPStatus.NOT_FOUND, "Workout not found.")
        if parse_programming_date(workout["scheduled_date"]) > today_utc_date():
            connection.close()
            raise ApiError(HTTPStatus.BAD_REQUEST, "Results can only be submitted on or after the workout date.")

        timestamp = isoformat(now_utc())
        with connection:
            existing = connection.execute(
                "select id from whiteboard_results where daily_workout_id = ? and user_id = ?",
                (workout_id, session["user_id"]),
            ).fetchone()
            action = "whiteboard_result_created" if existing is None else "whiteboard_result_updated"
            if existing is None:
                connection.execute(
                    """
                    insert into whiteboard_results (
                      daily_workout_id, gym_id, user_id, score_type, score_value,
                      score_label, notes_text, created_at, updated_at
                    )
                    values (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        workout_id,
                        session["active_gym_id"],
                        session["user_id"],
                        score_type,
                        score_value,
                        score_label,
                        notes_text,
                        timestamp,
                        timestamp,
                    ),
                )
            else:
                connection.execute(
                    """
                    update whiteboard_results
                    set score_type = ?,
                        score_value = ?,
                        score_label = ?,
                        notes_text = ?,
                        updated_at = ?
                    where id = ?
                    """,
                    (
                        score_type,
                        score_value,
                        score_label,
                        notes_text,
                        timestamp,
                        existing["id"],
                    ),
                )
            payload = daily_workout_payload(
                connection,
                workout,
                current_user_id=session["user_id"],
                can_edit=session["role"] in {"admin", "trainer"},
            )
            write_audit_log(
                connection,
                gym_id=session["active_gym_id"],
                actor_user_id=session["user_id"],
                target_user_id=session["user_id"],
                action=action,
                entity_type="whiteboard_result",
                entity_id=workout_id,
                details={
                    "workout_id": workout_id,
                    "score_type": score_type,
                    "score_label": score_label,
                },
            )
        connection.close()
        self.send_json(HTTPStatus.OK, {"workout": payload})

    def handle_list_workout_logs(self) -> None:
        session = self.require_active_gym_member_session()
        connection = get_connection()
        rows = connection.execute(
            """
            select
              workout_logs.id,
              workout_logs.daily_workout_id,
              workout_logs.class_schedule_id,
              workout_logs.score_type,
              workout_logs.score_value,
              workout_logs.score_label,
              workout_logs.notes_text,
              workout_logs.created_at,
              workout_logs.updated_at,
              daily_workouts.scheduled_date,
              daily_workouts.title as workout_title,
              class_schedules.title as class_title,
              class_schedules.start_time as class_start_time
            from workout_logs
            join daily_workouts on daily_workouts.id = workout_logs.daily_workout_id
            left join class_schedules on class_schedules.id = workout_logs.class_schedule_id
            where workout_logs.user_id = ? and workout_logs.gym_id = ?
            order by daily_workouts.scheduled_date desc, workout_logs.updated_at desc
            """,
            (session["user_id"], session["active_gym_id"]),
        ).fetchall()
        connection.close()
        self.send_json(HTTPStatus.OK, {"entries": [workout_log_payload(row) for row in rows]})

    def handle_submit_workout_log(self, body: dict[str, Any]) -> None:
        session = self.require_active_gym_member_session()
        workout_id = require_user_id(body.get("workout_id"))
        class_id = require_optional_user_id(body.get("class_id"))
        score_type, score_value, score_label = require_whiteboard_score(
            body.get("score_type"),
            body.get("score_value"),
        )
        notes_text = require_whiteboard_notes(body.get("notes_text"))
        connection = get_connection()
        workout = connection.execute(
            """
            select id, gym_id, scheduled_date, title
            from daily_workouts
            where id = ? and gym_id = ?
            """,
            (workout_id, session["active_gym_id"]),
        ).fetchone()
        if workout is None:
            connection.close()
            raise ApiError(HTTPStatus.NOT_FOUND, "Workout not found.")
        if class_id is not None:
            class_row = connection.execute(
                """
                select id from class_schedules
                where id = ? and gym_id = ?
                """,
                (class_id, session["active_gym_id"]),
            ).fetchone()
            if class_row is None:
                connection.close()
                raise ApiError(HTTPStatus.NOT_FOUND, "Class not found.")
        timestamp = isoformat(now_utc())
        with connection:
            existing = connection.execute(
                "select id from workout_logs where user_id = ? and daily_workout_id = ?",
                (session["user_id"], workout_id),
            ).fetchone()
            if existing is None:
                connection.execute(
                    """
                    insert into workout_logs (
                      user_id, gym_id, daily_workout_id, class_schedule_id, score_type,
                      score_value, score_label, notes_text, created_at, updated_at
                    ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        session["user_id"],
                        session["active_gym_id"],
                        workout_id,
                        class_id,
                        score_type,
                        score_value,
                        score_label,
                        notes_text,
                        timestamp,
                        timestamp,
                    ),
                )
                action = "workout_log_created"
            else:
                connection.execute(
                    """
                    update workout_logs
                    set class_schedule_id = ?,
                        score_type = ?,
                        score_value = ?,
                        score_label = ?,
                        notes_text = ?,
                        updated_at = ?
                    where id = ?
                    """,
                    (
                        class_id,
                        score_type,
                        score_value,
                        score_label,
                        notes_text,
                        timestamp,
                        existing["id"],
                    ),
                )
                action = "workout_log_updated"
            row = connection.execute(
                """
                select
                  workout_logs.id,
                  workout_logs.daily_workout_id,
                  workout_logs.class_schedule_id,
                  workout_logs.score_type,
                  workout_logs.score_value,
                  workout_logs.score_label,
                  workout_logs.notes_text,
                  workout_logs.created_at,
                  workout_logs.updated_at,
                  daily_workouts.scheduled_date,
                  daily_workouts.title as workout_title,
                  class_schedules.title as class_title,
                  class_schedules.start_time as class_start_time
                from workout_logs
                join daily_workouts on daily_workouts.id = workout_logs.daily_workout_id
                left join class_schedules on class_schedules.id = workout_logs.class_schedule_id
                where workout_logs.user_id = ? and workout_logs.daily_workout_id = ?
                """,
                (session["user_id"], workout_id),
            ).fetchone()
            write_audit_log(
                connection,
                gym_id=session["active_gym_id"],
                actor_user_id=session["user_id"],
                target_user_id=session["user_id"],
                action=action,
                entity_type="workout_log",
                entity_id=row["id"] if row is not None else None,
                details={"workout_id": workout_id, "score_type": score_type, "score_label": score_label},
            )
        connection.close()
        if row is None:
            raise ApiError(HTTPStatus.INTERNAL_SERVER_ERROR, "Workout log could not be saved.")
        self.send_json(HTTPStatus.OK, {"entry": workout_log_payload(row)})

    def handle_create_gym(self, body: dict[str, Any]) -> None:
        session = self.require_session()
        if session["account_type"] != "admin":
            raise ApiError(
                HTTPStatus.FORBIDDEN,
                "Only admin accounts can create a gym.",
            )
        name = require_gym_name(body.get("name"))
        logo_url = require_logo_url(body.get("logo_url"))
        timezone = require_timezone(body.get("timezone"))
        connection = get_connection()
        timestamp = isoformat(now_utc())
        with connection:
            slug = unique_gym_slug(connection, name)
            gym_cursor = connection.execute(
                """
                insert into gyms (
                  name, slug, logo_url, timezone, created_by_user_id, created_at, updated_at
                )
                values (?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    name,
                    slug,
                    logo_url,
                    timezone,
                    session["user_id"],
                    timestamp,
                    timestamp,
                ),
            )
            gym_id = int(gym_cursor.lastrowid)
            connection.execute(
                """
                insert into gym_memberships (
                  user_id, gym_id, active_role, roles_json, status, created_at, updated_at
                )
                values (?, ?, 'admin', ?, 'active', ?, ?)
                """,
                (
                    session["user_id"],
                    gym_id,
                    encode_roles(["admin"]),
                    timestamp,
                    timestamp,
                ),
            )
            connection.execute(
                "update users set active_gym_id = ?, updated_at = ? where id = ?",
                (gym_id, timestamp, session["user_id"]),
            )
            sync_user_context(connection, session["user_id"])
            gym = connection.execute(
                "select id, name, slug, logo_url, timezone from gyms where id = ?",
                (gym_id,),
            ).fetchone()
        connection.close()
        if gym is None:
            raise ApiError(HTTPStatus.INTERNAL_SERVER_ERROR, "Gym creation failed.")
        self.send_json(
            HTTPStatus.CREATED,
            {
                "gym": {
                    "id": gym["id"],
                    "name": gym["name"],
                    "slug": gym["slug"],
                    "logo_url": gym["logo_url"],
                    "timezone": gym["timezone"],
                }
            },
        )

    def handle_create_join_request(self, body: dict[str, Any]) -> None:
        session = self.require_session()
        gym_id = require_user_id(body.get("gym_id"))
        connection = get_connection()
        gym = connection.execute(
            "select id from gyms where id = ?",
            (gym_id,),
        ).fetchone()
        if gym is None:
            connection.close()
            raise ApiError(HTTPStatus.NOT_FOUND, "Gym not found.")
        existing_membership = connection.execute(
            """
            select id from gym_memberships
            where user_id = ? and gym_id = ? and status = 'active'
            """,
            (session["user_id"], gym_id),
        ).fetchone()
        if existing_membership is not None:
            connection.close()
            raise ApiError(HTTPStatus.CONFLICT, "You are already a member of this gym.")
        existing_request = connection.execute(
            """
            select id from gym_join_requests
            where user_id = ? and gym_id = ? and status = 'pending'
            """,
            (session["user_id"], gym_id),
        ).fetchone()
        if existing_request is not None:
            connection.close()
            raise ApiError(HTTPStatus.CONFLICT, "A join request is already pending.")
        timestamp = isoformat(now_utc())
        with connection:
            connection.execute(
                """
                insert into gym_join_requests (user_id, gym_id, status, created_at, updated_at)
                values (?, ?, 'pending', ?, ?)
                """,
                (session["user_id"], gym_id, timestamp, timestamp),
            )
        connection.close()
        self.send_json(HTTPStatus.CREATED, {"message": "Join request submitted."})

    def handle_list_join_requests(self) -> None:
        session = self.require_session()
        if session["role"] != "admin" or session["active_gym_id"] is None:
            raise ApiError(
                HTTPStatus.FORBIDDEN,
                "An active admin gym context is required.",
            )
        connection = get_connection()
        rows = connection.execute(
            """
            select
              gym_join_requests.id,
              gym_join_requests.created_at,
              users.email,
              users.display_name,
              users.nickname
            from gym_join_requests
            join users on users.id = gym_join_requests.user_id
            where gym_join_requests.gym_id = ?
              and gym_join_requests.status = 'pending'
            order by gym_join_requests.created_at asc
            """,
            (session["active_gym_id"],),
        ).fetchall()
        connection.close()
        self.send_json(
            HTTPStatus.OK,
            {
                "requests": [
                    {
                        "id": row["id"],
                        "email": row["email"],
                        "display_name": row["display_name"],
                        "nickname": row["nickname"],
                        "created_at": row["created_at"],
                    }
                    for row in rows
                ]
            },
        )

    def handle_list_audit_logs(self) -> None:
        session = self.require_role("admin")
        if session["active_gym_id"] is None:
            raise ApiError(
                HTTPStatus.FORBIDDEN,
                "An active admin gym context is required.",
            )
        connection = get_connection()
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
        connection.close()
        self.send_json(
            HTTPStatus.OK,
            {"logs": [audit_log_payload(row) for row in rows]},
        )

    def handle_list_my_join_requests(self) -> None:
        session = self.require_session()
        connection = get_connection()
        rows = connection.execute(
            """
            select
              gym_join_requests.id,
              gym_join_requests.status,
              gym_join_requests.created_at,
              gym_join_requests.reviewed_at,
              gyms.id as gym_id,
              gyms.name as gym_name,
              gyms.slug as gym_slug,
              gyms.logo_url as gym_logo_url,
              gyms.timezone as gym_timezone
            from gym_join_requests
            join gyms on gyms.id = gym_join_requests.gym_id
            where gym_join_requests.user_id = ?
            order by gym_join_requests.updated_at desc
            """,
            (session["user_id"],),
        ).fetchall()
        connection.close()
        self.send_json(
            HTTPStatus.OK,
            {
                "requests": [
                    {
                        "id": row["id"],
                        "status": row["status"],
                        "created_at": row["created_at"],
                        "reviewed_at": row["reviewed_at"],
                        "gym": {
                            "id": row["gym_id"],
                            "name": row["gym_name"],
                            "slug": row["gym_slug"],
                            "logo_url": row["gym_logo_url"],
                            "timezone": row["gym_timezone"],
                        },
                    }
                    for row in rows
                ]
            },
        )

    def handle_review_join_request(self, body: dict[str, Any]) -> None:
        session = self.require_session()
        if session["role"] != "admin" or session["active_gym_id"] is None:
            raise ApiError(
                HTTPStatus.FORBIDDEN,
                "An active admin gym context is required.",
            )
        request_id = require_user_id(body.get("request_id"))
        decision = require_join_request_decision(body.get("decision"))
        connection = get_connection()
        join_request = connection.execute(
            """
            select * from gym_join_requests
            where id = ? and gym_id = ? and status = 'pending'
            """,
            (request_id, session["active_gym_id"]),
        ).fetchone()
        if join_request is None:
            connection.close()
            raise ApiError(HTTPStatus.NOT_FOUND, "Join request not found.")
        timestamp = isoformat(now_utc())
        with connection:
            if decision == "approve":
                connection.execute(
                    """
                    insert into gym_memberships (
                      user_id, gym_id, active_role, roles_json, status, created_at, updated_at
                    )
                    values (?, ?, 'athlete', ?, 'active', ?, ?)
                    on conflict(user_id, gym_id) do update set
                      active_role = excluded.active_role,
                      roles_json = excluded.roles_json,
                      status = excluded.status,
                      updated_at = excluded.updated_at
                    """,
                    (
                        join_request["user_id"],
                        join_request["gym_id"],
                        encode_roles(["athlete"]),
                        timestamp,
                        timestamp,
                    ),
                )
                member_user = connection.execute(
                    "select active_gym_id from users where id = ?",
                    (join_request["user_id"],),
                ).fetchone()
                if member_user is not None and member_user["active_gym_id"] is None:
                    connection.execute(
                        "update users set active_gym_id = ?, updated_at = ? where id = ?",
                        (join_request["gym_id"], timestamp, join_request["user_id"]),
                    )
                sync_user_context(connection, join_request["user_id"])
            connection.execute(
                """
                update gym_join_requests
                set status = ?, reviewed_at = ?, reviewed_by_user_id = ?, updated_at = ?
                where id = ?
                """,
                (
                    "approved" if decision == "approve" else "rejected",
                    timestamp,
                    session["user_id"],
                    timestamp,
                    request_id,
                ),
            )
            write_audit_log(
                connection,
                gym_id=session["active_gym_id"],
                actor_user_id=session["user_id"],
                target_user_id=join_request["user_id"],
                action="join_request_reviewed",
                entity_type="gym_join_request",
                entity_id=request_id,
                details={
                    "decision": decision,
                    "join_request_id": request_id,
                },
            )
        connection.close()
        self.send_json(
            HTTPStatus.OK,
            {"message": f"Join request {'approved' if decision == 'approve' else 'rejected'}."},
        )

    def handle_list_role_users(self) -> None:
        session = self.require_role("admin")
        if session["active_gym_id"] is None:
            raise ApiError(
                HTTPStatus.FORBIDDEN,
                "An active admin gym context is required.",
            )
        connection = get_connection()
        rows = connection.execute(
            """
            select
              gym_memberships.id,
              gym_memberships.user_id,
              gym_memberships.active_role,
              gym_memberships.roles_json,
              users.email,
              users.display_name,
              users.nickname
            from gym_memberships
            join users on users.id = gym_memberships.user_id
            where gym_memberships.gym_id = ?
              and gym_memberships.status = 'active'
              and users.deleted_at is null
            order by
              case gym_memberships.active_role when 'admin' then 0 when 'trainer' then 1 else 2 end,
              lower(coalesce(nullif(users.display_name, ''), users.email)) asc
            """,
            (session["active_gym_id"],),
        ).fetchall()
        connection.close()
        self.send_json(
            HTTPStatus.OK,
            {"users": [role_managed_member_payload(row) for row in rows]},
        )

    def handle_assign_role(self, body: dict[str, Any]) -> None:
        session = self.require_role("admin")
        if session["active_gym_id"] is None:
            raise ApiError(
                HTTPStatus.FORBIDDEN,
                "An active admin gym context is required.",
            )
        user_id = require_user_id(body.get("user_id"))
        roles = require_role_list(body)
        managed_roles = [role for role in roles if role in {"athlete", "trainer"}]
        if not managed_roles:
            raise ApiError(
                HTTPStatus.BAD_REQUEST,
                "Managed roles must include athlete or trainer.",
            )
        connection = get_connection()
        membership_before = connection.execute(
            """
            select id, active_role
            from gym_memberships
            where user_id = ?
              and gym_id = ?
              and status = 'active'
            """,
            (user_id, session["active_gym_id"]),
        ).fetchone()
        if membership_before is None:
            connection.close()
            raise ApiError(HTTPStatus.NOT_FOUND, "Gym member not found.")
        if membership_before["active_role"] == "admin":
            connection.close()
            raise ApiError(
                HTTPStatus.FORBIDDEN,
                "Admin memberships cannot be changed from this screen.",
            )
        active_role = (
            membership_before["active_role"]
            if membership_before["active_role"] in managed_roles
            else managed_roles[0]
        )
        with connection:
            updated = connection.execute(
                """
                update gym_memberships
                set active_role = ?, roles_json = ?, updated_at = ?
                where id = ?
                """,
                (
                    active_role,
                    encode_roles(managed_roles),
                    isoformat(now_utc()),
                    membership_before["id"],
                ),
            )
            sync_user_context(connection, user_id)
            write_audit_log(
                connection,
                gym_id=session["active_gym_id"],
                actor_user_id=session["user_id"],
                target_user_id=user_id,
                action="gym_member_roles_updated",
                entity_type="gym_membership",
                entity_id=membership_before["id"],
                details={
                    "roles": managed_roles,
                    "active_role": active_role,
                },
            )
        if updated.rowcount == 0:
            connection.close()
            raise ApiError(HTTPStatus.NOT_FOUND, "Gym member not found.")
        user = connection.execute(
            """
            select
              gym_memberships.id,
              gym_memberships.user_id,
              gym_memberships.active_role,
              gym_memberships.roles_json,
              users.email,
              users.display_name,
              users.nickname
            from gym_memberships
            join users on users.id = gym_memberships.user_id
            where gym_memberships.id = ?
              and users.deleted_at is null
            """,
            (membership_before["id"],),
        ).fetchone()
        connection.close()
        if user is None:
            raise ApiError(HTTPStatus.NOT_FOUND, "Gym member not found.")
        self.send_json(HTTPStatus.OK, role_managed_member_payload(user))

    def handle_reset_password(self, body: dict[str, Any]) -> None:
        token = require_token(body.get("token"), label="Reset token")
        new_password = require_password(body.get("new_password"))
        logout_other_sessions = bool(body.get("logout_other_sessions", False))
        connection = get_connection()
        reset_row = connection.execute(
            "select * from password_reset_tokens where token_hash = ?",
            (hash_token(token),),
        ).fetchone()
        if reset_row is None or parse_iso(reset_row["expires_at"]) <= now_utc():
            connection.close()
            raise ApiError(HTTPStatus.BAD_REQUEST, "Reset token is invalid or expired.")

        with connection:
            connection.execute(
                "update users set password_hash = ?, updated_at = ? where id = ?",
                (hash_password(new_password), isoformat(now_utc()), reset_row["user_id"]),
            )
            connection.execute(
                "delete from password_reset_tokens where user_id = ?",
                (reset_row["user_id"],),
            )
            if logout_other_sessions:
                delete_sessions(connection, reset_row["user_id"])
        connection.close()
        self.send_json(HTTPStatus.OK, {"message": "Password updated."})

    def handle_verify_email(self, body: dict[str, Any]) -> None:
        token = require_token(body.get("token"), label="Verification token")
        connection = get_connection()
        verification_row = connection.execute(
            "select * from verification_tokens where token_hash = ?",
            (hash_token(token),),
        ).fetchone()
        if verification_row is None or parse_iso(verification_row["expires_at"]) <= now_utc():
            connection.close()
            raise ApiError(HTTPStatus.BAD_REQUEST, "Verification token is invalid or expired.")

        with connection:
            connection.execute(
                "update users set email_verified = 1, updated_at = ? where id = ?",
                (isoformat(now_utc()), verification_row["user_id"]),
            )
            connection.execute(
                "delete from verification_tokens where user_id = ?",
                (verification_row["user_id"],),
            )
        connection.close()
        self.send_json(HTTPStatus.OK, {"message": "Email verified."})

    def handle_resend_verification(self, body: dict[str, Any]) -> None:
        email = require_email(body.get("email"))
        connection = get_connection()
        user = connection.execute(
            "select * from users where email = ? and deleted_at is null",
            (email,),
        ).fetchone()
        if user is None:
            connection.close()
            self.send_json(HTTPStatus.OK, {"message": "If the account exists, a verification token has been issued in the backend log."})
            return

        if user["email_verified"]:
            connection.close()
            self.send_json(HTTPStatus.OK, {"message": "Email is already verified."})
            return

        with connection:
            token = issue_verification_token(connection, user["id"])
        connection.close()
        print(f"[boxos-backend] Verification token for {email}: {token}")
        self.send_json(HTTPStatus.OK, {"message": "Verification token reissued. Check the backend log."})

    def handle_change_password(self, body: dict[str, Any]) -> None:
        session = self.require_session()
        current_password = require_password(body.get("current_password"), label="Current password")
        new_password = require_password(body.get("new_password"), label="New password")
        logout_other_sessions = bool(body.get("logout_other_sessions", False))
        connection = get_connection()
        user = connection.execute(
            "select * from users where id = ? and deleted_at is null",
            (session["user_id"],),
        ).fetchone()
        if user is None or not verify_password(current_password, user["password_hash"]):
            connection.close()
            raise ApiError(HTTPStatus.UNAUTHORIZED, "Current password is incorrect.")

        with connection:
            connection.execute(
                "update users set password_hash = ?, updated_at = ? where id = ?",
                (hash_password(new_password), isoformat(now_utc()), user["id"]),
            )
            if logout_other_sessions:
                delete_sessions(
                    connection,
                    user["id"],
                    except_access_token_hash=session["access_token_hash"],
                )
            connection.execute(
                "delete from sessions where access_token_hash = ?",
                (session["access_token_hash"],),
            )
            tokens = create_session(connection, user["id"])
        connection.close()
        self.send_json(HTTPStatus.OK, tokens)

    def handle_register_device(self, body: dict[str, Any]) -> None:
        session = self.require_session()
        device_token = require_token(body.get("device_token"), label="Device token")
        platform = require_platform(body.get("platform"))
        connection = get_connection()
        with connection:
            connection.execute(
                """
                insert into device_registrations (
                    user_id, device_token, platform, created_at, updated_at
                )
                values (?, ?, ?, ?, ?)
                on conflict(device_token) do update set
                    user_id = excluded.user_id,
                    platform = excluded.platform,
                    updated_at = excluded.updated_at
                """,
                (
                    session["user_id"],
                    device_token,
                    platform,
                    isoformat(now_utc()),
                    isoformat(now_utc()),
                ),
            )
        connection.close()
        self.send_json(HTTPStatus.OK, {"message": "Device registered."})

    def handle_unregister_device(self, body: dict[str, Any]) -> None:
        session = self.require_session()
        device_token = require_token(body.get("device_token"), label="Device token")
        connection = get_connection()
        with connection:
            connection.execute(
                """
                delete from device_registrations
                where user_id = ? and device_token = ?
                """,
                (session["user_id"], device_token),
            )
        connection.close()
        self.send_json(HTTPStatus.OK, {"message": "Device unregistered."})

    def handle_delete_account(self, body: dict[str, Any]) -> None:
        session = self.require_session()
        current_password = require_password(body.get("current_password"), label="Current password")
        connection = get_connection()
        user = connection.execute(
            "select * from users where id = ? and deleted_at is null",
            (session["user_id"],),
        ).fetchone()
        if user is None or not verify_password(current_password, user["password_hash"]):
            connection.close()
            raise ApiError(HTTPStatus.UNAUTHORIZED, "Current password is incorrect.")

        with connection:
            connection.execute(
                """
                update users
                set email = ?, password_hash = ?, deleted_at = ?, purge_after = ?, updated_at = ?, email_verified = 0, display_name = ?, nickname = ?
                where id = ?
                """,
                (
                    f"deleted_{user['id']}@deleted.local",
                    hash_password(create_token("deleted")),
                    isoformat(now_utc()),
                    isoformat(now_utc() + timedelta(days=DELETE_RETENTION_DAYS)),
                    isoformat(now_utc()),
                    "Deleted User",
                    "",
                    user["id"],
                ),
            )
            connection.execute("delete from sessions where user_id = ?", (user["id"],))
            connection.execute("delete from verification_tokens where user_id = ?", (user["id"],))
            connection.execute("delete from password_reset_tokens where user_id = ?", (user["id"],))
            connection.execute("delete from device_registrations where user_id = ?", (user["id"],))
        connection.close()
        self.send_json(
            HTTPStatus.OK,
            {
                "message": (
                    "Account scheduled for deletion. Personal data has been anonymized "
                    f"and the record will be permanently purged after {DELETE_RETENTION_DAYS} days."
                )
            },
        )

    def require_session(self) -> sqlite3.Row:
        access_token = self.bearer_token()
        connection = get_connection()
        session = connection.execute(
            """
            select sessions.*, users.email, users.email_verified
            , users.role, users.roles_json, users.account_type, users.active_gym_id
            from sessions
            join users on users.id = sessions.user_id
            where sessions.access_token_hash = ? and users.deleted_at is null
            """,
            (hash_token(access_token),),
        ).fetchone()
        if session is None or parse_iso(session["access_expires_at"]) <= now_utc():
            with connection:
                connection.execute(
                    "delete from sessions where access_token_hash = ?",
                    (hash_token(access_token),),
                )
            connection.close()
            raise ApiError(HTTPStatus.UNAUTHORIZED, "Session expired.")
        connection.close()
        return session

    def require_role(self, required_role: str) -> sqlite3.Row:
        session = self.require_session()
        if session["role"] != required_role:
            raise ApiError(
                HTTPStatus.FORBIDDEN,
                f"The {required_role} role is required for this action.",
            )
        return session

    def require_schedule_manager_session(self) -> sqlite3.Row:
        session = self.require_active_gym_member_session()
        if session["active_gym_id"] is None:
            raise ApiError(
                HTTPStatus.FORBIDDEN,
                "An active gym context is required.",
            )
        if session["role"] not in {"admin", "trainer"}:
            raise ApiError(
                HTTPStatus.FORBIDDEN,
                "The admin or trainer role is required for this action.",
            )
        return session

    def require_active_gym_member_session(self) -> sqlite3.Row:
        session = self.require_session()
        if session["active_gym_id"] is None:
            raise ApiError(
                HTTPStatus.FORBIDDEN,
                "An active gym context is required.",
            )
        connection = get_connection()
        membership = connection.execute(
            """
            select id
            from gym_memberships
            where user_id = ? and gym_id = ? and status = 'active'
            """,
            (session["user_id"], session["active_gym_id"]),
        ).fetchone()
        connection.close()
        if membership is None:
            raise ApiError(
                HTTPStatus.FORBIDDEN,
                "You are not an active member of the selected gym.",
            )
        return session

    def bearer_token(self) -> str:
        header = self.headers.get("Authorization")
        if header is None or not header.startswith("Bearer "):
            raise ApiError(HTTPStatus.UNAUTHORIZED, "Missing bearer token.")
        return header.removeprefix("Bearer ").strip()

    def send_json(self, status: HTTPStatus, payload: dict[str, Any]) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status.value)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, PATCH, DELETE, OPTIONS")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self) -> None:
        self.send_response(HTTPStatus.NO_CONTENT.value)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, PATCH, DELETE, OPTIONS")
        self.end_headers()

    def log_message(self, format: str, *args: Any) -> None:
        return


def require_email(value: Any) -> str:
    email = str(value or "").strip().lower()
    if "@" not in email or "." not in email:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Enter a valid email.")
    return email


def require_password(value: Any, *, label: str = "Password") -> str:
    password = str(value or "")
    if len(password) < 8:
        raise ApiError(HTTPStatus.BAD_REQUEST, f"{label} must be at least 8 characters.")
    return password


def require_token(value: Any, *, label: str) -> str:
    token = str(value or "").strip()
    if not token:
        raise ApiError(HTTPStatus.BAD_REQUEST, f"{label} is required.")
    return token


def require_display_name(value: Any) -> str:
    display_name = str(value or "").strip()
    if not display_name:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Display name is required.")
    if len(display_name) > 50:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Display name must be 50 characters or fewer.")
    return display_name


def require_nickname(value: Any) -> str:
    nickname = str(value or "").strip()
    if len(nickname) > 30:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Nickname must be 30 characters or fewer.")
    return nickname


def require_platform(value: Any) -> str:
    platform = str(value or "").strip()
    if not platform:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Platform is required.")
    if len(platform) > 30:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Platform must be 30 characters or fewer.")
    return platform


def notification_preferences_payload(row: sqlite3.Row) -> dict[str, bool]:
    return {
        "booking_confirmations": bool(row["notify_booking_confirmations"]),
        "waitlist_promotions": bool(row["notify_waitlist_promotions"]),
        "payment_issues": bool(row["notify_payment_issues"]),
        "wod_posted": bool(row["notify_wod_posted"]),
        "pr_achievements": bool(row["notify_pr_achievements"]),
    }


def require_notification_preferences(body: dict[str, Any]) -> dict[str, bool]:
    required_keys = (
        "booking_confirmations",
        "waitlist_promotions",
        "payment_issues",
        "wod_posted",
        "pr_achievements",
    )
    preferences: dict[str, bool] = {}
    for key in required_keys:
        if key not in body:
            raise ApiError(
                HTTPStatus.BAD_REQUEST,
                f"{key.replace('_', ' ').capitalize()} is required.",
            )
        value = body[key]
        if not isinstance(value, bool):
            raise ApiError(
                HTTPStatus.BAD_REQUEST,
                f"{key.replace('_', ' ').capitalize()} must be true or false.",
            )
        preferences[key] = value
    return preferences


def role_user_payload(row: sqlite3.Row) -> dict[str, Any]:
    return {
        "id": row["id"],
        "email": row["email"],
        "role": row["role"],
        "available_roles": decode_roles(row["roles_json"]),
        "display_name": row["display_name"],
        "nickname": row["nickname"],
    }


def role_managed_member_payload(row: sqlite3.Row) -> dict[str, Any]:
    role = row["active_role"]
    available_roles = decode_roles(row["roles_json"])
    can_edit_role = role != "admin"
    if can_edit_role:
        available_roles = [
            managed_role
            for managed_role in available_roles
            if managed_role in {"athlete", "trainer"}
        ]
        if not available_roles:
            available_roles = ["athlete"]
    return {
        "id": row["user_id"],
        "membership_id": row["id"],
        "email": row["email"],
        "role": role,
        "available_roles": available_roles,
        "display_name": row["display_name"],
        "nickname": row["nickname"],
        "can_edit_role": can_edit_role,
    }


def audit_log_payload(row: sqlite3.Row) -> dict[str, Any]:
    return {
        "id": row["id"],
        "action": row["action"],
        "entity_type": row["entity_type"],
        "entity_id": row["entity_id"],
        "details": json.loads(row["details_json"]),
        "created_at": row["created_at"],
        "actor": {
            "email": row["actor_email"],
            "display_name": row["actor_display_name"],
            "nickname": row["actor_nickname"],
        },
        "target": None if row["target_email"] is None else {
            "email": row["target_email"],
            "display_name": row["target_display_name"],
            "nickname": row["target_nickname"],
        },
    }


def write_audit_log(
    connection: sqlite3.Connection,
    *,
    gym_id: int | None,
    actor_user_id: int,
    action: str,
    entity_type: str,
    entity_id: int | None = None,
    target_user_id: int | None = None,
    details: dict[str, Any] | None = None,
) -> None:
    connection.execute(
        """
        insert into audit_logs (
          gym_id, actor_user_id, target_user_id, action, entity_type,
          entity_id, details_json, created_at
        )
        values (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            gym_id,
            actor_user_id,
            target_user_id,
            action,
            entity_type,
            entity_id,
            json.dumps(details or {}, sort_keys=True),
            isoformat(now_utc()),
        ),
    )


def profile_payload(row: sqlite3.Row) -> dict[str, Any]:
    connection = get_connection()
    active_membership = get_active_membership(connection, row["id"]) if "id" in row.keys() else None
    memberships = (
        list_user_memberships(connection, row["id"])
        if "id" in row.keys()
        else []
    )
    connection.close()
    return {
        "email": row["email"],
        "role": row["role"],
        "available_roles": decode_roles(row["roles_json"]),
        "display_name": row["display_name"],
        "nickname": row["nickname"],
        "account_type": row["account_type"],
        "active_gym": active_gym_payload(active_membership),
        "memberships": [membership_payload(membership) for membership in memberships],
    }


def require_user_id(value: Any) -> int:
    try:
        user_id = int(value)
    except (TypeError, ValueError):
        raise ApiError(HTTPStatus.BAD_REQUEST, "User id is required.")
    if user_id <= 0:
        raise ApiError(HTTPStatus.BAD_REQUEST, "User id is required.")
    return user_id


def require_optional_user_id(value: Any) -> int | None:
    if value is None:
        return None
    trimmed = str(value).strip()
    if not trimmed:
        return None
    return require_user_id(trimmed)


def require_account_type(value: Any) -> str:
    account_type = normalize_account_type_value(value)
    if account_type not in ALLOWED_ACCOUNT_TYPES:
        raise ApiError(
            HTTPStatus.BAD_REQUEST,
            "Account type must be athlete or admin.",
        )
    return account_type


def require_gym_name(value: Any) -> str:
    name = str(value or "").strip()
    if not name:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Gym name is required.")
    if len(name) > 80:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Gym name must be 80 characters or fewer.")
    return name


def require_logo_url(value: Any) -> str:
    logo_url = str(value or "").strip()
    if not logo_url:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Gym logo URL is required.")
    if len(logo_url) > 300:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Gym logo URL must be 300 characters or fewer.")
    return logo_url


def require_timezone(value: Any) -> str:
    timezone = str(value or "").strip()
    if not timezone:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Timezone is required.")
    if len(timezone) > 100:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Timezone must be 100 characters or fewer.")
    return timezone


def require_schedule_title(value: Any) -> str:
    title = str(value or "").strip()
    if not title:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Class title is required.")
    if len(title) > 80:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Class title must be 80 characters or fewer.")
    return title


def require_class_type(value: Any) -> str:
    class_type = str(value or "").strip()
    allowed_types = {"WOD", "Open Gym", "Specialty", "PT"}
    if class_type not in allowed_types:
        raise ApiError(
            HTTPStatus.BAD_REQUEST,
            "Class type must be WOD, Open Gym, Specialty, or PT.",
        )
    return class_type


def require_capacity(value: Any) -> int:
    try:
        capacity = int(value)
    except (TypeError, ValueError):
        raise ApiError(HTTPStatus.BAD_REQUEST, "Capacity is required.")
    if capacity <= 0 or capacity > 200:
        raise ApiError(
            HTTPStatus.BAD_REQUEST,
            "Capacity must be between 1 and 200.",
        )
    return capacity


def require_duration_minutes(value: Any) -> int:
    try:
        duration_minutes = int(value)
    except (TypeError, ValueError):
        raise ApiError(HTTPStatus.BAD_REQUEST, "Duration is required.")
    if duration_minutes <= 0 or duration_minutes > 24 * 60:
        raise ApiError(
            HTTPStatus.BAD_REQUEST,
            "Duration must be between 1 and 1440 minutes.",
        )
    return duration_minutes


def require_schedule_duration_minutes(body: dict[str, Any]) -> int:
    if body.get("duration_minutes") not in (None, ""):
        return require_duration_minutes(body.get("duration_minutes"))

    end_time_value = body.get("end_time")
    if end_time_value in (None, ""):
        raise ApiError(HTTPStatus.BAD_REQUEST, "Duration is required.")

    try:
        start_time = parse_iso(str(body.get("start_time") or "").strip())
        end_time = parse_iso(str(end_time_value).strip())
    except ValueError:
        raise ApiError(
            HTTPStatus.BAD_REQUEST,
            "End time must be a valid ISO-8601 datetime.",
        )

    duration_minutes = int(round((end_time - start_time).total_seconds() / 60))
    return require_duration_minutes(duration_minutes)


def require_wod_description(value: Any) -> str:
    description = str(value or "").strip()
    if len(description) > 2000:
        raise ApiError(
            HTTPStatus.BAD_REQUEST,
            "WOD description must be 2000 characters or fewer.",
        )
    return description


def require_attendance_status(value: Any) -> str:
    attendance_status = str(value or "").strip().lower()
    if attendance_status not in {"booked", "attended", "no_show"}:
        raise ApiError(
            HTTPStatus.BAD_REQUEST,
            "Attendance status must be booked, attended, or no_show.",
        )
    return attendance_status


def require_future_datetime(value: Any, *, label: str) -> datetime:
    try:
        parsed = parse_iso(str(value or "").strip())
    except ValueError:
        raise ApiError(
            HTTPStatus.BAD_REQUEST,
            f"{label} must be a valid ISO-8601 datetime.",
        )
    if parsed <= now_utc():
        raise ApiError(
            HTTPStatus.BAD_REQUEST,
            f"{label} must be in the future.",
        )
    return parsed


def daily_workout_payload(
    connection: sqlite3.Connection,
    row: sqlite3.Row,
    *,
    current_user_id: int,
    can_edit: bool,
) -> dict[str, Any]:
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
    }


def get_workout_log_for_user(
    connection: sqlite3.Connection,
    workout_id: int,
    user_id: int,
) -> dict[str, Any] | None:
    row = connection.execute(
        """
        select
          workout_logs.id,
          workout_logs.daily_workout_id,
          workout_logs.class_schedule_id,
          workout_logs.score_type,
          workout_logs.score_value,
          workout_logs.score_label,
          workout_logs.notes_text,
          workout_logs.created_at,
          workout_logs.updated_at,
          daily_workouts.scheduled_date,
          daily_workouts.title as workout_title,
          class_schedules.title as class_title,
          class_schedules.start_time as class_start_time
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


def list_whiteboard_results(
    connection: sqlite3.Connection,
    workout_id: int,
) -> list[dict[str, Any]]:
    rows = connection.execute(
        """
        select
          whiteboard_results.id,
          whiteboard_results.user_id,
          whiteboard_results.score_type,
          whiteboard_results.score_value,
          whiteboard_results.score_label,
          whiteboard_results.notes_text,
          whiteboard_results.created_at,
          whiteboard_results.updated_at,
          users.display_name,
          users.nickname
        from whiteboard_results
        join users on users.id = whiteboard_results.user_id
        where whiteboard_results.daily_workout_id = ?
        order by
          case whiteboard_results.score_type
            when 'time' then 0
            when 'reps' then 1
            when 'load' then 2
            else 3
          end asc,
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


def get_whiteboard_result_for_user(
    connection: sqlite3.Connection,
    workout_id: int,
    user_id: int,
) -> dict[str, Any] | None:
    row = connection.execute(
        """
        select id, user_id, score_type, score_value, score_label, notes_text
        from whiteboard_results
        where daily_workout_id = ? and user_id = ?
        """,
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


def today_utc_date() -> datetime.date:
    return now_utc().date()


def parse_programming_date(value: str) -> datetime.date:
    return datetime.fromisoformat(value).date()


def require_programming_date(value: Any) -> str:
    raw = str(value or "").strip()
    if not raw:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Scheduled date is required.")
    try:
        scheduled_date = parse_programming_date(raw)
    except ValueError:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Scheduled date must be a valid ISO-8601 date.")
    if scheduled_date < today_utc_date():
        raise ApiError(HTTPStatus.BAD_REQUEST, "Scheduled date must be today or later.")
    return scheduled_date.isoformat()


def require_programming_title(value: Any) -> str:
    title = str(value or "").strip()
    if not title:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Workout title is required.")
    if len(title) > 80:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Workout title must be 80 characters or fewer.")
    return title


def require_programming_section(value: Any, *, label: str) -> str:
    text_value = str(value or "").strip()
    if len(text_value) > 4000:
        raise ApiError(HTTPStatus.BAD_REQUEST, f"{label} must be 4000 characters or fewer.")
    return text_value


def require_whiteboard_score(score_type_value: Any, score_value_value: Any) -> tuple[str, float, str]:
    score_type = str(score_type_value or "").strip().lower()
    if score_type not in {"time", "reps", "load"}:
        raise ApiError(
            HTTPStatus.BAD_REQUEST,
            "Score type must be time, reps, or load.",
        )
    raw_score_value = str(score_value_value or "").strip()
    if not raw_score_value:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Score value is required.")

    if score_type == "time":
        normalized = raw_score_value.replace(".", ":")
        parts = normalized.split(":")
        if len(parts) not in {2, 3}:
            raise ApiError(
                HTTPStatus.BAD_REQUEST,
                "Time score must be mm:ss or hh:mm:ss.",
            )
        try:
            numbers = [int(part) for part in parts]
        except ValueError:
            raise ApiError(
                HTTPStatus.BAD_REQUEST,
                "Time score must be mm:ss or hh:mm:ss.",
            )
        if any(number < 0 for number in numbers):
            raise ApiError(HTTPStatus.BAD_REQUEST, "Time score must be positive.")
        if len(numbers) == 2:
            minutes, seconds = numbers
            hours = 0
        else:
            hours, minutes, seconds = numbers
        if minutes >= 60 and len(numbers) == 3:
            raise ApiError(HTTPStatus.BAD_REQUEST, "Minutes must be below 60 for hh:mm:ss.")
        if seconds >= 60:
            raise ApiError(HTTPStatus.BAD_REQUEST, "Seconds must be below 60.")
        total_seconds = float(hours * 3600 + minutes * 60 + seconds)
        if total_seconds <= 0:
            raise ApiError(HTTPStatus.BAD_REQUEST, "Time score must be positive.")
        return score_type, total_seconds, raw_score_value

    try:
        score_value = float(raw_score_value)
    except ValueError:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Score value must be numeric.")
    if score_value <= 0:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Score value must be positive.")
    return score_type, score_value, raw_score_value


def require_whiteboard_notes(value: Any) -> str:
    notes = str(value or "").strip()
    if len(notes) > 500:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Notes must be 500 characters or fewer.")
    return notes


def require_join_request_decision(value: Any) -> str:
    decision = str(value or "").strip().lower()
    if decision not in {"approve", "reject"}:
        raise ApiError(
            HTTPStatus.BAD_REQUEST,
            "Decision must be approve or reject.",
        )
    return decision


def require_role_value(value: Any) -> str:
    role = normalize_role_value(value)
    if role not in ALLOWED_ROLES:
        raise ApiError(
            HTTPStatus.BAD_REQUEST,
            "Role must be athlete, trainer, or admin.",
        )
    return role


def require_role_list(body: dict[str, Any]) -> list[str]:
    if "roles" in body:
        raw_roles = body["roles"]
        if not isinstance(raw_roles, list):
            raise ApiError(HTTPStatus.BAD_REQUEST, "Roles must be a list.")
        return normalize_roles(raw_roles)
    return [require_role_value(body.get("role"))]


def normalize_roles(values: list[Any]) -> list[str]:
    roles = [require_role_value(value) for value in values]
    unique_roles = list(dict.fromkeys(roles))
    if not unique_roles:
        raise ApiError(HTTPStatus.BAD_REQUEST, "At least one role is required.")
    return unique_roles


def encode_roles(roles: list[str]) -> str:
    return json.dumps(roles)


def decode_roles(value: str | None) -> list[str]:
    if not value:
        return ["athlete"]
    try:
        raw_roles = json.loads(value)
    except json.JSONDecodeError:
        return ["athlete"]
    if not isinstance(raw_roles, list):
        return ["athlete"]
    normalized = []
    for role in raw_roles:
        role_value = normalize_role_value(role)
        if role_value in ALLOWED_ROLES and role_value not in normalized:
            normalized.append(role_value)
    return normalized or ["athlete"]


def run() -> None:
    init_db()
    print(f"[boxos-backend] Starting dev backend on http://{HOST}:{PORT}")
    print(f"[boxos-backend] Athlete demo account: {DEMO_EMAIL} / {DEMO_PASSWORD}")
    print(f"[boxos-backend] Admin demo account: {ADMIN_EMAIL} / {ADMIN_PASSWORD}")
    server = ThreadingHTTPServer((HOST, PORT), BoxOsHandler)
    server.serve_forever()


if __name__ == "__main__":
    run()
