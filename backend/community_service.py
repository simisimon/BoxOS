from __future__ import annotations

import sqlite3
from typing import Any


def chat_message_payload(
    row: sqlite3.Row, *, current_user_id: int
) -> dict[str, Any]:
    """Shape a chat_messages join row into the JSON returned by the API.

    The sender columns come in pre-joined as ``sender_*`` aliases so the caller
    does not have to do a second per-row lookup. ``user_id`` may be NULL for
    soft-deleted users; the payload exposes a sender placeholder in that case so
    the client can still render the message body in context.
    """
    deleted_at = row["deleted_at"]
    sender_user_id = row["user_id"]
    return {
        "id": row["id"],
        "body": row["body"] if deleted_at is None else "",
        "created_at": row["created_at"],
        "deleted_at": deleted_at,
        "is_own": sender_user_id is not None and sender_user_id == current_user_id,
        "sender": {
            "id": sender_user_id,
            "display_name": row["sender_display_name"] if sender_user_id is not None else "",
            "nickname": row["sender_nickname"] if sender_user_id is not None else "",
        },
    }


CHAT_MESSAGE_SELECT_SQL = """
    select
      chat_messages.id,
      chat_messages.gym_id,
      chat_messages.user_id,
      chat_messages.body,
      chat_messages.created_at,
      chat_messages.deleted_at,
      sender.display_name as sender_display_name,
      sender.nickname as sender_nickname
    from chat_messages
    left join users sender on sender.id = chat_messages.user_id
"""
