from __future__ import annotations

from backend import db, security, session_auth, settings
from backend.tests.support import FastApiTestCase


class AuthApiTests(FastApiTestCase):
    def test_login_requires_verified_email(self) -> None:
        signup = self.client.post("/auth/signup", json={"email": "needs-verify@boxos.app", "password": "BoxOS123!"})
        self.assertEqual(signup.status_code, 200)

        login = self.client.post(
            "/auth/login",
            json={"email": "needs-verify@boxos.app", "password": "BoxOS123!"},
        )
        self.assertEqual(login.status_code, 403)
        self.assertEqual(login.json()["detail"], "Verify your email before signing in.")

    def test_refresh_rotates_session_tokens(self) -> None:
        tokens = self.login(settings.DEMO_EMAIL, settings.DEMO_PASSWORD)

        refreshed = self.client.post("/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
        self.assertEqual(refreshed.status_code, 200, refreshed.text)
        new_tokens = refreshed.json()
        self.assertNotEqual(new_tokens["access_token"], tokens["access_token"])
        self.assertNotEqual(new_tokens["refresh_token"], tokens["refresh_token"])

        old_session = self.client.get("/auth/session", headers={"Authorization": f"Bearer {tokens['access_token']}"})
        self.assertEqual(old_session.status_code, 401)

        new_session = self.client.get("/auth/session", headers={"Authorization": f"Bearer {new_tokens['access_token']}"})
        self.assertEqual(new_session.status_code, 200)
        self.assertEqual(new_session.json()["email"], settings.DEMO_EMAIL)

    def test_change_password_revokes_current_session_and_accepts_new_password(self) -> None:
        self.create_verified_user("pw-change@boxos.app")
        tokens = self.login("pw-change@boxos.app", "BoxOS123!")
        headers = {"Authorization": f"Bearer {tokens['access_token']}"}

        changed = self.client.post(
            "/auth/change-password",
            headers=headers,
            json={
                "current_password": "BoxOS123!",
                "new_password": "NewPass123!",
                "logout_other_sessions": True,
            },
        )
        self.assertEqual(changed.status_code, 200, changed.text)

        current_session = self.client.get("/auth/session", headers=headers)
        self.assertEqual(current_session.status_code, 401)

        old_password_login = self.client.post(
            "/auth/login",
            json={"email": "pw-change@boxos.app", "password": "BoxOS123!"},
        )
        self.assertEqual(old_password_login.status_code, 401)

        new_password_login = self.client.post(
            "/auth/login",
            json={"email": "pw-change@boxos.app", "password": "NewPass123!"},
        )
        self.assertEqual(new_password_login.status_code, 200)

    def test_reset_password_invalidates_existing_sessions_when_requested(self) -> None:
        self.create_verified_user("reset-flow@boxos.app")
        first_tokens = self.login("reset-flow@boxos.app", "BoxOS123!")
        second_tokens = self.login("reset-flow@boxos.app", "BoxOS123!")

        user_id = self.lookup_user_id("reset-flow@boxos.app")
        connection = db.get_connection()
        try:
            with connection:
                token = session_auth.issue_password_reset_token(connection, user_id)
        finally:
            connection.close()

        reset = self.client.post(
            "/auth/reset-password",
            json={"token": token, "new_password": "ResetPass123!", "logout_other_sessions": True},
        )
        self.assertEqual(reset.status_code, 200, reset.text)

        for access_token in (first_tokens["access_token"], second_tokens["access_token"]):
            expired = self.client.get("/auth/session", headers={"Authorization": f"Bearer {access_token}"})
            self.assertEqual(expired.status_code, 401)

        relogin = self.client.post(
            "/auth/login",
            json={"email": "reset-flow@boxos.app", "password": "ResetPass123!"},
        )
        self.assertEqual(relogin.status_code, 200)

    def test_delete_account_anonymizes_user_and_clears_auth_artifacts(self) -> None:
        user_id = self.create_verified_user("delete-me@boxos.app")
        tokens = self.login("delete-me@boxos.app", "BoxOS123!")
        headers = {"Authorization": f"Bearer {tokens['access_token']}"}

        device = self.client.post(
            "/devices/register",
            headers=headers,
            json={"device_token": "device-delete-1", "platform": "ios"},
        )
        self.assertEqual(device.status_code, 200)

        deleted = self.client.request(
            "DELETE",
            "/auth/account",
            headers=headers,
            json={"current_password": "BoxOS123!"},
        )
        self.assertEqual(deleted.status_code, 200, deleted.text)

        connection = db.get_connection()
        try:
            user = connection.execute(
                "select email, deleted_at, email_verified, display_name, nickname from users where id = ?",
                (user_id,),
            ).fetchone()
            self.assertIsNotNone(user)
            self.assertTrue(str(user["email"]).startswith("deleted_"))
            self.assertIsNotNone(user["deleted_at"])
            self.assertEqual(user["email_verified"], 0)
            self.assertEqual(user["display_name"], "Deleted User")
            self.assertEqual(user["nickname"], "")
        finally:
            connection.close()

        self.assertEqual(self.count_rows("sessions", "user_id = ?", (user_id,)), 0)
        self.assertEqual(self.count_rows("device_registrations", "user_id = ?", (user_id,)), 0)
