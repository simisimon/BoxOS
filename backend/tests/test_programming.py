from __future__ import annotations

from datetime import timedelta

from backend import security, settings
from backend.tests.support import FastApiTestCase


class ProgrammingApiTests(FastApiTestCase):
    def test_cannot_create_duplicate_daily_workout_for_same_date(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("Programming Box")
        self.add_active_membership(settings.DEMO_EMAIL, gym_id)
        scheduled_date = security.now_utc().date().isoformat()

        first = self.client.post(
            "/programming/workouts",
            headers=admin_headers,
            json={
                "scheduled_date": scheduled_date,
                "title": "Fran",
                "strength_text": "Back squat",
                "metcon_text": "21-15-9 thrusters/pull-ups",
                "notes_text": "Send it",
            },
        )
        self.assertEqual(first.status_code, 200, first.text)

        duplicate = self.client.post(
            "/programming/workouts",
            headers=admin_headers,
            json={
                "scheduled_date": scheduled_date,
                "title": "Grace",
                "strength_text": "Clean",
                "metcon_text": "30 clean and jerks",
                "notes_text": "Heavy",
            },
        )
        self.assertEqual(duplicate.status_code, 409)
        self.assertEqual(duplicate.json()["detail"], "A workout already exists for this date.")

    def test_future_whiteboard_results_are_rejected(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("Whiteboard Box")
        self.add_active_membership(settings.DEMO_EMAIL, gym_id)

        created = self.client.post(
            "/programming/workouts",
            headers=admin_headers,
            json={
                "scheduled_date": (security.now_utc().date() + timedelta(days=1)).isoformat(),
                "title": "Murph Prep",
                "strength_text": "Strict pull-ups",
                "metcon_text": "Intervals",
                "notes_text": "Tomorrow",
            },
        )
        self.assertEqual(created.status_code, 200, created.text)
        workout_id = created.json()["workout"]["id"]

        athlete_headers = self.auth_headers(settings.DEMO_EMAIL, settings.DEMO_PASSWORD)
        whiteboard = self.client.post(
            "/programming/whiteboard-results",
            headers=athlete_headers,
            json={"workout_id": workout_id, "score_type": "time", "score_value": "12:34", "notes_text": "Too early"},
        )
        self.assertEqual(whiteboard.status_code, 400)
        self.assertEqual(whiteboard.json()["detail"], "Results can only be submitted on or after the workout date.")

    def test_personal_workout_validation_rejects_invalid_type(self) -> None:
        athlete_headers = self.auth_headers(settings.DEMO_EMAIL, settings.DEMO_PASSWORD)

        created = self.client.post(
            "/personal-workouts",
            headers=athlete_headers,
            json={"title": "Odd Format", "type": "ladder", "structure": {"rounds": 3}},
        )
        self.assertEqual(created.status_code, 400)
        self.assertEqual(
            created.json()["detail"],
            "Workout type must be amrap, for_time, emom, interval, strength, or custom.",
        )

    def test_logbook_upsert_keeps_single_entry_per_workout(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("Logbook Box")
        self.add_active_membership(settings.DEMO_EMAIL, gym_id)
        scheduled_date = security.now_utc().date().isoformat()

        created = self.client.post(
            "/programming/workouts",
            headers=admin_headers,
            json={
                "scheduled_date": scheduled_date,
                "title": "Cindy",
                "strength_text": "",
                "metcon_text": "20 min AMRAP",
                "notes_text": "Bodyweight",
            },
        )
        self.assertEqual(created.status_code, 200, created.text)
        workout_id = created.json()["workout"]["id"]

        athlete_headers = self.auth_headers(settings.DEMO_EMAIL, settings.DEMO_PASSWORD)
        first = self.client.post(
            "/logbook/entries",
            headers=athlete_headers,
            json={"workout_id": workout_id, "score_type": "reps", "score_value": 15, "notes_text": "Solid"},
        )
        self.assertEqual(first.status_code, 200, first.text)
        first_entry_id = first.json()["entry"]["id"]

        updated = self.client.post(
            "/logbook/entries",
            headers=athlete_headers,
            json={"workout_id": workout_id, "score_type": "reps", "score_value": 16, "notes_text": "Better"},
        )
        self.assertEqual(updated.status_code, 200, updated.text)
        self.assertEqual(updated.json()["entry"]["id"], first_entry_id)
        self.assertEqual(self.count_rows("workout_logs", "user_id = ? and daily_workout_id = ?", (self.lookup_user_id(settings.DEMO_EMAIL), workout_id)), 1)
