"""Request validators used only by the profile routes (see api/routes/profile.py)."""

from __future__ import annotations

from http import HTTPStatus
from typing import TYPE_CHECKING, Any

from backend.core import settings

if TYPE_CHECKING:
    pass

from backend.core.validation import ApiError


def require_display_name(value: Any) -> str:
    display_name = str(value or "").strip()
    if not display_name:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Display name is required.")
    if len(display_name) > 50:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Display name must be 50 characters or fewer.")
    return display_name


def require_nickname(value: Any) -> str:
    nickname = str(value or "").strip()
    if len(nickname) > 30:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Nickname must be 30 characters or fewer.")
    return nickname


def require_notification_preferences(body: dict[str, Any]) -> dict[str, bool]:
    required_keys = (
        "booking_confirmations",
        "waitlist_promotions",
        "payment_issues",
        "wod_posted",
        "pr_achievements",
        "announcement_activity",
    )
    preferences: dict[str, bool] = {}
    for key in required_keys:
        if key not in body:
            raise ApiError(
                HTTPStatus.BAD_REQUEST,
                f"{key.replace('_', ' ').capitalize()} is required.",
            )
        value = body[key]
        if not isinstance(value, bool):
            raise ApiError(
                HTTPStatus.BAD_REQUEST,
                f"{key.replace('_', ' ').capitalize()} must be true or false.",
            )
        preferences[key] = value
    return preferences


def require_avatar_content_type(value: Any) -> str:
    content_type = str(value or "").strip().lower()
    if content_type not in settings.ALLOWED_AVATAR_CONTENT_TYPES:
        raise ApiError(
            HTTPStatus.BAD_REQUEST,
            "Profile photos must be JPEG, PNG, or WEBP.",
        )
    return content_type
