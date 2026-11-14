"""Request validators used only by the notifications routes (see api/routes/notifications.py)."""

from __future__ import annotations

from http import HTTPStatus
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    pass

from backend.core.validation import ApiError


def require_platform(value: Any) -> str:
    platform = str(value or "").strip()
    if not platform:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Platform is required.")
    if len(platform) > 30:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Platform must be 30 characters or fewer.")
    return platform
