from __future__ import annotations

import sqlite3
from typing import Any

from backend.db import get_connection
from backend.security import isoformat, now_utc
from backend.validation import decode_roles


def slugify(value: str) -> str:
    normalized = [character.lower() if character.isalnum() else "-" for character in value.strip()]
    slug = "".join(normalized)
    while "--" in slug:
        slug = slug.replace("--", "-")
    return slug.strip("-") or "gym"


def unique_gym_slug(connection: sqlite3.Connection, name: str) -> str:
    base_slug = slugify(name)
    slug = base_slug
    counter = 2
    while connection.execute("select 1 from gyms where slug = ?", (slug,)).fetchone() is not None:
        slug = f"{base_slug}-{counter}"
        counter += 1
    return slug


def list_user_memberships(connection: sqlite3.Connection, user_id: int, *, status: str = "active") -> list[sqlite3.Row]:
    return connection.execute(
        """
        select gym_memberships.id, gym_memberships.user_id, gym_memberships.gym_id, gym_memberships.active_role,
               gym_memberships.roles_json, gym_memberships.status, gyms.name as gym_name, gyms.slug as gym_slug,
               gyms.logo_url as gym_logo_url, gyms.timezone as gym_timezone
        from gym_memberships
        join gyms on gyms.id = gym_memberships.gym_id
        where gym_memberships.user_id = ? and gym_memberships.status = ?
        order by gyms.name asc
        """,
        (user_id, status),
    ).fetchall()


def get_active_membership(connection: sqlite3.Connection, user_id: int) -> sqlite3.Row | None:
    user = connection.execute("select account_type, active_gym_id from users where id = ?", (user_id,)).fetchone()
    if user is None:
        return None
    active_gym_id = user["active_gym_id"]
    if active_gym_id is not None:
        membership = connection.execute(
            """
            select gym_memberships.id, gym_memberships.user_id, gym_memberships.gym_id, gym_memberships.active_role,
                   gym_memberships.roles_json, gym_memberships.status, gyms.name as gym_name, gyms.slug as gym_slug,
                   gyms.logo_url as gym_logo_url, gyms.timezone as gym_timezone
            from gym_memberships
            join gyms on gyms.id = gym_memberships.gym_id
            where gym_memberships.user_id = ? and gym_memberships.gym_id = ? and gym_memberships.status = 'active'
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
            set active_gym_id = null, role = ?, roles_json = ?, updated_at = ?
            where id = ?
            """,
            (user["role"], user["roles_json"], isoformat(now_utc()), user_id),
        )
        return
    connection.execute(
        """
        update users
        set active_gym_id = ?, role = ?, roles_json = ?, updated_at = ?
        where id = ?
        """,
        (active_membership["gym_id"], active_membership["active_role"], active_membership["roles_json"], isoformat(now_utc()), user_id),
    )


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
        available_roles = [managed_role for managed_role in available_roles if managed_role in {"athlete", "trainer"}]
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


def profile_payload(row: sqlite3.Row) -> dict[str, Any]:
    connection = get_connection()
    active_membership = get_active_membership(connection, row["id"]) if "id" in row.keys() else None
    memberships = list_user_memberships(connection, row["id"]) if "id" in row.keys() else []
    connection.close()
    keys = row.keys()
    return {
        "email": row["email"],
        "role": row["role"],
        "available_roles": decode_roles(row["roles_json"]),
        "display_name": row["display_name"],
        "nickname": row["nickname"],
        "account_type": row["account_type"],
        "profile_image_url": row["profile_image_url"] if "profile_image_url" in keys else "",
        "active_gym": active_gym_payload(active_membership),
        "memberships": [membership_payload(membership) for membership in memberships],
    }
