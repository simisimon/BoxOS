"""Request validators used only by the announcements routes (see api/routes/announcements.py)."""

from __future__ import annotations

from http import HTTPStatus
from typing import TYPE_CHECKING, Any

from backend.core import settings

if TYPE_CHECKING:
    pass

from backend.core.validation import ApiError


def require_announcement_image_content_type(value: Any) -> str:
    content_type = str(value or "").strip().lower()
    if content_type not in settings.ALLOWED_ANNOUNCEMENT_IMAGE_CONTENT_TYPES:
        raise ApiError(
            HTTPStatus.BAD_REQUEST,
            "Announcement images must be JPEG, PNG, or WEBP.",
        )
    return content_type


def require_announcement_title(value: Any) -> str:
    title = str(value or "").strip()
    if not title:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Announcement title is required.")
    if len(title) > 120:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Announcement title must be 120 characters or fewer.")
    return title


def require_announcement_description(value: Any) -> str:
    description = str(value or "").strip()
    if not description:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Announcement description is required.")
    if len(description) > 5000:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Announcement description must be 5000 characters or fewer.")
    return description


def require_announcement_comment_body(value: Any) -> str:
    body = str(value or "").strip()
    if not body:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Comment is required.")
    if len(body) > 1500:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Comment must be 1500 characters or fewer.")
    return body


def require_optional_image_url(value: Any) -> str | None:
    if value is None:
        return None
    image_url = str(value).strip()
    if not image_url:
        return None
    if len(image_url) > 500:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Announcement image URL must be 500 characters or fewer.")
    return image_url
