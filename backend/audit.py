from __future__ import annotations

import json
import sqlite3
from typing import Any

from backend.security import isoformat, now_utc

def audit_log_payload(row: sqlite3.Row) -> dict[str, Any]:
    return {
        "id": row["id"],
        "action": row["action"],
        "entity_type": row["entity_type"],
        "entity_id": row["entity_id"],
        "details": json.loads(row["details_json"]),
        "created_at": row["created_at"],
        "actor": {
            "email": row["actor_email"],
            "display_name": row["actor_display_name"],
            "nickname": row["actor_nickname"],
        },
        "target": None if row["target_email"] is None else {
            "email": row["target_email"],
            "display_name": row["target_display_name"],
            "nickname": row["target_nickname"],
        },
    }


def write_audit_log(
    connection: sqlite3.Connection,
    *,
    gym_id: int | None,
    actor_user_id: int,
    action: str,
    entity_type: str,
    entity_id: int | None = None,
    target_user_id: int | None = None,
    details: dict[str, Any] | None = None,
) -> None:
    connection.execute(
        """
        insert into audit_logs (
          gym_id, actor_user_id, target_user_id, action, entity_type,
          entity_id, details_json, created_at
        )
        values (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            gym_id,
            actor_user_id,
            target_user_id,
            action,
            entity_type,
            entity_id,
            json.dumps(details or {}, sort_keys=True),
            isoformat(now_utc()),
        ),
    )


