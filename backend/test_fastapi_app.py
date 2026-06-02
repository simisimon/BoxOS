from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path
from datetime import timedelta

from backend import db, security, settings, session_auth, validation

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
class FastApiBackendTests(unittest.TestCase):
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

    def test_health(self) -> None:
        response = self.client.get("/health")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"status": "ok"})

    def test_login_session_and_profile_update(self) -> None:
        login = self.client.post(
            "/auth/login",
            json={"email": settings.DEMO_EMAIL, "password": settings.DEMO_PASSWORD},
        )
        self.assertEqual(login.status_code, 200)
        tokens = login.json()
        self.assertIn("access_token", tokens)

        headers = {"Authorization": f"Bearer {tokens['access_token']}"}
        session_response = self.client.get("/auth/session", headers=headers)
        self.assertEqual(session_response.status_code, 200)
        self.assertEqual(session_response.json()["email"], settings.DEMO_EMAIL)

        updated = self.client.patch(
            "/profile",
            headers=headers,
            json={"display_name": "Fast Athlete", "nickname": "fast"},
        )
        self.assertEqual(updated.status_code, 200)
        self.assertEqual(updated.json()["display_name"], "Fast Athlete")
        self.assertEqual(updated.json()["nickname"], "fast")

    def test_admin_can_create_gym(self) -> None:
        login = self.client.post(
            "/auth/login",
            json={"email": settings.ADMIN_EMAIL, "password": settings.ADMIN_PASSWORD},
        )
        headers = {"Authorization": f"Bearer {login.json()['access_token']}"}
        created = self.client.post(
            "/gyms",
            headers=headers,
            json={
                "name": "FastAPI Box",
                "logo_url": "https://example.com/logo.png",
                "timezone": "Europe/Berlin",
            },
        )
        self.assertEqual(created.status_code, 201)
        self.assertEqual(created.json()["gym"]["slug"], "fastapi-box")

    def test_schedule_booking_and_waitlist_flow(self) -> None:
        admin_login = self.client.post(
            "/auth/login",
            json={"email": settings.ADMIN_EMAIL, "password": settings.ADMIN_PASSWORD},
        )
        admin_headers = {"Authorization": f"Bearer {admin_login.json()['access_token']}"}
        created_gym = self.client.post(
            "/gyms",
            headers=admin_headers,
            json={
                "name": "Schedule Box",
                "logo_url": "https://example.com/schedule.png",
                "timezone": "Europe/Berlin",
            },
        )
        self.assertEqual(created_gym.status_code, 201)
        gym_id = created_gym.json()["gym"]["id"]

        connection = db.get_connection()
        demo_user = connection.execute(
            "select id from users where email = ?",
            (settings.DEMO_EMAIL,),
        ).fetchone()
        self.assertIsNotNone(demo_user)
        timestamp = security.isoformat(security.now_utc())
        with connection:
            connection.execute(
                """
                insert into gym_memberships (user_id, gym_id, active_role, roles_json, status, created_at, updated_at)
                values (?, ?, 'athlete', ?, 'active', ?, ?)
                """,
                (demo_user["id"], gym_id, validation.encode_roles(["athlete"]), timestamp, timestamp),
            )
            connection.execute(
                "update users set active_gym_id = ?, role = 'athlete', roles_json = ? where id = ?",
                (gym_id, validation.encode_roles(["athlete"]), demo_user["id"]),
            )
        connection.close()

        create_class = self.client.post(
            "/schedule/classes",
            headers=admin_headers,
            json={
                "title": "Morning WOD",
                "class_type": "crossfit",
                "start_time": security.isoformat(security.now_utc() + timedelta(days=1)),
                "duration_minutes": 60,
                "capacity": 1,
                "wod_description": "Burpees and rowing",
                "recurrence_frequency": "none",
            },
        )
        self.assertEqual(create_class.status_code, 201)
        class_id = create_class.json()["class"]["id"]

        athlete_login = self.client.post(
            "/auth/login",
            json={"email": settings.DEMO_EMAIL, "password": settings.DEMO_PASSWORD},
        )
        athlete_headers = {"Authorization": f"Bearer {athlete_login.json()['access_token']}"}

        booking = self.client.post("/schedule/bookings", headers=athlete_headers, json={"class_id": class_id})
        self.assertEqual(booking.status_code, 201)

        classes = self.client.get("/schedule/classes", headers=athlete_headers)
        self.assertEqual(classes.status_code, 200)
        self.assertEqual(classes.json()["classes"][0]["booked_count"], 1)
        self.assertTrue(classes.json()["classes"][0]["is_booked"])

        second_user_email = "waitlist@boxos.app"
        connection = db.get_connection()
        with connection:
            connection.execute(
                """
                insert into users (
                  email, password_hash, email_verified, role, roles_json, display_name, nickname, account_type,
                  created_at, updated_at, active_gym_id
                ) values (?, ?, 1, 'athlete', ?, 'Wait List', 'wait', 'athlete', ?, ?, ?)
                """,
                (
                    second_user_email,
                    security.hash_password("BoxOS123!"),
                    validation.encode_roles(["athlete"]),
                    timestamp,
                    timestamp,
                    gym_id,
                ),
            )
            second_user = connection.execute("select id from users where email = ?", (second_user_email,)).fetchone()
            connection.execute(
                """
                insert into gym_memberships (user_id, gym_id, active_role, roles_json, status, created_at, updated_at)
                values (?, ?, 'athlete', ?, 'active', ?, ?)
                """,
                (second_user["id"], gym_id, validation.encode_roles(["athlete"]), timestamp, timestamp),
            )
        connection.close()

        waitlist_login = self.client.post(
            "/auth/login",
            json={"email": second_user_email, "password": "BoxOS123!"},
        )
        waitlist_headers = {"Authorization": f"Bearer {waitlist_login.json()['access_token']}"}
        waitlisted = self.client.post("/schedule/waitlist", headers=waitlist_headers, json={"class_id": class_id})
        self.assertEqual(waitlisted.status_code, 201)

        cancelled = self.client.request("DELETE", "/schedule/bookings", headers=athlete_headers, json={"class_id": class_id})
        self.assertEqual(cancelled.status_code, 200)

        classes_after = self.client.get("/schedule/classes", headers=waitlist_headers)
        self.assertEqual(classes_after.status_code, 200)
        self.assertTrue(classes_after.json()["classes"][0]["is_booked"])
        self.assertEqual(classes_after.json()["classes"][0]["waitlist_count"], 0)

    def test_join_requests_role_management_and_active_gym_switch(self) -> None:
        admin_login = self.client.post(
            "/auth/login",
            json={"email": settings.ADMIN_EMAIL, "password": settings.ADMIN_PASSWORD},
        )
        admin_headers = {"Authorization": f"Bearer {admin_login.json()['access_token']}"}
        gym_one = self.client.post(
            "/gyms",
            headers=admin_headers,
            json={
                "name": "Gym One",
                "logo_url": "https://example.com/one.png",
                "timezone": "Europe/Berlin",
            },
        )
        gym_two = self.client.post(
            "/gyms",
            headers=admin_headers,
            json={
                "name": "Gym Two",
                "logo_url": "https://example.com/two.png",
                "timezone": "Europe/Berlin",
            },
        )
        self.assertEqual(gym_one.status_code, 201)
        self.assertEqual(gym_two.status_code, 201)

        athlete_login = self.client.post(
            "/auth/login",
            json={"email": settings.DEMO_EMAIL, "password": settings.DEMO_PASSWORD},
        )
        athlete_headers = {"Authorization": f"Bearer {athlete_login.json()['access_token']}"}
        join_request = self.client.post(
            "/gyms/join-requests",
            headers=athlete_headers,
            json={"gym_id": gym_one.json()["gym"]["id"]},
        )
        self.assertEqual(join_request.status_code, 201)

        pending = self.client.get("/gyms/join-requests", headers=admin_headers)
        self.assertEqual(pending.status_code, 200)
        request_id = pending.json()["requests"][0]["id"]

        reviewed = self.client.patch(
            "/gyms/join-requests",
            headers=admin_headers,
            json={"request_id": request_id, "decision": "approve"},
        )
        self.assertEqual(reviewed.status_code, 200)

        my_requests = self.client.get("/gyms/my-requests", headers=athlete_headers)
        self.assertEqual(my_requests.status_code, 200)
        self.assertEqual(my_requests.json()["requests"][0]["status"], "approved")

        switch_gym = self.client.patch(
            "/profile/active-gym",
            headers=athlete_headers,
            json={"gym_id": gym_one.json()["gym"]["id"]},
        )
        self.assertEqual(switch_gym.status_code, 200)
        self.assertEqual(switch_gym.json()["active_gym"]["id"], gym_one.json()["gym"]["id"])

        role_users = self.client.get("/roles/users", headers=admin_headers)
        self.assertEqual(role_users.status_code, 200)
        demo_member = next(user for user in role_users.json()["users"] if user["email"] == settings.DEMO_EMAIL)

        role_update = self.client.patch(
            "/roles/users",
            headers=admin_headers,
            json={"user_id": demo_member["id"], "roles": ["athlete", "trainer"]},
        )
        self.assertEqual(role_update.status_code, 200)
        self.assertEqual(role_update.json()["available_roles"], ["athlete", "trainer"])

        active_role = self.client.patch(
            "/profile/active-role",
            headers=athlete_headers,
            json={"role": "trainer"},
        )
        self.assertEqual(active_role.status_code, 200)
        self.assertEqual(active_role.json()["role"], "trainer")

    def test_announcements_and_notifications_flow(self) -> None:
        admin_login = self.client.post(
            "/auth/login",
            json={"email": settings.ADMIN_EMAIL, "password": settings.ADMIN_PASSWORD},
        )
        admin_headers = {"Authorization": f"Bearer {admin_login.json()['access_token']}"}
        created_gym = self.client.post(
            "/gyms",
            headers=admin_headers,
            json={
                "name": "News Box",
                "logo_url": "https://example.com/news.png",
                "timezone": "Europe/Berlin",
            },
        )
        gym_id = created_gym.json()["gym"]["id"]

        connection = db.get_connection()
        demo_user = connection.execute("select id from users where email = ?", (settings.DEMO_EMAIL,)).fetchone()
        timestamp = security.isoformat(security.now_utc())
        with connection:
            connection.execute(
                "insert into gym_memberships (user_id, gym_id, active_role, roles_json, status, created_at, updated_at) values (?, ?, 'athlete', ?, 'active', ?, ?)",
                (demo_user["id"], gym_id, validation.encode_roles(["athlete"]), timestamp, timestamp),
            )
            connection.execute(
                "update users set active_gym_id = ?, role = 'athlete', roles_json = ? where id = ?",
                (gym_id, validation.encode_roles(["athlete"]), demo_user["id"]),
            )
        connection.close()

        announcement = self.client.post(
            "/announcements",
            headers=admin_headers,
            json={"title": "Holiday Hours", "description": "Open gym on Saturday", "image_url": None},
        )
        self.assertEqual(announcement.status_code, 201)
        announcement_id = announcement.json()["announcement"]["id"]

        athlete_login = self.client.post(
            "/auth/login",
            json={"email": settings.DEMO_EMAIL, "password": settings.DEMO_PASSWORD},
        )
        athlete_headers = {"Authorization": f"Bearer {athlete_login.json()['access_token']}"}

        listed = self.client.get("/announcements", headers=athlete_headers)
        self.assertEqual(listed.status_code, 200)
        self.assertEqual(listed.json()["announcements"][0]["title"], "Holiday Hours")

        liked = self.client.post("/announcements/likes", headers=athlete_headers, json={"announcement_id": announcement_id})
        self.assertEqual(liked.status_code, 200)
        self.assertEqual(liked.json()["announcement"]["like_count"], 1)

        commented = self.client.post(
            "/announcements/comments",
            headers=athlete_headers,
            json={"announcement_id": announcement_id, "body": "Nice, danke!"},
        )
        self.assertEqual(commented.status_code, 201)
        comment_id = commented.json()["comment"]["id"]

        notifications = self.client.get("/notifications", headers=admin_headers)
        self.assertEqual(notifications.status_code, 200)
        self.assertGreaterEqual(notifications.json()["unread_count"], 2)

        marked = self.client.patch("/notifications/read-all", headers=admin_headers)
        self.assertEqual(marked.status_code, 200)
        self.assertEqual(marked.json()["unread_count"], 0)

        prefs = self.client.get("/profile/notifications", headers=athlete_headers)
        self.assertEqual(prefs.status_code, 200)
        updated_prefs = self.client.patch(
            "/profile/notifications",
            headers=athlete_headers,
            json={
                "booking_confirmations": True,
                "waitlist_promotions": True,
                "payment_issues": True,
                "wod_posted": True,
                "pr_achievements": True,
                "announcement_activity": False,
            },
        )
        self.assertEqual(updated_prefs.status_code, 200)
        self.assertFalse(updated_prefs.json()["announcement_activity"])

        updated_comment = self.client.patch(
            "/announcements/comments",
            headers=athlete_headers,
            json={"id": comment_id, "body": "Nice, danke euch!"},
        )
        self.assertEqual(updated_comment.status_code, 200)
        self.assertEqual(updated_comment.json()["comment"]["body"], "Nice, danke euch!")

        deleted_comment = self.client.request("DELETE", "/announcements/comments", headers=athlete_headers, json={"id": comment_id})
        self.assertEqual(deleted_comment.status_code, 200)
        self.assertTrue(deleted_comment.json()["deleted"])

    def test_auth_device_and_account_management_flow(self) -> None:
        signup = self.client.post(
            "/auth/signup",
            json={"email": "fresh@boxos.app", "password": "BoxOS123!"},
        )
        self.assertEqual(signup.status_code, 200)

        connection = db.get_connection()
        verification = connection.execute(
            "select token_hash from verification_tokens join users on users.id = verification_tokens.user_id where users.email = ?",
            ("fresh@boxos.app",),
        ).fetchone()
        connection.close()
        self.assertIsNotNone(verification)

        login_before_verify = self.client.post(
            "/auth/login",
            json={"email": "fresh@boxos.app", "password": "BoxOS123!"},
        )
        self.assertEqual(login_before_verify.status_code, 403)

        # issue a fresh readable token through the service layer for test use
        connection = db.get_connection()
        user = connection.execute("select id from users where email = ?", ("fresh@boxos.app",)).fetchone()
        with connection:
            token = session_auth.issue_verification_token(connection, user["id"])
        connection.close()

        verified = self.client.post("/auth/verify-email", json={"token": token})
        self.assertEqual(verified.status_code, 200)

        login = self.client.post(
            "/auth/login",
            json={"email": "fresh@boxos.app", "password": "BoxOS123!"},
        )
        self.assertEqual(login.status_code, 200)
        tokens = login.json()
        headers = {"Authorization": f"Bearer {tokens['access_token']}"}

        registered = self.client.post(
            "/devices/register",
            headers=headers,
            json={"device_token": "device-token-1", "platform": "ios"},
        )
        self.assertEqual(registered.status_code, 200)

        changed = self.client.post(
            "/auth/change-password",
            headers=headers,
            json={
                "current_password": "BoxOS123!",
                "new_password": "NewPass123!",
                "logout_other_sessions": True,
            },
        )
        self.assertEqual(changed.status_code, 200)
        new_tokens = changed.json()
        new_headers = {"Authorization": f"Bearer {new_tokens['access_token']}"}

        old_session = self.client.get("/auth/session", headers=headers)
        self.assertEqual(old_session.status_code, 401)

        unregistered = self.client.request(
            "DELETE",
            "/devices/current",
            headers=new_headers,
            json={"device_token": "device-token-1"},
        )
        self.assertEqual(unregistered.status_code, 200)

        reset_request = self.client.post(
            "/auth/request-password-reset",
            json={"email": "fresh@boxos.app"},
        )
        self.assertEqual(reset_request.status_code, 200)

        connection = db.get_connection()
        with connection:
            reset_token = session_auth.issue_password_reset_token(connection, user["id"])
        connection.close()

        reset = self.client.post(
            "/auth/reset-password",
            json={"token": reset_token, "new_password": "ResetPass123!", "logout_other_sessions": True},
        )
        self.assertEqual(reset.status_code, 200)

        relogin = self.client.post(
            "/auth/login",
            json={"email": "fresh@boxos.app", "password": "ResetPass123!"},
        )
        self.assertEqual(relogin.status_code, 200)
        relogin_headers = {"Authorization": f"Bearer {relogin.json()['access_token']}"}

        deleted = self.client.request(
            "DELETE",
            "/auth/account",
            headers=relogin_headers,
            json={"current_password": "ResetPass123!"},
        )
        self.assertEqual(deleted.status_code, 200)

    def test_programming_personal_workouts_and_analytics_flow(self) -> None:
        admin_login = self.client.post(
            "/auth/login",
            json={"email": settings.ADMIN_EMAIL, "password": settings.ADMIN_PASSWORD},
        )
        admin_headers = {"Authorization": f"Bearer {admin_login.json()['access_token']}"}
        created_gym = self.client.post(
            "/gyms",
            headers=admin_headers,
            json={
                "name": "Programming Box",
                "logo_url": "https://example.com/programming.png",
                "timezone": "Europe/Berlin",
            },
        )
        self.assertEqual(created_gym.status_code, 201)
        gym_id = created_gym.json()["gym"]["id"]

        connection = db.get_connection()
        demo_user = connection.execute("select id from users where email = ?", (settings.DEMO_EMAIL,)).fetchone()
        timestamp = security.isoformat(security.now_utc())
        with connection:
            connection.execute(
                "insert into gym_memberships (user_id, gym_id, active_role, roles_json, status, created_at, updated_at) values (?, ?, 'athlete', ?, 'active', ?, ?)",
                (demo_user["id"], gym_id, validation.encode_roles(["athlete"]), timestamp, timestamp),
            )
            connection.execute(
                "update users set active_gym_id = ?, role = 'athlete', roles_json = ? where id = ?",
                (gym_id, validation.encode_roles(["athlete"]), demo_user["id"]),
            )
        connection.close()

        workout_date = (security.now_utc() - timedelta(days=1)).date().isoformat()
        created_workout = self.client.post(
            "/programming/workouts",
            headers=admin_headers,
            json={
                "scheduled_date": workout_date,
                "title": "Fran",
                "strength_text": "Front squats",
                "metcon_text": "21-15-9 thrusters/pull-ups",
                "notes_text": "Go hard",
            },
        )
        self.assertEqual(created_workout.status_code, 201)
        workout_id = created_workout.json()["workout"]["id"]

        athlete_login = self.client.post(
            "/auth/login",
            json={"email": settings.DEMO_EMAIL, "password": settings.DEMO_PASSWORD},
        )
        athlete_headers = {"Authorization": f"Bearer {athlete_login.json()['access_token']}"}

        workouts = self.client.get("/programming/workouts", headers=athlete_headers)
        self.assertEqual(workouts.status_code, 200)
        self.assertEqual(workouts.json()["workouts"][0]["title"], "Fran")

        whiteboard = self.client.post(
            "/programming/whiteboard-results",
            headers=athlete_headers,
            json={"workout_id": workout_id, "score_type": "time", "score_value": 355, "notes_text": "Felt good"},
        )
        self.assertEqual(whiteboard.status_code, 200)

        log_entry = self.client.post(
            "/logbook/entries",
            headers=athlete_headers,
            json={"workout_id": workout_id, "score_type": "time", "score_value": 355, "notes_text": "PR!"},
        )
        self.assertEqual(log_entry.status_code, 200)
        self.assertTrue(log_entry.json()["entry"]["is_pr"])

        logs = self.client.get("/logbook/entries", headers=athlete_headers)
        self.assertEqual(logs.status_code, 200)
        self.assertEqual(len(logs.json()["entries"]), 1)

        personal = self.client.post(
            "/personal-workouts",
            headers=athlete_headers,
            json={"title": "Accessory Day", "type": "amrap", "structure": {"rounds": 5, "movements": ["row", "situp"]}},
        )
        self.assertEqual(personal.status_code, 200)
        personal_id = personal.json()["workout"]["id"]

        listed_personal = self.client.get("/personal-workouts", headers=athlete_headers)
        self.assertEqual(listed_personal.status_code, 200)
        self.assertEqual(len(listed_personal.json()["workouts"]), 1)

        exercises = self.client.get("/exercises?limit=5", headers=athlete_headers)
        self.assertEqual(exercises.status_code, 200)
        self.assertLessEqual(len(exercises.json()["exercises"]), 5)

        benchmarks = self.client.get("/benchmark-workouts", headers=athlete_headers)
        self.assertEqual(benchmarks.status_code, 200)

        audit_logs = self.client.get("/audit-logs", headers=admin_headers)
        self.assertEqual(audit_logs.status_code, 200)
        self.assertGreaterEqual(len(audit_logs.json()["logs"]), 1)

        analytics = self.client.get("/admin/analytics?window_days=14", headers=admin_headers)
        self.assertEqual(analytics.status_code, 200)
        self.assertEqual(analytics.json()["overview"]["window_days"], 14)

        deleted_personal = self.client.request(
            "DELETE",
            "/personal-workouts",
            headers=athlete_headers,
            json={"id": personal_id},
        )
        self.assertEqual(deleted_personal.status_code, 200)
