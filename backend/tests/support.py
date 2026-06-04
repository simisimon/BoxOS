from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path

from backend import db, security, session_auth, settings, validation

FASTAPI_AVAILABLE = importlib.util.find_spec("fastapi") is not None
TESTCLIENT_AVAILABLE = False
if FASTAPI_AVAILABLE:
    TESTCLIENT_AVAILABLE = importlib.util.find_spec("fastapi.testclient") is not None

if FASTAPI_AVAILABLE and TESTCLIENT_AVAILABLE:
    from fastapi.testclient import TestClient
    from backend.fastapi_app import app
else:  # pragma: no cover
    TestClient = None
    app = None


@unittest.skipUnless(FASTAPI_AVAILABLE and TESTCLIENT_AVAILABLE, "fastapi is not installed")
class FastApiTestCase(unittest.TestCase):
    maxDiff = None

    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        settings.DB_PATH = Path(self.temp_dir.name) / "test.db"
        settings.UPLOADS_ROOT = Path(self.temp_dir.name) / "uploads"
        settings.ANNOUNCEMENT_UPLOADS_DIR = settings.UPLOADS_ROOT / "announcements"
        self.client = TestClient(app)
        db.init_db()

    def tearDown(self) -> None:
        self.client.close()
        self.temp_dir.cleanup()

    def login(self, email: str, password: str) -> dict[str, str]:
        response = self.client.post("/auth/login", json={"email": email, "password": password})
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()

    def auth_headers(self, email: str, password: str) -> dict[str, str]:
        tokens = self.login(email, password)
        return {"Authorization": f"Bearer {tokens['access_token']}"}

    def create_gym_as_admin(self, name: str = "Test Box") -> tuple[dict[str, str], int]:
        admin_headers = self.auth_headers(settings.ADMIN_EMAIL, settings.ADMIN_PASSWORD)
        response = self.client.post(
            "/gyms",
            headers=admin_headers,
            json={
                "name": name,
                "logo_url": f"https://example.com/{name.lower().replace(' ', '-')}.png",
                "timezone": "Europe/Berlin",
            },
        )
        self.assertEqual(response.status_code, 201, response.text)
        return admin_headers, response.json()["gym"]["id"]

    def lookup_user_id(self, email: str) -> int:
        connection = db.get_connection()
        try:
            row = connection.execute("select id from users where email = ?", (email,)).fetchone()
            self.assertIsNotNone(row)
            return int(row["id"])
        finally:
            connection.close()

    def add_active_membership(self, email: str, gym_id: int, roles: list[str] | None = None, active_role: str = "athlete") -> int:
        roles = roles or [active_role]
        user_id = self.lookup_user_id(email)
        timestamp = security.isoformat(security.now_utc())
        connection = db.get_connection()
        try:
            with connection:
                connection.execute(
                    """
                    insert into gym_memberships (user_id, gym_id, active_role, roles_json, status, created_at, updated_at)
                    values (?, ?, ?, ?, 'active', ?, ?)
                    on conflict(user_id, gym_id) do update set
                      active_role = excluded.active_role,
                      roles_json = excluded.roles_json,
                      status = excluded.status,
                      updated_at = excluded.updated_at
                    """,
                    (user_id, gym_id, active_role, validation.encode_roles(roles), timestamp, timestamp),
                )
                connection.execute(
                    "update users set active_gym_id = ?, role = ?, roles_json = ?, updated_at = ? where id = ?",
                    (gym_id, active_role, validation.encode_roles(roles), timestamp, user_id),
                )
            return user_id
        finally:
            connection.close()

    def create_verified_user(self, email: str, password: str = "BoxOS123!", account_type: str = "athlete") -> int:
        signup_endpoint = "/auth/signup-admin" if account_type == "admin" else "/auth/signup"
        signup = self.client.post(signup_endpoint, json={"email": email, "password": password})
        self.assertEqual(signup.status_code, 200, signup.text)
        user_id = self.lookup_user_id(email)
        connection = db.get_connection()
        try:
            with connection:
                token = session_auth.issue_verification_token(connection, user_id)
            verified = self.client.post("/auth/verify-email", json={"token": token})
            self.assertEqual(verified.status_code, 200, verified.text)
        finally:
            connection.close()
        return user_id

    def count_rows(self, table: str, where: str = "1=1", params: tuple = ()) -> int:
        connection = db.get_connection()
        try:
            row = connection.execute(f"select count(*) as count from {table} where {where}", params).fetchone()
            return int(row["count"])
        finally:
            connection.close()
