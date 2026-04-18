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
