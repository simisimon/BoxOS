"""Friends across gyms: follows with approval and the results feed.

A follow starts as a request; the person followed accepts or declines it.
People find each other by name among the members of a gym they share, or
anywhere with a personal invite code. The feed shows the results of the
people you follow: everything they log when they share with "Followers and
my gym", only results at a gym you share when they keep them to "My gym",
and nothing when they keep them to themselves.
"""

from __future__ import annotations

import secrets
from http import HTTPStatus
from typing import Any, TYPE_CHECKING

from backend import notifications_core
from backend.security import isoformat, now_utc
from backend.validation import ApiError

if TYPE_CHECKING:
    from backend.db import ManagedConnection, Row

MAX_FEED = 50
_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"


def _name(row: Row) -> str:
    name = (row["display_name"] or "").strip() or (row["nickname"] or "").strip()
    return name or str(row["email"]).split("@")[0]


def member_gym_ids(connection: ManagedConnection, user_id: int) -> set[int]:
    rows = connection.execute(
        "select gym_id from gym_memberships where user_id = ? and status = 'active'",
        (user_id,),
    ).fetchall()
    return {int(row["gym_id"]) for row in rows}


def follows(connection: ManagedConnection, *, follower_id: int, followee_id: int) -> bool:
    row = connection.execute(
        "select 1 from athlete_follows where follower_id = ? and followee_id = ? and status = 'accepted'",
        (follower_id, followee_id),
    ).fetchone()
    return row is not None


def invite_code(connection: ManagedConnection, user_id: int) -> str:
    """The athlete's code for invite links, made on first use."""
    row = connection.execute("select follow_code from users where id = ?", (user_id,)).fetchone()
    if row and row["follow_code"]:
        return row["follow_code"]
    for _ in range(10):
        code = "".join(secrets.choice(_CODE_ALPHABET) for _ in range(8))
        taken = connection.execute("select 1 from users where follow_code = ?", (code,)).fetchone()
        if taken is None:
            connection.execute("update users set follow_code = ? where id = ?", (code, user_id))
            return code
    raise ApiError(HTTPStatus.SERVICE_UNAVAILABLE, "Could not make an invite code. Try again.")


def _person(row: Row) -> dict[str, Any]:
    return {
        "user_id": row["id"],
        "name": _name(row),
        "avatar_url": row["profile_image_url"] or "",
        "gym_name": row["gym_name"] or "",
    }


_PERSON_COLUMNS = """
    u.id, u.display_name, u.nickname, u.email, u.profile_image_url,
    coalesce(g.name, '') as gym_name
"""


def overview(connection: ManagedConnection, *, user_id: int) -> dict[str, Any]:
    """Who the athlete follows and who follows them, with open requests."""
    outgoing = connection.execute(
        f"""
        select {_PERSON_COLUMNS}, f.status
        from athlete_follows f
        join users u on u.id = f.followee_id
        left join gyms g on g.id = u.active_gym_id
        where f.follower_id = ? and u.deleted_at is null
        order by lower(coalesce(nullif(u.display_name, ''), u.email))
        """,
        (user_id,),
    ).fetchall()
    incoming = connection.execute(
        f"""
        select {_PERSON_COLUMNS}, f.status
        from athlete_follows f
        join users u on u.id = f.follower_id
        left join gyms g on g.id = u.active_gym_id
        where f.followee_id = ? and u.deleted_at is null
        order by f.created_at desc
        """,
        (user_id,),
    ).fetchall()
    return {
        "invite_code": invite_code(connection, user_id),
        "following": [_person(r) for r in outgoing if r["status"] == "accepted"],
        "sent": [_person(r) for r in outgoing if r["status"] == "pending"],
        "followers": [_person(r) for r in incoming if r["status"] == "accepted"],
        "requests": [_person(r) for r in incoming if r["status"] == "pending"],
    }


def search(connection: ManagedConnection, *, user_id: int, query: str, limit: int = 20) -> list[dict[str, Any]]:
    """Members of the athlete's gyms whose name matches, with the follow
    status (none, pending, accepted)."""
    wanted = " ".join(query.strip().lower().split())
    if len(wanted) < 2:
        return []
    pattern = f"%{wanted}%"
    rows = connection.execute(
        f"""
        select distinct {_PERSON_COLUMNS}, coalesce(f.status, 'none') as status
        from gym_memberships mine
        join gym_memberships theirs on theirs.gym_id = mine.gym_id and theirs.status = 'active'
        join users u on u.id = theirs.user_id
        left join gyms g on g.id = u.active_gym_id
        left join athlete_follows f on f.follower_id = ? and f.followee_id = u.id
        where mine.user_id = ? and mine.status = 'active' and u.id <> ? and u.deleted_at is null
          and (lower(coalesce(u.display_name, '')) like ? or lower(coalesce(u.nickname, '')) like ?)
        limit ?
        """,
        (user_id, user_id, user_id, pattern, pattern, max(1, min(limit, 50))),
    ).fetchall()
    people = [{**_person(r), "status": r["status"]} for r in rows]
    return sorted(people, key=lambda p: p["name"].lower())


def _user(connection: ManagedConnection, user_id: int) -> Row | None:
    return connection.execute(
        """
        select id, display_name, nickname, email, notify_result_activity, active_gym_id
        from users where id = ? and deleted_at is null
        """,
        (user_id,),
    ).fetchone()


def _notify(connection: ManagedConnection, *, to: Row, title: str, body: str, entity_id: int) -> None:
    if not bool(to["notify_result_activity"]):
        return
    notifications_core.create_notification(
        connection,
        user_id=to["id"],
        gym_id=to["active_gym_id"],
        type="follow",
        title=title,
        body=body,
        entity_type="user",
        entity_id=entity_id,
    )


def request_follow(
    connection: ManagedConnection,
    *,
    user_id: int,
    target_id: int | None = None,
    code: str | None = None,
) -> dict[str, Any]:
    """Asks to follow someone: a member of a shared gym, or anyone by their
    invite code. Returns the follow status."""
    if code:
        row = connection.execute(
            "select id from users where follow_code = ? and deleted_at is null",
            (code.strip().upper(),),
        ).fetchone()
        if row is None:
            raise ApiError(HTTPStatus.NOT_FOUND, "No athlete has this invite code.")
        target_id = int(row["id"])
    elif target_id is not None:
        if not member_gym_ids(connection, user_id) & member_gym_ids(connection, target_id):
            raise ApiError(HTTPStatus.NOT_FOUND, "Athlete not found.")
    else:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Choose who to follow.")
    if target_id == user_id:
        raise ApiError(HTTPStatus.BAD_REQUEST, "You can't follow yourself.")
    target = _user(connection, target_id)
    me = _user(connection, user_id)
    if target is None or me is None:
        raise ApiError(HTTPStatus.NOT_FOUND, "Athlete not found.")
    existing = connection.execute(
        "select status from athlete_follows where follower_id = ? and followee_id = ?",
        (user_id, target_id),
    ).fetchone()
    if existing is not None:
        return {"user_id": target_id, "status": existing["status"]}
    connection.execute(
        """
        insert into athlete_follows (follower_id, followee_id, status, created_at)
        values (?, ?, 'pending', ?)
        """,
        (user_id, target_id, isoformat(now_utc())),
    )
    _notify(
        connection,
        to=target,
        title="Follow request",
        body=f"{_name(me)} wants to follow your results.",
        entity_id=user_id,
    )
    return {"user_id": target_id, "status": "pending"}


def accept(connection: ManagedConnection, *, user_id: int, follower_id: int) -> None:
    updated = connection.execute(
        """
        update athlete_follows set status = 'accepted', accepted_at = ?
        where follower_id = ? and followee_id = ? and status = 'pending'
        returning follower_id
        """,
        (isoformat(now_utc()), follower_id, user_id),
    ).fetchone()
    if updated is None:
        raise ApiError(HTTPStatus.NOT_FOUND, "Follow request not found.")
    follower = _user(connection, follower_id)
    me = _user(connection, user_id)
    if follower is not None and me is not None:
        _notify(
            connection,
            to=follower,
            title="Follow request accepted",
            body=f"You now follow {_name(me)}.",
            entity_id=user_id,
        )


def remove_follower(connection: ManagedConnection, *, user_id: int, follower_id: int) -> None:
    """Declines a request or removes a follower."""
    deleted = connection.execute(
        "delete from athlete_follows where follower_id = ? and followee_id = ? returning follower_id",
        (follower_id, user_id),
    ).fetchone()
    if deleted is None:
        raise ApiError(HTTPStatus.NOT_FOUND, "Follower not found.")


def unfollow(connection: ManagedConnection, *, user_id: int, followee_id: int) -> None:
    """Stops following, or withdraws a request."""
    deleted = connection.execute(
        "delete from athlete_follows where follower_id = ? and followee_id = ? returning followee_id",
        (user_id, followee_id),
    ).fetchone()
    if deleted is None:
        raise ApiError(HTTPStatus.NOT_FOUND, "You don't follow this athlete.")


def feed(connection: ManagedConnection, *, user_id: int, offset: int = 0, limit: int = MAX_FEED) -> dict[str, Any]:
    """Results of the people the athlete follows, newest logged first."""
    from backend import result_social_service, results_service

    gyms = sorted(member_gym_ids(connection, user_id)) or [0]
    marks = ", ".join("?" for _ in gyms)
    columns = ", ".join("r." + c.strip() for c in results_service.RESULT_COLUMNS.split(","))
    limit = max(1, min(limit, MAX_FEED))
    rows = connection.execute(
        f"""
        select {columns},
               u.display_name, u.nickname, u.email, u.profile_image_url,
               coalesce(g.name, '') as gym_name
        from athlete_follows f
        join workout_results r on r.user_id = f.followee_id
        join users u on u.id = r.user_id
        left join gyms g on g.id = r.gym_id
        where f.follower_id = ? and f.status = 'accepted' and u.deleted_at is null
          and (
            u.results_visibility = 'followers'
            or (u.results_visibility = 'gym' and r.gym_id in ({marks}))
          )
        order by r.created_at desc, r.id desc
        limit ? offset ?
        """,
        (user_id, *gyms, limit + 1, max(0, offset)),
    ).fetchall()
    more = len(rows) > limit
    rows = rows[:limit]
    prs = results_service.pr_flags(connection, rows)
    social = result_social_service.social_counts(
        connection, result_ids=[int(r["id"]) for r in rows], viewer_id=user_id
    )
    entries = []
    for row in rows:
        payload = results_service.result_payload(row)
        payload["notes"] = ""
        entries.append(
            {
                **payload,
                **social[int(row["id"])],
                "is_pr": int(row["id"]) in prs,
                "user_id": row["user_id"],
                "name": _name(row),
                "avatar_url": row["profile_image_url"] or "",
                "gym_name": row["gym_name"],
            }
        )
    return {"entries": entries, "has_more": more}
