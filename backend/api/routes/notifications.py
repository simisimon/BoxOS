from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from backend.api.deps import require_session
from backend.api.validators import notifications as validators
from backend.core import db, security, validation
from backend.services import announcement_service

router = APIRouter()


class DeviceRegisterRequest(BaseModel):
    device_token: str
    platform: str


class DeviceTokenRequest(BaseModel):
    device_token: str


@router.get("/notifications")
def list_notifications(
    session: dict[str, Any] = Depends(require_session),
) -> dict[str, Any]:
    connection = db.get_connection()
    try:
        rows = connection.execute(
            "select id, user_id, gym_id, type, title, body, entity_type, entity_id, read_at, created_at from notifications where user_id = ? order by created_at desc, id desc limit 50",
            (session["user_id"],),
        ).fetchall()
        unread_count = connection.execute(
            "select count(*) as count from notifications where user_id = ? and read_at is null",
            (session["user_id"],),
        ).fetchone()["count"]
        return {"unread_count": unread_count, "notifications": [announcement_service.notification_payload(row) for row in rows]}
    finally:
        connection.close()


@router.patch("/notifications/read-all")
def mark_notifications_read(
    session: dict[str, Any] = Depends(require_session),
) -> dict[str, Any]:
    connection = db.get_connection()
    try:
        with connection:
            connection.execute(
                "update notifications set read_at = ? where user_id = ? and read_at is null",
                (security.isoformat(security.now_utc()), session["user_id"]),
            )
        rows = connection.execute(
            "select id, user_id, gym_id, type, title, body, entity_type, entity_id, read_at, created_at from notifications where user_id = ? order by created_at desc, id desc limit 50",
            (session["user_id"],),
        ).fetchall()
        return {"unread_count": 0, "notifications": [announcement_service.notification_payload(row) for row in rows]}
    finally:
        connection.close()


@router.post("/devices/register")
def register_device(body: DeviceRegisterRequest, session: dict[str, Any] = Depends(require_session)) -> dict[str, Any]:
    device_token = validation.require_token(body.device_token, label="Device token")
    platform = validators.require_platform(body.platform)
    connection = db.get_connection()
    try:
        now = security.isoformat(security.now_utc())
        with connection:
            connection.execute(
                """
                insert into device_registrations (
                    user_id, device_token, platform, created_at, updated_at
                )
                values (?, ?, ?, ?, ?)
                on conflict(device_token) do update set
                    user_id = excluded.user_id,
                    platform = excluded.platform,
                    updated_at = excluded.updated_at
                """,
                (session["user_id"], device_token, platform, now, now),
            )
        return {"message": "Device registered."}
    finally:
        connection.close()


@router.delete("/devices/current")
def unregister_device(body: DeviceTokenRequest, session: dict[str, Any] = Depends(require_session)) -> dict[str, Any]:
    device_token = validation.require_token(body.device_token, label="Device token")
    connection = db.get_connection()
    try:
        with connection:
            connection.execute(
                "delete from device_registrations where user_id = ? and device_token = ?",
                (session["user_id"], device_token),
            )
        return {"message": "Device unregistered."}
    finally:
        connection.close()
