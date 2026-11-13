from __future__ import annotations

import os
from pathlib import Path

try:
    from dateutil import tz as dateutil_tz
except ImportError:  # pragma: no cover - optional runtime fallback
    dateutil_tz = None

try:
    import pytz
except ImportError:  # pragma: no cover - optional runtime fallback
    pytz = None

BACKEND_ROOT = Path(__file__).resolve().parent
# "production" turns on the startup checks in production_problems().
ENV = os.getenv("BOXOS_ENV", "dev").strip().lower()
# PostgreSQL connection string used by the backend. Format:
# postgresql://user:password@host:port/database
DATABASE_URL = os.getenv("BOXOS_DATABASE_URL", "postgresql://boxos:boxos@localhost:5432/boxos")
UPLOADS_ROOT = Path(os.getenv("BOXOS_UPLOADS_ROOT", str(BACKEND_ROOT / "uploads")))
ANNOUNCEMENT_UPLOADS_DIR = Path(
    os.getenv("BOXOS_ANNOUNCEMENT_UPLOADS_DIR", str(UPLOADS_ROOT / "announcements"))
)
GYM_LOGOS_DIR = Path(
    os.getenv("BOXOS_GYM_LOGOS_DIR", str(UPLOADS_ROOT / "gym_logos"))
)
AVATARS_DIR = Path(
    os.getenv("BOXOS_AVATARS_DIR", str(UPLOADS_ROOT / "avatars"))
)
EXERCISES_SEED_PATH = BACKEND_ROOT / "data" / "exercises.json"
BENCHMARKS_SEED_PATH = BACKEND_ROOT / "data" / "benchmark_workouts.json"
HOST = os.getenv("BOXOS_HOST", "127.0.0.1")
PORT = int(os.getenv("BOXOS_PORT", "8080"))
CORS_ALLOW_ORIGINS = [
    origin.strip()
    for origin in os.getenv("BOXOS_CORS_ALLOW_ORIGINS", "http://localhost:3000,http://localhost:3001").split(",")
    if origin.strip()
]
LOG_DELIVERY_TOKENS = os.getenv("BOXOS_LOG_DELIVERY_TOKENS", "1") == "1"
RATE_LIMIT_ENABLED = os.getenv("BOXOS_RATE_LIMIT_ENABLED", "1") == "1"
# Invite-only production: with sign-up off the /auth/signup* endpoints answer
# 403 and accounts are created with `python -m backend.manage create-user`.
SIGNUP_ENABLED = os.getenv("BOXOS_SIGNUP_ENABLED", "1") == "1"
# The demo/trainer/admin accounts below use public passwords. Keep them for
# dev and tests; set BOXOS_SEED_DEMO_USERS=0 in production.
SEED_DEMO_USERS = os.getenv("BOXOS_SEED_DEMO_USERS", "1") == "1"

# Stripe Connect (payments). Empty secret key = payments are switched off and
# the app hides them. Use test-mode keys (sk_test_...) for development.
STRIPE_SECRET_KEY = os.getenv("BOXOS_STRIPE_SECRET_KEY", "")
STRIPE_WEBHOOK_SECRET = os.getenv("BOXOS_STRIPE_WEBHOOK_SECRET", "")
STRIPE_ACCOUNT_COUNTRY = os.getenv("BOXOS_STRIPE_ACCOUNT_COUNTRY", "DE")
# Where Stripe sends owners back after onboarding (the Flutter web app).
APP_BASE_URL = os.getenv("BOXOS_APP_BASE_URL", "http://localhost:3001").rstrip("/")
DELETE_RETENTION_DAYS = 30
MAX_RECURRENCE_OCCURRENCES = 365
MAX_ANNOUNCEMENT_IMAGE_BYTES = 5 * 1024 * 1024
ALLOWED_ANNOUNCEMENT_IMAGE_CONTENT_TYPES = {
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
}
MAX_GYM_LOGO_BYTES = 2 * 1024 * 1024  # 2MB for gym logos
ALLOWED_GYM_LOGO_CONTENT_TYPES = {
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
}
# Avatars are small by definition; cap stricter than announcement images so a
# stray full-resolution camera dump can't sit in the uploads directory.
MAX_AVATAR_BYTES = 2 * 1024 * 1024  # 2MB
ALLOWED_AVATAR_CONTENT_TYPES = {
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
}
ALLOWED_ROLES = {"athlete", "trainer", "admin"}
ALLOWED_ACCOUNT_TYPES = {"athlete", "admin"}
RECURRENCE_OCCURRENCE_LIMITS = {
    "daily": 365,
    "weekly": 53,
    "monthly": 14,
}
DEMO_EMAIL = "demo@boxos.app"
DEMO_PASSWORD = "BoxOS123!"
TRAINER_EMAIL = "trainer@boxos.app"
TRAINER_PASSWORD = "BoxOS123!"
ADMIN_EMAIL = "admin@boxos.app"
ADMIN_PASSWORD = "BoxOS123!"
ACCESS_TOKEN_TTL_MINUTES = 15
REFRESH_TOKEN_TTL_DAYS = 30


def production_problems() -> list[str]:
    """Settings that must not reach production. Empty outside BOXOS_ENV=production."""
    if ENV != "production":
        return []
    problems = []
    if "boxos:boxos@" in DATABASE_URL or ":change-me@" in DATABASE_URL:
        problems.append("BOXOS_DATABASE_URL still uses a placeholder or dev password.")
    if SEED_DEMO_USERS:
        problems.append("BOXOS_SEED_DEMO_USERS is on; it creates accounts with public passwords.")
    if LOG_DELIVERY_TOKENS:
        problems.append("BOXOS_LOG_DELIVERY_TOKENS is on; reset and verification tokens would be logged.")
    if any("localhost" in origin for origin in CORS_ALLOW_ORIGINS):
        problems.append("BOXOS_CORS_ALLOW_ORIGINS still allows localhost.")
    # shortcut: payments are not launched yet; drop this check when they are.
    if STRIPE_SECRET_KEY:
        problems.append("BOXOS_STRIPE_SECRET_KEY is set, but payments are switched off in production.")
    return problems
