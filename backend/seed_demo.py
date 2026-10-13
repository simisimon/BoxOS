"""Seed a rich demo box so every view (dashboard, members, schedule, analytics,
programming, tracking, community) renders with realistic data instead of empty
zero-states.

Idempotent: re-running drops the demo gym (cascading its classes, bookings,
memberships, workouts, …) and rebuilds it, reusing demo users by email.

Run it against the dev stack:

    docker compose --profile dev exec backend-dev python -m backend.seed_demo

Then log in as the owner printed at the end to land on the populated dashboard.
"""

from __future__ import annotations

import random
from datetime import datetime, timedelta, timezone

from backend import db, settings
from backend.membership_service import slugify
from backend.security import hash_password, isoformat, now_utc
from backend.validation import encode_roles, normalize_roles

# --- Demo identities --------------------------------------------------------
OWNER_EMAIL = "owner@boxos.dev"
OWNER_PASSWORD = "BoxOS!demo1"
OWNER_NAME = "Jordan Cole"

GYM_NAME = "Iron Forge CrossFit"
GYM_TIMEZONE = "Europe/Berlin"

N_MEMBERS = 120  # active roster (excluding the owner)
N_ADMINS = 5
N_TRAINERS = 11
N_PENDING_REQUESTS = 4

_MEMBER_PASSWORD_HASH = hash_password("Passw0rd!123")

_FIRST_NAMES = [
    "Maya", "Dan", "Sara", "Alex", "Rafa", "Kai", "Nora", "Leo", "Ivy", "Sam",
    "Tomas", "Lena", "Omar", "Priya", "Jonas", "Mila", "Hugo", "Zoe", "Aria",
    "Finn", "Ana", "Marco", "Elin", "Yusuf", "Clara", "Nikola", "Ruth", "Theo",
    "Isla", "Diego", "Freya", "Amir", "Nina", "Pablo", "Greta", "Ravi", "Lucia",
    "Bjorn", "Tara", "Ken", "Suki", "Malik", "Elena", "Cato", "Vera", "Noah",
    "Ines", "Ola", "Rhea", "Milan",
]
_LAST_NAMES = [
    "Rivera", "Kessler", "Okafor", "Park", "Diaz", "Novak", "Tan", "Weber",
    "Haas", "Fischer", "Ibrahim", "Costa", "Nguyen", "Bauer", "Moretti",
    "Schulz", "Petrov", "Andersson", "Kowalski", "Silva", "Meyer", "Lund",
    "Berg", "Roth", "Vidal", "Horvat", "Keller", "Marsh", "Falk", "Reyes",
]

_CLASS_WEEKDAY = [
    ("06:00", "Olympic Lifting", "Olympic Lifting", 14),
    ("09:00", "Metcon", "Metcon", 20),
    ("12:00", "Open Gym", "Open Gym", 24),
    ("17:30", "Metcon", "Metcon", 20),
    ("18:30", "Endurance", "Endurance", 18),
]
_CLASS_WEEKEND = [
    ("10:00", "Community WOD", "Metcon", 24),
    ("11:00", "Open Gym", "Open Gym", 24),
]

_PAST_DAYS = 34  # classes reach back far enough for the 30-day window
_FUTURE_DAYS = 6  # forward load / pressure classes


def _ts() -> str:
    return isoformat(now_utc())


def _upsert_user(conn, *, email, display_name, nickname, role, roles, account_type,
                 created_at, password_hash=None):
    password_hash = password_hash or _MEMBER_PASSWORD_HASH
    encoded = encode_roles(normalize_roles(roles))
    existing = conn.execute("select id from users where email = ?", (email.lower(),)).fetchone()
    if existing is not None:
        conn.execute(
            """
            update users set display_name = ?, nickname = ?, role = ?, roles_json = ?,
              account_type = ?, email_verified = 1, deleted_at = null, purge_after = null,
              password_hash = ?, updated_at = ?
            where id = ?
            """,
            (display_name, nickname, role, encoded, account_type, password_hash,
             _ts(), existing["id"]),
        )
        return int(existing["id"])
    row = conn.execute(
        """
        insert into users (email, password_hash, email_verified, role, roles_json,
          display_name, nickname, account_type, created_at, updated_at)
        values (?, ?, 1, ?, ?, ?, ?, ?, ?, ?)
        returning id
        """,
        (email.lower(), password_hash, role, encoded, display_name, nickname,
         account_type, created_at, created_at),
    ).fetchone()
    return int(row["id"])


def seed(rng: random.Random | None = None) -> None:
    rng = rng or random.Random(42)
    db.init_db()
    conn = db.get_connection()
    today = datetime.now(timezone.utc).date()
    try:
        with conn:
            # --- Owner + gym (drop any prior demo gym to stay idempotent) ----
            owner_id = _upsert_user(
                conn, email=OWNER_EMAIL, display_name=OWNER_NAME, nickname="jordan",
                role="admin", roles=["athlete", "trainer", "admin"], account_type="admin",
                created_at=isoformat(now_utc() - timedelta(days=400)),
                password_hash=hash_password(OWNER_PASSWORD),
            )
            slug = slugify(GYM_NAME)
            conn.execute("delete from gyms where slug = ?", (slug,))
            gym_id = int(conn.execute(
                """
                insert into gyms (name, slug, logo_url, timezone, created_by_user_id, created_at, updated_at)
                values (?, ?, '', ?, ?, ?, ?) returning id
                """,
                (GYM_NAME, slug, GYM_TIMEZONE, owner_id, _ts(), _ts()),
            ).fetchone()["id"])
            conn.execute("update users set active_gym_id = ? where id = ?", (gym_id, owner_id))
            _add_membership(conn, owner_id, gym_id, "admin", ["athlete", "trainer", "admin"],
                            created_at=isoformat(now_utc() - timedelta(days=400)))

            # --- Members --------------------------------------------------
            member_ids: list[int] = []
            trainer_ids: list[int] = []
            used_emails: set[str] = set()
            for i in range(N_MEMBERS):
                first = rng.choice(_FIRST_NAMES)
                last = rng.choice(_LAST_NAMES)
                name = f"{first} {last}"
                email = f"{first}.{last}.{i}@members.boxos.dev".lower()
                used_emails.add(email)
                if i < N_ADMINS:
                    role, roles = "admin", ["athlete", "trainer", "admin"]
                elif i < N_ADMINS + N_TRAINERS:
                    role, roles = "trainer", ["athlete", "trainer"]
                else:
                    role, roles = "athlete", ["athlete"]
                # 6 members joined inside the 14-day window; the rest are older.
                age_days = rng.randint(1, 13) if i < 6 else rng.randint(15, 360)
                created_at = isoformat(now_utc() - timedelta(days=age_days))
                uid = _upsert_user(
                    conn, email=email, display_name=name, nickname=f"{first.lower()}{i}",
                    role=role, roles=roles, account_type="athlete", created_at=created_at,
                )
                _add_membership(conn, uid, gym_id, role, roles, created_at=created_at)
                member_ids.append(uid)
                if role in ("trainer", "admin"):
                    trainer_ids.append(uid)
            trainer_ids.append(owner_id)

            # --- Pending join requests ------------------------------------
            for i in range(N_PENDING_REQUESTS):
                first = rng.choice(_FIRST_NAMES)
                last = rng.choice(_LAST_NAMES)
                email = f"pending.{first}.{last}.{i}@applicants.boxos.dev".lower()
                if email in used_emails:
                    email = f"pending.{first}.{last}.{i}.x@applicants.boxos.dev".lower()
                uid = _upsert_user(
                    conn, email=email, display_name=f"{first} {last}", nickname=f"{first.lower()}_new",
                    role="athlete", roles=["athlete"], account_type="athlete",
                    created_at=isoformat(now_utc() - timedelta(hours=2 + i * 3)),
                )
                conn.execute("delete from gym_join_requests where user_id = ? and gym_id = ?", (uid, gym_id))
                conn.execute(
                    """insert into gym_join_requests (user_id, gym_id, status, created_at, updated_at)
                       values (?, ?, 'pending', ?, ?)""",
                    (uid, gym_id, isoformat(now_utc() - timedelta(hours=2 + i * 3)), _ts()),
                )

            # --- Classes + bookings + attendance --------------------------
            _seed_classes(conn, rng, gym_id, owner_id, trainer_ids, member_ids, today)

            # --- Programming + whiteboard + athlete progress --------------
            _seed_programming(conn, rng, gym_id, owner_id, member_ids, today)
            _seed_demo_athlete(conn, rng, gym_id)
            _seed_community(conn, rng, gym_id, owner_id, member_ids)

        print("Seeded demo box:")
        print(f"  gym         : {GYM_NAME} (id {gym_id}, {GYM_TIMEZONE})")
        print(f"  members     : {len(member_ids)} active (+ owner), {N_PENDING_REQUESTS} pending requests")
        print(f"  owner login : {OWNER_EMAIL} / {OWNER_PASSWORD}")
    finally:
        conn.close()


def _add_membership(conn, user_id, gym_id, active_role, roles, *, created_at):
    conn.execute("delete from gym_memberships where user_id = ? and gym_id = ?", (user_id, gym_id))
    conn.execute(
        """insert into gym_memberships (user_id, gym_id, active_role, roles_json, status, created_at, updated_at)
           values (?, ?, ?, ?, 'active', ?, ?)""",
        (user_id, gym_id, active_role, encode_roles(normalize_roles(roles)), created_at, _ts()),
    )


def _seed_classes(conn, rng, gym_id, owner_id, trainer_ids, member_ids, today):
    for offset in range(-_PAST_DAYS, _FUTURE_DAYS + 1):
        day = today + timedelta(days=offset)
        templates = _CLASS_WEEKEND if day.weekday() >= 5 else _CLASS_WEEKDAY
        for time_str, title, class_type, capacity in templates:
            start = f"{day.isoformat()}T{time_str}:00"
            end_hour = int(time_str[:2]) + 1
            end = f"{day.isoformat()}T{end_hour:02d}:{time_str[3:]}:00"
            trainer = rng.choice(trainer_ids)
            class_id = int(conn.execute(
                """
                insert into class_schedules (gym_id, title, class_type, start_time, end_time,
                  duration_minutes, capacity, assigned_trainer_user_id, created_by_user_id,
                  updated_by_user_id, created_at, updated_at)
                values (?, ?, ?, ?, ?, 60, ?, ?, ?, ?, ?, ?) returning id
                """,
                (gym_id, title, class_type, start, end, capacity, trainer, owner_id, owner_id, _ts(), _ts()),
            ).fetchone()["id"])

            is_past = offset < 0
            if is_past:
                fill = max(1, round(capacity * rng.uniform(0.55, 0.95)))
            elif offset == 0 and time_str == "17:30":
                fill = capacity  # full pressure class
            elif offset >= 0 and time_str == "06:00":
                fill = capacity  # full pressure class
            elif offset >= 0 and time_str == "12:00":
                fill = max(1, round(capacity * 0.375))  # low fill
            else:
                fill = max(1, round(capacity * rng.uniform(0.5, 0.85)))
            fill = min(fill, capacity, len(member_ids))

            attendees = rng.sample(member_ids, fill)
            for uid in attendees:
                if is_past:
                    r = rng.random()
                    if r < 0.87:
                        status, marked = "attended", _ts()
                    elif r < 0.96:
                        status, marked = "no_show", _ts()
                    else:
                        status, marked = "booked", None
                else:
                    status, marked = "booked", None
                conn.execute(
                    """insert into class_bookings (class_schedule_id, user_id, attendance_status,
                         attendance_marked_at, attendance_marked_by_user_id, created_at)
                       values (?, ?, ?, ?, ?, ?)""",
                    (class_id, uid, status, marked, owner_id if marked else None, _ts()),
                )

            # Waitlist on the full upcoming pressure classes.
            if not is_past and fill >= capacity:
                waitlist_n = 5 if time_str == "17:30" else 3
                pool = [m for m in member_ids if m not in attendees]
                for uid in rng.sample(pool, min(waitlist_n, len(pool))):
                    conn.execute(
                        """insert into class_waitlist_entries (class_schedule_id, user_id, created_at)
                           values (?, ?, ?)""",
                        (class_id, uid, _ts()),
                    )


def _seed_programming(conn, rng, gym_id, owner_id, member_ids, today):
    sections = [
        ("Strength · Back Squat", "5·5·3·3·1 building to a heavy single.", "weight"),
        ("Metcon · Fran", "21-15-9 Thrusters (43/30kg) + Pull-ups. For time.", "time"),
        ("Accessory", "3 rounds: 12 GHD sit-ups, 40s hollow hold.", "rounds_reps"),
    ]
    for offset in range(-6, 1):
        day = today + timedelta(days=offset)
        wod_id = int(conn.execute(
            """
            insert into daily_workouts (gym_id, scheduled_date, title, status, published_at,
              published_by_user_id, created_by_user_id, updated_by_user_id, created_at, updated_at)
            values (?, ?, ?, 'published', ?, ?, ?, ?, ?, ?) returning id
            """,
            (gym_id, day.isoformat(), "Fran", _ts(), owner_id, owner_id, owner_id, _ts(), _ts()),
        ).fetchone()["id"])
        for pos, (title, desc, score) in enumerate(sections):
            conn.execute(
                """insert into daily_workout_sections (daily_workout_id, position, title, description, score_type)
                   values (?, ?, ?, ?, ?)""",
                (wod_id, pos, title, desc, score),
            )
        # Whiteboard results on today's WOD.
        if offset == 0:
            for uid in rng.sample(member_ids, min(14, len(member_ids))):
                secs = rng.randint(168, 320)
                conn.execute(
                    """insert into whiteboard_results (daily_workout_id, gym_id, user_id, score_type,
                         score_value, score_label, notes_text, created_at, updated_at)
                       values (?, ?, ?, 'time', ?, ?, '', ?, ?)""",
                    (wod_id, gym_id, uid, secs, f"{secs // 60}:{secs % 60:02d}", _ts(), _ts()),
                )


def _seed_demo_athlete(conn, rng, gym_id):
    """Give the standard demo athlete membership + logbook + tracking history so
    the athlete-facing profile snapshot and tracking PR chart populate."""
    athlete = conn.execute("select id from users where email = ?", (settings.DEMO_EMAIL.lower(),)).fetchone()
    if athlete is None:
        return
    aid = int(athlete["id"])
    _add_membership(conn, aid, gym_id, "athlete", ["athlete"],
                    created_at=isoformat(now_utc() - timedelta(days=120)))
    conn.execute("update users set active_gym_id = ? where id = ?", (gym_id, aid))

    # Log the athlete into recent published WODs (drives sessions/streak/PRs).
    wods = conn.execute(
        "select id, scheduled_date from daily_workouts where gym_id = ? order by scheduled_date desc limit 12",
        (gym_id,),
    ).fetchall()
    for i, wod in enumerate(wods):
        conn.execute("delete from workout_logs where user_id = ? and daily_workout_id = ?", (aid, wod["id"]))
        secs = 260 - i * 4
        is_pr = 1 if i in (0, 3) else 0
        conn.execute(
            """insert into workout_logs (user_id, gym_id, daily_workout_id, class_schedule_id,
                 score_type, score_value, score_label, notes_text, is_pr, pr_rank, created_at, updated_at)
               values (?, ?, ?, null, 'time', ?, ?, '', ?, ?, ?, ?)""",
            (aid, gym_id, wod["id"], secs, f"{secs // 60}:{secs % 60:02d}", is_pr,
             1 if is_pr else None, f"{wod['scheduled_date']}T18:00:00", _ts()),
        )

    # A benchmark ("Fran") retested five times, improving.
    conn.execute("delete from tracking_sessions where user_id = ? and source_key = 'fran'", (aid,))
    times = [231, 219, 210, 205, 199]
    for i, secs in enumerate(times):
        created = isoformat(now_utc() - timedelta(days=(len(times) - i) * 12))
        conn.execute(
            """insert into tracking_sessions (user_id, source_kind, source_key, workout_title,
                 score_type, score_value, score_label, notes_text, created_at)
               values (?, 'benchmark', 'fran', 'Fran', 'time', ?, ?, '', ?)""",
            (aid, secs, f"{secs // 60}:{secs % 60:02d}", created),
        )


def _seed_community(conn, rng, gym_id, owner_id, member_ids):
    conn.execute(
        """insert into announcements (gym_id, title, description, image_url, created_by_user_id, created_at, updated_at)
           values (?, ?, ?, null, ?, ?, ?)""",
        (gym_id, "Open gym hours extended", "Evening open gym now runs until 21:00 on weekdays. "
         "Come get your accessory work in.", owner_id, _ts(), _ts()),
    )
    messages = [
        "Who's in for the 17:30 Metcon? 🔥",
        "New PR on Fran today, finally sub-3:20!",
        "Reminder: bring clean shoes for the platform.",
        "Great energy in the 06:00 lifting session 💪",
    ]
    for i, body in enumerate(messages):
        uid = rng.choice(member_ids)
        conn.execute(
            """insert into chat_messages (gym_id, user_id, body, created_at, updated_at)
               values (?, ?, ?, ?, ?)""",
            (gym_id, uid, body, isoformat(now_utc() - timedelta(hours=i * 2)), _ts()),
        )


if __name__ == "__main__":
    seed()
