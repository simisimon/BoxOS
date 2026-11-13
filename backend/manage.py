"""Account administration for invite-only deployments.

Run inside the backend container. On the server (production stack):

    docker compose -f docker-compose.prod.yml exec backend python -m backend.manage create-user \\
      --email anna@example.com --name "Anna Weber" --role athlete --gym "CrossFit Example"

In the local dev stack the service is called backend-dev:

    docker compose exec backend-dev python -m backend.manage list-users

Commands:
    create-user      create an account (verified) and print its password
    reset-password   set a new password, sign the user out everywhere, print it
    deactivate-user  sign the user out and lock the password (undo: reset-password)
    list-users       list accounts with role and gym
    list-gyms        list gyms with their slug

Roles: athlete, trainer (coaches classes) or admin (box owner; can create a
box in the app). Passwords are generated unless --password is given.
"""

from __future__ import annotations

import argparse
import secrets
import string
import sys
from typing import Any, Sequence

from backend import db, security, validation
from backend.membership_service import sync_user_context

ROLE_SETS = {
    "athlete": ["athlete"],
    "trainer": ["athlete", "trainer"],
    "admin": ["athlete", "trainer", "admin"],
}

# No look-alike characters (0/O, 1/l/I) so a password read out loud or copied
# from a message still works.
_PASSWORD_ALPHABET = "".join(
    ch for ch in string.ascii_letters + string.digits if ch not in "0O1lI"
)


class CommandError(Exception):
    pass


def generate_password(length: int = 14) -> str:
    return "".join(secrets.choice(_PASSWORD_ALPHABET) for _ in range(length))


def _find_gym(connection: Any, value: str) -> Any:
    needle = value.strip()
    rows = connection.execute(
        "select id, name, slug from gyms where slug = ? or lower(name) = lower(?) order by id",
        (needle.lower(), needle),
    ).fetchall()
    if not rows:
        raise CommandError(f'No gym named "{value}". Run list-gyms to see the gyms.')
    if len(rows) > 1:
        slugs = ", ".join(row["slug"] for row in rows)
        raise CommandError(f'Several gyms match "{value}"; use the slug instead ({slugs}).')
    return rows[0]


def _find_user(connection: Any, email: str) -> Any:
    row = connection.execute(
        "select * from users where email = ? and deleted_at is null",
        (validation.require_email(email),),
    ).fetchone()
    if row is None:
        raise CommandError(f"No account with email {email}.")
    return row


def create_user(
    *,
    email: str,
    name: str,
    role: str,
    gym: str | None = None,
    nickname: str | None = None,
    password: str | None = None,
) -> str:
    """Create a verified account, optionally inside a gym. Returns the password."""
    normalized_email = validation.require_email(email)
    display_name = name.strip()
    if not display_name:
        raise CommandError("--name must not be empty.")
    if role not in ROLE_SETS:
        raise CommandError(f"--role must be one of {', '.join(ROLE_SETS)}.")
    password = password or generate_password()
    validation.require_password(password)
    roles = ROLE_SETS[role]
    account_type = "admin" if role == "admin" else "athlete"
    nickname = (nickname or display_name.split()[0]).strip().lower()
    timestamp = security.isoformat(security.now_utc())

    connection = db.get_connection()
    try:
        existing = connection.execute(
            "select id from users where email = ? and deleted_at is null",
            (normalized_email,),
        ).fetchone()
        if existing is not None:
            raise CommandError(f"{normalized_email} already has an account. Use reset-password instead.")
        gym_row = _find_gym(connection, gym) if gym else None
        with connection:
            user_id = int(
                connection.execute(
                    """
                    insert into users (email, password_hash, email_verified, role, roles_json, display_name, nickname,
                                       account_type, created_at, updated_at)
                    values (?, ?, 1, ?, ?, ?, ?, ?, ?, ?)
                    returning id
                    """,
                    (
                        normalized_email,
                        security.hash_password(password),
                        role,
                        validation.encode_roles(roles),
                        display_name,
                        nickname,
                        account_type,
                        timestamp,
                        timestamp,
                    ),
                ).fetchone()["id"]
            )
            if gym_row is not None:
                connection.execute(
                    """
                    insert into gym_memberships (user_id, gym_id, active_role, roles_json, status, created_at, updated_at)
                    values (?, ?, ?, ?, 'active', ?, ?)
                    """,
                    (user_id, gym_row["id"], role, validation.encode_roles(roles), timestamp, timestamp),
                )
                connection.execute(
                    "update users set active_gym_id = ? where id = ?",
                    (gym_row["id"], user_id),
                )
                sync_user_context(connection, user_id)
        return password
    finally:
        connection.close()


def reset_password(*, email: str, password: str | None = None) -> str:
    password = password or generate_password()
    validation.require_password(password)
    connection = db.get_connection()
    try:
        user = _find_user(connection, email)
        with connection:
            connection.execute(
                "update users set password_hash = ?, email_verified = 1, updated_at = ? where id = ?",
                (security.hash_password(password), security.isoformat(security.now_utc()), user["id"]),
            )
            connection.execute("delete from sessions where user_id = ?", (user["id"],))
            connection.execute("delete from password_reset_tokens where user_id = ?", (user["id"],))
        return password
    finally:
        connection.close()


def deactivate_user(*, email: str) -> None:
    """Sign the user out and replace the password with one nobody knows."""
    connection = db.get_connection()
    try:
        user = _find_user(connection, email)
        with connection:
            connection.execute(
                "update users set password_hash = ?, updated_at = ? where id = ?",
                (
                    security.hash_password(secrets.token_urlsafe(32)),
                    security.isoformat(security.now_utc()),
                    user["id"],
                ),
            )
            connection.execute("delete from sessions where user_id = ?", (user["id"],))
            connection.execute("delete from password_reset_tokens where user_id = ?", (user["id"],))
    finally:
        connection.close()


def list_users(*, gym: str | None = None) -> list[dict[str, Any]]:
    connection = db.get_connection()
    try:
        params: tuple[Any, ...] = ()
        gym_filter = ""
        if gym:
            gym_row = _find_gym(connection, gym)
            gym_filter = "and gym_memberships.gym_id = ?"
            params = (gym_row["id"],)
        rows = connection.execute(
            f"""
            select users.email, users.display_name, users.role, users.created_at,
                   coalesce(string_agg(gyms.name, ', ' order by gyms.name), '') as gyms
            from users
            left join gym_memberships on gym_memberships.user_id = users.id and gym_memberships.status = 'active'
            left join gyms on gyms.id = gym_memberships.gym_id
            where users.deleted_at is null {gym_filter}
            group by users.id
            order by users.email
            """,
            params,
        ).fetchall()
        return [dict(row) for row in rows]
    finally:
        connection.close()


def list_gyms() -> list[dict[str, Any]]:
    connection = db.get_connection()
    try:
        rows = connection.execute("select id, name, slug from gyms order by name").fetchall()
        return [dict(row) for row in rows]
    finally:
        connection.close()


def _print_credentials(email: str, password: str) -> None:
    print(f"  Email:    {email}")
    print(f"  Password: {password}")
    print("Ask them to change the password under Profile after the first login.")


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="python -m backend.manage", description="BoxOS account administration.")
    commands = parser.add_subparsers(dest="command", required=True)

    create = commands.add_parser("create-user", help="Create an account and print its password.")
    create.add_argument("--email", required=True)
    create.add_argument("--name", required=True, help='Display name, e.g. "Anna Weber".')
    create.add_argument("--role", choices=sorted(ROLE_SETS), default="athlete")
    create.add_argument("--gym", help="Gym name or slug to add the user to.")
    create.add_argument("--nickname")
    create.add_argument("--password", help="Use this password instead of a generated one.")

    reset = commands.add_parser("reset-password", help="Set a new password and print it.")
    reset.add_argument("--email", required=True)
    reset.add_argument("--password", help="Use this password instead of a generated one.")

    deactivate = commands.add_parser("deactivate-user", help="Sign out and lock the account.")
    deactivate.add_argument("--email", required=True)

    users = commands.add_parser("list-users", help="List accounts.")
    users.add_argument("--gym", help="Only users of this gym (name or slug).")

    commands.add_parser("list-gyms", help="List gyms.")

    args = parser.parse_args(argv)
    try:
        db.init_db()
        if args.command == "create-user":
            password = create_user(
                email=args.email,
                name=args.name,
                role=args.role,
                gym=args.gym,
                nickname=args.nickname,
                password=args.password,
            )
            print(f"Created {args.role} account for {args.name}.")
            _print_credentials(args.email.strip().lower(), password)
        elif args.command == "reset-password":
            password = reset_password(email=args.email, password=args.password)
            print("Password reset; all sessions were signed out.")
            _print_credentials(args.email.strip().lower(), password)
        elif args.command == "deactivate-user":
            deactivate_user(email=args.email)
            print(f"{args.email} is signed out and can no longer log in. Undo with reset-password.")
        elif args.command == "list-users":
            rows = list_users(gym=args.gym)
            for row in rows:
                print(f"{row['email']:<36} {row['role']:<8} {row['display_name']:<24} {row['gyms']}")
            print(f"{len(rows)} account(s).")
        elif args.command == "list-gyms":
            for row in list_gyms():
                print(f"{row['slug']:<32} {row['name']}")
    except (CommandError, validation.ApiError) as error:
        message = getattr(error, "detail", None) or str(error)
        print(f"Error: {message}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
