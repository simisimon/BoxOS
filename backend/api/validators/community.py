"""Request validators used only by the community routes (see api/routes/community.py)."""

from __future__ import annotations

from http import HTTPStatus
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    pass

from backend.core.validation import ApiError


def require_chat_message_body(value: Any) -> str:
    body = str(value or "").strip()
    if not body:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Message body is required.")
    if len(body) > 2000:
        raise ApiError(
            HTTPStatus.BAD_REQUEST,
            "Message body must be 2000 characters or fewer.",
        )
    return body
