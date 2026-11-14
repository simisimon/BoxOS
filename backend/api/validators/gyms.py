"""Request validators used only by the gyms routes (see api/routes/gyms.py)."""

from __future__ import annotations

from http import HTTPStatus
from typing import TYPE_CHECKING, Any

from backend.core import settings

if TYPE_CHECKING:
    pass

from backend.core.validation import ApiError


def require_gym_name(value: Any) -> str:
    name = str(value or "").strip()
    if not name:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Gym name is required.")
    if len(name) > 80:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Gym name must be 80 characters or fewer.")
    return name


def require_logo_url(value: Any) -> str:
    logo_url = str(value or "").strip()
    if not logo_url:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Gym logo URL is required.")
    if len(logo_url) > 300:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Gym logo URL must be 300 characters or fewer.")
    return logo_url


def require_gym_logo_content_type(value: Any) -> str:
    content_type = str(value or "").strip().lower()
    if content_type not in settings.ALLOWED_GYM_LOGO_CONTENT_TYPES:
        raise ApiError(
            HTTPStatus.BAD_REQUEST,
            "Gym logos must be JPEG, PNG, or WEBP.",
        )
    return content_type


def require_timezone(value: Any) -> str:
    timezone = str(value or "").strip()
    if not timezone:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Timezone is required.")
    if len(timezone) > 100:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Timezone must be 100 characters or fewer.")
    return timezone
