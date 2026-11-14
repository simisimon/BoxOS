from __future__ import annotations

import contextlib
import io

from backend import db, manage, settings
from backend.tests.support import FastApiTestCase


class SignupSwitchTests(FastApiTestCase):
    def tearDown(self) -> None:
        settings.SIGNUP_ENABLED = True
        super().tearDown()

    def test_signup_is_refused_when_disabled(self) -> None:
        settings.SIGNUP_ENABLED = False
        for path in ("/auth/signup", "/auth/signup-admin", "/auth/signup-owner"):
            response = self.client.post(path, json={"email": "closed@boxos.app", "password": "BoxOS123!"})
            self.assertEqual(response.status_code, 403, path)

    def test_signup_works_when_enabled(self) -> None:
        response = self.client.post("/auth/signup", json={"email": "open@boxos.app", "password": "BoxOS123!"})
        self.assertEqual(response.status_code, 200, response.text)


class ManageCommandTests(FastApiTestCase):
    def test_create_user_in_gym_can_log_in_with_printed_password(self) -> None:
        _, gym_id = self.create_gym_as_admin("Iron Test Box")

        password = manage.create_user(
            email="Anna@Example.com", name="Anna Weber", role="trainer", gym="iron test box"
        )

        headers = self.auth_headers("anna@example.com", password)
        session = self.client.get("/auth/session", headers=headers)
        self.assertEqual(session.status_code, 200, session.text)
        body = session.json()
        self.assertEqual(body["active_gym"]["id"], gym_id)
        self.assertEqual(body["role"], "trainer")

    def test_create_user_without_gym(self) -> None:
        password = manage.create_user(email="owner@example.com", name="Olli Owner", role="admin")
        self.login("owner@example.com", password)

    def test_create_user_rejects_duplicates_and_unknown_gyms(self) -> None:
        manage.create_user(email="dup@example.com", name="Dup", role="athlete")
        with self.assertRaises(manage.CommandError):
            manage.create_user(email="dup@example.com", name="Dup", role="athlete")
        with self.assertRaises(manage.CommandError):
            manage.create_user(email="nogym@example.com", name="No Gym", role="athlete", gym="Nowhere")

    def test_reset_password_signs_out_and_sets_new_password(self) -> None:
        old_password = manage.create_user(email="reset@example.com", name="Rita", role="athlete")
        headers = self.auth_headers("reset@example.com", old_password)

        new_password = manage.reset_password(email="reset@example.com")

        self.assertNotEqual(new_password, old_password)
        self.assertEqual(self.client.get("/auth/session", headers=headers).status_code, 401)
        self.login("reset@example.com", new_password)

    def test_deactivate_user_blocks_login_until_reset(self) -> None:
        password = manage.create_user(email="gone@example.com", name="Gina", role="athlete")
        headers = self.auth_headers("gone@example.com", password)

        manage.deactivate_user(email="gone@example.com")

        self.assertEqual(self.client.get("/auth/session", headers=headers).status_code, 401)
        response = self.client.post("/auth/login", json={"email": "gone@example.com", "password": password})
        self.assertEqual(response.status_code, 401)

    def test_cli_create_and_list(self) -> None:
        self.create_gym_as_admin("CLI Box")
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = manage.main(
                ["create-user", "--email", "cli@example.com", "--name", "Cleo", "--gym", "CLI Box"]
            )
            self.assertEqual(code, 0)
            self.assertEqual(manage.main(["list-users", "--gym", "CLI Box"]), 0)
        text = out.getvalue()
        self.assertIn("Password:", text)
        self.assertIn("cli@example.com", text)

        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            self.assertEqual(manage.main(["reset-password", "--email", "missing@example.com"]), 1)
        self.assertIn("No account", err.getvalue())


class ProductionSettingsTests(FastApiTestCase):
    def setUp(self) -> None:
        super().setUp()
        self._saved = (
            settings.ENV,
            settings.DATABASE_URL,
            settings.SEED_DEMO_USERS,
            settings.LOG_DELIVERY_TOKENS,
            settings.CORS_ALLOW_ORIGINS,
            settings.STRIPE_SECRET_KEY,
        )

    def tearDown(self) -> None:
        (
            settings.ENV,
            settings.DATABASE_URL,
            settings.SEED_DEMO_USERS,
            settings.LOG_DELIVERY_TOKENS,
            settings.CORS_ALLOW_ORIGINS,
            settings.STRIPE_SECRET_KEY,
        ) = self._saved
        super().tearDown()

    def test_dev_has_no_production_problems(self) -> None:
        settings.ENV = "dev"
        self.assertEqual(settings.production_problems(), [])

    def test_production_flags_dev_defaults(self) -> None:
        settings.ENV = "production"
        settings.DATABASE_URL = "postgresql://boxos:boxos@db:5432/boxos"
        settings.SEED_DEMO_USERS = True
        settings.LOG_DELIVERY_TOKENS = True
        settings.CORS_ALLOW_ORIGINS = ["http://localhost:3001"]
        settings.STRIPE_SECRET_KEY = "sk_test_x"
        self.assertEqual(len(settings.production_problems()), 5)

    def test_production_flags_placeholder_password(self) -> None:
        settings.ENV = "production"
        settings.DATABASE_URL = "postgresql://boxos:change-me@db:5432/boxos"
        settings.SEED_DEMO_USERS = False
        settings.LOG_DELIVERY_TOKENS = False
        settings.CORS_ALLOW_ORIGINS = ["https://app.boxos-app.de"]
        settings.STRIPE_SECRET_KEY = ""
        self.assertEqual(len(settings.production_problems()), 1)

    def test_production_with_safe_settings_passes(self) -> None:
        settings.ENV = "production"
        settings.DATABASE_URL = "postgresql://boxos:s3cret@db:5432/boxos"
        settings.SEED_DEMO_USERS = False
        settings.LOG_DELIVERY_TOKENS = False
        settings.CORS_ALLOW_ORIGINS = ["https://app.boxos-app.de"]
        settings.STRIPE_SECRET_KEY = ""
        self.assertEqual(settings.production_problems(), [])


class SeedTestDataTests(FastApiTestCase):
    def setUp(self) -> None:
        super().setUp()
        self.admin_headers, self.gym_id = self.create_gym_as_admin("Real Box")
        self.member_id = self.add_active_membership(settings.DEMO_EMAIL, self.gym_id)
        self.real_wod_day = "2000-01-01"
        connection = db.get_connection()
        try:
            with connection:
                owner = connection.execute("select id from users where email = ?", (settings.ADMIN_EMAIL,)).fetchone()
                connection.execute(
                    """insert into daily_workouts (gym_id, scheduled_date, title, status, created_by_user_id,
                         updated_by_user_id, created_at, updated_at)
                       values (?, ?, 'Owner WOD', 'draft', ?, ?, 'now', 'now')""",
                    (self.gym_id, self.real_wod_day, owner["id"], owner["id"]),
                )
        finally:
            connection.close()

    def seed(self, *extra: str) -> str:
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = manage.main(["seed-test-data", "--gym", "real-box", "--members", "6", "--trainers", "1",
                                "--weeks", "1", *extra])
        self.assertEqual(code, 0)
        return out.getvalue()

    def test_seeds_existing_gym_and_reruns_without_duplicates(self) -> None:
        output = self.seed()
        self.assertIn("--remove", output)
        test_users = "email like '%@test.boxos.invalid'"
        # 1 trainer + 6 members + 2 join requests
        self.assertEqual(self.count_rows("users", test_users), 9)
        self.assertEqual(self.count_rows("gym_memberships", "gym_id = ?", (self.gym_id,)), 1 + 1 + 1 + 6)
        self.assertEqual(self.count_rows("gym_join_requests", "gym_id = ? and status = 'pending'", (self.gym_id,)), 2)
        classes = self.count_rows("class_schedules", "gym_id = ?", (self.gym_id,))
        self.assertGreater(classes, 0)
        self.assertGreater(self.count_rows("daily_workouts", "gym_id = ? and title = 'Test WOD'", (self.gym_id,)), 0)
        self.assertEqual(self.count_rows("gyms"), 1)
        results = self.count_rows("workout_results", "source = 'gym' and gym_id = ?", (self.gym_id,))
        self.assertGreater(results, 0)
        # Only test accounts log, and only on the test WODs.
        self.assertEqual(
            self.count_rows(
                "workout_results r",
                "r.source = 'gym' and (r.user_id not in (select id from users where email like '%@test.boxos.invalid')"
                " or r.daily_workout_id not in (select id from daily_workouts where title = 'Test WOD'))",
            ),
            0,
        )

        self.seed()
        self.assertEqual(self.count_rows("users", test_users), 9)
        self.assertEqual(self.count_rows("class_schedules", "gym_id = ?", (self.gym_id,)), classes)

    def test_test_accounts_cannot_log_in(self) -> None:
        self.seed()
        connection = db.get_connection()
        try:
            emails = [row["email"] for row in connection.execute(
                "select email from users where email like '%@test.boxos.invalid'").fetchall()]
        finally:
            connection.close()
        for password in ("Passw0rd!123", "BoxOS123!", "BoxOS!demo1"):
            response = self.client.post("/auth/login", json={"email": emails[0], "password": password})
            self.assertEqual(response.status_code, 401, response.text)

    def test_remove_keeps_owner_members_and_their_data(self) -> None:
        self.seed()
        self.seed("--remove")
        self.assertEqual(self.count_rows("users", "email like '%@test.boxos.invalid'"), 0)
        self.assertEqual(self.count_rows("class_schedules", "gym_id = ?", (self.gym_id,)), 0)
        self.assertEqual(self.count_rows("membership_plans", "gym_id = ?", (self.gym_id,)), 0)
        self.assertEqual(self.count_rows("chat_messages", "gym_id = ?", (self.gym_id,)), 0)
        self.assertEqual(self.count_rows("workout_results"), 0)
        self.assertEqual(self.count_rows("athlete_follows"), 0)
        self.assertEqual(self.count_rows("gym_memberships", "gym_id = ?", (self.gym_id,)), 2)
        self.assertEqual(self.count_rows("daily_workouts", "gym_id = ?", (self.gym_id,)), 1)
        self.auth_headers(settings.ADMIN_EMAIL, settings.ADMIN_PASSWORD)
        self.auth_headers(settings.DEMO_EMAIL, settings.DEMO_PASSWORD)
