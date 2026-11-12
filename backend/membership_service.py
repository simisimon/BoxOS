from __future__ import annotations

from typing import Any, TYPE_CHECKING

from backend.db import get_connection
from backend.security import isoformat, now_utc
from backend.validation import decode_roles, encode_roles

if TYPE_CHECKING:
    from backend.db import ManagedConnection, Row


def slugify(value: str) -> str:
    normalized = [character.lower() if character.isalnum() else "-" for character in value.strip()]
    slug = "".join(normalized)
    while "--" in slug:
        slug = slug.replace("--", "-")
    return slug.strip("-") or "gym"


def unique_gym_slug(connection: ManagedConnection, name: str) -> str:
    base_slug = slugify(name)
    slug = base_slug
    counter = 2
    while connection.execute("select 1 from gyms where slug = ?", (slug,)).fetchone() is not None:
        slug = f"{base_slug}-{counter}"
        counter += 1
    return slug


def list_user_memberships(connection: ManagedConnection, user_id: int, *, status: str = "active") -> list[Row]:
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


def get_active_membership(connection: ManagedConnection, user_id: int) -> Row | None:
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


def membership_payload(row: Row) -> dict[str, Any]:
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


def active_gym_payload(row: Row | None) -> dict[str, Any] | None:
    if row is None:
        return None
    return {
        "id": row["gym_id"],
        "name": row["gym_name"],
        "slug": row["gym_slug"],
        "logo_url": row["gym_logo_url"],
        "timezone": row["gym_timezone"],
    }


def sync_user_context(connection: ManagedConnection, user_id: int) -> None:
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


def role_user_payload(row: Row) -> dict[str, Any]:
    return {
        "id": row["id"],
        "email": row["email"],
        "role": row["role"],
        "available_roles": decode_roles(row["roles_json"]),
        "display_name": row["display_name"],
        "nickname": row["nickname"],
    }


def role_managed_member_payload(row: Row) -> dict[str, Any]:
    role = row["active_role"]
    available_roles = decode_roles(row["roles_json"])
    can_edit_role = role != "admin"
    if can_edit_role:
        available_roles = [managed_role for managed_role in available_roles if managed_role in {"athlete", "trainer"}]
        if not available_roles:
            available_roles = ["athlete"]
    total_bookings = int(row["total_bookings"]) if "total_bookings" in row.keys() else 0
    attended_bookings = int(row["attended_bookings"]) if "attended_bookings" in row.keys() else 0
    return {
        "id": row["user_id"],
        "membership_id": row["id"],
        "email": row["email"],
        "role": role,
        "available_roles": available_roles,
        "display_name": row["display_name"],
        "nickname": row["nickname"],
        "can_edit_role": can_edit_role,
        "profile_image_url": row["profile_image_url"] if "profile_image_url" in row.keys() else "",
        "status": row["status"] if "status" in row.keys() else "active",
        "admin_note": row["admin_note"] if "admin_note" in row.keys() else "",
        "joined_at": row["joined_at"] if "joined_at" in row.keys() else None,
        "total_bookings": total_bookings,
        "attended_bookings": attended_bookings,
        "no_show_bookings": int(row["no_show_bookings"]) if "no_show_bookings" in row.keys() else 0,
        "booking_rate": 0.0 if total_bookings <= 0 else round((attended_bookings / total_bookings) * 100, 1),
        "last_booking_at": row["last_booking_at"] if "last_booking_at" in row.keys() else None,
    }


def profile_payload(row: Row) -> dict[str, Any]:
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


OWNER_ROLES_FILTER = "gym_memberships.roles_json like '%\"admin\"%'"


def is_gym_owner(connection: ManagedConnection, user_id: int, gym_id: int) -> bool:
    row = connection.execute(
        f"""
        select gym_memberships.id
        from gym_memberships
        join users on users.id = gym_memberships.user_id
        where gym_memberships.user_id = ? and gym_memberships.gym_id = ?
          and gym_memberships.status = 'active'
          and users.deleted_at is null
          and {OWNER_ROLES_FILTER}
        """,
        (user_id, gym_id),
    ).fetchone()
    return row is not None


def sole_owned_gyms(connection: ManagedConnection, user_id: int) -> list[dict[str, Any]]:
    """Gyms the user owns where no other (non-deleted) owner is left.

    Each entry lists the other members who could take over ownership. An empty
    ``members`` list means nobody else belongs to the gym.
    """
    gyms = connection.execute(
        f"""
        select gyms.id, gyms.name
        from gym_memberships
        join gyms on gyms.id = gym_memberships.gym_id
        where gym_memberships.user_id = ?
          and gym_memberships.status = 'active'
          and {OWNER_ROLES_FILTER}
          and not exists (
            select 1
            from gym_memberships as other
            join users as other_user on other_user.id = other.user_id
            where other.gym_id = gym_memberships.gym_id
              and other.user_id <> gym_memberships.user_id
              and other.status = 'active'
              and other_user.deleted_at is null
              and other.roles_json like '%"admin"%'
          )
        order by lower(gyms.name) asc, gyms.id asc
        """,
        (user_id,),
    ).fetchall()
    result: list[dict[str, Any]] = []
    for gym in gyms:
        members = connection.execute(
            """
            select users.id, users.email, users.display_name, users.nickname, users.profile_image_url,
                   gym_memberships.active_role, gym_memberships.status
            from gym_memberships
            join users on users.id = gym_memberships.user_id
            where gym_memberships.gym_id = ?
              and gym_memberships.user_id <> ?
              and gym_memberships.status in ('active', 'paused')
              and users.deleted_at is null
            order by case gym_memberships.active_role when 'trainer' then 0 else 1 end,
                     lower(coalesce(nullif(users.display_name, ''), users.email)) asc
            """,
            (gym["id"], user_id),
        ).fetchall()
        result.append(
            {
                "id": gym["id"],
                "name": gym["name"],
                "members": [
                    {
                        "id": member["id"],
                        "email": member["email"],
                        "display_name": member["display_name"],
                        "nickname": member["nickname"],
                        "profile_image_url": member["profile_image_url"],
                        "role": member["active_role"],
                        "status": member["status"],
                    }
                    for member in members
                ],
            }
        )
    return result


def make_gym_owner(connection: ManagedConnection, *, gym_id: int, user_id: int) -> bool:
    """Give an existing (active or paused) member the owner role in a gym.

    The member keeps their other roles, becomes active, and switches to the
    owner role. Returns False when the user is not a member of the gym.
    """
    membership = connection.execute(
        """
        select gym_memberships.id, gym_memberships.roles_json
        from gym_memberships
        join users on users.id = gym_memberships.user_id
        where gym_memberships.user_id = ? and gym_memberships.gym_id = ?
          and gym_memberships.status in ('active', 'paused')
          and users.deleted_at is null
        """,
        (user_id, gym_id),
    ).fetchone()
    if membership is None:
        return False
    roles = ["admin"] + [role for role in decode_roles(membership["roles_json"]) if role != "admin"]
    timestamp = isoformat(now_utc())
    connection.execute(
        """
        update gym_memberships
        set active_role = 'admin', roles_json = ?, status = 'active', updated_at = ?
        where id = ?
        """,
        (encode_roles(roles), timestamp, membership["id"]),
    )
    # Owner screens need the owner account type as well as the owner role.
    connection.execute(
        "update users set account_type = 'admin', updated_at = ? where id = ?",
        (timestamp, user_id),
    )
    sync_user_context(connection, user_id)
    return True
