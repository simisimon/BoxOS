"""Copy an existing BoxOS SQLite database into a PostgreSQL database.

The legacy backend stored everything in SQLite. After the move to PostgreSQL this
one-shot script migrates the data over. It:

  1. creates the BoxOS schema in the target Postgres database (idempotent),
  2. copies every table, parent rows before child rows so foreign keys hold,
  3. resets the identity sequences so new inserts continue past the copied ids.

Usage (run from the repository root):

    python scripts/migrate_sqlite_to_postgres.py \
        --sqlite backend/boxos_dev.db \
        --postgres postgresql://boxos:boxos@localhost:5432/boxos

Both arguments are optional and default to settings.DB_PATH and
settings.DATABASE_URL respectively. The target should be an empty database.
"""

from __future__ import annotations

import argparse
import sqlite3
import sys
from pathlib import Path

# Allow running as a plain script from the repo root.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import psycopg
from psycopg.rows import dict_row

from backend import db, settings

# Parent tables first so foreign keys are satisfiable as we go. The circular
# users.active_gym_id -> gyms reference is a deferrable constraint, so copying
# users before gyms inside a single transaction is fine.
TABLE_ORDER = [
    "users",
    "gyms",
    "exercises",
    "benchmark_workouts",
    "sessions",
    "verification_tokens",
    "password_reset_tokens",
    "device_registrations",
    "gym_memberships",
    "gym_join_requests",
    "class_schedules",
    "class_bookings",
    "class_waitlist_entries",
    "daily_workouts",
    "whiteboard_results",
    "audit_logs",
    "workout_logs",
    "notifications",
    "announcements",
    "announcement_likes",
    "announcement_comments",
    "personal_workouts",
]

# Tables whose identity sequence on the "id" column must be advanced after copying.
IDENTITY_TABLES = [name for name in TABLE_ORDER if name not in {"exercises", "benchmark_workouts", "announcement_likes"}]


def _sqlite_table_names(source: sqlite3.Connection) -> set[str]:
    rows = source.execute("select name from sqlite_master where type = 'table'").fetchall()
    return {row[0] for row in rows}


def _copy_table(source: sqlite3.Connection, target: psycopg.Connection, table: str) -> int:
    rows = source.execute(f"select * from {table}").fetchall()
    if not rows:
        return 0
    columns = [description[0] for description in source.execute(f"select * from {table} limit 0").description]
    column_list = ", ".join(columns)
    placeholders = ", ".join(["%s"] * len(columns))
    statement = f"insert into {table} ({column_list}) values ({placeholders})"
    with target.cursor() as cursor:
        cursor.executemany(statement, [tuple(row) for row in rows])
    return len(rows)


def _reset_sequences(target: psycopg.Connection) -> None:
    with target.cursor() as cursor:
        for table in IDENTITY_TABLES:
            cursor.execute(
                "select setval(pg_get_serial_sequence(%s, 'id'), coalesce((select max(id) from "
                + table
                + "), 1), (select count(*) from "
                + table
                + ") > 0)",
                (table,),
            )


def migrate(sqlite_path: Path, postgres_url: str) -> None:
    if not sqlite_path.exists():
        raise SystemExit(f"SQLite database not found: {sqlite_path}")

    print(f"Source SQLite : {sqlite_path}")
    print(f"Target Postgres: {postgres_url}")

    # 1. Create the schema in the target database.
    settings.DATABASE_URL = postgres_url
    schema_connection = db.get_connection()
    try:
        with schema_connection:
            db._apply_schema(schema_connection)
    finally:
        schema_connection.close()

    source = sqlite3.connect(str(sqlite_path))
    available = _sqlite_table_names(source)
    target = psycopg.connect(postgres_url, row_factory=dict_row, autocommit=False)
    try:
        total = 0
        for table in TABLE_ORDER:
            if table not in available:
                print(f"  - {table}: skipped (not present in source)")
                continue
            copied = _copy_table(source, target, table)
            total += copied
            print(f"  - {table}: {copied} rows")
        _reset_sequences(target)
        target.commit()
        print(f"Done. Copied {total} rows across {len(TABLE_ORDER)} tables.")
    except Exception:
        target.rollback()
        raise
    finally:
        target.close()
        source.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="Migrate a BoxOS SQLite database to PostgreSQL.")
    parser.add_argument("--sqlite", default=str(settings.DB_PATH), help="Path to the source SQLite database file.")
    parser.add_argument("--postgres", default=settings.DATABASE_URL, help="Target PostgreSQL connection URL.")
    args = parser.parse_args()
    migrate(Path(args.sqlite), args.postgres)


if __name__ == "__main__":
    main()
