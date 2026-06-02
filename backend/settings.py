from __future__ import annotations

from pathlib import Path

try:
    from dateutil import tz as dateutil_tz
except ImportError:  # pragma: no cover - optional runtime fallback
    dateutil_tz = None

try:
    import pytz
except ImportError:  # pragma: no cover - optional runtime fallback
    pytz = None

DB_PATH = Path(__file__).with_name("boxos_dev.db")
UPLOADS_ROOT = Path(__file__).with_name("uploads")
ANNOUNCEMENT_UPLOADS_DIR = UPLOADS_ROOT / "announcements"
EXERCISES_SEED_PATH = Path(__file__).with_name("data") / "exercises.json"
BENCHMARKS_SEED_PATH = Path(__file__).with_name("data") / "benchmark_workouts.json"
HOST = "127.0.0.1"
PORT = 8080
DELETE_RETENTION_DAYS = 30
MAX_RECURRENCE_OCCURRENCES = 365
MAX_ANNOUNCEMENT_IMAGE_BYTES = 5 * 1024 * 1024
ALLOWED_ANNOUNCEMENT_IMAGE_CONTENT_TYPES = {
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
