from __future__ import annotations

from datetime import timedelta
from http import HTTPStatus
from typing import Any

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from backend.api.deps import require_active_gym_member_session
from backend.api.validators import community as validators
from backend.core import audit, db, security
from backend.services import community_service

router = APIRouter()


class ChatMessageCreateRequest(BaseModel):
    body: str


@router.get("/community/dashboard")
def get_community_dashboard(
    session: dict[str, Any] = Depends(require_active_gym_member_session),
) -> dict[str, Any]:
    """Return the shared community snapshot for the active gym.

    This endpoint is intentionally available to every active member role
    because the community view is a shared owner/trainer/member space.
    """
    now = security.now_utc()
    seven_days_ago = security.isoformat(now - timedelta(days=7))
    connection = db.get_connection()
    try:
        stats_row = connection.execute(
            """
            select
              count(*) filter (where gym_memberships.status = 'active') as active_members,
              count(*) filter (
                where gym_memberships.status = 'active'
                  and gym_memberships.active_role = 'trainer'
              ) as active_trainers,
              count(*) filter (
                where gym_memberships.status = 'active'
                  and gym_memberships.active_role = 'admin'
              ) as owners
            from gym_memberships
            join users on users.id = gym_memberships.user_id
            where gym_memberships.gym_id = ?
              and users.deleted_at is null
            """,
            (session["active_gym_id"],),
        ).fetchone()
        message_count_row = connection.execute(
            """
            select count(*) as count
            from chat_messages
            where gym_id = ?
              and deleted_at is null
              and created_at >= ?
            """,
            (session["active_gym_id"], seven_days_ago),
        ).fetchone()
        return {
            "stats": {
                "active_members": int(stats_row["active_members"] if stats_row else 0),
                "active_trainers": int(stats_row["active_trainers"] if stats_row else 0),
                "owners": int(stats_row["owners"] if stats_row else 0),
                "messages_last_7_days": int(
                    message_count_row["count"] if message_count_row else 0
                ),
            },
        }
    finally:
        connection.close()


@router.get("/community/messages")
def list_community_messages(
    since_id: int | None = None,
    session: dict[str, Any] = Depends(require_active_gym_member_session),
) -> dict[str, Any]:
    """List chat messages for the user's active gym.

    By default returns the most recent 50 messages (newest last, so the client
    can render them in chronological order). With ``since_id`` returns up to
    200 messages with ``id > since_id`` so the polling loop can pull only what
    changed. Soft-deleted messages are still returned (body blanked) so a
    poller sees deletions and can update its cache.
    """
    connection = db.get_connection()
    try:
        if since_id is not None and since_id > 0:
            rows = connection.execute(
                f"""
                {community_service.CHAT_MESSAGE_SELECT_SQL}
                where chat_messages.gym_id = ? and chat_messages.id > ?
                order by chat_messages.id asc
                limit 200
                """,
                (session["active_gym_id"], since_id),
            ).fetchall()
        else:
            rows = connection.execute(
                f"""
                {community_service.CHAT_MESSAGE_SELECT_SQL}
                where chat_messages.gym_id = ?
                order by chat_messages.id desc
                limit 50
                """,
                (session["active_gym_id"],),
            ).fetchall()
            rows = list(reversed(rows))
        return {
            "messages": [
                community_service.chat_message_payload(row, current_user_id=session["user_id"])
                for row in rows
            ]
        }
    finally:
        connection.close()


@router.post("/community/messages", status_code=HTTPStatus.CREATED.value)
def create_community_message(
    body: ChatMessageCreateRequest,
    session: dict[str, Any] = Depends(require_active_gym_member_session),
) -> dict[str, Any]:
    message_body = validators.require_chat_message_body(body.body)
    timestamp = security.isoformat(security.now_utc())
    connection = db.get_connection()
    try:
        with connection:
            cursor = connection.execute(
                """
                insert into chat_messages (gym_id, user_id, body, created_at, updated_at)
                values (?, ?, ?, ?, ?)
                returning id
                """,
                (
                    session["active_gym_id"],
                    session["user_id"],
                    message_body,
                    timestamp,
                    timestamp,
                ),
            )
            message_id = int(cursor.fetchone()["id"])
            row = connection.execute(
                f"{community_service.CHAT_MESSAGE_SELECT_SQL} where chat_messages.id = ?",
                (message_id,),
            ).fetchone()
            payload = community_service.chat_message_payload(
                row, current_user_id=session["user_id"]
            )
        return {"message": payload}
    finally:
        connection.close()


@router.delete("/community/messages/{message_id}")
def delete_community_message(
    message_id: int,
    session: dict[str, Any] = Depends(require_active_gym_member_session),
) -> dict[str, Any]:
    """Soft-delete a message.

    Members can always delete their own messages. Trainers and admins can
    additionally moderate other members' messages — the soft-delete keeps the
    row so the client poller can transition the bubble to a 'message deleted'
    state without a hard refresh.
    """
    connection = db.get_connection()
    try:
        row = connection.execute(
            "select id, gym_id, user_id, deleted_at from chat_messages where id = ?",
            (message_id,),
        ).fetchone()
        if row is None or row["gym_id"] != session["active_gym_id"]:
            raise HTTPException(
                status_code=HTTPStatus.NOT_FOUND.value, detail="Message not found."
            )
        if row["deleted_at"] is not None:
            return {"message": {"id": int(row["id"]), "deleted": True}}
        is_owner_message = row["user_id"] == session["user_id"]
        is_moderator = session["role"] in {"admin", "trainer"}
        if not is_owner_message and not is_moderator:
            raise HTTPException(
                status_code=HTTPStatus.FORBIDDEN.value,
                detail="You can only delete your own messages.",
            )
        timestamp = security.isoformat(security.now_utc())
        with connection:
            connection.execute(
                """
                update chat_messages
                set deleted_at = ?, updated_at = ?
                where id = ?
                """,
                (timestamp, timestamp, message_id),
            )
            if not is_owner_message:
                audit.write_audit_log(
                    connection,
                    gym_id=session["active_gym_id"],
                    actor_user_id=session["user_id"],
                    action="chat_message_moderated",
                    entity_type="chat_message",
                    entity_id=message_id,
                    details={"target_user_id": row["user_id"]},
                )
        return {"message": {"id": message_id, "deleted": True}}
    finally:
        connection.close()
