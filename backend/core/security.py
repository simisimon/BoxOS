from __future__ import annotations

import hashlib
import hmac
import secrets
from datetime import UTC, datetime

def now_utc() -> datetime:
    return datetime.now(UTC)


def isoformat(value: datetime) -> str:
    return value.isoformat()


def parse_iso(value: str) -> datetime:
    return datetime.fromisoformat(value)


def pbkdf2_hash(password: str, salt: str) -> str:
    digest = hashlib.pbkdf2_hmac(
        "sha256",
        password.encode("utf-8"),
        salt.encode("utf-8"),
        120_000,
    )
    return digest.hex()


def hash_password(password: str) -> str:
    salt = secrets.token_hex(16)
    digest = pbkdf2_hash(password, salt)
    return f"{salt}${digest}"


def verify_password(password: str, encoded: str) -> bool:
    salt, stored_digest = encoded.split("$", 1)
    computed = pbkdf2_hash(password, salt)
    return hmac.compare_digest(computed, stored_digest)


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def create_token(prefix: str) -> str:
    return f"{prefix}_{secrets.token_urlsafe(24)}"
