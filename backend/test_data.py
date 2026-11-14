"""Test data for an existing box, safe to use in production.

Unlike ``seed_demo`` (dev only: its own gym and public passwords), this fills
a box that already exists with a small roster, classes, bookings, WODs, plans
and messages. Every test account has an email on ``@test.boxos.invalid`` and a
random password nobody knows, so none of them can log in. All seeded content
is created by a test trainer, so deleting the test accounts removes it too.

    python -m backend.manage seed-test-data --gym <slug>
    python -m backend.manage seed-test-data --gym <slug> --remove
"""

from __future__ import annotations

import random
import secrets
from datetime import datetime, timedelta, timezone
from typing import Any

from backend import db, seed_demo, seed_results
from backend.security import hash_password, isoformat, now_utc

TEST_DOMAIN = "test.boxos.invalid"


def _email_prefix(gym_id: int) -> str:
    return f"g{gym_id}."


def _test_user_ids(conn: Any, gym_id: int) -> list[int]:
    rows = conn.execute(
        "select id from users where email like ?",
        (f"{_email_prefix(gym_id)}%@{TEST_DOMAIN}",),
    ).fetchall()
    return [int(row["id"]) for row in rows]


def remove(gym_id: int) -> int:
    """Delete this box's test accounts and everything they created. Returns the count."""
    conn = db.get_connection()
    try:
        with conn:
            return _remove(conn, gym_id)
    finally:
        conn.close()


def _remove(conn: Any, gym_id: int) -> int:
    ids = _test_user_ids(conn, gym_id)
    if not ids:
        return 0
    marks = ",".join("?" for _ in ids)
    # Plans keep their row when the creator goes (set null), so delete them
    # first, unless the owner has since assigned one to a real member.
    conn.execute(
        f"""
        delete from membership_plans
        where gym_id = ? and created_by_user_id in ({marks})
          and not exists (
            select 1 from member_plans
            where member_plans.plan_id = membership_plans.id and member_plans.user_id not in ({marks})
          )
        """,
        (gym_id, *ids, *ids),
    )
    # Chat keeps messages of deleted accounts (set null), so drop them here.
    conn.execute(f"delete from chat_messages where user_id in ({marks})", tuple(ids))
    # Cascades: memberships, bookings, requests, and the classes,
    # templates, WODs and announcements the test trainer created.
    conn.execute(f"delete from users where id in ({marks})", tuple(ids))
    return len(ids)


def seed(*, gym_id: int, members: int = 20, trainers: int = 2, weeks: int = 2,
         rng: random.Random | None = None) -> dict[str, int]:
    """Replace this box's test data. The owner and real members are not touched."""
    if members < 1 or trainers < 1 or weeks < 1:
        raise ValueError("members, trainers and weeks must be at least 1.")
    rng = rng or random.Random()
    today = datetime.now(timezone.utc).date()
    conn = db.get_connection()
    try:
        with conn:
            gym = conn.execute("select id, timezone from gyms where id = ?", (gym_id,)).fetchone()
            if gym is None:
                raise ValueError(f"No gym with id {gym_id}.")
            _remove(conn, gym_id)

            def add_user(index: int, role: str, roles: list[str], age_days: int) -> int:
                first = rng.choice(seed_demo._FIRST_NAMES)
                last = rng.choice(seed_demo._LAST_NAMES)
                created_at = isoformat(now_utc() - timedelta(days=age_days))
                return seed_demo._upsert_user(
                    conn,
                    email=f"{_email_prefix(gym_id)}{first}.{last}.{index}@{TEST_DOMAIN}".lower(),
                    display_name=f"{first} {last}", nickname=f"{first.lower()}{index}",
                    role=role, roles=roles, account_type="athlete", created_at=created_at,
                    password_hash=hash_password(secrets.token_urlsafe(32)),
                )

            trainer_ids = []
            for i in range(trainers):
                uid = add_user(i, "trainer", ["athlete", "trainer"], rng.randint(60, 300))
                seed_demo._add_membership(conn, uid, gym_id, "trainer", ["athlete", "trainer"],
                                          created_at=isoformat(now_utc() - timedelta(days=60)))
                trainer_ids.append(uid)
            creator = trainer_ids[0]

            member_ids = []
            for i in range(members):
                age_days = rng.randint(1, 13) if i < 3 else rng.randint(15, 300)
                uid = add_user(trainers + i, "athlete", ["athlete"], age_days)
                seed_demo._add_membership(conn, uid, gym_id, "athlete", ["athlete"],
                                          created_at=isoformat(now_utc() - timedelta(days=age_days)))
                member_ids.append(uid)

            requests = 2
            for i in range(requests):
                uid = add_user(trainers + members + i, "athlete", ["athlete"], 0)
                conn.execute(
                    """insert into gym_join_requests (user_id, gym_id, status, created_at, updated_at)
                       values (?, ?, 'pending', ?, ?)""",
                    (uid, gym_id, seed_demo._ts(), seed_demo._ts()),
                )

            # Small roster: a third of it per class, so not everyone is in every class.
            seed_demo._seed_classes(
                conn, rng, gym_id, creator, trainer_ids, member_ids + trainer_ids, today,
                timezone_name=gym["timezone"] or "UTC", past_days=weeks * 7, future_days=weeks * 7,
                max_fill=max(3, len(member_ids) // 3),
            )
            plans, plan_requests = seed_demo._seed_plans(conn, rng, gym_id, creator, member_ids, today)
            wods = _seed_wods(conn, gym_id, creator, today, weeks)
            seed_demo._seed_community(conn, rng, gym_id, creator, member_ids)
            results = seed_results.seed_results(
                conn, rng, gym_id=gym_id, athlete_ids=member_ids + trainer_ids, created_by=creator,
            )
        return {
            "members": members, "trainers": trainers, "requests": requests,
            "plans": plans, "plan_requests": plan_requests, "wods": wods,
            "results": results["results"], "logbook": results["personal"], "follows": results["follows"],
        }
    finally:
        conn.close()


def _seed_wods(conn: Any, gym_id: int, creator: int, today: Any, weeks: int) -> int:
    """One published WOD per day for the past week and the next days, with
    real blocks, skipping days that already have the box's own WOD (one WOD
    per gym per day)."""
    count = 0
    for offset in range(-7, weeks * 7 // 2 + 1):
        day = (today + timedelta(days=offset)).isoformat()
        row = conn.execute(
            """
            insert into daily_workouts (gym_id, scheduled_date, title, status, published_at,
              published_by_user_id, created_by_user_id, updated_by_user_id, created_at, updated_at)
            values (?, ?, 'Test WOD', 'published', ?, ?, ?, ?, ?, ?)
            on conflict (gym_id, scheduled_date) do nothing
            returning id
            """,
            (gym_id, day, seed_demo._ts(), creator, creator, creator, seed_demo._ts(), seed_demo._ts()),
        ).fetchone()
        if row is None:
            continue
        seed_results.program_day(conn, row["id"], offset % 5)
        count += 1
    return count
