from __future__ import annotations

import base64
import binascii
import json
from http import HTTPStatus
from pathlib import Path
from typing import TYPE_CHECKING, Any

from backend.core import settings

if TYPE_CHECKING:
    pass

class ApiError(Exception):
    def __init__(self, status: HTTPStatus, message: str):
        super().__init__(message)
        self.status = status
        self.message = message

def normalize_account_type_value(value: Any) -> str:
    account_type = str(value or "").strip().lower()
    if account_type == "owner":
        return "admin"
    return account_type


def normalize_role_value(value: Any) -> str:
    role = str(value or "").strip().lower()
    if role == "box":
        return "admin"
    return role


def require_email(value: Any) -> str:
    email = str(value or "").strip().lower()
    if "@" not in email or "." not in email:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Enter a valid email.")
    return email


def require_password(value: Any, *, label: str = "Password") -> str:
    password = str(value or "")
    if len(password) < 8:
        raise ApiError(HTTPStatus.BAD_REQUEST, f"{label} must be at least 8 characters.")
    return password


def require_token(value: Any, *, label: str) -> str:
    token = str(value or "").strip()
    if not token:
        raise ApiError(HTTPStatus.BAD_REQUEST, f"{label} is required.")
    return token


def require_user_id(value: Any) -> int:
    try:
        user_id = int(value)
    except (TypeError, ValueError):
        raise ApiError(HTTPStatus.BAD_REQUEST, "User id is required.")
    if user_id <= 0:
        raise ApiError(HTTPStatus.BAD_REQUEST, "User id is required.")
    return user_id


def require_account_type(value: Any) -> str:
    account_type = normalize_account_type_value(value)
    if account_type not in settings.ALLOWED_ACCOUNT_TYPES:
        raise ApiError(
            HTTPStatus.BAD_REQUEST,
            "Account type must be athlete or admin.",
        )
    return account_type


def require_upload_filename(value: Any) -> str:
    filename = Path(str(value or "upload").strip()).name
    if not filename:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Filename is required.")
    if len(filename) > 120:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Filename is too long.")
    return filename


BUILTIN_CLASS_TYPES = ("WOD", "Open Gym", "Skill", "PT")


def require_base64_bytes(value: Any, *, label: str, max_bytes: int) -> bytes:
    data = str(value or "").strip()
    if not data:
        raise ApiError(HTTPStatus.BAD_REQUEST, f"{label} is required.")
    try:
        decoded = base64.b64decode(data, validate=True)
    except (ValueError, binascii.Error) as error:
        raise ApiError(HTTPStatus.BAD_REQUEST, f"{label} must be valid base64.") from error
    if not decoded:
        raise ApiError(HTTPStatus.BAD_REQUEST, f"{label} is required.")
    if len(decoded) > max_bytes:
        raise ApiError(HTTPStatus.BAD_REQUEST, f"{label} is too large.")
    return decoded


def require_join_request_decision(value: Any) -> str:
    decision = str(value or "").strip().lower()
    if decision not in {"approve", "reject"}:
        raise ApiError(
            HTTPStatus.BAD_REQUEST,
            "Decision must be approve or reject.",
        )
    return decision


def require_role_value(value: Any) -> str:
    role = normalize_role_value(value)
    if role not in settings.ALLOWED_ROLES:
        raise ApiError(
            HTTPStatus.BAD_REQUEST,
            "Role must be athlete, trainer, or admin.",
        )
    return role


def normalize_roles(values: list[Any]) -> list[str]:
    roles = [require_role_value(value) for value in values]
    unique_roles = list(dict.fromkeys(roles))
    if not unique_roles:
        raise ApiError(HTTPStatus.BAD_REQUEST, "At least one role is required.")
    return unique_roles


def encode_roles(roles: list[str]) -> str:
    return json.dumps(roles)


def decode_roles(value: str | None) -> list[str]:
    if not value:
        return ["athlete"]
    try:
        raw_roles = json.loads(value)
    except json.JSONDecodeError:
        return ["athlete"]
    if not isinstance(raw_roles, list):
        return ["athlete"]
    normalized = []
    for role in raw_roles:
        role_value = normalize_role_value(role)
        if role_value in settings.ALLOWED_ROLES and role_value not in normalized:
            normalized.append(role_value)
    return normalized or ["athlete"]
