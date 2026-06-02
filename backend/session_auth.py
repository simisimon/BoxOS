from __future__ import annotations

import sqlite3
from datetime import timedelta

from backend import settings
from backend.security import create_token, hash_token, isoformat, now_utc

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
            isoformat(now + timedelta(minutes=settings.ACCESS_TOKEN_TTL_MINUTES)),
            isoformat(now + timedelta(days=settings.REFRESH_TOKEN_TTL_DAYS)),
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


