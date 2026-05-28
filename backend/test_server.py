from __future__ import annotations

import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from datetime import timedelta
from pathlib import Path

from backend import server


class BackendServerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        server.DB_PATH = Path(self.temp_dir.name) / "test.db"
        server.init_db()
        self.http_server = server.ThreadingHTTPServer(("127.0.0.1", 0), server.BoxOsHandler)
        self.base_url = f"http://127.0.0.1:{self.http_server.server_port}"
        self.server_thread = threading.Thread(
            target=self.http_server.serve_forever,
            daemon=True,
        )
        self.server_thread.start()

    def tearDown(self) -> None:
        self.http_server.shutdown()
        self.http_server.server_close()
        self.server_thread.join(timeout=2)
        self.temp_dir.cleanup()

    def test_demo_user_is_seeded(self) -> None:
        connection = server.get_connection()
        row = connection.execute(
            "select email, email_verified, role from users where email = ?",
            (server.DEMO_EMAIL,),
        ).fetchone()
        connection.close()

        self.assertIsNotNone(row)
        self.assertEqual(row["email"], server.DEMO_EMAIL)
        self.assertEqual(row["email_verified"], 1)
        self.assertEqual(row["role"], "athlete")

    def test_init_db_is_idempotent_with_seeded_users(self) -> None:
        server.init_db()

        connection = server.get_connection()
        rows = connection.execute(
            "select email from users where email in (?, ?, ?)",
            (server.DEMO_EMAIL, server.TRAINER_EMAIL, server.ADMIN_EMAIL),
        ).fetchall()
        connection.close()

        self.assertEqual(len(rows), 3)

    def test_password_hash_round_trip(self) -> None:
        encoded = server.hash_password("BoxOS123!")
        self.assertTrue(server.verify_password("BoxOS123!", encoded))
        self.assertFalse(server.verify_password("wrong-pass", encoded))

    def test_create_session_returns_tokens(self) -> None:
        connection = server.get_connection()
        user = connection.execute(
            "select id from users where email = ?",
            (server.DEMO_EMAIL,),
        ).fetchone()
        self.assertIsNotNone(user)

        with connection:
            tokens = server.create_session(connection, user["id"])
        stored = connection.execute("select * from sessions").fetchone()
        connection.close()

        self.assertIn("access_token", tokens)
        self.assertIn("refresh_token", tokens)
        self.assertEqual(stored["access_token_hash"], server.hash_token(tokens["access_token"]))
        expires_at = server.parse_iso(stored["access_expires_at"])
        created_at = server.parse_iso(stored["created_at"])
        ttl_seconds = (expires_at - created_at).total_seconds()
        self.assertGreaterEqual(ttl_seconds, 14 * 60)
        self.assertLessEqual(ttl_seconds, 15 * 60)

    def test_demo_login_and_session_endpoint(self) -> None:
        login_response = self.post_json(
            "/auth/login",
            {
                "email": server.DEMO_EMAIL,
                "password": server.DEMO_PASSWORD,
            },
        )
        self.assertIn("access_token", login_response)
        self.assertIn("refresh_token", login_response)

        session_request = urllib.request.Request(
            f"{self.base_url}/auth/session",
            headers={"Authorization": f"Bearer {login_response['access_token']}"},
            method="GET",
        )
        with urllib.request.urlopen(session_request) as response:
            payload = response.read().decode("utf-8")

        self.assertIn(server.DEMO_EMAIL, payload)
        self.assertIn("athlete", payload)

    def test_refresh_rotates_session_and_invalidates_old_refresh_token(self) -> None:
        login_response = self.post_json(
            "/auth/login",
            {
                "email": server.DEMO_EMAIL,
                "password": server.DEMO_PASSWORD,
            },
        )

        refreshed = self.post_json(
            "/auth/refresh",
            {"refresh_token": login_response["refresh_token"]},
        )

        self.assertNotEqual(refreshed["refresh_token"], login_response["refresh_token"])

        with self.assertRaises(urllib.error.HTTPError) as error_context:
            self.post_json(
                "/auth/refresh",
                {"refresh_token": login_response["refresh_token"]},
            )

        self.assertEqual(error_context.exception.code, 401)

    def test_logout_all_revokes_other_active_sessions(self) -> None:
        first_login = self.post_json(
            "/auth/login",
            {
                "email": server.DEMO_EMAIL,
                "password": server.DEMO_PASSWORD,
            },
        )
        second_login = self.post_json(
            "/auth/login",
            {
                "email": server.DEMO_EMAIL,
                "password": server.DEMO_PASSWORD,
            },
        )

        self.post_json_with_auth(
            "/auth/logout-all",
            {},
            access_token=first_login["access_token"],
        )

        session_request = urllib.request.Request(
            f"{self.base_url}/auth/session",
            headers={"Authorization": f"Bearer {second_login['access_token']}"},
            method="GET",
        )
        with self.assertRaises(urllib.error.HTTPError) as error_context:
            urllib.request.urlopen(session_request)

        self.assertEqual(error_context.exception.code, 401)

    def test_profile_fetch_and_update(self) -> None:
        login_response = self.post_json(
            "/auth/login",
            {
                "email": server.DEMO_EMAIL,
                "password": server.DEMO_PASSWORD,
            },
        )

        profile_request = urllib.request.Request(
            f"{self.base_url}/profile",
            headers={"Authorization": f"Bearer {login_response['access_token']}"},
            method="GET",
        )
        with urllib.request.urlopen(profile_request) as response:
            profile = json_loads(response.read())

        self.assertEqual(profile["display_name"], "Demo Athlete")
        self.assertEqual(profile["nickname"], "demo")
        self.assertEqual(profile["role"], "athlete")

        updated = self.patch_json(
            "/profile",
            {
                "display_name": "Basti Athlete",
                "nickname": "basti",
            },
            access_token=login_response["access_token"],
        )

        self.assertEqual(updated["display_name"], "Basti Athlete")
        self.assertEqual(updated["nickname"], "basti")
        self.assertEqual(updated["role"], "athlete")

    def test_admin_signup_can_create_gym(self) -> None:
        self.post_json(
            "/auth/signup-admin",
            {
                "email": "newadmin@boxos.app",
                "password": "AdminPass123!",
            },
        )
        self._verify_user_email("newadmin@boxos.app")
        login_response = self.post_json(
            "/auth/login",
            {
                "email": "newadmin@boxos.app",
                "password": "AdminPass123!",
            },
        )

        created = self.post_json_with_auth(
            "/gyms",
            {
                "name": "CrossFit Mitte",
                "logo_url": "https://example.com/logo.png",
                "timezone": "Europe/Berlin",
            },
            access_token=login_response["access_token"],
        )

        self.assertEqual(created["gym"]["name"], "CrossFit Mitte")
        self.assertEqual(created["gym"]["slug"], "crossfit-mitte")

        connection = server.get_connection()
        user = connection.execute(
            "select id, active_gym_id, role, account_type from users where email = ?",
            ("newadmin@boxos.app",),
        ).fetchone()
        membership = connection.execute(
            """
            select active_role, roles_json, status
            from gym_memberships
            where user_id = ? and gym_id = ?
            """,
            (user["id"], user["active_gym_id"]),
        ).fetchone()
        connection.close()

        self.assertEqual(user["account_type"], "admin")
        self.assertEqual(user["role"], "admin")
        self.assertIsNotNone(user["active_gym_id"])
        self.assertEqual(membership["active_role"], "admin")
        self.assertEqual(server.decode_roles(membership["roles_json"]), ["admin"])

    def test_athlete_cannot_create_gym(self) -> None:
        login_response = self.post_json(
            "/auth/login",
            {
                "email": server.DEMO_EMAIL,
                "password": server.DEMO_PASSWORD,
            },
        )

        request = urllib.request.Request(
            f"{self.base_url}/gyms",
            data=json_bytes(
                {
                    "name": "Should Fail",
                    "logo_url": "https://example.com/logo.png",
                    "timezone": "Europe/Berlin",
                }
            ),
            headers={
                "Authorization": f"Bearer {login_response['access_token']}",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        with self.assertRaises(urllib.error.HTTPError) as error_context:
            urllib.request.urlopen(request)

        self.assertEqual(error_context.exception.code, 403)

    def test_join_request_can_be_approved_by_admin(self) -> None:
        self.post_json(
            "/auth/signup-admin",
            {
                "email": "admin2@boxos.app",
                "password": "AdminPass123!",
            },
        )
        self._verify_user_email("admin2@boxos.app")
        admin_login = self.post_json(
            "/auth/login",
            {
                "email": "admin2@boxos.app",
                "password": "AdminPass123!",
            },
        )
        created_gym = self.post_json_with_auth(
            "/gyms",
            {
                "name": "BoxOS Downtown",
                "logo_url": "https://example.com/downtown.png",
                "timezone": "Europe/Berlin",
            },
            access_token=admin_login["access_token"],
        )

        athlete_login = self.post_json(
            "/auth/login",
            {
                "email": server.DEMO_EMAIL,
                "password": server.DEMO_PASSWORD,
            },
        )
        requested = self.post_json_with_auth(
            "/gyms/join-requests",
            {"gym_id": created_gym["gym"]["id"]},
            access_token=athlete_login["access_token"],
        )
        self.assertEqual(requested["message"], "Join request submitted.")

        requests_request = urllib.request.Request(
            f"{self.base_url}/gyms/join-requests",
            headers={"Authorization": f"Bearer {admin_login['access_token']}"},
            method="GET",
        )
        with urllib.request.urlopen(requests_request) as response:
            pending_payload = json_loads(response.read())

        self.assertEqual(len(pending_payload["requests"]), 1)
        request_id = pending_payload["requests"][0]["id"]

        reviewed = self.patch_json(
            "/gyms/join-requests",
            {
                "request_id": request_id,
                "decision": "approve",
            },
            access_token=admin_login["access_token"],
        )
        self.assertEqual(reviewed["message"], "Join request approved.")

        connection = server.get_connection()
        membership = connection.execute(
            """
            select active_role, roles_json, status
            from gym_memberships
            where gym_id = ? and user_id = (
              select id from users where email = ?
            )
            """,
            (created_gym["gym"]["id"], server.DEMO_EMAIL),
        ).fetchone()
        pending = connection.execute(
            "select status from gym_join_requests where id = ?",
            (request_id,),
        ).fetchone()
        connection.close()

        self.assertEqual(membership["active_role"], "athlete")
        self.assertEqual(server.decode_roles(membership["roles_json"]), ["athlete"])
        self.assertEqual(pending["status"], "approved")

    def test_join_request_status_is_visible_and_active_gym_can_switch(self) -> None:
        self.post_json(
            "/auth/signup-admin",
            {
                "email": "admin3@boxos.app",
                "password": "AdminPass123!",
            },
        )
        self._verify_user_email("admin3@boxos.app")
        admin_login = self.post_json(
            "/auth/login",
            {
                "email": "admin3@boxos.app",
                "password": "AdminPass123!",
            },
        )
        gym_one = self.post_json_with_auth(
            "/gyms",
            {
                "name": "Gym One",
                "logo_url": "https://example.com/one.png",
                "timezone": "Europe/Berlin",
            },
            access_token=admin_login["access_token"],
        )
        gym_two = self.post_json_with_auth(
            "/gyms",
            {
                "name": "Gym Two",
                "logo_url": "https://example.com/two.png",
                "timezone": "Europe/Berlin",
            },
            access_token=admin_login["access_token"],
        )

        athlete_login = self.post_json(
            "/auth/login",
            {
                "email": server.DEMO_EMAIL,
                "password": server.DEMO_PASSWORD,
            },
        )
        self.post_json_with_auth(
            "/gyms/join-requests",
            {"gym_id": gym_one["gym"]["id"]},
            access_token=athlete_login["access_token"],
        )

        self.patch_json(
            "/profile/active-gym",
            {"gym_id": gym_one["gym"]["id"]},
            access_token=admin_login["access_token"],
        )

        admin_requests_request = urllib.request.Request(
            f"{self.base_url}/gyms/join-requests",
            headers={"Authorization": f"Bearer {admin_login['access_token']}"},
            method="GET",
        )
        with urllib.request.urlopen(admin_requests_request) as response:
            admin_requests = json_loads(response.read())
        request_id = admin_requests["requests"][0]["id"]

        self.patch_json(
            "/gyms/join-requests",
            {
                "request_id": request_id,
                "decision": "approve",
            },
            access_token=admin_login["access_token"],
        )

        my_requests_request = urllib.request.Request(
            f"{self.base_url}/gyms/my-requests",
            headers={"Authorization": f"Bearer {athlete_login['access_token']}"},
            method="GET",
        )
        with urllib.request.urlopen(my_requests_request) as response:
            my_requests = json_loads(response.read())

        self.assertEqual(my_requests["requests"][0]["status"], "approved")
        self.assertEqual(my_requests["requests"][0]["gym"]["name"], "Gym One")

        connection = server.get_connection()
        athlete = connection.execute(
            "select id from users where email = ?",
            (server.DEMO_EMAIL,),
        ).fetchone()
        with connection:
            connection.execute(
                """
                insert into gym_memberships (
                  user_id, gym_id, active_role, roles_json, status, created_at, updated_at
                )
                values (?, ?, 'athlete', ?, 'active', ?, ?)
                """,
                (
                    athlete["id"],
                    gym_two["gym"]["id"],
                    server.encode_roles(["athlete"]),
                    server.isoformat(server.now_utc()),
                    server.isoformat(server.now_utc()),
                ),
            )
            server.sync_user_context(connection, athlete["id"])
        connection.close()

        switched = self.patch_json(
            "/profile/active-gym",
            {"gym_id": gym_two["gym"]["id"]},
            access_token=athlete_login["access_token"],
        )
        self.assertEqual(switched["active_gym"]["id"], gym_two["gym"]["id"])
        self.assertEqual(switched["active_gym"]["name"], "Gym Two")

    def test_supported_roles_are_exposed_in_profile(self) -> None:
        login_response = self.post_json(
            "/auth/login",
            {
                "email": server.DEMO_EMAIL,
                "password": server.DEMO_PASSWORD,
            },
        )

        connection = server.get_connection()
        with connection:
            connection.execute(
                "update users set role = 'trainer' where email = ?",
                (server.DEMO_EMAIL,),
            )
        connection.close()

        profile_request = urllib.request.Request(
            f"{self.base_url}/profile",
            headers={"Authorization": f"Bearer {login_response['access_token']}"},
            method="GET",
        )
        with urllib.request.urlopen(profile_request) as response:
            trainer_profile = json_loads(response.read())

        self.assertEqual(trainer_profile["role"], "trainer")
        self.assertEqual(trainer_profile["available_roles"], ["athlete"])

        connection = server.get_connection()
        with connection:
            connection.execute(
                "update users set role = 'admin', roles_json = ? where email = ?",
                ('["athlete", "admin"]', server.DEMO_EMAIL),
            )
        connection.close()

        with urllib.request.urlopen(profile_request) as response:
            admin_profile = json_loads(response.read())

        self.assertEqual(admin_profile["role"], "admin")
        self.assertEqual(admin_profile["available_roles"], ["athlete", "admin"])

    def test_active_role_switch_is_persisted(self) -> None:
        login_response = self.post_json(
            "/auth/login",
            {
                "email": server.DEMO_EMAIL,
                "password": server.DEMO_PASSWORD,
            },
        )

        connection = server.get_connection()
        with connection:
            connection.execute(
                "update users set role = 'athlete', roles_json = ? where email = ?",
                ('["athlete", "trainer"]', server.DEMO_EMAIL),
            )
        connection.close()

        updated = self.patch_json(
            "/profile/active-role",
            {
                "role": "trainer",
            },
            access_token=login_response["access_token"],
        )

        self.assertEqual(updated["role"], "trainer")
        self.assertEqual(updated["available_roles"], ["athlete", "trainer"])

        session_request = urllib.request.Request(
            f"{self.base_url}/auth/session",
            headers={"Authorization": f"Bearer {login_response['access_token']}"},
            method="GET",
        )
        with urllib.request.urlopen(session_request) as response:
            payload = json_loads(response.read())

        self.assertEqual(payload["role"], "trainer")
        self.assertEqual(payload["available_roles"], ["athlete", "trainer"])

    def test_admin_role_can_list_and_assign_roles(self) -> None:
        login_response = self.post_json(
            "/auth/login",
            {
                "email": server.ADMIN_EMAIL,
                "password": server.ADMIN_PASSWORD,
            },
        )
        created_gym = self.post_json_with_auth(
            "/gyms",
            {
                "name": "Admin Test Gym",
                "logo_url": "https://example.com/admin-test.png",
                "timezone": "Europe/Berlin",
            },
            access_token=login_response["access_token"],
        )
        connection = server.get_connection()
        trainer_user = connection.execute(
            "select id from users where email = ?",
            (server.TRAINER_EMAIL,),
        ).fetchone()
        self.assertIsNotNone(trainer_user)
        with connection:
            connection.execute(
                """
                insert into gym_memberships (
                  user_id, gym_id, active_role, roles_json, status, created_at, updated_at
                )
                values (?, ?, 'athlete', ?, 'active', ?, ?)
                """,
                (
                    trainer_user["id"],
                    created_gym["gym"]["id"],
                    server.encode_roles(["athlete"]),
                    server.isoformat(server.now_utc()),
                    server.isoformat(server.now_utc()),
                ),
            )
        connection.close()

        users_request = urllib.request.Request(
            f"{self.base_url}/roles/users",
            headers={"Authorization": f"Bearer {login_response['access_token']}"},
            method="GET",
        )
        with urllib.request.urlopen(users_request) as response:
            payload = json_loads(response.read())

        self.assertIn("users", payload)
        trainer_user = next(
            user for user in payload["users"] if user["email"] == server.TRAINER_EMAIL
        )
        self.assertEqual(trainer_user["role"], "athlete")
        self.assertEqual(trainer_user["available_roles"], ["athlete"])
        self.assertTrue(trainer_user["can_edit_role"])

        updated = self.patch_json(
            "/roles/users",
            {
                "user_id": trainer_user["id"],
                "roles": ["athlete", "trainer"],
            },
            access_token=login_response["access_token"],
        )
        self.assertEqual(updated["email"], server.TRAINER_EMAIL)
        self.assertEqual(updated["role"], "athlete")
        self.assertEqual(updated["available_roles"], ["athlete", "trainer"])

        audit_logs = self.get_json_with_auth(
            "/audit-logs",
            access_token=login_response["access_token"],
        )
        self.assertEqual(audit_logs["logs"][0]["action"], "gym_member_roles_updated")
        self.assertEqual(audit_logs["logs"][0]["details"]["roles"], ["athlete", "trainer"])

    def test_non_admin_role_cannot_manage_roles(self) -> None:
        login_response = self.post_json(
            "/auth/login",
            {
                "email": server.DEMO_EMAIL,
                "password": server.DEMO_PASSWORD,
            },
        )

        request = urllib.request.Request(
            f"{self.base_url}/roles/users",
            headers={"Authorization": f"Bearer {login_response['access_token']}"},
            method="GET",
        )
        with self.assertRaises(urllib.error.HTTPError) as error_context:
            urllib.request.urlopen(request)

        self.assertEqual(error_context.exception.code, 403)

    def test_admin_can_create_and_update_schedule_class(self) -> None:
        login_response = self.post_json(
            "/auth/login",
            {
                "email": server.ADMIN_EMAIL,
                "password": server.ADMIN_PASSWORD,
            },
        )
        self.post_json_with_auth(
            "/gyms",
            {
                "name": "Schedule Gym",
                "logo_url": "https://example.com/schedule.png",
                "timezone": "Europe/Berlin",
            },
            access_token=login_response["access_token"],
        )
        start_time = server.now_utc() + timedelta(days=1)
        end_time = start_time + timedelta(hours=1)
        created = self.post_json_with_auth(
            "/schedule/classes",
            {
                "title": "Morning WOD",
                "class_type": "WOD",
                "start_time": server.isoformat(start_time),
                "end_time": server.isoformat(end_time),
                "capacity": 14,
            },
            access_token=login_response["access_token"],
        )
        self.assertEqual(created["class"]["title"], "Morning WOD")

        updated = self.patch_json(
            "/schedule/classes",
            {
                "id": created["class"]["id"],
                "title": "Morning Open Gym",
                "class_type": "Open Gym",
                "start_time": server.isoformat(start_time + timedelta(hours=1)),
                "end_time": server.isoformat(end_time + timedelta(hours=1)),
                "capacity": 16,
            },
            access_token=login_response["access_token"],
        )
        self.assertEqual(updated["class"]["title"], "Morning Open Gym")
        self.assertEqual(updated["class"]["class_type"], "Open Gym")
        self.assertEqual(updated["class"]["capacity"], 16)

        audit_logs = self.get_json_with_auth(
            "/audit-logs",
            access_token=login_response["access_token"],
        )
        actions = [entry["action"] for entry in audit_logs["logs"][:2]]
        self.assertEqual(actions, ["schedule_class_updated", "schedule_class_created"])

    def test_admin_can_create_daily_recurring_schedule_classes(self) -> None:
        login_response = self.post_json(
            "/auth/login",
            {
                "email": server.ADMIN_EMAIL,
                "password": server.ADMIN_PASSWORD,
            },
        )
        self.post_json_with_auth(
            "/gyms",
            {
                "name": "Recurring Daily Gym",
                "logo_url": "https://example.com/recurring-daily.png",
                "timezone": "Europe/Berlin",
            },
            access_token=login_response["access_token"],
        )
        start_time = server.now_utc() + timedelta(days=1)
        created = self.post_json_with_auth(
            "/schedule/classes",
            {
                "title": "Daily WOD",
                "class_type": "WOD",
                "start_time": server.isoformat(start_time),
                "capacity": 12,
                "duration_minutes": 60,
                "recurrence_frequency": "daily",
                "occurrence_count": 3,
            },
            access_token=login_response["access_token"],
        )

        self.assertEqual(created["created_count"], 3)
        self.assertEqual(len(created["classes"]), 3)
        self.assertEqual(created["class"]["title"], "Daily WOD")
        self.assertEqual(
            created["classes"][1]["start_time"],
            server.isoformat(start_time + timedelta(days=1)),
        )
        self.assertEqual(
            created["classes"][2]["start_time"],
            server.isoformat(start_time + timedelta(days=2)),
        )

    def test_admin_can_create_weekly_recurring_schedule_classes(self) -> None:
        login_response = self.post_json(
            "/auth/login",
            {
                "email": server.ADMIN_EMAIL,
                "password": server.ADMIN_PASSWORD,
            },
        )
        self.post_json_with_auth(
            "/gyms",
            {
                "name": "Recurring Weekly Gym",
                "logo_url": "https://example.com/recurring-weekly.png",
                "timezone": "Europe/Berlin",
            },
            access_token=login_response["access_token"],
        )
        start_time = server.now_utc() + timedelta(days=1)
        created = self.post_json_with_auth(
            "/schedule/classes",
            {
                "title": "Weekly WOD",
                "class_type": "WOD",
                "start_time": server.isoformat(start_time),
                "capacity": 12,
                "duration_minutes": 60,
                "recurrence_frequency": "weekly",
                "occurrence_count": 3,
            },
            access_token=login_response["access_token"],
        )

        self.assertEqual(created["created_count"], 3)
        self.assertEqual(
            created["classes"][1]["start_time"],
            server.isoformat(start_time + timedelta(days=7)),
        )
        self.assertEqual(
            created["classes"][2]["start_time"],
            server.isoformat(start_time + timedelta(days=14)),
        )

    def test_weekly_recurring_schedule_preserves_local_start_time_across_dst(self) -> None:
        login_response = self.post_json(
            "/auth/login",
            {
                "email": server.ADMIN_EMAIL,
                "password": server.ADMIN_PASSWORD,
            },
        )
        self.post_json_with_auth(
            "/gyms",
            {
                "name": "Recurring DST Weekly Gym",
                "logo_url": "https://example.com/recurring-dst-weekly.png",
                "timezone": "Europe/Berlin",
            },
            access_token=login_response["access_token"],
        )
        created = self.post_json_with_auth(
            "/schedule/classes",
            {
                "title": "DST Weekly WOD",
                "class_type": "WOD",
                "start_time": "2026-10-19T07:00:00+00:00",
                "capacity": 12,
                "duration_minutes": 60,
                "recurrence_frequency": "weekly",
                "occurrence_count": 3,
            },
            access_token=login_response["access_token"],
        )

        self.assertEqual(
            [schedule_class["start_time"] for schedule_class in created["classes"]],
            [
                "2026-10-19T07:00:00+00:00",
                "2026-10-26T08:00:00+00:00",
                "2026-11-02T08:00:00+00:00",
            ],
        )

    def test_admin_can_create_monthly_recurring_schedule_classes(self) -> None:
        login_response = self.post_json(
            "/auth/login",
            {
                "email": server.ADMIN_EMAIL,
                "password": server.ADMIN_PASSWORD,
            },
        )
        self.post_json_with_auth(
            "/gyms",
            {
                "name": "Recurring Monthly Gym",
                "logo_url": "https://example.com/recurring-monthly.png",
                "timezone": "Europe/Berlin",
            },
            access_token=login_response["access_token"],
        )
        start_time = server.now_utc() + timedelta(days=1)
        created = self.post_json_with_auth(
            "/schedule/classes",
            {
                "title": "Monthly WOD",
                "class_type": "WOD",
                "start_time": server.isoformat(start_time),
                "capacity": 12,
                "duration_minutes": 60,
                "recurrence_frequency": "monthly",
                "occurrence_count": 3,
            },
            access_token=login_response["access_token"],
        )

        self.assertEqual(created["created_count"], 3)
        self.assertEqual(
            created["classes"][1]["start_time"],
            server.isoformat(start_time + timedelta(days=28)),
        )
        self.assertEqual(
            created["classes"][2]["start_time"],
            server.isoformat(start_time + timedelta(days=56)),
        )

    def test_monthly_recurring_schedule_preserves_local_start_time_across_dst(self) -> None:
        login_response = self.post_json(
            "/auth/login",
            {
                "email": server.ADMIN_EMAIL,
                "password": server.ADMIN_PASSWORD,
            },
        )
        self.post_json_with_auth(
            "/gyms",
            {
                "name": "Recurring DST Monthly Gym",
                "logo_url": "https://example.com/recurring-dst-monthly.png",
                "timezone": "Europe/Berlin",
            },
            access_token=login_response["access_token"],
        )
        created = self.post_json_with_auth(
            "/schedule/classes",
            {
                "title": "DST Monthly WOD",
                "class_type": "WOD",
                "start_time": "2026-10-05T07:00:00+00:00",
                "capacity": 12,
                "duration_minutes": 60,
                "recurrence_frequency": "monthly",
                "occurrence_count": 3,
            },
            access_token=login_response["access_token"],
        )

        self.assertEqual(
            [schedule_class["start_time"] for schedule_class in created["classes"]],
            [
                "2026-10-05T07:00:00+00:00",
                "2026-11-02T08:00:00+00:00",
                "2026-11-30T08:00:00+00:00",
            ],
        )

    def test_schedule_creation_rejects_invalid_recurrence_inputs(self) -> None:
        login_response = self.post_json(
            "/auth/login",
            {
                "email": server.ADMIN_EMAIL,
                "password": server.ADMIN_PASSWORD,
            },
        )
        self.post_json_with_auth(
            "/gyms",
            {
                "name": "Recurring Validation Gym",
                "logo_url": "https://example.com/recurring-validation.png",
                "timezone": "Europe/Berlin",
            },
            access_token=login_response["access_token"],
        )
        start_time = server.now_utc() + timedelta(days=1)

        invalid_frequency_request = urllib.request.Request(
            f"{self.base_url}/schedule/classes",
            data=json_bytes(
                {
                    "title": "Broken Recurrence",
                    "class_type": "WOD",
                    "start_time": server.isoformat(start_time),
                    "capacity": 12,
                    "duration_minutes": 60,
                    "recurrence_frequency": "hourly",
                    "occurrence_count": 2,
                }
            ),
            headers={
                "Authorization": f"Bearer {login_response['access_token']}",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        with self.assertRaises(urllib.error.HTTPError) as invalid_frequency_error:
            urllib.request.urlopen(invalid_frequency_request)

        self.assertEqual(invalid_frequency_error.exception.code, 400)
        self.assertIn(
            "Invalid recurrence frequency.",
            json_loads(invalid_frequency_error.exception.read())["message"],
        )

        invalid_count_request = urllib.request.Request(
            f"{self.base_url}/schedule/classes",
            data=json_bytes(
                {
                    "title": "Broken Count",
                    "class_type": "WOD",
                    "start_time": server.isoformat(start_time),
                    "capacity": 12,
                    "duration_minutes": 60,
                    "recurrence_frequency": "weekly",
                    "occurrence_count": 0,
                }
            ),
            headers={
                "Authorization": f"Bearer {login_response['access_token']}",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        with self.assertRaises(urllib.error.HTTPError) as invalid_count_error:
            urllib.request.urlopen(invalid_count_request)

        self.assertEqual(invalid_count_error.exception.code, 400)
        self.assertIn(
            "Occurrence count must be at least 1.",
            json_loads(invalid_count_error.exception.read())["message"],
        )

    def test_schedule_creation_rejects_excessive_occurrence_count(self) -> None:
        login_response = self.post_json(
            "/auth/login",
            {
                "email": server.ADMIN_EMAIL,
                "password": server.ADMIN_PASSWORD,
            },
        )
        self.post_json_with_auth(
            "/gyms",
            {
                "name": "Recurring Limit Gym",
                "logo_url": "https://example.com/recurring-limit.png",
                "timezone": "Europe/Berlin",
            },
            access_token=login_response["access_token"],
        )

        request = urllib.request.Request(
            f"{self.base_url}/schedule/classes",
            data=json_bytes(
                {
                    "title": "Too Many Classes",
                    "class_type": "WOD",
                    "start_time": server.isoformat(server.now_utc() + timedelta(days=1)),
                    "capacity": 12,
                    "duration_minutes": 60,
                    "recurrence_frequency": "daily",
                    "occurrence_count": 366,
                }
            ),
            headers={
                "Authorization": f"Bearer {login_response['access_token']}",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        with self.assertRaises(urllib.error.HTTPError) as error_context:
            urllib.request.urlopen(request)

        self.assertEqual(error_context.exception.code, 400)
        self.assertIn(
            "Occurrence count must be 365 or fewer.",
            json_loads(error_context.exception.read())["message"],
        )

    def test_schedule_creation_rejects_excessive_weekly_occurrence_count(self) -> None:
        login_response = self.post_json(
            "/auth/login",
            {
                "email": server.ADMIN_EMAIL,
                "password": server.ADMIN_PASSWORD,
            },
        )
        self.post_json_with_auth(
            "/gyms",
            {
                "name": "Recurring Weekly Limit Gym",
                "logo_url": "https://example.com/recurring-weekly-limit.png",
                "timezone": "Europe/Berlin",
            },
            access_token=login_response["access_token"],
        )

        request = urllib.request.Request(
            f"{self.base_url}/schedule/classes",
            data=json_bytes(
                {
                    "title": "Too Many Weekly Classes",
                    "class_type": "WOD",
                    "start_time": server.isoformat(server.now_utc() + timedelta(days=1)),
                    "capacity": 12,
                    "duration_minutes": 60,
                    "recurrence_frequency": "weekly",
                    "occurrence_count": 54,
                }
            ),
            headers={
                "Authorization": f"Bearer {login_response['access_token']}",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        with self.assertRaises(urllib.error.HTTPError) as error_context:
            urllib.request.urlopen(request)

        self.assertEqual(error_context.exception.code, 400)
        self.assertIn(
            "Occurrence count must be 53 or fewer for weekly recurrence.",
            json_loads(error_context.exception.read())["message"],
        )

    def test_schedule_creation_rejects_excessive_monthly_occurrence_count(self) -> None:
        login_response = self.post_json(
            "/auth/login",
            {
                "email": server.ADMIN_EMAIL,
                "password": server.ADMIN_PASSWORD,
            },
        )
        self.post_json_with_auth(
            "/gyms",
            {
                "name": "Recurring Monthly Limit Gym",
                "logo_url": "https://example.com/recurring-monthly-limit.png",
                "timezone": "Europe/Berlin",
            },
            access_token=login_response["access_token"],
        )

        request = urllib.request.Request(
            f"{self.base_url}/schedule/classes",
            data=json_bytes(
                {
                    "title": "Too Many Monthly Classes",
                    "class_type": "WOD",
                    "start_time": server.isoformat(server.now_utc() + timedelta(days=1)),
                    "capacity": 12,
                    "duration_minutes": 60,
                    "recurrence_frequency": "monthly",
                    "occurrence_count": 15,
                }
            ),
            headers={
                "Authorization": f"Bearer {login_response['access_token']}",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        with self.assertRaises(urllib.error.HTTPError) as error_context:
            urllib.request.urlopen(request)

        self.assertEqual(error_context.exception.code, 400)
        self.assertIn(
            "Occurrence count must be 14 or fewer for monthly recurrence.",
            json_loads(error_context.exception.read())["message"],
        )

    def test_recurring_schedule_creation_writes_audit_log_for_each_created_class(self) -> None:
        login_response = self.post_json(
            "/auth/login",
            {
                "email": server.ADMIN_EMAIL,
                "password": server.ADMIN_PASSWORD,
            },
        )
        self.post_json_with_auth(
            "/gyms",
            {
                "name": "Recurring Audit Gym",
                "logo_url": "https://example.com/recurring-audit.png",
                "timezone": "Europe/Berlin",
            },
            access_token=login_response["access_token"],
        )
        start_time = server.now_utc() + timedelta(days=1)
        created = self.post_json_with_auth(
            "/schedule/classes",
            {
                "title": "Audit WOD",
                "class_type": "WOD",
                "start_time": server.isoformat(start_time),
                "capacity": 12,
                "duration_minutes": 60,
                "recurrence_frequency": "daily",
                "occurrence_count": 3,
            },
            access_token=login_response["access_token"],
        )

        audit_logs = self.get_json_with_auth(
            "/audit-logs",
            access_token=login_response["access_token"],
        )
        created_logs = [
            entry
            for entry in audit_logs["logs"]
            if entry["action"] == "schedule_class_created"
        ]

        self.assertEqual(len(created_logs), 3)
        self.assertEqual(
            {entry["entity_id"] for entry in created_logs},
            {schedule_class["id"] for schedule_class in created["classes"]},
        )
        self.assertEqual(
            {entry["details"]["start_time"] for entry in created_logs},
            {
                server.isoformat(start_time + timedelta(days=offset))
                for offset in range(3)
            },
        )
        self.assertTrue(
            all(
                entry["details"]["recurrence_frequency"] == "daily"
                for entry in created_logs
            )
        )
        self.assertTrue(
            all(entry["details"]["occurrence_count"] == 3 for entry in created_logs)
        )

    def test_admin_can_create_single_schedule_class_without_recurrence_fields(self) -> None:
        login_response = self.post_json(
            "/auth/login",
            {
                "email": server.ADMIN_EMAIL,
                "password": server.ADMIN_PASSWORD,
            },
        )
        self.post_json_with_auth(
            "/gyms",
            {
                "name": "Single Create Gym",
                "logo_url": "https://example.com/single-create.png",
                "timezone": "Europe/Berlin",
            },
            access_token=login_response["access_token"],
        )
        base_time = server.now_utc()
        start_time = base_time + timedelta(seconds=1)
        original_now_utc = server.now_utc
        original_require_future_datetime = server.require_future_datetime
        call_count = 0

        def fake_now_utc() -> object:
            nonlocal call_count
            call_count += 1
            if call_count == 1:
                return base_time
            return base_time + timedelta(seconds=2)

        def fake_require_future_datetime(value: object, *, label: str) -> object:
            return start_time

        server.now_utc = fake_now_utc
        server.require_future_datetime = fake_require_future_datetime
        try:
            created = self.post_json_with_auth(
                "/schedule/classes",
                {
                    "title": "One-Off WOD",
                    "class_type": "WOD",
                    "start_time": server.isoformat(start_time),
                    "capacity": 12,
                    "duration_minutes": 60,
                },
                access_token=login_response["access_token"],
            )
        finally:
            server.now_utc = original_now_utc
            server.require_future_datetime = original_require_future_datetime

        self.assertEqual(created["class"]["title"], "One-Off WOD")
        self.assertEqual(created["created_count"], 1)
        self.assertEqual(len(created["classes"]), 1)
        self.assertEqual(created["classes"][0]["start_time"], server.isoformat(start_time))

    def test_updating_generated_recurring_class_does_not_mutate_siblings(self) -> None:
        login_response = self.post_json(
            "/auth/login",
            {
                "email": server.ADMIN_EMAIL,
                "password": server.ADMIN_PASSWORD,
            },
        )
        self.post_json_with_auth(
            "/gyms",
            {
                "name": "Recurring Edit Safety Gym",
                "logo_url": "https://example.com/recurring-edit-safety.png",
                "timezone": "Europe/Berlin",
            },
            access_token=login_response["access_token"],
        )
        created = self.post_json_with_auth(
            "/schedule/classes",
            {
                "title": "Edit Safety WOD",
                "class_type": "WOD",
                "start_time": server.isoformat(server.now_utc() + timedelta(days=2)),
                "capacity": 12,
                "duration_minutes": 60,
                "recurrence_frequency": "weekly",
                "occurrence_count": 3,
            },
            access_token=login_response["access_token"],
        )

        second_class = created["classes"][1]
        second_start = server.parse_iso(second_class["start_time"])
        second_end = server.parse_iso(second_class["end_time"])
        updated = self.patch_json(
            "/schedule/classes",
            {
                "id": second_class["id"],
                "title": "Edited Instance Only",
                "class_type": "Open Gym",
                "start_time": server.isoformat(second_start + timedelta(hours=2)),
                "end_time": server.isoformat(second_end + timedelta(hours=2)),
                "capacity": 9,
            },
            access_token=login_response["access_token"],
        )

        listed = self.get_json_with_auth(
            "/schedule/classes",
            access_token=login_response["access_token"],
        )

        self.assertEqual(updated["class"]["id"], second_class["id"])
        self.assertEqual(updated["class"]["title"], "Edited Instance Only")
        self.assertEqual(len(listed["classes"]), 3)
        self.assertEqual(listed["classes"][0]["title"], "Edit Safety WOD")
        self.assertEqual(listed["classes"][0]["class_type"], "WOD")
        self.assertEqual(listed["classes"][1]["title"], "Edited Instance Only")
        self.assertEqual(listed["classes"][1]["class_type"], "Open Gym")
        self.assertEqual(listed["classes"][2]["title"], "Edit Safety WOD")
        self.assertEqual(listed["classes"][2]["class_type"], "WOD")

    def test_deleting_generated_recurring_class_does_not_remove_siblings(self) -> None:
        login_response = self.post_json(
            "/auth/login",
            {
                "email": server.ADMIN_EMAIL,
                "password": server.ADMIN_PASSWORD,
            },
        )
        self.post_json_with_auth(
            "/gyms",
            {
                "name": "Recurring Delete Safety Gym",
                "logo_url": "https://example.com/recurring-delete-safety.png",
                "timezone": "Europe/Berlin",
            },
            access_token=login_response["access_token"],
        )
        created = self.post_json_with_auth(
            "/schedule/classes",
            {
                "title": "Delete Safety WOD",
                "class_type": "WOD",
                "start_time": server.isoformat(server.now_utc() + timedelta(days=2)),
                "capacity": 12,
                "duration_minutes": 60,
                "recurrence_frequency": "weekly",
                "occurrence_count": 3,
            },
            access_token=login_response["access_token"],
        )

        deleted = self.delete_json_with_auth(
            "/schedule/classes",
            {"id": created["classes"][1]["id"]},
            access_token=login_response["access_token"],
        )
        listed = self.get_json_with_auth(
            "/schedule/classes",
            access_token=login_response["access_token"],
        )

        self.assertEqual(deleted["message"], "Schedule class deleted.")
        self.assertEqual(len(listed["classes"]), 2)
        self.assertEqual(
            [schedule_class["id"] for schedule_class in listed["classes"]],
            [created["classes"][0]["id"], created["classes"][2]["id"]],
        )
        self.assertTrue(
            all(schedule_class["title"] == "Delete Safety WOD" for schedule_class in listed["classes"])
        )

    def test_athlete_can_book_and_cancel_future_class(self) -> None:
        admin_login = self.post_json(
            "/auth/login",
            {
                "email": server.ADMIN_EMAIL,
                "password": server.ADMIN_PASSWORD,
            },
        )
        created_gym = self.post_json_with_auth(
            "/gyms",
            {
                "name": "Booking Gym",
                "logo_url": "https://example.com/booking.png",
                "timezone": "Europe/Berlin",
            },
            access_token=admin_login["access_token"],
        )
        start_time = server.now_utc() + timedelta(days=1)
        end_time = start_time + timedelta(hours=1)
        created_class = self.post_json_with_auth(
            "/schedule/classes",
            {
                "title": "Booked WOD",
                "class_type": "WOD",
                "start_time": server.isoformat(start_time),
                "end_time": server.isoformat(end_time),
                "capacity": 12,
            },
            access_token=admin_login["access_token"],
        )

        athlete_login = self.post_json(
            "/auth/login",
            {
                "email": server.DEMO_EMAIL,
                "password": server.DEMO_PASSWORD,
            },
        )
        self.post_json_with_auth(
            "/gyms/join-requests",
            {"gym_id": created_gym["gym"]["id"]},
            access_token=athlete_login["access_token"],
        )
        pending_requests = self.get_json_with_auth(
            "/gyms/join-requests",
            access_token=admin_login["access_token"],
        )
        self.patch_json(
            "/gyms/join-requests",
            {
                "request_id": pending_requests["requests"][0]["id"],
                "decision": "approve",
            },
            access_token=admin_login["access_token"],
        )
        self.patch_json(
            "/profile/active-gym",
            {"gym_id": created_gym["gym"]["id"]},
            access_token=athlete_login["access_token"],
        )

        booked = self.post_json_with_auth(
            "/schedule/bookings",
            {"class_id": created_class["class"]["id"]},
            access_token=athlete_login["access_token"],
        )
        self.assertEqual(booked["message"], "Class booked.")

        listed = self.get_json_with_auth(
            "/schedule/classes",
            access_token=athlete_login["access_token"],
        )
        self.assertEqual(listed["classes"][0]["booked_count"], 1)
        self.assertEqual(listed["classes"][0]["remaining_spots"], 11)
        self.assertTrue(listed["classes"][0]["is_booked"])

        cancelled = self.delete_json_with_auth(
            "/schedule/bookings",
            {"class_id": created_class["class"]["id"]},
            access_token=athlete_login["access_token"],
        )
        self.assertEqual(cancelled["message"], "Booking cancelled.")

        listed_after_cancel = self.get_json_with_auth(
            "/schedule/classes",
            access_token=athlete_login["access_token"],
        )
        self.assertEqual(listed_after_cancel["classes"][0]["booked_count"], 0)
        self.assertEqual(listed_after_cancel["classes"][0]["remaining_spots"], 12)
        self.assertFalse(listed_after_cancel["classes"][0]["is_booked"])

    def test_booking_rejects_duplicates_and_full_classes(self) -> None:
        admin_login = self.post_json(
            "/auth/login",
            {
                "email": server.ADMIN_EMAIL,
                "password": server.ADMIN_PASSWORD,
            },
        )
        created_gym = self.post_json_with_auth(
            "/gyms",
            {
                "name": "Full Booking Gym",
                "logo_url": "https://example.com/full-booking.png",
                "timezone": "Europe/Berlin",
            },
            access_token=admin_login["access_token"],
        )
        start_time = server.now_utc() + timedelta(days=1)
        end_time = start_time + timedelta(hours=1)
        created_class = self.post_json_with_auth(
            "/schedule/classes",
            {
                "title": "Limited Spots",
                "class_type": "WOD",
                "start_time": server.isoformat(start_time),
                "end_time": server.isoformat(end_time),
                "capacity": 1,
            },
            access_token=admin_login["access_token"],
        )

        athlete_login = self.post_json(
            "/auth/login",
            {
                "email": server.DEMO_EMAIL,
                "password": server.DEMO_PASSWORD,
            },
        )
        trainer_login = self.post_json(
            "/auth/login",
            {
                "email": server.TRAINER_EMAIL,
                "password": server.TRAINER_PASSWORD,
            },
        )
        connection = server.get_connection()
        trainer_user = connection.execute(
            "select id from users where email = ?",
            (server.TRAINER_EMAIL,),
        ).fetchone()
        self.assertIsNotNone(trainer_user)
        now = server.now_utc()
        with connection:
            connection.execute(
                """
                insert into gym_memberships (
                  user_id, gym_id, active_role, roles_json, status, created_at, updated_at
                )
                values (?, ?, 'athlete', ?, 'active', ?, ?)
                """,
                (
                    trainer_user["id"],
                    created_gym["gym"]["id"],
                    server.encode_roles(["athlete"]),
                    server.isoformat(now),
                    server.isoformat(now),
                ),
            )
            connection.execute(
                "update users set active_gym_id = ? where id = ?",
                (created_gym["gym"]["id"], trainer_user["id"]),
            )
            server.sync_user_context(connection, trainer_user["id"])
        connection.close()

        self.post_json_with_auth(
            "/gyms/join-requests",
            {"gym_id": created_gym["gym"]["id"]},
            access_token=athlete_login["access_token"],
        )
        pending_requests = self.get_json_with_auth(
            "/gyms/join-requests",
            access_token=admin_login["access_token"],
        )
        self.patch_json(
            "/gyms/join-requests",
            {
                "request_id": pending_requests["requests"][0]["id"],
                "decision": "approve",
            },
            access_token=admin_login["access_token"],
        )
        self.patch_json(
            "/profile/active-gym",
            {"gym_id": created_gym["gym"]["id"]},
            access_token=athlete_login["access_token"],
        )

        self.post_json_with_auth(
            "/schedule/bookings",
            {"class_id": created_class["class"]["id"]},
            access_token=athlete_login["access_token"],
        )

        duplicate_request = urllib.request.Request(
            f"{self.base_url}/schedule/bookings",
            data=json_bytes({"class_id": created_class["class"]["id"]}),
            headers={
                "Authorization": f"Bearer {athlete_login['access_token']}",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        with self.assertRaises(urllib.error.HTTPError) as duplicate_error:
            urllib.request.urlopen(duplicate_request)
        self.assertEqual(duplicate_error.exception.code, 409)

        full_request = urllib.request.Request(
            f"{self.base_url}/schedule/bookings",
            data=json_bytes({"class_id": created_class["class"]["id"]}),
            headers={
                "Authorization": f"Bearer {trainer_login['access_token']}",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        with self.assertRaises(urllib.error.HTTPError) as full_error:
            urllib.request.urlopen(full_request)
        self.assertEqual(full_error.exception.code, 409)

    def test_waitlist_join_for_full_class(self) -> None:
        admin_login = self.post_json(
            "/auth/login",
            {
                "email": server.ADMIN_EMAIL,
                "password": server.ADMIN_PASSWORD,
            },
        )
        created_gym = self.post_json_with_auth(
            "/gyms",
            {
                "name": "Waitlist Gym",
                "logo_url": "https://example.com/waitlist.png",
                "timezone": "Europe/Berlin",
            },
            access_token=admin_login["access_token"],
        )
        start_time = server.now_utc() + timedelta(days=1)
        end_time = start_time + timedelta(hours=1)
        created_class = self.post_json_with_auth(
            "/schedule/classes",
            {
                "title": "Crowded Class",
                "class_type": "WOD",
                "start_time": server.isoformat(start_time),
                "end_time": server.isoformat(end_time),
                "capacity": 1,
            },
            access_token=admin_login["access_token"],
        )

        athlete_login = self.post_json(
            "/auth/login",
            {
                "email": server.DEMO_EMAIL,
                "password": server.DEMO_PASSWORD,
            },
        )
        trainer_login = self.post_json(
            "/auth/login",
            {
                "email": server.TRAINER_EMAIL,
                "password": server.TRAINER_PASSWORD,
            },
        )
        self._add_active_gym_membership(
            email=server.TRAINER_EMAIL,
            gym_id=created_gym["gym"]["id"],
            roles=["athlete"],
        )
        self._approve_demo_user_for_gym(
            admin_token=admin_login["access_token"],
            athlete_token=athlete_login["access_token"],
            gym_id=created_gym["gym"]["id"],
        )

        self.post_json_with_auth(
            "/schedule/bookings",
            {"class_id": created_class["class"]["id"]},
            access_token=athlete_login["access_token"],
        )

        joined = self.post_json_with_auth(
            "/schedule/waitlist",
            {"class_id": created_class["class"]["id"]},
            access_token=trainer_login["access_token"],
        )
        self.assertEqual(joined["message"], "Added to waitlist.")

        listed = self.get_json_with_auth(
            "/schedule/classes",
            access_token=trainer_login["access_token"],
        )
        self.assertEqual(listed["classes"][0]["waitlist_count"], 1)
        self.assertTrue(listed["classes"][0]["is_waitlisted"])

        duplicate_request = urllib.request.Request(
            f"{self.base_url}/schedule/waitlist",
            data=json_bytes({"class_id": created_class["class"]["id"]}),
            headers={
                "Authorization": f"Bearer {trainer_login['access_token']}",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        with self.assertRaises(urllib.error.HTTPError) as duplicate_error:
            urllib.request.urlopen(duplicate_request)
        self.assertEqual(duplicate_error.exception.code, 409)

    def test_schedule_payload_includes_waitlist_state(self) -> None:
        admin_login = self.post_json(
            "/auth/login",
            {
                "email": server.ADMIN_EMAIL,
                "password": server.ADMIN_PASSWORD,
            },
        )
        created_gym = self.post_json_with_auth(
            "/gyms",
            {
                "name": "Waitlist Payload Gym",
                "logo_url": "https://example.com/waitlist-payload.png",
                "timezone": "Europe/Berlin",
            },
            access_token=admin_login["access_token"],
        )
        start_time = server.now_utc() + timedelta(days=1)
        end_time = start_time + timedelta(hours=1)
        created_class = self.post_json_with_auth(
            "/schedule/classes",
            {
                "title": "Payload Class",
                "class_type": "WOD",
                "start_time": server.isoformat(start_time),
                "end_time": server.isoformat(end_time),
                "capacity": 1,
            },
            access_token=admin_login["access_token"],
        )

        athlete_login = self.post_json(
            "/auth/login",
            {
                "email": server.DEMO_EMAIL,
                "password": server.DEMO_PASSWORD,
            },
        )
        trainer_login = self.post_json(
            "/auth/login",
            {
                "email": server.TRAINER_EMAIL,
                "password": server.TRAINER_PASSWORD,
            },
        )
        self._add_active_gym_membership(
            email=server.TRAINER_EMAIL,
            gym_id=created_gym["gym"]["id"],
            roles=["athlete"],
        )
        self._approve_demo_user_for_gym(
            admin_token=admin_login["access_token"],
            athlete_token=athlete_login["access_token"],
            gym_id=created_gym["gym"]["id"],
        )

        self.post_json_with_auth(
            "/schedule/bookings",
            {"class_id": created_class["class"]["id"]},
            access_token=athlete_login["access_token"],
        )
        self.post_json_with_auth(
            "/schedule/waitlist",
            {"class_id": created_class["class"]["id"]},
            access_token=trainer_login["access_token"],
        )

        trainer_schedule = self.get_json_with_auth(
            "/schedule/classes",
            access_token=trainer_login["access_token"],
        )
        athlete_schedule = self.get_json_with_auth(
            "/schedule/classes",
            access_token=athlete_login["access_token"],
        )

        self.assertEqual(trainer_schedule["classes"][0]["waitlist_count"], 1)
        self.assertTrue(trainer_schedule["classes"][0]["is_waitlisted"])
        self.assertFalse(trainer_schedule["classes"][0]["is_booked"])
        self.assertEqual(athlete_schedule["classes"][0]["waitlist_count"], 1)
        self.assertFalse(athlete_schedule["classes"][0]["is_waitlisted"])
        self.assertTrue(athlete_schedule["classes"][0]["is_booked"])

    def test_cancelling_booking_promotes_next_waitlisted_athlete(self) -> None:
        admin_login = self.post_json(
            "/auth/login",
            {
                "email": server.ADMIN_EMAIL,
                "password": server.ADMIN_PASSWORD,
            },
        )
        created_gym = self.post_json_with_auth(
            "/gyms",
            {
                "name": "Promotion Gym",
                "logo_url": "https://example.com/promotion.png",
                "timezone": "Europe/Berlin",
            },
            access_token=admin_login["access_token"],
        )
        start_time = server.now_utc() + timedelta(days=1)
        end_time = start_time + timedelta(hours=1)
        created_class = self.post_json_with_auth(
            "/schedule/classes",
            {
                "title": "Promotion Class",
                "class_type": "WOD",
                "start_time": server.isoformat(start_time),
                "end_time": server.isoformat(end_time),
                "capacity": 1,
            },
            access_token=admin_login["access_token"],
        )

        athlete_login = self.post_json(
            "/auth/login",
            {
                "email": server.DEMO_EMAIL,
                "password": server.DEMO_PASSWORD,
            },
        )
        trainer_login = self.post_json(
            "/auth/login",
            {
                "email": server.TRAINER_EMAIL,
                "password": server.TRAINER_PASSWORD,
            },
        )
        self._add_active_gym_membership(
            email=server.TRAINER_EMAIL,
            gym_id=created_gym["gym"]["id"],
            roles=["athlete"],
        )
        self._approve_demo_user_for_gym(
            admin_token=admin_login["access_token"],
            athlete_token=athlete_login["access_token"],
            gym_id=created_gym["gym"]["id"],
        )

        self.post_json_with_auth(
            "/schedule/bookings",
            {"class_id": created_class["class"]["id"]},
            access_token=athlete_login["access_token"],
        )
        self.post_json_with_auth(
            "/schedule/waitlist",
            {"class_id": created_class["class"]["id"]},
            access_token=trainer_login["access_token"],
        )

        cancelled = self.delete_json_with_auth(
            "/schedule/bookings",
            {"class_id": created_class["class"]["id"]},
            access_token=athlete_login["access_token"],
        )
        self.assertEqual(cancelled["message"], "Booking cancelled.")

        trainer_schedule = self.get_json_with_auth(
            "/schedule/classes",
            access_token=trainer_login["access_token"],
        )
        self.assertTrue(trainer_schedule["classes"][0]["is_booked"])
        self.assertFalse(trainer_schedule["classes"][0]["is_waitlisted"])
        self.assertEqual(trainer_schedule["classes"][0]["waitlist_count"], 0)
        self.assertEqual(trainer_schedule["classes"][0]["booked_count"], 1)

    def test_booking_confirmation_notification(self) -> None:
        admin_login = self.post_json(
            "/auth/login",
            {"email": server.ADMIN_EMAIL, "password": server.ADMIN_PASSWORD},
        )
        created_gym = self.post_json_with_auth(
            "/gyms",
            {
                "name": "Booking Notification Gym",
                "logo_url": "https://example.com/booking-notify.png",
                "timezone": "Europe/Berlin",
            },
            access_token=admin_login["access_token"],
        )
        athlete_login = self.post_json(
            "/auth/login",
            {"email": server.DEMO_EMAIL, "password": server.DEMO_PASSWORD},
        )
        self._approve_demo_user_for_gym(
            admin_token=admin_login["access_token"],
            athlete_token=athlete_login["access_token"],
            gym_id=created_gym["gym"]["id"],
        )
        start_time = server.now_utc() + timedelta(days=1)
        end_time = start_time + timedelta(hours=1)
        created_class = self.post_json_with_auth(
            "/schedule/classes",
            {
                "title": "Notify Me Class",
                "class_type": "WOD",
                "start_time": server.isoformat(start_time),
                "end_time": server.isoformat(end_time),
                "capacity": 12,
            },
            access_token=admin_login["access_token"],
        )

        self.post_json_with_auth(
            "/schedule/bookings",
            {"class_id": created_class["class"]["id"]},
            access_token=athlete_login["access_token"],
        )

        notifications = self.get_json_with_auth(
            "/notifications",
            access_token=athlete_login["access_token"],
        )
        self.assertEqual(notifications["notifications"][0]["type"], "booking_confirmed")
        self.assertIn("Notify Me Class", notifications["notifications"][0]["body"])

    def test_waitlist_promotion_notification(self) -> None:
        admin_login = self.post_json(
            "/auth/login",
            {"email": server.ADMIN_EMAIL, "password": server.ADMIN_PASSWORD},
        )
        created_gym = self.post_json_with_auth(
            "/gyms",
            {
                "name": "Promotion Notification Gym",
                "logo_url": "https://example.com/promotion-notify.png",
                "timezone": "Europe/Berlin",
            },
            access_token=admin_login["access_token"],
        )
        athlete_login = self.post_json(
            "/auth/login",
            {"email": server.DEMO_EMAIL, "password": server.DEMO_PASSWORD},
        )
        trainer_login = self.post_json(
            "/auth/login",
            {"email": server.TRAINER_EMAIL, "password": server.TRAINER_PASSWORD},
        )
        self._add_active_gym_membership(
            email=server.TRAINER_EMAIL,
            gym_id=created_gym["gym"]["id"],
            roles=["athlete"],
        )
        self._approve_demo_user_for_gym(
            admin_token=admin_login["access_token"],
            athlete_token=athlete_login["access_token"],
            gym_id=created_gym["gym"]["id"],
        )
        start_time = server.now_utc() + timedelta(days=1)
        end_time = start_time + timedelta(hours=1)
        created_class = self.post_json_with_auth(
            "/schedule/classes",
            {
                "title": "Promote Me Class",
                "class_type": "WOD",
                "start_time": server.isoformat(start_time),
                "end_time": server.isoformat(end_time),
                "capacity": 1,
            },
            access_token=admin_login["access_token"],
        )
        self.post_json_with_auth(
            "/schedule/bookings",
            {"class_id": created_class["class"]["id"]},
            access_token=athlete_login["access_token"],
        )
        self.post_json_with_auth(
            "/schedule/waitlist",
            {"class_id": created_class["class"]["id"]},
            access_token=trainer_login["access_token"],
        )

        self.delete_json_with_auth(
            "/schedule/bookings",
            {"class_id": created_class["class"]["id"]},
            access_token=athlete_login["access_token"],
        )

        notifications = self.get_json_with_auth(
            "/notifications",
            access_token=trainer_login["access_token"],
        )
        self.assertEqual(notifications["notifications"][0]["type"], "waitlist_promoted")
        self.assertIn("Promote Me Class", notifications["notifications"][0]["body"])

    def test_schedule_update_notifies_affected_athletes(self) -> None:
        admin_login = self.post_json(
            "/auth/login",
            {"email": server.ADMIN_EMAIL, "password": server.ADMIN_PASSWORD},
        )
        created_gym = self.post_json_with_auth(
            "/gyms",
            {
                "name": "Schedule Update Notification Gym",
                "logo_url": "https://example.com/schedule-update.png",
                "timezone": "Europe/Berlin",
            },
            access_token=admin_login["access_token"],
        )
        athlete_login = self.post_json(
            "/auth/login",
            {"email": server.DEMO_EMAIL, "password": server.DEMO_PASSWORD},
        )
        self._approve_demo_user_for_gym(
            admin_token=admin_login["access_token"],
            athlete_token=athlete_login["access_token"],
            gym_id=created_gym["gym"]["id"],
        )
        start_time = server.now_utc() + timedelta(days=1)
        end_time = start_time + timedelta(hours=1)
        created_class = self.post_json_with_auth(
            "/schedule/classes",
            {
                "title": "Changing Class",
                "class_type": "WOD",
                "start_time": server.isoformat(start_time),
                "end_time": server.isoformat(end_time),
                "capacity": 10,
            },
            access_token=admin_login["access_token"],
        )
        self.post_json_with_auth(
            "/schedule/bookings",
            {"class_id": created_class["class"]["id"]},
            access_token=athlete_login["access_token"],
        )

        self.patch_json(
            "/schedule/classes",
            {
                "id": created_class["class"]["id"],
                "title": "Changed Class",
                "class_type": "WOD",
                "start_time": server.isoformat(start_time + timedelta(hours=2)),
                "end_time": server.isoformat(end_time + timedelta(hours=2)),
                "capacity": 10,
            },
            access_token=admin_login["access_token"],
        )

        notifications = self.get_json_with_auth(
            "/notifications",
            access_token=athlete_login["access_token"],
        )
        self.assertEqual(notifications["notifications"][0]["type"], "schedule_updated")
        self.assertIn("Changed Class", notifications["notifications"][0]["body"])

    def test_schedule_capacity_cannot_drop_below_existing_bookings(self) -> None:
        admin_login = self.post_json(
            "/auth/login",
            {
                "email": server.ADMIN_EMAIL,
                "password": server.ADMIN_PASSWORD,
            },
        )
        created_gym = self.post_json_with_auth(
            "/gyms",
            {
                "name": "Capacity Guard Gym",
                "logo_url": "https://example.com/capacity-guard.png",
                "timezone": "Europe/Berlin",
            },
            access_token=admin_login["access_token"],
        )
        start_time = server.now_utc() + timedelta(days=1)
        end_time = start_time + timedelta(hours=1)
        created_class = self.post_json_with_auth(
            "/schedule/classes",
            {
                "title": "Packed Class",
                "class_type": "WOD",
                "start_time": server.isoformat(start_time),
                "end_time": server.isoformat(end_time),
                "capacity": 2,
            },
            access_token=admin_login["access_token"],
        )

        athlete_login = self.post_json(
            "/auth/login",
            {
                "email": server.DEMO_EMAIL,
                "password": server.DEMO_PASSWORD,
            },
        )
        self.post_json_with_auth(
            "/gyms/join-requests",
            {"gym_id": created_gym["gym"]["id"]},
            access_token=athlete_login["access_token"],
        )
        pending_requests = self.get_json_with_auth(
            "/gyms/join-requests",
            access_token=admin_login["access_token"],
        )
        self.patch_json(
            "/gyms/join-requests",
            {
                "request_id": pending_requests["requests"][0]["id"],
                "decision": "approve",
            },
            access_token=admin_login["access_token"],
        )
        self.patch_json(
            "/profile/active-gym",
            {"gym_id": created_gym["gym"]["id"]},
            access_token=athlete_login["access_token"],
        )
        self.post_json_with_auth(
            "/schedule/bookings",
            {"class_id": created_class["class"]["id"]},
            access_token=athlete_login["access_token"],
        )

        shrink_request = urllib.request.Request(
            f"{self.base_url}/schedule/classes",
            data=json_bytes(
                {
                    "id": created_class["class"]["id"],
                    "title": "Packed Class",
                    "class_type": "WOD",
                    "start_time": server.isoformat(start_time),
                    "end_time": server.isoformat(end_time),
                    "capacity": 0,
                }
            ),
            headers={
                "Authorization": f"Bearer {admin_login['access_token']}",
                "Content-Type": "application/json",
            },
            method="PATCH",
        )
        with self.assertRaises(urllib.error.HTTPError) as shrink_error:
            urllib.request.urlopen(shrink_request)
        self.assertEqual(shrink_error.exception.code, 400)

    def test_trainer_can_record_attendance_for_booked_athlete(self) -> None:
        admin_login = self.post_json(
            "/auth/login",
            {
                "email": server.ADMIN_EMAIL,
                "password": server.ADMIN_PASSWORD,
            },
        )
        created_gym = self.post_json_with_auth(
            "/gyms",
            {
                "name": "Attendance Gym",
                "logo_url": "https://example.com/attendance.png",
                "timezone": "Europe/Berlin",
            },
            access_token=admin_login["access_token"],
        )
        athlete_login = self.post_json(
            "/auth/login",
            {
                "email": server.DEMO_EMAIL,
                "password": server.DEMO_PASSWORD,
            },
        )
        trainer_login = self.post_json(
            "/auth/login",
            {
                "email": server.TRAINER_EMAIL,
                "password": server.TRAINER_PASSWORD,
            },
        )
        self.post_json_with_auth(
            "/gyms/join-requests",
            {"gym_id": created_gym["gym"]["id"]},
            access_token=athlete_login["access_token"],
        )
        pending_requests = self.get_json_with_auth(
            "/gyms/join-requests",
            access_token=admin_login["access_token"],
        )
        self.patch_json(
            "/gyms/join-requests",
            {
                "request_id": pending_requests["requests"][0]["id"],
                "decision": "approve",
            },
            access_token=admin_login["access_token"],
        )
        connection = server.get_connection()
        trainer_user = connection.execute(
            "select id from users where email = ?",
            (server.TRAINER_EMAIL,),
        ).fetchone()
        athlete_user = connection.execute(
            "select id from users where email = ?",
            (server.DEMO_EMAIL,),
        ).fetchone()
        self.assertIsNotNone(trainer_user)
        self.assertIsNotNone(athlete_user)
        now = server.now_utc()
        with connection:
            connection.execute(
                """
                insert into gym_memberships (
                  user_id, gym_id, active_role, roles_json, status, created_at, updated_at
                )
                values (?, ?, 'trainer', ?, 'active', ?, ?)
                """,
                (
                    trainer_user["id"],
                    created_gym["gym"]["id"],
                    server.encode_roles(["athlete", "trainer"]),
                    server.isoformat(now),
                    server.isoformat(now),
                ),
            )
            connection.execute(
                "update users set active_gym_id = ? where id = ?",
                (created_gym["gym"]["id"], trainer_user["id"]),
            )
            connection.execute(
                "update users set active_gym_id = ? where id = ?",
                (created_gym["gym"]["id"], athlete_user["id"]),
            )
            server.sync_user_context(connection, trainer_user["id"])
            server.sync_user_context(connection, athlete_user["id"])
            class_cursor = connection.execute(
                """
                insert into class_schedules (
                  gym_id, title, class_type, start_time, end_time, capacity,
                  created_by_user_id, updated_by_user_id, created_at, updated_at
                )
                values (?, 'Past WOD', 'WOD', ?, ?, 12, ?, ?, ?, ?)
                """,
                (
                    created_gym["gym"]["id"],
                    server.isoformat(now - timedelta(hours=2)),
                    server.isoformat(now - timedelta(hours=1)),
                    trainer_user["id"],
                    trainer_user["id"],
                    server.isoformat(now),
                    server.isoformat(now),
                ),
            )
            class_id = int(class_cursor.lastrowid)
            connection.execute(
                """
                insert into class_bookings (
                  class_schedule_id, user_id, attendance_status, created_at
                )
                values (?, ?, 'booked', ?)
                """,
                (class_id, athlete_user["id"], server.isoformat(now - timedelta(hours=3))),
            )
        connection.close()

        updated = self.patch_json(
            "/schedule/bookings/attendance",
            {
                "class_id": class_id,
                "user_id": athlete_user["id"],
                "attendance_status": "attended",
            },
            access_token=trainer_login["access_token"],
        )
        self.assertEqual(updated["class"]["bookings"][0]["attendance_status"], "attended")

        athlete_schedule = self.get_json_with_auth(
            "/schedule/classes",
            access_token=athlete_login["access_token"],
        )
        self.assertEqual(athlete_schedule["classes"][0]["attendance_status"], "attended")

    def test_athlete_cannot_record_attendance(self) -> None:
        admin_login = self.post_json(
            "/auth/login",
            {
                "email": server.ADMIN_EMAIL,
                "password": server.ADMIN_PASSWORD,
            },
        )
        created_gym = self.post_json_with_auth(
            "/gyms",
            {
                "name": "Attendance Guard Gym",
                "logo_url": "https://example.com/attendance-guard.png",
                "timezone": "Europe/Berlin",
            },
            access_token=admin_login["access_token"],
        )
        athlete_login = self.post_json(
            "/auth/login",
            {
                "email": server.DEMO_EMAIL,
                "password": server.DEMO_PASSWORD,
            },
        )
        self.post_json_with_auth(
            "/gyms/join-requests",
            {"gym_id": created_gym["gym"]["id"]},
            access_token=athlete_login["access_token"],
        )
        pending_requests = self.get_json_with_auth(
            "/gyms/join-requests",
            access_token=admin_login["access_token"],
        )
        self.patch_json(
            "/gyms/join-requests",
            {
                "request_id": pending_requests["requests"][0]["id"],
                "decision": "approve",
            },
            access_token=admin_login["access_token"],
        )
        connection = server.get_connection()
        athlete_user = connection.execute(
            "select id from users where email = ?",
            (server.DEMO_EMAIL,),
        ).fetchone()
        self.assertIsNotNone(athlete_user)
        now = server.now_utc()
        with connection:
            connection.execute(
                "update users set active_gym_id = ? where id = ?",
                (created_gym["gym"]["id"], athlete_user["id"]),
            )
            server.sync_user_context(connection, athlete_user["id"])
            class_cursor = connection.execute(
                """
                insert into class_schedules (
                  gym_id, title, class_type, start_time, end_time, capacity,
                  created_by_user_id, updated_by_user_id, created_at, updated_at
                )
                values (?, 'Past Open Gym', 'Open Gym', ?, ?, 12, ?, ?, ?, ?)
                """,
                (
                    created_gym["gym"]["id"],
                    server.isoformat(now - timedelta(hours=2)),
                    server.isoformat(now - timedelta(hours=1)),
                    athlete_user["id"],
                    athlete_user["id"],
                    server.isoformat(now),
                    server.isoformat(now),
                ),
            )
            class_id = int(class_cursor.lastrowid)
            connection.execute(
                """
                insert into class_bookings (
                  class_schedule_id, user_id, attendance_status, created_at
                )
                values (?, ?, 'booked', ?)
                """,
                (class_id, athlete_user["id"], server.isoformat(now - timedelta(hours=3))),
            )
        connection.close()

        request = urllib.request.Request(
            f"{self.base_url}/schedule/bookings/attendance",
            data=json_bytes(
                {
                    "class_id": class_id,
                    "user_id": athlete_user["id"],
                    "attendance_status": "attended",
                }
            ),
            headers={
                "Authorization": f"Bearer {athlete_login['access_token']}",
                "Content-Type": "application/json",
            },
            method="PATCH",
        )
        with self.assertRaises(urllib.error.HTTPError) as error_context:
            urllib.request.urlopen(request)
        self.assertEqual(error_context.exception.code, 403)

    def test_trainer_can_manage_schedule_for_active_gym(self) -> None:
        admin_login = self.post_json(
            "/auth/login",
            {
                "email": server.ADMIN_EMAIL,
                "password": server.ADMIN_PASSWORD,
            },
        )
        created_gym = self.post_json_with_auth(
            "/gyms",
            {
                "name": "Trainer Schedule Gym",
                "logo_url": "https://example.com/trainer-schedule.png",
                "timezone": "Europe/Berlin",
            },
            access_token=admin_login["access_token"],
        )
        connection = server.get_connection()
        trainer_user = connection.execute(
            "select id from users where email = ?",
            (server.TRAINER_EMAIL,),
        ).fetchone()
        self.assertIsNotNone(trainer_user)
        now = server.now_utc()
        with connection:
            connection.execute(
                """
                insert into gym_memberships (
                  user_id, gym_id, active_role, roles_json, status, created_at, updated_at
                )
                values (?, ?, 'trainer', ?, 'active', ?, ?)
                """,
                (
                    trainer_user["id"],
                    created_gym["gym"]["id"],
                    server.encode_roles(["athlete", "trainer"]),
                    server.isoformat(now),
                    server.isoformat(now),
                ),
            )
            connection.execute(
                "update users set active_gym_id = ? where id = ?",
                (created_gym["gym"]["id"], trainer_user["id"]),
            )
            server.sync_user_context(connection, trainer_user["id"])
        connection.close()

        trainer_login = self.post_json(
            "/auth/login",
            {
                "email": server.TRAINER_EMAIL,
                "password": server.TRAINER_PASSWORD,
            },
        )
        start_time = server.now_utc() + timedelta(days=2)
        end_time = start_time + timedelta(hours=1)
        created = self.post_json_with_auth(
            "/schedule/classes",
            {
                "title": "Trainer Class",
                "class_type": "Specialty",
                "start_time": server.isoformat(start_time),
                "end_time": server.isoformat(end_time),
                "capacity": 10,
            },
            access_token=trainer_login["access_token"],
        )
        self.assertEqual(created["class"]["class_type"], "Specialty")

    def test_trainer_cannot_list_join_requests(self) -> None:
        admin_login = self.post_json(
            "/auth/login",
            {"email": server.ADMIN_EMAIL, "password": server.ADMIN_PASSWORD},
        )
        created_gym = self.post_json_with_auth(
            "/gyms",
            {
                "name": "Trainer Join Request Gym",
                "logo_url": "https://example.com/trainer-join.png",
                "timezone": "Europe/Berlin",
            },
            access_token=admin_login["access_token"],
        )
        connection = server.get_connection()
        trainer_user = connection.execute(
            "select id from users where email = ?",
            (server.TRAINER_EMAIL,),
        ).fetchone()
        self.assertIsNotNone(trainer_user)
        now = server.now_utc()
        with connection:
            connection.execute(
                """
                insert into gym_memberships (
                  user_id, gym_id, active_role, roles_json, status, created_at, updated_at
                )
                values (?, ?, 'trainer', ?, 'active', ?, ?)
                """,
                (
                    trainer_user["id"],
                    created_gym["gym"]["id"],
                    server.encode_roles(["athlete", "trainer"]),
                    server.isoformat(now),
                    server.isoformat(now),
                ),
            )
            connection.execute(
                "update users set active_gym_id = ? where id = ?",
                (created_gym["gym"]["id"], trainer_user["id"]),
            )
            server.sync_user_context(connection, trainer_user["id"])
        connection.close()

        trainer_login = self.post_json(
            "/auth/login",
            {"email": server.TRAINER_EMAIL, "password": server.TRAINER_PASSWORD},
        )
        request = urllib.request.Request(
            f"{self.base_url}/gyms/join-requests",
            headers={"Authorization": f"Bearer {trainer_login['access_token']}"},
            method="GET",
        )
        with self.assertRaises(urllib.error.HTTPError) as error_context:
            urllib.request.urlopen(request)

        self.assertEqual(error_context.exception.code, 403)

    def test_trainer_cannot_view_audit_logs(self) -> None:
        admin_login = self.post_json(
            "/auth/login",
            {"email": server.ADMIN_EMAIL, "password": server.ADMIN_PASSWORD},
        )
        created_gym = self.post_json_with_auth(
            "/gyms",
            {
                "name": "Trainer Audit Gym",
                "logo_url": "https://example.com/trainer-audit.png",
                "timezone": "Europe/Berlin",
            },
            access_token=admin_login["access_token"],
        )
        connection = server.get_connection()
        trainer_user = connection.execute(
            "select id from users where email = ?",
            (server.TRAINER_EMAIL,),
        ).fetchone()
        self.assertIsNotNone(trainer_user)
        now = server.now_utc()
        with connection:
            connection.execute(
                """
                insert into gym_memberships (
                  user_id, gym_id, active_role, roles_json, status, created_at, updated_at
                )
                values (?, ?, 'trainer', ?, 'active', ?, ?)
                """,
                (
                    trainer_user["id"],
                    created_gym["gym"]["id"],
                    server.encode_roles(["athlete", "trainer"]),
                    server.isoformat(now),
                    server.isoformat(now),
                ),
            )
            connection.execute(
                "update users set active_gym_id = ? where id = ?",
                (created_gym["gym"]["id"], trainer_user["id"]),
            )
            server.sync_user_context(connection, trainer_user["id"])
        connection.close()

        trainer_login = self.post_json(
            "/auth/login",
            {"email": server.TRAINER_EMAIL, "password": server.TRAINER_PASSWORD},
        )
        request = urllib.request.Request(
            f"{self.base_url}/audit-logs",
            headers={"Authorization": f"Bearer {trainer_login['access_token']}"},
            method="GET",
        )
        with self.assertRaises(urllib.error.HTTPError) as error_context:
            urllib.request.urlopen(request)

        self.assertEqual(error_context.exception.code, 403)

    def test_trainer_cannot_list_role_management_users(self) -> None:
        admin_login = self.post_json(
            "/auth/login",
            {"email": server.ADMIN_EMAIL, "password": server.ADMIN_PASSWORD},
        )
        created_gym = self.post_json_with_auth(
            "/gyms",
            {
                "name": "Trainer Role List Gym",
                "logo_url": "https://example.com/trainer-role-list.png",
                "timezone": "Europe/Berlin",
            },
            access_token=admin_login["access_token"],
        )
        connection = server.get_connection()
        trainer_user = connection.execute(
            "select id from users where email = ?",
            (server.TRAINER_EMAIL,),
        ).fetchone()
        self.assertIsNotNone(trainer_user)
        now = server.now_utc()
        with connection:
            connection.execute(
                """
                insert into gym_memberships (
                  user_id, gym_id, active_role, roles_json, status, created_at, updated_at
                )
                values (?, ?, 'trainer', ?, 'active', ?, ?)
                """,
                (
                    trainer_user["id"],
                    created_gym["gym"]["id"],
                    server.encode_roles(["athlete", "trainer"]),
                    server.isoformat(now),
                    server.isoformat(now),
                ),
            )
            connection.execute(
                "update users set active_gym_id = ? where id = ?",
                (created_gym["gym"]["id"], trainer_user["id"]),
            )
            server.sync_user_context(connection, trainer_user["id"])
        connection.close()

        trainer_login = self.post_json(
            "/auth/login",
            {"email": server.TRAINER_EMAIL, "password": server.TRAINER_PASSWORD},
        )
        request = urllib.request.Request(
            f"{self.base_url}/roles/users",
            headers={"Authorization": f"Bearer {trainer_login['access_token']}"},
            method="GET",
        )
        with self.assertRaises(urllib.error.HTTPError) as error_context:
            urllib.request.urlopen(request)

        self.assertEqual(error_context.exception.code, 403)

    def test_trainer_cannot_assign_roles(self) -> None:
        admin_login = self.post_json(
            "/auth/login",
            {"email": server.ADMIN_EMAIL, "password": server.ADMIN_PASSWORD},
        )
        created_gym = self.post_json_with_auth(
            "/gyms",
            {
                "name": "Trainer Role Assign Gym",
                "logo_url": "https://example.com/trainer-role-assign.png",
                "timezone": "Europe/Berlin",
            },
            access_token=admin_login["access_token"],
        )
        athlete_login = self.post_json(
            "/auth/login",
            {"email": server.DEMO_EMAIL, "password": server.DEMO_PASSWORD},
        )
        self.post_json_with_auth(
            "/gyms/join-requests",
            {"gym_id": created_gym["gym"]["id"]},
            access_token=athlete_login["access_token"],
        )
        pending_requests = self.get_json_with_auth(
            "/gyms/join-requests",
            access_token=admin_login["access_token"],
        )
        self.patch_json(
            "/gyms/join-requests",
            {"request_id": pending_requests["requests"][0]["id"], "decision": "approve"},
            access_token=admin_login["access_token"],
        )
        connection = server.get_connection()
        trainer_user = connection.execute(
            "select id from users where email = ?",
            (server.TRAINER_EMAIL,),
        ).fetchone()
        athlete_user = connection.execute(
            "select id from users where email = ?",
            (server.DEMO_EMAIL,),
        ).fetchone()
        self.assertIsNotNone(trainer_user)
        self.assertIsNotNone(athlete_user)
        now = server.now_utc()
        with connection:
            connection.execute(
                """
                insert into gym_memberships (
                  user_id, gym_id, active_role, roles_json, status, created_at, updated_at
                )
                values (?, ?, 'trainer', ?, 'active', ?, ?)
                """,
                (
                    trainer_user["id"],
                    created_gym["gym"]["id"],
                    server.encode_roles(["athlete", "trainer"]),
                    server.isoformat(now),
                    server.isoformat(now),
                ),
            )
            connection.execute(
                "update users set active_gym_id = ? where id = ?",
                (created_gym["gym"]["id"], trainer_user["id"]),
            )
            server.sync_user_context(connection, trainer_user["id"])
        connection.close()

        trainer_login = self.post_json(
            "/auth/login",
            {"email": server.TRAINER_EMAIL, "password": server.TRAINER_PASSWORD},
        )
        request = urllib.request.Request(
            f"{self.base_url}/roles/users",
            data=json_bytes({"user_id": athlete_user["id"], "roles": ["athlete", "trainer"]}),
            headers={
                "Authorization": f"Bearer {trainer_login['access_token']}",
                "Content-Type": "application/json",
            },
            method="PATCH",
        )
        with self.assertRaises(urllib.error.HTTPError) as error_context:
            urllib.request.urlopen(request)

        self.assertEqual(error_context.exception.code, 403)

    def test_admin_can_create_and_update_daily_workout(self) -> None:
        admin_login = self.post_json(
            "/auth/login",
            {
                "email": server.ADMIN_EMAIL,
                "password": server.ADMIN_PASSWORD,
            },
        )
        self.post_json_with_auth(
            "/gyms",
            {
                "name": "Programming Gym",
                "logo_url": "https://example.com/programming.png",
                "timezone": "Europe/Berlin",
            },
            access_token=admin_login["access_token"],
        )

        scheduled_date = (server.now_utc() + timedelta(days=1)).date().isoformat()
        created = self.post_json_with_auth(
            "/programming/workouts",
            {
                "scheduled_date": scheduled_date,
                "title": "Tuesday WOD",
                "strength_text": "Back squat 5x5",
                "metcon_text": "12 min AMRAP: 10 burpees, 15 air squats",
                "notes_text": "Scale reps for beginners.",
            },
            access_token=admin_login["access_token"],
        )
        self.assertEqual(created["workout"]["title"], "Tuesday WOD")
        self.assertEqual(created["workout"]["scheduled_date"], scheduled_date)

        updated = self.patch_json(
            "/programming/workouts",
            {
                "id": created["workout"]["id"],
                "scheduled_date": scheduled_date,
                "title": "Tuesday Engine",
                "strength_text": "Back squat 6x3",
                "metcon_text": "15 min AMRAP: 12 cals, 12 wall balls",
                "notes_text": "Push the final 5 minutes.",
            },
            access_token=admin_login["access_token"],
        )
        self.assertEqual(updated["workout"]["title"], "Tuesday Engine")
        self.assertEqual(updated["workout"]["strength_text"], "Back squat 6x3")

        audit_logs = self.get_json_with_auth(
            "/audit-logs",
            access_token=admin_login["access_token"],
        )
        actions = [entry["action"] for entry in audit_logs["logs"][:2]]
        self.assertEqual(actions, ["daily_workout_updated", "daily_workout_created"])

    def test_active_gym_members_can_list_daily_workouts(self) -> None:
        admin_login = self.post_json(
            "/auth/login",
            {
                "email": server.ADMIN_EMAIL,
                "password": server.ADMIN_PASSWORD,
            },
        )
        created_gym = self.post_json_with_auth(
            "/gyms",
            {
                "name": "Athlete Programming Gym",
                "logo_url": "https://example.com/athlete-programming.png",
                "timezone": "Europe/Berlin",
            },
            access_token=admin_login["access_token"],
        )
        scheduled_date = (server.now_utc() + timedelta(days=2)).date().isoformat()
        self.post_json_with_auth(
            "/programming/workouts",
            {
                "scheduled_date": scheduled_date,
                "title": "Wednesday Grind",
                "strength_text": "Strict press 5x5",
                "metcon_text": "For time: 21-15-9 deadlifts and hand-release push-ups",
                "notes_text": "Stimulus is steady pace.",
            },
            access_token=admin_login["access_token"],
        )

        athlete_login = self.post_json(
            "/auth/login",
            {
                "email": server.DEMO_EMAIL,
                "password": server.DEMO_PASSWORD,
            },
        )
        self.post_json_with_auth(
            "/gyms/join-requests",
            {"gym_id": created_gym["gym"]["id"]},
            access_token=athlete_login["access_token"],
        )
        pending_requests = self.get_json_with_auth(
            "/gyms/join-requests",
            access_token=admin_login["access_token"],
        )
        self.patch_json(
            "/gyms/join-requests",
            {
                "request_id": pending_requests["requests"][0]["id"],
                "decision": "approve",
            },
            access_token=admin_login["access_token"],
        )
        self.patch_json(
            "/profile/active-gym",
            {"gym_id": created_gym["gym"]["id"]},
            access_token=athlete_login["access_token"],
        )

        listed = self.get_json_with_auth(
            "/programming/workouts",
            access_token=athlete_login["access_token"],
        )
        self.assertEqual(len(listed["workouts"]), 1)
        self.assertEqual(listed["workouts"][0]["title"], "Wednesday Grind")
        self.assertFalse(listed["workouts"][0]["can_edit"])

    def test_athlete_cannot_manage_daily_workouts(self) -> None:
        admin_login = self.post_json(
            "/auth/login",
            {
                "email": server.ADMIN_EMAIL,
                "password": server.ADMIN_PASSWORD,
            },
        )
        created_gym = self.post_json_with_auth(
            "/gyms",
            {
                "name": "Blocked Programming Gym",
                "logo_url": "https://example.com/blocked-programming.png",
                "timezone": "Europe/Berlin",
            },
            access_token=admin_login["access_token"],
        )
        athlete_login = self.post_json(
            "/auth/login",
            {
                "email": server.DEMO_EMAIL,
                "password": server.DEMO_PASSWORD,
            },
        )
        self.post_json_with_auth(
            "/gyms/join-requests",
            {"gym_id": created_gym["gym"]["id"]},
            access_token=athlete_login["access_token"],
        )
        pending_requests = self.get_json_with_auth(
            "/gyms/join-requests",
            access_token=admin_login["access_token"],
        )
        self.patch_json(
            "/gyms/join-requests",
            {
                "request_id": pending_requests["requests"][0]["id"],
                "decision": "approve",
            },
            access_token=admin_login["access_token"],
        )
        self.patch_json(
            "/profile/active-gym",
            {"gym_id": created_gym["gym"]["id"]},
            access_token=athlete_login["access_token"],
        )

        request = urllib.request.Request(
            f"{self.base_url}/programming/workouts",
            data=json_bytes(
                {
                    "scheduled_date": (server.now_utc() + timedelta(days=1)).date().isoformat(),
                    "title": "Blocked Workout",
                    "strength_text": "",
                    "metcon_text": "Run 400m",
                    "notes_text": "",
                }
            ),
            headers={
                "Authorization": f"Bearer {athlete_login['access_token']}",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        with self.assertRaises(urllib.error.HTTPError) as error_context:
            urllib.request.urlopen(request)

        self.assertEqual(error_context.exception.code, 403)

    def test_active_gym_member_can_submit_whiteboard_result(self) -> None:
        admin_login = self.post_json(
            "/auth/login",
            {
                "email": server.ADMIN_EMAIL,
                "password": server.ADMIN_PASSWORD,
            },
        )
        created_gym = self.post_json_with_auth(
            "/gyms",
            {
                "name": "Whiteboard Gym",
                "logo_url": "https://example.com/whiteboard.png",
                "timezone": "Europe/Berlin",
            },
            access_token=admin_login["access_token"],
        )
        scheduled_date = server.now_utc().date().isoformat()
        created_workout = self.post_json_with_auth(
            "/programming/workouts",
            {
                "scheduled_date": scheduled_date,
                "title": "Friday Sprint",
                "strength_text": "",
                "metcon_text": "For time: 30-20-10 wall balls and burpees",
                "notes_text": "",
            },
            access_token=admin_login["access_token"],
        )

        athlete_login = self.post_json(
            "/auth/login",
            {
                "email": server.DEMO_EMAIL,
                "password": server.DEMO_PASSWORD,
            },
        )
        self.post_json_with_auth(
            "/gyms/join-requests",
            {"gym_id": created_gym["gym"]["id"]},
            access_token=athlete_login["access_token"],
        )
        pending_requests = self.get_json_with_auth(
            "/gyms/join-requests",
            access_token=admin_login["access_token"],
        )
        self.patch_json(
            "/gyms/join-requests",
            {
                "request_id": pending_requests["requests"][0]["id"],
                "decision": "approve",
            },
            access_token=admin_login["access_token"],
        )
        self.patch_json(
            "/profile/active-gym",
            {"gym_id": created_gym["gym"]["id"]},
            access_token=athlete_login["access_token"],
        )

        updated = self.post_json_with_auth(
            "/programming/whiteboard-results",
            {
                "workout_id": created_workout["workout"]["id"],
                "score_type": "time",
                "score_value": "08:41",
                "notes_text": "Unbroken burpees until the final round.",
            },
            access_token=athlete_login["access_token"],
        )

        self.assertEqual(updated["workout"]["my_whiteboard_result"]["score_label"], "08:41")
        self.assertEqual(len(updated["workout"]["whiteboard_results"]), 1)
        self.assertEqual(updated["workout"]["whiteboard_results"][0]["athlete_name"], "Demo Athlete")

        audit_logs = self.get_json_with_auth(
            "/audit-logs",
            access_token=admin_login["access_token"],
        )
        self.assertEqual(audit_logs["logs"][0]["action"], "whiteboard_result_created")
        self.assertEqual(audit_logs["logs"][0]["details"]["score_label"], "08:41")

    def test_active_gym_member_can_log_workout_and_list_history(self) -> None:
        admin_login = self.post_json(
            "/auth/login",
            {"email": server.ADMIN_EMAIL, "password": server.ADMIN_PASSWORD},
        )
        created_gym = self.post_json_with_auth(
            "/gyms",
            {
                "name": "Logbook Gym",
                "logo_url": "https://example.com/logbook.png",
                "timezone": "Europe/Berlin",
            },
            access_token=admin_login["access_token"],
        )
        scheduled_date = server.now_utc().date().isoformat()
        created_workout = self.post_json_with_auth(
            "/programming/workouts",
            {
                "scheduled_date": scheduled_date,
                "title": "Sunday Hero",
                "strength_text": "",
                "metcon_text": "For time: 21-15-9 thrusters and pull-ups",
                "notes_text": "",
            },
            access_token=admin_login["access_token"],
        )
        athlete_login = self.post_json(
            "/auth/login",
            {"email": server.DEMO_EMAIL, "password": server.DEMO_PASSWORD},
        )
        self.post_json_with_auth(
            "/gyms/join-requests",
            {"gym_id": created_gym["gym"]["id"]},
            access_token=athlete_login["access_token"],
        )
        pending_requests = self.get_json_with_auth(
            "/gyms/join-requests",
            access_token=admin_login["access_token"],
        )
        self.patch_json(
            "/gyms/join-requests",
            {"request_id": pending_requests["requests"][0]["id"], "decision": "approve"},
            access_token=admin_login["access_token"],
        )
        self.patch_json(
            "/profile/active-gym",
            {"gym_id": created_gym["gym"]["id"]},
            access_token=athlete_login["access_token"],
        )

        created_entry = self.post_json_with_auth(
            "/logbook/entries",
            {
                "workout_id": created_workout["workout"]["id"],
                "score_type": "time",
                "score_value": "07:32",
                "notes_text": "Scaled pull-ups with band.",
            },
            access_token=athlete_login["access_token"],
        )
        self.assertEqual(created_entry["entry"]["score_label"], "07:32")
        self.assertEqual(created_entry["entry"]["workout_title"], "Sunday Hero")

        listed = self.get_json_with_auth(
            "/logbook/entries",
            access_token=athlete_login["access_token"],
        )
        self.assertEqual(len(listed["entries"]), 1)
        self.assertEqual(listed["entries"][0]["notes_text"], "Scaled pull-ups with band.")

        audit_logs = self.get_json_with_auth(
            "/audit-logs",
            access_token=admin_login["access_token"],
        )
        self.assertEqual(audit_logs["logs"][0]["action"], "workout_log_created")

    def test_workout_log_pr_detection_marks_best_benchmark_result(self) -> None:
        admin_login = self.post_json(
            "/auth/login",
            {"email": server.ADMIN_EMAIL, "password": server.ADMIN_PASSWORD},
        )
        created_gym = self.post_json_with_auth(
            "/gyms",
            {
                "name": "PR Gym",
                "logo_url": "https://example.com/pr.png",
                "timezone": "Europe/Berlin",
            },
            access_token=admin_login["access_token"],
        )
        first_date = server.now_utc().date().isoformat()
        second_date = (server.now_utc() + timedelta(days=1)).date().isoformat()
        first_workout = self.post_json_with_auth(
            "/programming/workouts",
            {
                "scheduled_date": first_date,
                "title": "Fran",
                "strength_text": "",
                "metcon_text": "21-15-9 thrusters and pull-ups",
                "notes_text": "",
            },
            access_token=admin_login["access_token"],
        )
        second_workout = self.post_json_with_auth(
            "/programming/workouts",
            {
                "scheduled_date": second_date,
                "title": "Fran",
                "strength_text": "",
                "metcon_text": "21-15-9 thrusters and pull-ups",
                "notes_text": "",
            },
            access_token=admin_login["access_token"],
        )
        athlete_login = self.post_json(
            "/auth/login",
            {"email": server.DEMO_EMAIL, "password": server.DEMO_PASSWORD},
        )
        self.post_json_with_auth(
            "/gyms/join-requests",
            {"gym_id": created_gym["gym"]["id"]},
            access_token=athlete_login["access_token"],
        )
        pending_requests = self.get_json_with_auth(
            "/gyms/join-requests",
            access_token=admin_login["access_token"],
        )
        self.patch_json(
            "/gyms/join-requests",
            {"request_id": pending_requests["requests"][0]["id"], "decision": "approve"},
            access_token=admin_login["access_token"],
        )
        self.patch_json(
            "/profile/active-gym",
            {"gym_id": created_gym["gym"]["id"]},
            access_token=athlete_login["access_token"],
        )

        first_entry = self.post_json_with_auth(
            "/logbook/entries",
            {
                "workout_id": first_workout["workout"]["id"],
                "score_type": "time",
                "score_value": "08:00",
                "notes_text": "",
            },
            access_token=athlete_login["access_token"],
        )
        second_entry = self.post_json_with_auth(
            "/logbook/entries",
            {
                "workout_id": second_workout["workout"]["id"],
                "score_type": "time",
                "score_value": "07:20",
                "notes_text": "Big improvement.",
            },
            access_token=athlete_login["access_token"],
        )

        self.assertTrue(second_entry["entry"]["is_pr"])
        self.assertEqual(second_entry["entry"]["pr_rank"], 1)

        listed = self.get_json_with_auth(
            "/logbook/entries",
            access_token=athlete_login["access_token"],
        )
        fran_entries = [entry for entry in listed["entries"] if entry["workout_title"] == "Fran"]
        self.assertEqual(len(fran_entries), 2)
        self.assertTrue(fran_entries[0]["is_pr"])
        self.assertEqual(fran_entries[0]["score_label"], "07:20")
        self.assertFalse(fran_entries[1]["is_pr"])
        self.assertEqual(fran_entries[1]["pr_rank"], 2)

    def test_whiteboard_results_are_ranked_for_gym_members(self) -> None:
        admin_login = self.post_json(
            "/auth/login",
            {
                "email": server.ADMIN_EMAIL,
                "password": server.ADMIN_PASSWORD,
            },
        )
        created_gym = self.post_json_with_auth(
            "/gyms",
            {
                "name": "Leaderboard Gym",
                "logo_url": "https://example.com/leaderboard.png",
                "timezone": "Europe/Berlin",
            },
            access_token=admin_login["access_token"],
        )
        scheduled_date = server.now_utc().date().isoformat()
        created_workout = self.post_json_with_auth(
            "/programming/workouts",
            {
                "scheduled_date": scheduled_date,
                "title": "Saturday Chipper",
                "strength_text": "",
                "metcon_text": "Max reps in 12 minutes",
                "notes_text": "",
            },
            access_token=admin_login["access_token"],
        )

        self.post_json(
            "/auth/signup",
            {
                "email": "whiteboard2@boxos.app",
                "password": server.DEMO_PASSWORD,
            },
        )
        self._verify_user_email("whiteboard2@boxos.app")
        second_athlete_login = self.post_json(
            "/auth/login",
            {
                "email": "whiteboard2@boxos.app",
                "password": server.DEMO_PASSWORD,
            },
        )

        for login in (self.post_json(
            "/auth/login",
            {
                "email": server.DEMO_EMAIL,
                "password": server.DEMO_PASSWORD,
            },
        ), second_athlete_login):
            self.post_json_with_auth(
                "/gyms/join-requests",
                {"gym_id": created_gym["gym"]["id"]},
                access_token=login["access_token"],
            )

        pending_requests = self.get_json_with_auth(
            "/gyms/join-requests",
            access_token=admin_login["access_token"],
        )
        for request in pending_requests["requests"]:
            self.patch_json(
                "/gyms/join-requests",
                {"request_id": request["id"], "decision": "approve"},
                access_token=admin_login["access_token"],
            )

        demo_login = self.post_json(
            "/auth/login",
            {
                "email": server.DEMO_EMAIL,
                "password": server.DEMO_PASSWORD,
            },
        )
        for login in (demo_login, second_athlete_login):
            self.patch_json(
                "/profile/active-gym",
                {"gym_id": created_gym["gym"]["id"]},
                access_token=login["access_token"],
            )

        self.post_json_with_auth(
            "/programming/whiteboard-results",
            {
                "workout_id": created_workout["workout"]["id"],
                "score_type": "reps",
                "score_value": 120,
                "notes_text": "",
            },
            access_token=demo_login["access_token"],
        )
        listed = self.post_json_with_auth(
            "/programming/whiteboard-results",
            {
                "workout_id": created_workout["workout"]["id"],
                "score_type": "reps",
                "score_value": 132,
                "notes_text": "Strong finish.",
            },
            access_token=second_athlete_login["access_token"],
        )

        self.assertEqual(len(listed["workout"]["whiteboard_results"]), 2)
        self.assertEqual(listed["workout"]["whiteboard_results"][0]["score_label"], "132")
        self.assertEqual(listed["workout"]["whiteboard_results"][0]["rank"], 1)
        self.assertEqual(listed["workout"]["whiteboard_results"][1]["score_label"], "120")
        self.assertEqual(listed["workout"]["whiteboard_results"][1]["rank"], 2)

    def test_join_request_review_is_audited(self) -> None:
        admin_login = self.post_json(
            "/auth/login",
            {
                "email": server.ADMIN_EMAIL,
                "password": server.ADMIN_PASSWORD,
            },
        )
        created_gym = self.post_json_with_auth(
            "/gyms",
            {
                "name": "Audit Join Request Gym",
                "logo_url": "https://example.com/audit-join.png",
                "timezone": "Europe/Berlin",
            },
            access_token=admin_login["access_token"],
        )
        athlete_login = self.post_json(
            "/auth/login",
            {
                "email": server.DEMO_EMAIL,
                "password": server.DEMO_PASSWORD,
            },
        )
        self.post_json_with_auth(
            "/gyms/join-requests",
            {"gym_id": created_gym["gym"]["id"]},
            access_token=athlete_login["access_token"],
        )
        pending_requests = self.get_json_with_auth(
            "/gyms/join-requests",
            access_token=admin_login["access_token"],
        )

        self.patch_json(
            "/gyms/join-requests",
            {
                "request_id": pending_requests["requests"][0]["id"],
                "decision": "approve",
            },
            access_token=admin_login["access_token"],
        )

        audit_logs = self.get_json_with_auth(
            "/audit-logs",
            access_token=admin_login["access_token"],
        )
        self.assertEqual(audit_logs["logs"][0]["action"], "join_request_reviewed")
        self.assertEqual(audit_logs["logs"][0]["details"]["decision"], "approve")

    def test_athlete_cannot_manage_schedule(self) -> None:
        admin_login = self.post_json(
            "/auth/login",
            {
                "email": server.ADMIN_EMAIL,
                "password": server.ADMIN_PASSWORD,
            },
        )
        created_gym = self.post_json_with_auth(
            "/gyms",
            {
                "name": "Athlete Schedule Gym",
                "logo_url": "https://example.com/athlete-schedule.png",
                "timezone": "Europe/Berlin",
            },
            access_token=admin_login["access_token"],
        )
        athlete_login = self.post_json(
            "/auth/login",
            {
                "email": server.DEMO_EMAIL,
                "password": server.DEMO_PASSWORD,
            },
        )
        self.post_json_with_auth(
            "/gyms/join-requests",
            {"gym_id": created_gym["gym"]["id"]},
            access_token=athlete_login["access_token"],
        )
        requests_request = urllib.request.Request(
            f"{self.base_url}/gyms/join-requests",
            headers={"Authorization": f"Bearer {admin_login['access_token']}"},
            method="GET",
        )
        with urllib.request.urlopen(requests_request) as response:
            pending_payload = json_loads(response.read())
        self.patch_json(
            "/gyms/join-requests",
            {
                "request_id": pending_payload["requests"][0]["id"],
                "decision": "approve",
            },
            access_token=admin_login["access_token"],
        )
        self.patch_json(
            "/profile/active-gym",
            {"gym_id": created_gym["gym"]["id"]},
            access_token=athlete_login["access_token"],
        )

        request = urllib.request.Request(
            f"{self.base_url}/schedule/classes",
            data=json_bytes(
                {
                    "title": "Blocked Class",
                    "class_type": "WOD",
                    "start_time": server.isoformat(server.now_utc() + timedelta(days=1)),
                    "end_time": server.isoformat(server.now_utc() + timedelta(days=1, hours=1)),
                    "capacity": 12,
                }
            ),
            headers={
                "Authorization": f"Bearer {athlete_login['access_token']}",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        with self.assertRaises(urllib.error.HTTPError) as error_context:
            urllib.request.urlopen(request)

        self.assertEqual(error_context.exception.code, 403)

    def test_admin_cannot_change_admin_membership_from_role_management(self) -> None:
        login_response = self.post_json(
            "/auth/login",
            {
                "email": server.ADMIN_EMAIL,
                "password": server.ADMIN_PASSWORD,
            },
        )
        self.post_json_with_auth(
            "/gyms",
            {
                "name": "Locked Admin Gym",
                "logo_url": "https://example.com/locked-admin.png",
                "timezone": "Europe/Berlin",
            },
            access_token=login_response["access_token"],
        )
        connection = server.get_connection()
        admin_user = connection.execute(
            "select id from users where email = ?",
            (server.ADMIN_EMAIL,),
        ).fetchone()
        connection.close()
        self.assertIsNotNone(admin_user)

        request = urllib.request.Request(
            f"{self.base_url}/roles/users",
            data=json_bytes(
                {"user_id": admin_user["id"], "roles": ["athlete", "trainer"]}
            ),
            headers={
                "Authorization": f"Bearer {login_response['access_token']}",
                "Content-Type": "application/json",
            },
            method="PATCH",
        )
        with self.assertRaises(urllib.error.HTTPError) as error_context:
            urllib.request.urlopen(request)

        self.assertEqual(error_context.exception.code, 403)

    def test_account_deletion_soft_deletes_then_purges(self) -> None:
        login_response = self.post_json(
            "/auth/login",
            {
                "email": server.DEMO_EMAIL,
                "password": server.DEMO_PASSWORD,
            },
        )

        delete_request = urllib.request.Request(
            f"{self.base_url}/auth/account",
            data=json_bytes({"current_password": server.DEMO_PASSWORD}),
            headers={
                "Authorization": f"Bearer {login_response['access_token']}",
                "Content-Type": "application/json",
            },
            method="DELETE",
        )
        with urllib.request.urlopen(delete_request) as response:
            delete_payload = json_loads(response.read())

        self.assertIn("scheduled for deletion", delete_payload["message"])

        connection = server.get_connection()
        deleted_user = connection.execute(
            """
            select email, display_name, nickname, deleted_at, purge_after
            from users
            where email like 'deleted_%@deleted.local'
            """
        ).fetchone()
        self.assertIsNotNone(deleted_user)
        self.assertEqual(deleted_user["display_name"], "Deleted User")
        self.assertEqual(deleted_user["nickname"], "")
        self.assertIsNotNone(deleted_user["deleted_at"])
        self.assertIsNotNone(deleted_user["purge_after"])

        with connection:
            connection.execute(
                "update users set purge_after = ? where email = ?",
                (
                    server.isoformat(server.now_utc() - server.timedelta(days=1)),
                    deleted_user["email"],
                ),
            )
            server.purge_deleted_users(connection)

        remaining = connection.execute(
            "select id from users where email = ?",
            (deleted_user["email"],),
        ).fetchone()
        connection.close()
        self.assertIsNone(remaining)

    def test_device_registration_and_logout_cleanup(self) -> None:
        login_response = self.post_json(
            "/auth/login",
            {
                "email": server.DEMO_EMAIL,
                "password": server.DEMO_PASSWORD,
            },
        )

        registered = self.post_json_with_auth(
            "/devices/register",
            {
                "device_token": "device-token-1",
                "platform": "web",
            },
            access_token=login_response["access_token"],
        )
        self.assertEqual(registered["message"], "Device registered.")

        connection = server.get_connection()
        device_row = connection.execute(
            "select user_id, device_token, platform from device_registrations where device_token = ?",
            ("device-token-1",),
        ).fetchone()
        self.assertIsNotNone(device_row)
        self.assertEqual(device_row["platform"], "web")

        delete_request = urllib.request.Request(
            f"{self.base_url}/devices/current",
            data=json_bytes({"device_token": "device-token-1"}),
            headers={
                "Authorization": f"Bearer {login_response['access_token']}",
                "Content-Type": "application/json",
            },
            method="DELETE",
        )
        with urllib.request.urlopen(delete_request) as response:
            payload = json_loads(response.read())

        self.assertEqual(payload["message"], "Device unregistered.")
        device_row_after = connection.execute(
            "select id from device_registrations where device_token = ?",
            ("device-token-1",),
        ).fetchone()
        connection.close()
        self.assertIsNone(device_row_after)

    def test_notification_preferences_fetch_and_update(self) -> None:
        login_response = self.post_json(
            "/auth/login",
            {
                "email": server.DEMO_EMAIL,
                "password": server.DEMO_PASSWORD,
            },
        )

        fetch_request = urllib.request.Request(
            f"{self.base_url}/profile/notifications",
            headers={"Authorization": f"Bearer {login_response['access_token']}"},
            method="GET",
        )
        with urllib.request.urlopen(fetch_request) as response:
            preferences = json_loads(response.read())

        self.assertTrue(preferences["booking_confirmations"])
        self.assertTrue(preferences["wod_posted"])

        updated = self.patch_json(
            "/profile/notifications",
            {
                "booking_confirmations": False,
                "waitlist_promotions": True,
                "payment_issues": True,
                "wod_posted": False,
                "pr_achievements": False,
            },
            access_token=login_response["access_token"],
        )

        self.assertFalse(updated["booking_confirmations"])
        self.assertFalse(updated["wod_posted"])
        self.assertFalse(updated["pr_achievements"])

    def test_workout_post_creates_notifications_for_active_members(self) -> None:
        admin_login = self.post_json(
            "/auth/login",
            {"email": server.ADMIN_EMAIL, "password": server.ADMIN_PASSWORD},
        )
        gym = self.post_json_with_auth(
            "/gyms",
            {
                "name": "Notify Box",
                "logo_url": "https://example.com/notify.png",
                "timezone": "Europe/Berlin",
            },
            access_token=admin_login["access_token"],
        )
        athlete_login = self.post_json(
            "/auth/login",
            {"email": server.DEMO_EMAIL, "password": server.DEMO_PASSWORD},
        )
        self.post_json_with_auth(
            "/gyms/join-requests",
            {"gym_id": gym["gym"]["id"]},
            access_token=athlete_login["access_token"],
        )
        pending_requests = self.get_json_with_auth(
            "/gyms/join-requests",
            access_token=admin_login["access_token"],
        )
        self.patch_json(
            "/gyms/join-requests",
            {"request_id": pending_requests["requests"][0]["id"], "decision": "approve"},
            access_token=admin_login["access_token"],
        )
        self.patch_json(
            "/profile/active-gym",
            {"gym_id": gym["gym"]["id"]},
            access_token=athlete_login["access_token"],
        )

        self.post_json_with_auth(
            "/programming/workouts",
            {
                "scheduled_date": server.now_utc().date().isoformat(),
                "title": "Nancy",
                "strength_text": "",
                "metcon_text": "5 rounds for time",
                "notes_text": "",
            },
            access_token=admin_login["access_token"],
        )

        notifications = self.get_json_with_auth(
            "/notifications",
            access_token=athlete_login["access_token"],
        )

        self.assertEqual(notifications["unread_count"], 1)
        self.assertEqual(notifications["notifications"][0]["type"], "wod_posted")
        self.assertIn("Nancy", notifications["notifications"][0]["body"])

    def test_pr_notification_respects_preferences_and_can_be_marked_read(self) -> None:
        admin_login = self.post_json(
            "/auth/login",
            {"email": server.ADMIN_EMAIL, "password": server.ADMIN_PASSWORD},
        )
        gym = self.post_json_with_auth(
            "/gyms",
            {
                "name": "PR Notify Box",
                "logo_url": "https://example.com/pr-notify.png",
                "timezone": "Europe/Berlin",
            },
            access_token=admin_login["access_token"],
        )
        athlete_login = self.post_json(
            "/auth/login",
            {"email": server.DEMO_EMAIL, "password": server.DEMO_PASSWORD},
        )
        self.post_json_with_auth(
            "/gyms/join-requests",
            {"gym_id": gym["gym"]["id"]},
            access_token=athlete_login["access_token"],
        )
        pending_requests = self.get_json_with_auth(
            "/gyms/join-requests",
            access_token=admin_login["access_token"],
        )
        self.patch_json(
            "/gyms/join-requests",
            {"request_id": pending_requests["requests"][0]["id"], "decision": "approve"},
            access_token=admin_login["access_token"],
        )
        self.patch_json(
            "/profile/active-gym",
            {"gym_id": gym["gym"]["id"]},
            access_token=athlete_login["access_token"],
        )
        workout = self.post_json_with_auth(
            "/programming/workouts",
            {
                "scheduled_date": server.now_utc().date().isoformat(),
                "title": "Grace",
                "strength_text": "",
                "metcon_text": "30 clean and jerks for time",
                "notes_text": "",
            },
            access_token=admin_login["access_token"],
        )
        self.patch_json(
            "/profile/notifications",
            {
                "booking_confirmations": True,
                "waitlist_promotions": True,
                "payment_issues": True,
                "wod_posted": True,
                "pr_achievements": False,
            },
            access_token=athlete_login["access_token"],
        )
        self.post_json_with_auth(
            "/logbook/entries",
            {
                "workout_id": workout["workout"]["id"],
                "score_type": "time",
                "score_value": "03:30",
                "notes_text": "",
            },
            access_token=athlete_login["access_token"],
        )
        notifications_without_pr = self.get_json_with_auth(
            "/notifications",
            access_token=athlete_login["access_token"],
        )
        self.assertEqual(
            [item["type"] for item in notifications_without_pr["notifications"]],
            ["wod_posted"],
        )

        self.patch_json(
            "/profile/notifications",
            {
                "booking_confirmations": True,
                "waitlist_promotions": True,
                "payment_issues": True,
                "wod_posted": True,
                "pr_achievements": True,
            },
            access_token=athlete_login["access_token"],
        )
        next_workout = self.post_json_with_auth(
            "/programming/workouts",
            {
                "scheduled_date": (server.now_utc() + timedelta(days=1)).date().isoformat(),
                "title": "Grace",
                "strength_text": "",
                "metcon_text": "30 clean and jerks for time",
                "notes_text": "",
            },
            access_token=admin_login["access_token"],
        )
        self.post_json_with_auth(
            "/logbook/entries",
            {
                "workout_id": next_workout["workout"]["id"],
                "score_type": "time",
                "score_value": "03:10",
                "notes_text": "",
            },
            access_token=athlete_login["access_token"],
        )
        notifications_with_pr = self.get_json_with_auth(
            "/notifications",
            access_token=athlete_login["access_token"],
        )
        self.assertEqual(notifications_with_pr["unread_count"], 3)
        self.assertEqual(notifications_with_pr["notifications"][0]["type"], "pr_achieved")

        marked = self.patch_json(
            "/notifications/read-all",
            {},
            access_token=athlete_login["access_token"],
        )
        self.assertEqual(marked["unread_count"], 0)
        self.assertIsNotNone(marked["notifications"][0]["read_at"])

    def post_json(self, path: str, payload: dict[str, object]) -> dict[str, object]:
        request = urllib.request.Request(
            f"{self.base_url}{path}",
            data=json_bytes(payload),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(request) as response:
            return json_loads(response.read())

    def post_json_with_auth(
        self,
        path: str,
        payload: dict[str, object],
        *,
        access_token: str,
    ) -> dict[str, object]:
        request = urllib.request.Request(
            f"{self.base_url}{path}",
            data=json_bytes(payload),
            headers={
                "Authorization": f"Bearer {access_token}",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        with urllib.request.urlopen(request) as response:
            return json_loads(response.read())

    def get_json_with_auth(self, path: str, *, access_token: str) -> dict[str, object]:
        request = urllib.request.Request(
            f"{self.base_url}{path}",
            headers={"Authorization": f"Bearer {access_token}"},
            method="GET",
        )
        with urllib.request.urlopen(request) as response:
            return json_loads(response.read())

    def test_schedule_requires_active_gym_context(self) -> None:
        athlete_login = self.post_json(
            "/auth/login",
            {"email": server.DEMO_EMAIL, "password": server.DEMO_PASSWORD},
        )

        request = urllib.request.Request(
            f"{self.base_url}/schedule/classes",
            headers={"Authorization": f"Bearer {athlete_login['access_token']}"},
            method="GET",
        )
        with self.assertRaises(urllib.error.HTTPError) as error_context:
            urllib.request.urlopen(request)

        self.assertEqual(error_context.exception.code, 403)

    def test_athlete_cannot_book_class_from_other_gym(self) -> None:
        admin_login = self.post_json(
            "/auth/login",
            {"email": server.ADMIN_EMAIL, "password": server.ADMIN_PASSWORD},
        )
        gym_one = self.post_json_with_auth(
            "/gyms",
            {
                "name": "Booking Home Gym",
                "logo_url": "https://example.com/booking-home.png",
                "timezone": "Europe/Berlin",
            },
            access_token=admin_login["access_token"],
        )
        gym_two = self.post_json_with_auth(
            "/gyms",
            {
                "name": "Booking Other Gym",
                "logo_url": "https://example.com/booking-other.png",
                "timezone": "Europe/Berlin",
            },
            access_token=admin_login["access_token"],
        )
        self._add_active_gym_membership(
            email=server.DEMO_EMAIL,
            gym_id=gym_one["gym"]["id"],
            roles=["athlete"],
        )

        future_start = server.now_utc() + timedelta(days=2)
        connection = server.get_connection()
        athlete_user = connection.execute(
            "select id from users where email = ?",
            (server.DEMO_EMAIL,),
        ).fetchone()
        self.assertIsNotNone(athlete_user)
        with connection:
            cursor = connection.execute(
                """
                insert into class_schedules (
                  gym_id, title, class_type, start_time, end_time, duration_minutes, capacity,
                  created_by_user_id, updated_by_user_id, created_at, updated_at
                )
                values (?, 'Other Gym Class', 'CrossFit', ?, ?, 60, 12, ?, ?, ?, ?)
                """,
                (
                    gym_two["gym"]["id"],
                    server.isoformat(future_start),
                    server.isoformat(future_start + timedelta(hours=1)),
                    athlete_user["id"],
                    athlete_user["id"],
                    server.isoformat(server.now_utc()),
                    server.isoformat(server.now_utc()),
                ),
            )
            class_id = int(cursor.lastrowid)
        connection.close()

        athlete_login = self.post_json(
            "/auth/login",
            {"email": server.DEMO_EMAIL, "password": server.DEMO_PASSWORD},
        )
        request = urllib.request.Request(
            f"{self.base_url}/schedule/bookings",
            data=json_bytes({"class_id": class_id}),
            headers={
                "Authorization": f"Bearer {athlete_login['access_token']}",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        with self.assertRaises(urllib.error.HTTPError) as error_context:
            urllib.request.urlopen(request)

        self.assertEqual(error_context.exception.code, 404)

    def test_trainer_cannot_record_attendance_for_other_gym_class(self) -> None:
        admin_login = self.post_json(
            "/auth/login",
            {"email": server.ADMIN_EMAIL, "password": server.ADMIN_PASSWORD},
        )
        gym_one = self.post_json_with_auth(
            "/gyms",
            {
                "name": "Attendance Home Gym",
                "logo_url": "https://example.com/attendance-home.png",
                "timezone": "Europe/Berlin",
            },
            access_token=admin_login["access_token"],
        )
        gym_two = self.post_json_with_auth(
            "/gyms",
            {
                "name": "Attendance Other Gym",
                "logo_url": "https://example.com/attendance-other.png",
                "timezone": "Europe/Berlin",
            },
            access_token=admin_login["access_token"],
        )
        self._add_active_gym_membership(
            email=server.TRAINER_EMAIL,
            gym_id=gym_one["gym"]["id"],
            roles=["athlete", "trainer"],
            active_role="trainer",
        )

        connection = server.get_connection()
        trainer_user = connection.execute(
            "select id from users where email = ?",
            (server.TRAINER_EMAIL,),
        ).fetchone()
        athlete_user = connection.execute(
            "select id from users where email = ?",
            (server.DEMO_EMAIL,),
        ).fetchone()
        self.assertIsNotNone(trainer_user)
        self.assertIsNotNone(athlete_user)
        now = server.now_utc()
        with connection:
            connection.execute(
                """
                insert into gym_memberships (
                  user_id, gym_id, active_role, roles_json, status, created_at, updated_at
                )
                values (?, ?, 'athlete', ?, 'active', ?, ?)
                """,
                (
                    athlete_user["id"],
                    gym_two["gym"]["id"],
                    server.encode_roles(["athlete"]),
                    server.isoformat(now),
                    server.isoformat(now),
                ),
            )
            class_cursor = connection.execute(
                """
                insert into class_schedules (
                  gym_id, title, class_type, start_time, end_time, duration_minutes, capacity,
                  created_by_user_id, updated_by_user_id, created_at, updated_at
                )
                values (?, 'Other Attendance Class', 'Open Gym', ?, ?, 60, 12, ?, ?, ?, ?)
                """,
                (
                    gym_two["gym"]["id"],
                    server.isoformat(now - timedelta(hours=2)),
                    server.isoformat(now - timedelta(hours=1)),
                    trainer_user["id"],
                    trainer_user["id"],
                    server.isoformat(now),
                    server.isoformat(now),
                ),
            )
            class_id = int(class_cursor.lastrowid)
            connection.execute(
                """
                insert into class_bookings (
                  class_schedule_id, user_id, attendance_status, created_at
                ) values (?, ?, 'booked', ?)
                """,
                (class_id, athlete_user["id"], server.isoformat(now - timedelta(hours=3))),
            )
        connection.close()

        trainer_login = self.post_json(
            "/auth/login",
            {"email": server.TRAINER_EMAIL, "password": server.TRAINER_PASSWORD},
        )
        request = urllib.request.Request(
            f"{self.base_url}/schedule/bookings/attendance",
            data=json_bytes(
                {
                    "class_id": class_id,
                    "user_id": athlete_user["id"],
                    "attendance_status": "attended",
                }
            ),
            headers={
                "Authorization": f"Bearer {trainer_login['access_token']}",
                "Content-Type": "application/json",
            },
            method="PATCH",
        )
        with self.assertRaises(urllib.error.HTTPError) as error_context:
            urllib.request.urlopen(request)

        self.assertEqual(error_context.exception.code, 404)

    def test_athlete_cannot_submit_whiteboard_result_for_other_gym_workout(self) -> None:
        admin_login = self.post_json(
            "/auth/login",
            {"email": server.ADMIN_EMAIL, "password": server.ADMIN_PASSWORD},
        )
        gym_one = self.post_json_with_auth(
            "/gyms",
            {
                "name": "Whiteboard Home Gym",
                "logo_url": "https://example.com/whiteboard-home.png",
                "timezone": "Europe/Berlin",
            },
            access_token=admin_login["access_token"],
        )
        gym_two = self.post_json_with_auth(
            "/gyms",
            {
                "name": "Whiteboard Other Gym",
                "logo_url": "https://example.com/whiteboard-other.png",
                "timezone": "Europe/Berlin",
            },
            access_token=admin_login["access_token"],
        )
        self._add_active_gym_membership(
            email=server.DEMO_EMAIL,
            gym_id=gym_one["gym"]["id"],
            roles=["athlete"],
        )

        connection = server.get_connection()
        athlete_user = connection.execute(
            "select id from users where email = ?",
            (server.DEMO_EMAIL,),
        ).fetchone()
        self.assertIsNotNone(athlete_user)
        with connection:
            cursor = connection.execute(
                """
                insert into daily_workouts (
                  gym_id, scheduled_date, title, strength_text, metcon_text, notes_text,
                  created_by_user_id, updated_by_user_id, created_at, updated_at
                )
                values (?, ?, 'Other Gym WOD', '', 'Run 5k', '', ?, ?, ?, ?)
                """,
                (
                    gym_two["gym"]["id"],
                    (server.now_utc() - timedelta(days=1)).date().isoformat(),
                    athlete_user["id"],
                    athlete_user["id"],
                    server.isoformat(server.now_utc()),
                    server.isoformat(server.now_utc()),
                ),
            )
            workout_id = int(cursor.lastrowid)
        connection.close()

        athlete_login = self.post_json(
            "/auth/login",
            {"email": server.DEMO_EMAIL, "password": server.DEMO_PASSWORD},
        )
        request = urllib.request.Request(
            f"{self.base_url}/programming/whiteboard",
            data=json_bytes(
                {
                    "workout_id": workout_id,
                    "score_type": "time",
                    "score_value": 1500,
                    "notes_text": "blocked",
                }
            ),
            headers={
                "Authorization": f"Bearer {athlete_login['access_token']}",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        with self.assertRaises(urllib.error.HTTPError) as error_context:
            urllib.request.urlopen(request)

        self.assertEqual(error_context.exception.code, 404)

    def test_athlete_cannot_log_workout_with_other_gym_class_reference(self) -> None:
        admin_login = self.post_json(
            "/auth/login",
            {"email": server.ADMIN_EMAIL, "password": server.ADMIN_PASSWORD},
        )
        gym_one = self.post_json_with_auth(
            "/gyms",
            {
                "name": "Logbook Home Gym",
                "logo_url": "https://example.com/logbook-home.png",
                "timezone": "Europe/Berlin",
            },
            access_token=admin_login["access_token"],
        )
        gym_two = self.post_json_with_auth(
            "/gyms",
            {
                "name": "Logbook Other Gym",
                "logo_url": "https://example.com/logbook-other.png",
                "timezone": "Europe/Berlin",
            },
            access_token=admin_login["access_token"],
        )
        self._add_active_gym_membership(
            email=server.DEMO_EMAIL,
            gym_id=gym_one["gym"]["id"],
            roles=["athlete"],
        )

        connection = server.get_connection()
        athlete_user = connection.execute(
            "select id from users where email = ?",
            (server.DEMO_EMAIL,),
        ).fetchone()
        self.assertIsNotNone(athlete_user)
        now = server.now_utc()
        with connection:
            workout_cursor = connection.execute(
                """
                insert into daily_workouts (
                  gym_id, scheduled_date, title, strength_text, metcon_text, notes_text,
                  created_by_user_id, updated_by_user_id, created_at, updated_at
                )
                values (?, ?, 'Home Gym WOD', '', '21-15-9 thrusters and pull-ups', '', ?, ?, ?, ?)
                """,
                (
                    gym_one["gym"]["id"],
                    now.date().isoformat(),
                    athlete_user["id"],
                    athlete_user["id"],
                    server.isoformat(now),
                    server.isoformat(now),
                ),
            )
            workout_id = int(workout_cursor.lastrowid)
            class_cursor = connection.execute(
                """
                insert into class_schedules (
                  gym_id, title, class_type, start_time, end_time, duration_minutes, capacity,
                  created_by_user_id, updated_by_user_id, created_at, updated_at
                )
                values (?, 'Other Gym Class Ref', 'CrossFit', ?, ?, 60, 12, ?, ?, ?, ?)
                """,
                (
                    gym_two["gym"]["id"],
                    server.isoformat(now + timedelta(hours=1)),
                    server.isoformat(now + timedelta(hours=2)),
                    athlete_user["id"],
                    athlete_user["id"],
                    server.isoformat(now),
                    server.isoformat(now),
                ),
            )
            class_id = int(class_cursor.lastrowid)
        connection.close()

        athlete_login = self.post_json(
            "/auth/login",
            {"email": server.DEMO_EMAIL, "password": server.DEMO_PASSWORD},
        )
        request = urllib.request.Request(
            f"{self.base_url}/logbook",
            data=json_bytes(
                {
                    "workout_id": workout_id,
                    "class_id": class_id,
                    "score_type": "rounds_reps",
                    "score_value": 189,
                    "notes_text": "blocked",
                }
            ),
            headers={
                "Authorization": f"Bearer {athlete_login['access_token']}",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        with self.assertRaises(urllib.error.HTTPError) as error_context:
            urllib.request.urlopen(request)

        self.assertEqual(error_context.exception.code, 404)

    def _verify_user_email(self, email: str) -> None:
        connection = server.get_connection()
        user = connection.execute(
            "select id from users where email = ?",
            (email,),
        ).fetchone()
        self.assertIsNotNone(user)
        with connection:
            token = server.issue_verification_token(connection, user["id"])
        connection.close()
        verified = self.post_json("/auth/verify-email", {"token": token})
        self.assertEqual(verified["message"], "Email verified.")

    def _approve_demo_user_for_gym(
        self, *, admin_token: str, athlete_token: str, gym_id: int
    ) -> None:
        self.post_json_with_auth(
            "/gyms/join-requests",
            {"gym_id": gym_id},
            access_token=athlete_token,
        )
        pending_requests = self.get_json_with_auth(
            "/gyms/join-requests",
            access_token=admin_token,
        )
        self.patch_json(
            "/gyms/join-requests",
            {
                "request_id": pending_requests["requests"][0]["id"],
                "decision": "approve",
            },
            access_token=admin_token,
        )
        self.patch_json(
            "/profile/active-gym",
            {"gym_id": gym_id},
            access_token=athlete_token,
        )

    def _add_active_gym_membership(
        self, *, email: str, gym_id: int, roles: list[str], active_role: str = "athlete"
    ) -> None:
        connection = server.get_connection()
        user = connection.execute(
            "select id from users where email = ?",
            (email,),
        ).fetchone()
        self.assertIsNotNone(user)
        now = server.now_utc()
        with connection:
            connection.execute(
                """
                insert into gym_memberships (
                  user_id, gym_id, active_role, roles_json, status, created_at, updated_at
                )
                values (?, ?, ?, ?, 'active', ?, ?)
                """,
                (
                    user["id"],
                    gym_id,
                    active_role,
                    server.encode_roles(roles),
                    server.isoformat(now),
                    server.isoformat(now),
                ),
            )
            connection.execute(
                "update users set active_gym_id = ? where id = ?",
                (gym_id, user["id"]),
            )
            server.sync_user_context(connection, user["id"])
        connection.close()

    def patch_json(
        self,
        path: str,
        payload: dict[str, object],
        *,
        access_token: str,
    ) -> dict[str, object]:
        request = urllib.request.Request(
            f"{self.base_url}{path}",
            data=json_bytes(payload),
            headers={
                "Authorization": f"Bearer {access_token}",
                "Content-Type": "application/json",
            },
            method="PATCH",
        )
        with urllib.request.urlopen(request) as response:
            return json_loads(response.read())

    def delete_json_with_auth(
        self,
        path: str,
        payload: dict[str, object],
        *,
        access_token: str,
    ) -> dict[str, object]:
        request = urllib.request.Request(
            f"{self.base_url}{path}",
            data=json_bytes(payload),
            headers={
                "Authorization": f"Bearer {access_token}",
                "Content-Type": "application/json",
            },
            method="DELETE",
        )
        with urllib.request.urlopen(request) as response:
            return json_loads(response.read())


def json_bytes(payload: dict[str, object]) -> bytes:
    import json

    return json.dumps(payload).encode("utf-8")


def json_loads(payload: bytes) -> dict[str, object]:
    import json

    return json.loads(payload.decode("utf-8"))


if __name__ == "__main__":
    unittest.main()
