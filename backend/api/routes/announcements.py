from __future__ import annotations

import secrets
from http import HTTPStatus
from typing import Any

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from backend.api.common import EntityIdRequest
from backend.api.deps import (
    require_active_gym_member_session,
    require_schedule_manager_session,
)
from backend.api.validators import announcements as validators
from backend.core import audit, db, security, settings, validation
from backend.services import announcement_service

router = APIRouter()


class AnnouncementRequest(BaseModel):
    title: str
    description: str
    image_url: str | None = None


class AnnouncementUpdateRequest(AnnouncementRequest):
    id: int


class AnnouncementIdRequest(BaseModel):
    announcement_id: int


class AnnouncementCommentRequest(BaseModel):
    announcement_id: int
    body: str


class AnnouncementCommentUpdateRequest(BaseModel):
    id: int
    body: str


class AnnouncementImageUploadRequest(BaseModel):
    filename: str
    content_type: str
    data_base64: str


@router.get("/announcements")
def list_announcements(
    session: dict[str, Any] = Depends(require_active_gym_member_session),
) -> dict[str, list[dict[str, Any]]]:
    connection = db.get_connection()
    try:
        rows = connection.execute(
            """
            select announcements.id, announcements.gym_id, announcements.title, announcements.description,
                   announcements.image_url, announcements.created_by_user_id, announcements.created_at, announcements.updated_at,
                   users.display_name as author_display_name, users.nickname as author_nickname, users.email as author_email
            from announcements
            join users on users.id = announcements.created_by_user_id
            where announcements.gym_id = ?
            order by announcements.created_at desc, announcements.id desc
            """,
            (session["active_gym_id"],),
        ).fetchall()
        return {
            "announcements": [
                announcement_service.announcement_payload(
                    connection,
                    row,
                    current_user_id=session["user_id"],
                    session_role=str(session["role"]),
                )
                for row in rows
            ]
        }
    finally:
        connection.close()


@router.post("/announcements", status_code=HTTPStatus.CREATED.value)
def create_announcement(
    body: AnnouncementRequest,
    session: dict[str, Any] = Depends(require_schedule_manager_session),
) -> dict[str, Any]:
    title = validators.require_announcement_title(body.title)
    description = validators.require_announcement_description(body.description)
    image_url = validators.require_optional_image_url(body.image_url)
    connection = db.get_connection()
    try:
        timestamp = security.isoformat(security.now_utc())
        with connection:
            cursor = connection.execute(
                "insert into announcements (gym_id, title, description, image_url, created_by_user_id, created_at, updated_at) values (?, ?, ?, ?, ?, ?, ?) returning id",
                (session["active_gym_id"], title, description, image_url, session["user_id"], timestamp, timestamp),
            )
            new_announcement_id = int(cursor.fetchone()["id"])
            row = announcement_service.get_announcement_row(connection, announcement_id=new_announcement_id, gym_id=session["active_gym_id"])
            if row is None:
                raise HTTPException(status_code=HTTPStatus.INTERNAL_SERVER_ERROR.value, detail="Announcement creation failed.")
            audit.write_audit_log(
                connection,
                gym_id=session["active_gym_id"],
                actor_user_id=session["user_id"],
                action="announcement_created",
                entity_type="announcement",
                entity_id=new_announcement_id,
                details={"title": title, "has_image": bool(image_url)},
            )
        return {"announcement": announcement_service.announcement_payload(connection, row, current_user_id=session["user_id"], session_role=str(session["role"]))}
    finally:
        connection.close()


@router.post("/announcements/image", status_code=HTTPStatus.CREATED.value)
def upload_announcement_image(
    body: AnnouncementImageUploadRequest,
    _: dict[str, Any] = Depends(require_schedule_manager_session),
) -> dict[str, str]:
    filename = validation.require_upload_filename(body.filename)
    content_type = validators.require_announcement_image_content_type(body.content_type)
    raw_bytes = validation.require_base64_bytes(body.data_base64, label="Image data", max_bytes=settings.MAX_ANNOUNCEMENT_IMAGE_BYTES)
    extension = settings.ALLOWED_ANNOUNCEMENT_IMAGE_CONTENT_TYPES[content_type]
    stored_name = f"announcement_{secrets.token_urlsafe(12)}{extension}"
    file_path = settings.ANNOUNCEMENT_UPLOADS_DIR / stored_name
    file_path.write_bytes(raw_bytes)
    return {"filename": filename, "image_url": f"/uploads/announcements/{stored_name}"}


@router.patch("/announcements")
def update_announcement(
    body: AnnouncementUpdateRequest,
    session: dict[str, Any] = Depends(require_schedule_manager_session),
) -> dict[str, Any]:
    announcement_id = validation.require_user_id(body.id)
    title = validators.require_announcement_title(body.title)
    description = validators.require_announcement_description(body.description)
    image_url = validators.require_optional_image_url(body.image_url)
    connection = db.get_connection()
    try:
        existing = connection.execute(
            "select id, created_by_user_id from announcements where id = ? and gym_id = ?",
            (announcement_id, session["active_gym_id"]),
        ).fetchone()
        if existing is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Announcement not found.")
        announcement_service.ensure_announcement_manage_permission(existing, session)
        with connection:
            connection.execute(
                "update announcements set title = ?, description = ?, image_url = ?, updated_at = ? where id = ? and gym_id = ?",
                (title, description, image_url, security.isoformat(security.now_utc()), announcement_id, session["active_gym_id"]),
            )
            row = announcement_service.get_announcement_row(connection, announcement_id=announcement_id, gym_id=session["active_gym_id"])
            if row is None:
                raise HTTPException(status_code=HTTPStatus.INTERNAL_SERVER_ERROR.value, detail="Announcement update failed.")
            audit.write_audit_log(connection, gym_id=session["active_gym_id"], actor_user_id=session["user_id"], action="announcement_updated", entity_type="announcement", entity_id=announcement_id, details={"title": title, "has_image": bool(image_url)})
        return {"announcement": announcement_service.announcement_payload(connection, row, current_user_id=session["user_id"], session_role=str(session["role"]))}
    finally:
        connection.close()


@router.delete("/announcements")
def delete_announcement(
    body: EntityIdRequest,
    session: dict[str, Any] = Depends(require_schedule_manager_session),
) -> dict[str, bool]:
    announcement_id = body.id
    connection = db.get_connection()
    try:
        existing = connection.execute(
            "select id, title, created_by_user_id from announcements where id = ? and gym_id = ?",
            (announcement_id, session["active_gym_id"]),
        ).fetchone()
        if existing is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Announcement not found.")
        announcement_service.ensure_announcement_manage_permission(existing, session)
        with connection:
            connection.execute("delete from announcements where id = ? and gym_id = ?", (announcement_id, session["active_gym_id"]))
            audit.write_audit_log(connection, gym_id=session["active_gym_id"], actor_user_id=session["user_id"], action="announcement_deleted", entity_type="announcement", entity_id=announcement_id, details={"title": existing["title"]})
        return {"deleted": True}
    finally:
        connection.close()


@router.post("/announcements/likes")
def like_announcement(
    body: AnnouncementIdRequest,
    session: dict[str, Any] = Depends(require_active_gym_member_session),
) -> dict[str, Any]:
    announcement_id = body.announcement_id
    connection = db.get_connection()
    try:
        announcement = announcement_service.get_announcement_row(connection, announcement_id=announcement_id, gym_id=session["active_gym_id"])
        if announcement is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Announcement not found.")
        with connection:
            cursor = connection.execute(
                "insert into announcement_likes (announcement_id, user_id, created_at) values (?, ?, ?) on conflict do nothing",
                (announcement_id, session["user_id"], security.isoformat(security.now_utc())),
            )
            if cursor.rowcount:
                announcement_service.create_announcement_like_notification(connection, recipient_user_id=int(announcement["created_by_user_id"]), actor_user_id=int(session["user_id"]), gym_id=int(session["active_gym_id"]), announcement_id=announcement_id, announcement_title=str(announcement["title"]))
        refreshed = announcement_service.get_announcement_row(connection, announcement_id=announcement_id, gym_id=session["active_gym_id"])
        return {"announcement": announcement_service.announcement_payload(connection, refreshed, current_user_id=session["user_id"], session_role=str(session["role"]))}
    finally:
        connection.close()


@router.delete("/announcements/likes")
def unlike_announcement(
    body: AnnouncementIdRequest,
    session: dict[str, Any] = Depends(require_active_gym_member_session),
) -> dict[str, Any]:
    announcement_id = body.announcement_id
    connection = db.get_connection()
    try:
        announcement = announcement_service.get_announcement_row(connection, announcement_id=announcement_id, gym_id=session["active_gym_id"])
        if announcement is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Announcement not found.")
        with connection:
            connection.execute("delete from announcement_likes where announcement_id = ? and user_id = ?", (announcement_id, session["user_id"]))
        refreshed = announcement_service.get_announcement_row(connection, announcement_id=announcement_id, gym_id=session["active_gym_id"])
        return {"announcement": announcement_service.announcement_payload(connection, refreshed, current_user_id=session["user_id"], session_role=str(session["role"]))}
    finally:
        connection.close()


@router.post("/announcements/comments", status_code=HTTPStatus.CREATED.value)
def create_announcement_comment(
    body: AnnouncementCommentRequest,
    session: dict[str, Any] = Depends(require_active_gym_member_session),
) -> dict[str, Any]:
    announcement_id = validation.require_user_id(body.announcement_id)
    comment_body = validators.require_announcement_comment_body(body.body)
    connection = db.get_connection()
    try:
        announcement = announcement_service.get_announcement_row(connection, announcement_id=announcement_id, gym_id=session["active_gym_id"])
        if announcement is None:
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Announcement not found.")
        timestamp = security.isoformat(security.now_utc())
        with connection:
            cursor = connection.execute(
                "insert into announcement_comments (announcement_id, gym_id, user_id, body, created_at, updated_at) values (?, ?, ?, ?, ?, ?) returning id",
                (announcement_id, session["active_gym_id"], session["user_id"], comment_body, timestamp, timestamp),
            )
            new_comment_id = int(cursor.fetchone()["id"])
            comment = announcement_service.get_announcement_comment_row(connection, new_comment_id)
            if comment is None:
                raise HTTPException(status_code=HTTPStatus.INTERNAL_SERVER_ERROR.value, detail="Comment creation failed.")
            announcement_service.create_announcement_comment_notification(connection, recipient_user_id=int(announcement["created_by_user_id"]), actor_user_id=int(session["user_id"]), gym_id=int(session["active_gym_id"]), announcement_id=announcement_id, announcement_title=str(announcement["title"]), comment_body=comment_body)
            audit.write_audit_log(connection, gym_id=session["active_gym_id"], actor_user_id=session["user_id"], action="announcement_comment_created", entity_type="announcement_comment", entity_id=new_comment_id, details={"announcement_id": announcement_id})
        return {"comment": announcement_service.announcement_comment_payload(comment, current_user_id=session["user_id"], session_role=str(session["role"]))}
    finally:
        connection.close()


@router.patch("/announcements/comments")
def update_announcement_comment(
    body: AnnouncementCommentUpdateRequest,
    session: dict[str, Any] = Depends(require_active_gym_member_session),
) -> dict[str, Any]:
    comment_id = validation.require_user_id(body.id)
    comment_body = validators.require_announcement_comment_body(body.body)
    connection = db.get_connection()
    try:
        existing = announcement_service.get_announcement_comment_row(connection, comment_id)
        if existing is None or int(existing["gym_id"]) != int(session["active_gym_id"]):
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Comment not found.")
        announcement_service.ensure_announcement_comment_manage_permission(existing, session)
        with connection:
            connection.execute("update announcement_comments set body = ?, updated_at = ? where id = ?", (comment_body, security.isoformat(security.now_utc()), comment_id))
            comment = announcement_service.get_announcement_comment_row(connection, comment_id)
            if comment is None:
                raise HTTPException(status_code=HTTPStatus.INTERNAL_SERVER_ERROR.value, detail="Comment update failed.")
            audit.write_audit_log(connection, gym_id=session["active_gym_id"], actor_user_id=session["user_id"], action="announcement_comment_updated", entity_type="announcement_comment", entity_id=comment_id, details={"announcement_id": existing["announcement_id"]})
        return {"comment": announcement_service.announcement_comment_payload(comment, current_user_id=session["user_id"], session_role=str(session["role"]))}
    finally:
        connection.close()


@router.delete("/announcements/comments")
def delete_announcement_comment(
    body: EntityIdRequest,
    session: dict[str, Any] = Depends(require_active_gym_member_session),
) -> dict[str, bool]:
    comment_id = body.id
    connection = db.get_connection()
    try:
        existing = announcement_service.get_announcement_comment_row(connection, comment_id)
        if existing is None or int(existing["gym_id"]) != int(session["active_gym_id"]):
            raise HTTPException(status_code=HTTPStatus.NOT_FOUND.value, detail="Comment not found.")
        announcement_service.ensure_announcement_comment_manage_permission(existing, session)
        with connection:
            connection.execute("delete from announcement_comments where id = ?", (comment_id,))
            audit.write_audit_log(connection, gym_id=session["active_gym_id"], actor_user_id=session["user_id"], action="announcement_comment_deleted", entity_type="announcement_comment", entity_id=comment_id, details={"announcement_id": existing["announcement_id"]})
        return {"deleted": True}
    finally:
        connection.close()
