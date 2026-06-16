from __future__ import annotations

from backend import db, security, settings
from backend.tests.support import FastApiTestCase


class CommunityChatTests(FastApiTestCase):
    def test_dashboard_returns_stats_and_newest_prs_for_members(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("Dashboard Box")
        athlete_id = self.add_active_membership(settings.DEMO_EMAIL, gym_id)
        self.create_verified_user("trainer@boxos.app")
        trainer_id = self.add_active_membership(
            "trainer@boxos.app",
            gym_id,
            roles=["trainer"],
            active_role="trainer",
        )
        athlete_headers = self.auth_headers(
            settings.DEMO_EMAIL, settings.DEMO_PASSWORD
        )
        timestamp = security.isoformat(security.now_utc())
        connection = db.get_connection()
        try:
            with connection:
                workout_id = int(
                    connection.execute(
                        """
                        insert into daily_workouts (
                          gym_id, scheduled_date, title, status, published_at,
                          published_by_user_id, created_by_user_id, updated_by_user_id,
                          created_at, updated_at
                        )
                        values (?, '2026-06-16', 'Fran', 'published', ?, ?, ?, ?, ?, ?)
                        returning id
                        """,
                        (
                            gym_id,
                            timestamp,
                            trainer_id,
                            trainer_id,
                            trainer_id,
                            timestamp,
                            timestamp,
                        ),
                    ).fetchone()["id"]
                )
                connection.execute(
                    """
                    insert into workout_logs (
                      user_id, gym_id, daily_workout_id, score_type, score_value,
                      score_label, notes_text, is_pr, pr_rank, created_at, updated_at
                    )
                    values (?, ?, ?, 'time', 321, '5:21', '', 1, 1, ?, ?)
                    """,
                    (athlete_id, gym_id, workout_id, timestamp, timestamp),
                )
                connection.execute(
                    """
                    insert into chat_messages (gym_id, user_id, body, created_at, updated_at)
                    values (?, ?, 'Nice PR!', ?, ?)
                    """,
                    (gym_id, trainer_id, timestamp, timestamp),
                )
        finally:
            connection.close()

        response = self.client.get("/community/dashboard", headers=athlete_headers)
        self.assertEqual(response.status_code, 200, response.text)
        payload = response.json()
        self.assertEqual(payload["stats"]["active_members"], 3)
        self.assertEqual(payload["stats"]["active_trainers"], 1)
        self.assertEqual(payload["stats"]["owners"], 1)
        self.assertEqual(payload["stats"]["prs_last_30_days"], 1)
        self.assertEqual(payload["stats"]["messages_last_7_days"], 1)
        self.assertEqual(len(payload["newest_prs"]), 1)
        self.assertEqual(payload["newest_prs"][0]["workout_title"], "Fran")
        self.assertEqual(payload["newest_prs"][0]["score_label"], "5:21")

    def test_send_and_list_messages_in_active_gym(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("Chat Box")
        self.add_active_membership(settings.DEMO_EMAIL, gym_id)
        athlete_headers = self.auth_headers(
            settings.DEMO_EMAIL, settings.DEMO_PASSWORD
        )

        first = self.client.post(
            "/community/messages",
            headers=admin_headers,
            json={"body": "Welcome to the box!"},
        )
        self.assertEqual(first.status_code, 201, first.text)

        second = self.client.post(
            "/community/messages",
            headers=athlete_headers,
            json={"body": "Excited to be here."},
        )
        self.assertEqual(second.status_code, 201, second.text)

        listed = self.client.get("/community/messages", headers=athlete_headers)
        self.assertEqual(listed.status_code, 200, listed.text)
        messages = listed.json()["messages"]
        self.assertEqual(len(messages), 2)
        self.assertEqual(messages[0]["body"], "Welcome to the box!")
        self.assertFalse(messages[0]["is_own"])  # admin's message
        self.assertTrue(messages[1]["is_own"])  # athlete's own message

    def test_since_id_only_returns_newer_messages(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("Poll Box")
        self.add_active_membership(settings.DEMO_EMAIL, gym_id)

        first = self.client.post(
            "/community/messages",
            headers=admin_headers,
            json={"body": "First"},
        )
        first_id = first.json()["message"]["id"]

        second = self.client.post(
            "/community/messages",
            headers=admin_headers,
            json={"body": "Second"},
        )
        second_id = second.json()["message"]["id"]

        polled = self.client.get(
            f"/community/messages?since_id={first_id}", headers=admin_headers
        )
        self.assertEqual(polled.status_code, 200, polled.text)
        ids = [item["id"] for item in polled.json()["messages"]]
        self.assertEqual(ids, [second_id])

    def test_owner_can_delete_own_message(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("Delete Own Box")
        self.add_active_membership(settings.DEMO_EMAIL, gym_id)
        athlete_headers = self.auth_headers(
            settings.DEMO_EMAIL, settings.DEMO_PASSWORD
        )

        created = self.client.post(
            "/community/messages",
            headers=athlete_headers,
            json={"body": "Oops typo"},
        )
        message_id = created.json()["message"]["id"]

        deleted = self.client.delete(
            f"/community/messages/{message_id}", headers=athlete_headers
        )
        self.assertEqual(deleted.status_code, 200, deleted.text)

        listed = self.client.get("/community/messages", headers=athlete_headers)
        messages = listed.json()["messages"]
        self.assertEqual(len(messages), 1)
        self.assertEqual(messages[0]["body"], "")
        self.assertIsNotNone(messages[0]["deleted_at"])

    def test_athlete_cannot_delete_others_messages(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("Moderation Box")
        self.add_active_membership(settings.DEMO_EMAIL, gym_id)
        athlete_headers = self.auth_headers(
            settings.DEMO_EMAIL, settings.DEMO_PASSWORD
        )

        created = self.client.post(
            "/community/messages",
            headers=admin_headers,
            json={"body": "Admin says hello"},
        )
        message_id = created.json()["message"]["id"]

        forbidden = self.client.delete(
            f"/community/messages/{message_id}", headers=athlete_headers
        )
        self.assertEqual(forbidden.status_code, 403, forbidden.text)

    def test_admin_can_moderate_other_messages(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("Mod Box")
        self.add_active_membership(settings.DEMO_EMAIL, gym_id)
        athlete_headers = self.auth_headers(
            settings.DEMO_EMAIL, settings.DEMO_PASSWORD
        )

        created = self.client.post(
            "/community/messages",
            headers=athlete_headers,
            json={"body": "Inappropriate message"},
        )
        message_id = created.json()["message"]["id"]

        moderated = self.client.delete(
            f"/community/messages/{message_id}", headers=admin_headers
        )
        self.assertEqual(moderated.status_code, 200, moderated.text)

    def test_messages_are_scoped_to_active_gym(self) -> None:
        admin_a_headers, gym_a = self.create_gym_as_admin("Gym A")
        self.add_active_membership(settings.DEMO_EMAIL, gym_a)
        self.client.post(
            "/community/messages",
            headers=admin_a_headers,
            json={"body": "Hello Gym A"},
        )

        # Switch the athlete's active gym to a separate box.
        self.create_verified_user("athlete-b@boxos.app")
        admin_b_headers = self.auth_headers(
            settings.ADMIN_EMAIL, settings.ADMIN_PASSWORD
        )
        gym_b_response = self.client.post(
            "/gyms",
            headers=admin_b_headers,
            json={
                "name": "Gym B",
                "logo_url": "https://example.com/b.png",
                "timezone": "Europe/Berlin",
            },
        )
        gym_b = gym_b_response.json()["gym"]["id"]
        self.add_active_membership("athlete-b@boxos.app", gym_b)
        athlete_b_headers = self.auth_headers("athlete-b@boxos.app", "BoxOS123!")

        listed = self.client.get("/community/messages", headers=athlete_b_headers)
        self.assertEqual(listed.json()["messages"], [])

    def test_empty_body_is_rejected(self) -> None:
        admin_headers, _ = self.create_gym_as_admin("Empty Body Box")

        response = self.client.post(
            "/community/messages",
            headers=admin_headers,
            json={"body": "   "},
        )
        self.assertEqual(response.status_code, 400, response.text)
        self.assertEqual(response.json()["detail"], "Message body is required.")
