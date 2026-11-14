"""Request validators used only by the members routes (see api/routes/members.py)."""

from __future__ import annotations

from http import HTTPStatus
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    pass

from backend.core.validation import ApiError, normalize_roles, require_role_value

# Membership status vocabulary. Kept as a small closed set so the UI and
# downstream queries can safely switch over the value. "removed" is used as a
# soft delete — the row stays for audit, just hidden from the roster.
MEMBERSHIP_STATUSES = {"active", "paused", "removed"}
MAX_MEMBERSHIP_ADMIN_NOTE_LENGTH = 500


def require_membership_status(value: Any) -> str:
    text = str(value or "").strip().lower()
    if text not in MEMBERSHIP_STATUSES:
        raise ApiError(
            HTTPStatus.BAD_REQUEST,
            "Status must be 'active', 'paused', or 'removed'.",
        )
    return text


def require_admin_note(value: Any) -> str:
    """Coerces and length-checks the admin-only note attached to a membership.

    Notes are free-text and may legitimately be empty (admin clears the field),
    so this returns "" rather than raising for an empty input.
    """
    note = str(value or "").strip()
    if len(note) > MAX_MEMBERSHIP_ADMIN_NOTE_LENGTH:
        raise ApiError(
            HTTPStatus.BAD_REQUEST,
            f"Admin note must be {MAX_MEMBERSHIP_ADMIN_NOTE_LENGTH} characters or fewer.",
        )
    return note


def require_role_list(body: dict[str, Any]) -> list[str]:
    if "roles" in body:
        raw_roles = body["roles"]
        if not isinstance(raw_roles, list):
            raise ApiError(HTTPStatus.BAD_REQUEST, "Roles must be a list.")
        return normalize_roles(raw_roles)
    return [require_role_value(body.get("role"))]
