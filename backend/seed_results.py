"""Results test data shared by ``seed_demo`` and ``test_data``.

WODs with real blocks (a lift, a named metcon, a warm-up without a score),
athletes' results on them with PRs building up over the weeks, fist bumps
and comments, personal logbook entries, and follows between athletes.
Everything is written straight to the tables, scored by ``results_service``
so labels and sort values match what the app would store.
"""

from __future__ import annotations

import json
import random
from datetime import date, datetime, timedelta
from typing import Any

from backend import results_service, workout_service
from backend.security import isoformat, now_utc

# One day of programming per entry; the days cycle, so every lift and named
# workout comes back and athletes build a history with PRs.
_DAYS: list[tuple[str, list[dict[str, Any]]]] = [
    ("Fran", [
        {"title": "Warm-up", "description": "3 rounds: 200 m row, 10 air squats, 5 inchworms.", "score_type": "none"},
        {"title": "Strength", "description": "Back Squat, build to a heavy triple.", "score_type": "weight",
         "kind": "exercise", "exercise_name": "Back Squat", "set_unit": "percent",
         "sets": [{"reps": 5, "value": 70}, {"reps": 5, "value": 75}, {"reps": 3, "value": 80}, {"reps": 3, "value": 85}]},
        {"title": "Metcon", "description": "21-15-9\nThrusters (43/30 kg)\nPull-ups\nFor time, 10 min cap.",
         "score_type": "time", "workout_name": "Fran"},
    ]),
    ("Pull day", [
        {"title": "Warm-up", "description": "2 rounds: 10 banded good mornings, 10 ring rows.", "score_type": "none"},
        {"title": "Strength", "description": "Deadlift 5-5-5-3-3.", "score_type": "weight",
         "kind": "exercise", "exercise_name": "Deadlift", "set_unit": "percent",
         "sets": [{"reps": 5, "value": 70}, {"reps": 5, "value": 75}, {"reps": 5, "value": 80}, {"reps": 3, "value": 85}, {"reps": 3, "value": 88}]},
        {"title": "Metcon", "description": "AMRAP 20 min\n5 pull-ups\n10 push-ups\n15 air squats",
         "score_type": "rounds_reps", "workout_name": "Cindy"},
    ]),
    ("Engine", [
        {"title": "Warm-up", "description": "5 min easy bike, mobility.", "score_type": "none"},
        {"title": "Metcon", "description": "2000 m row for time.", "score_type": "time", "workout_name": "Row 2k"},
        {"title": "Finisher", "description": "Max calories on the assault bike in 1 min.", "score_type": "calories",
         "workout_name": "1 min bike"},
    ]),
    ("Overhead", [
        {"title": "Warm-up", "description": "PVC pass-throughs, 3 x 10 empty-bar push presses.", "score_type": "none"},
        {"title": "Strength", "description": "Push Press 5 x 3.", "score_type": "weight",
         "kind": "exercise", "exercise_name": "Push Press", "set_unit": "percent",
         "sets": [{"reps": 3, "value": 75}, {"reps": 3, "value": 80}, {"reps": 3, "value": 85}, {"reps": 3, "value": 85}, {"reps": 3, "value": 85}]},
        {"title": "Metcon", "description": "3 rounds for time\n400 m run\n21 kettlebell swings (24/16 kg)\n12 pull-ups",
         "score_type": "time", "workout_name": "Helen"},
    ]),
    ("Grip and go", [
        {"title": "Warm-up", "description": "Skill: kipping swings, 3 x 10.", "score_type": "none"},
        {"title": "Metcon", "description": "30 clean and jerks (61/43 kg) for time.", "score_type": "time",
         "workout_name": "Grace"},
        {"title": "Accessory", "description": "Max unbroken toes-to-bar.", "score_type": "reps",
         "workout_name": "Max toes-to-bar"},
    ]),
]

# A typical Rx athlete's level; each athlete gets a factor around it.
_ONE_REP_MAX = {"Back Squat": 120.0, "Deadlift": 150.0, "Push Press": 70.0}
_BASE_TIME = {"Fran": 330, "Row 2k": 460, "Helen": 690, "Grace": 260}
_BASE_OTHER = {"Cindy": 17.0, "1 min bike": 22.0, "Max toes-to-bar": 15.0}
_TIME_CAP = {"Fran": 600}
_NOTES = [
    "Felt strong today.", "Went unbroken on the first round.", "Grip gave out at the end.",
    "Banded pull-ups.", "Scaled the weight, form first.", "New belt, who dis.",
    "Paced it better than last time.", "Legs were still sore from Tuesday.",
]
_COMMENTS = [
    "Beast mode!", "Huge, congrats!", "That pace though 🔥", "Nice PR!",
    "Teach me your ways.", "Strong work today.", "See you at the 6 pm class!",
]
# Logbook entries: benchmarks done outside the box.
_PERSONAL_BENCHMARKS = [("murph", 2700), ("fran", 330), ("grace", 260), ("helen", 690), ("annie", 520), ("karen", 560)]


def program_day(conn: Any, workout_id: int, day_index: int) -> str:
    """Fills a WOD with the day's blocks; returns its title."""
    title, sections = _DAYS[day_index % len(_DAYS)]
    workout_service.replace_workout_sections(conn, daily_workout_id=workout_id, sections=sections)
    return title


def _round(kg: float) -> float:
    return max(20.0, round(kg / 2.5) * 2.5)


def _clock(seconds: float) -> str:
    seconds = int(max(60, seconds))
    return f"{seconds // 60}:{seconds % 60:02d}"


def _score(rng: random.Random, section: Any, level: float) -> dict[str, Any] | None:
    """What an athlete at ``level`` (1.0 = typical Rx) logs on a block."""
    name = section["workout_name"] or ""
    if section["kind"] == "exercise":
        one_rm = _ONE_REP_MAX.get(section["exercise_name"], 80.0) * level
        prescribed = json.loads(section["sets_json"] or "[]") or [{"reps": 5, "value": 75}]
        sets = []
        for item in prescribed:
            pct = float(item.get("value") or 75) / 100
            sets.append({"reps": int(item["reps"]), "kg": _round(one_rm * pct * rng.uniform(0.97, 1.04))})
        return {"sets": sets}
    score_type = section["score_type"]
    if score_type == "time":
        seconds = _BASE_TIME.get(name, 600) / level * rng.uniform(0.92, 1.1)
        cap = _TIME_CAP.get(name)
        if cap and seconds > cap:
            return {"score": str(rng.randint(60, 80)), "time_capped": True}
        return {"score": _clock(seconds)}
    base = _BASE_OTHER.get(name, 15.0) * level * rng.uniform(0.9, 1.1)
    if score_type == "rounds_reps":
        return {"score": f"{int(base)}+{rng.randint(0, 29)}"}
    if score_type == "weight":
        return {"score": str(_round(base * 5))}
    if score_type == "distance":
        return {"score": str(int(base * 100))}
    return {"score": str(max(1, int(base)))}


def _insert(conn: Any, *, user_id: int, gym_id: int | None, performed_on: str, logged_at: str,
            section: Any | None, entry: dict[str, Any], division: str, notes: str,
            class_id: int | None = None, description: str = "") -> int:
    value, label, sets = results_service.parse_score(
        score_type=entry["score_type"] if section is None else section["score_type"],
        kind=entry.get("kind", "workout") if section is None else section["kind"],
        score=entry.get("score"),
        time_capped=bool(entry.get("time_capped")),
        sets=entry.get("sets"),
    )
    row = conn.execute(
        """
        insert into workout_results (
          user_id, gym_id, section_id, daily_workout_id, performed_on, class_schedule_id,
          movement_id, workout_name, section_title, score_type, score_value, score_label,
          division, time_capped, sets_json, notes, source, description, created_at, updated_at
        )
        values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        on conflict do nothing
        returning id
        """,
        (
            user_id,
            gym_id,
            None if section is None else section["id"],
            None if section is None else section["daily_workout_id"],
            performed_on,
            class_id,
            entry.get("movement_id") if section is None else section["movement_id"],
            entry.get("workout_name", "") if section is None else section["workout_name"],
            entry.get("title", "") if section is None else section["title"],
            entry["score_type"] if section is None else section["score_type"],
            value,
            label,
            division,
            1 if entry.get("time_capped") else 0,
            json.dumps(sets),
            notes,
            "personal" if section is None else "gym",
            description,
            logged_at,
            logged_at,
        ),
    ).fetchone()
    return int(row["id"]) if row else 0


def seed_results(conn: Any, rng: random.Random, *, gym_id: int, athlete_ids: list[int],
                 star_id: int | None = None, created_by: int | None = None) -> dict[str, int]:
    """Results on the gym's published WODs up to today, plus bumps, comments,
    logbook entries, privacy choices and follows among ``athlete_ids``.
    ``star_id`` (the demo athlete) logs nearly every WOD and keeps improving,
    so their profile shows PRs and a percentage chart. ``created_by`` limits
    the results to WODs that user programmed (test data leaves the box's own
    WODs alone)."""
    if not athlete_ids:
        return {"results": 0, "personal": 0, "follows": 0}
    today = results_service.gym_today(conn, gym_id)
    sections = conn.execute(
        """
        select s.id, s.daily_workout_id, s.title, s.score_type, s.kind, s.exercise_name,
               s.sets_json, s.movement_id, s.workout_name, w.scheduled_date
        from daily_workout_sections s
        join daily_workouts w on w.id = s.daily_workout_id
        where w.gym_id = ? and w.status = 'published' and w.scheduled_date <= ?
          and s.score_type <> 'none' and (cast(? as integer) is null or w.created_by_user_id = ?)
        order by w.scheduled_date, s.position
        """,
        (gym_id, today, created_by, created_by),
    ).fetchall()
    everyone = list(dict.fromkeys([*athlete_ids, *([star_id] if star_id else [])]))
    # Re-seeding starts over: earlier logbook entries and follows of these
    # athletes go (gym results went with the gym's WODs).
    marks = ",".join("?" for _ in everyone)
    conn.execute(f"delete from workout_results where source = 'personal' and user_id in ({marks})", tuple(everyone))
    conn.execute(
        f"delete from athlete_follows where follower_id in ({marks}) or followee_id in ({marks})",
        (*everyone, *everyone),
    )
    level = {uid: rng.uniform(0.7, 1.25) for uid in everyone}
    scaled = {uid: level[uid] < 0.85 for uid in everyone}
    first_day = min((s["scheduled_date"] for s in sections), default=today)
    span = max(1, (date.fromisoformat(today) - date.fromisoformat(first_day)).days)
    result_ids: list[tuple[int, int]] = []
    by_day: dict[str, list[Any]] = {}
    for section in sections:
        by_day.setdefault(section["scheduled_date"], []).append(section)
    for day, day_sections in by_day.items():
        booked = [
            int(row["user_id"])
            for row in conn.execute(
                """
                select distinct b.user_id
                from class_bookings b join class_schedules c on c.id = b.class_schedule_id
                where c.gym_id = ? and c.start_time like ? and b.attendance_status <> 'no_show'
                """,
                (gym_id, f"{day}%"),
            ).fetchall()
            if int(row["user_id"]) in level
        ]
        crowd = booked or rng.sample(athlete_ids, k=max(1, len(athlete_ids) // 4))
        loggers = [uid for uid in crowd if rng.random() < 0.7]
        if star_id and star_id not in loggers and rng.random() < 0.9:
            loggers.append(star_id)
        # Everyone gets a little better over the weeks, the demo athlete most.
        progress = (date.fromisoformat(day) - date.fromisoformat(first_day)).days / span
        for uid in loggers:
            athlete_level = level[uid] * (1 + progress * (0.12 if uid == star_id else 0.04))
            class_id = results_service.booked_class_id(conn, user_id=uid, gym_id=gym_id, day=day)
            for section in day_sections:
                if rng.random() < 0.15:
                    continue
                entry = _score(rng, section, athlete_level * rng.uniform(0.97, 1.03))
                if entry is None:
                    continue
                logged = f"{day}T{rng.randint(7, 20):02d}:{rng.randint(0, 59):02d}:00+00:00"
                rid = _insert(
                    conn, user_id=uid, gym_id=gym_id, performed_on=day, logged_at=logged,
                    section=section, entry=entry,
                    division="scaled" if scaled[uid] and rng.random() < 0.8 else "rx",
                    notes=rng.choice(_NOTES) if rng.random() < 0.15 else "",
                    class_id=class_id,
                )
                if rid:
                    result_ids.append((rid, uid))

    # Fist bumps and comments from other athletes.
    stamp = isoformat(now_utc())
    for rid, owner in result_ids:
        if rng.random() < 0.35:
            fans = rng.sample(everyone, k=min(len(everyone), rng.randint(1, 5)))
            for fan in fans:
                if fan != owner:
                    conn.execute(
                        "insert into result_bumps (result_id, user_id, created_at) values (?, ?, ?) on conflict do nothing",
                        (rid, fan, stamp),
                    )
        if rng.random() < 0.08:
            author = rng.choice(everyone)
            if author != owner:
                conn.execute(
                    "insert into result_comments (result_id, user_id, body, created_at) values (?, ?, ?, ?)",
                    (rid, author, rng.choice(_COMMENTS), stamp),
                )

    personal = _seed_logbook(conn, rng, everyone, level, star_id)
    follows = _seed_follows(conn, rng, everyone, star_id)
    return {"results": len(result_ids), "personal": personal, "follows": follows}


def _seed_logbook(conn: Any, rng: random.Random, athletes: list[int], level: dict[int, float],
                  star_id: int | None) -> int:
    """Benchmarks and lifts some athletes log on their own."""
    benchmarks = {
        row["id"]: results_service.benchmark_payload(row)
        for row in conn.execute("select id, name, category, structure_json from benchmark_workouts").fetchall()
    }
    deadlift = conn.execute(
        "select id from movements where gym_id is null and lower(name) = 'deadlift'"
    ).fetchone()
    today = datetime.now().date()
    count = 0
    writers = [uid for uid in athletes if rng.random() < 0.3]
    if star_id and star_id not in writers:
        writers.append(star_id)
    for uid in writers:
        entries = 6 if uid == star_id else rng.randint(1, 3)
        for i in range(entries):
            key, base = rng.choice(_PERSONAL_BENCHMARKS)
            benchmark = benchmarks.get(key)
            if benchmark is None:
                continue
            day = today - timedelta(days=rng.randint(20, 180) if uid != star_id else 30 * (entries - i))
            seconds = base / level[uid] * rng.uniform(0.9, 1.1)
            _insert(
                conn, user_id=uid, gym_id=None, performed_on=day.isoformat(),
                logged_at=f"{day.isoformat()}T10:00:00+00:00", section=None,
                entry={"score_type": "time", "score": _clock(seconds), "workout_name": benchmark["name"],
                       "title": benchmark["name"]},
                division="rx" if level[uid] >= 0.85 else "scaled", notes="",
                description=benchmark["description"],
            )
            count += 1
        if deadlift is not None and (uid == star_id or rng.random() < 0.3):
            day = today - timedelta(days=rng.randint(40, 90))
            kg = _round(_ONE_REP_MAX["Deadlift"] * level[uid])
            _insert(
                conn, user_id=uid, gym_id=None, performed_on=day.isoformat(),
                logged_at=f"{day.isoformat()}T10:00:00+00:00", section=None,
                entry={"score_type": "weight", "kind": "exercise", "movement_id": int(deadlift["id"]),
                       "title": "Deadlift", "sets": [{"reps": 1, "kg": kg}, {"reps": 3, "kg": _round(kg * 0.9)}]},
                division="rx", notes="Testing day at the old gym.",
            )
            count += 1
    return count


def _seed_follows(conn: Any, rng: random.Random, athletes: list[int], star_id: int | None) -> int:
    """Privacy choices and follows: most athletes follow a few others, some
    requests are still open. The demo athlete follows people who share with
    followers, so their Friends feed has something in it."""
    for uid in athletes:
        if uid == star_id:
            continue
        roll = rng.random()
        visibility = "followers" if roll < 0.35 else "private" if roll < 0.4 else "gym"
        conn.execute("update users set results_visibility = ? where id = ?", (visibility, uid))
    stamp = isoformat(now_utc())
    count = 0

    def follow(follower: int, followee: int, status: str) -> None:
        nonlocal count
        inserted = conn.execute(
            """
            insert into athlete_follows (follower_id, followee_id, status, created_at, accepted_at)
            values (?, ?, ?, ?, ?)
            on conflict do nothing
            returning follower_id
            """,
            (follower, followee, status, stamp, stamp if status == "accepted" else None),
        ).fetchone()
        count += 1 if inserted else 0

    others = [uid for uid in athletes if uid != star_id]
    for uid in others:
        for followee in rng.sample(others, k=min(len(others), rng.randint(0, 4))):
            if followee != uid:
                follow(uid, followee, "accepted" if rng.random() < 0.85 else "pending")
    if star_id and others:
        sharing = [
            int(row["id"])
            for row in conn.execute(
                f"select id from users where results_visibility = 'followers' and id in ({','.join('?' for _ in others)})",
                tuple(others),
            ).fetchall()
        ]
        for followee in sharing[:5]:
            follow(star_id, followee, "accepted")
        for follower in [uid for uid in others if uid not in sharing][:2]:
            follow(follower, star_id, "pending")
        for follower in sharing[5:8]:
            follow(follower, star_id, "accepted")
    return count
