from __future__ import annotations

from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from backend.core import db, security, settings
from backend.tests.support import FastApiTestCase


def _sections() -> list[dict[str, str]]:
    return [{"title": "Metcon", "description": "21-15-9", "score_type": "time"}]


class ScheduledReleaseTests(FastApiTestCase):
    def _create(self, headers: dict[str, str], scheduled_date: str) -> int:
        created = self.client.post(
            "/programming/workouts",
            headers=headers,
            json={"scheduled_date": scheduled_date, "title": "Fran", "sections": _sections()},
        )
        self.assertEqual(created.status_code, 200, created.text)
        return created.json()["workout"]["id"]

    def _athlete_workouts(self) -> list[dict]:
        headers = self.auth_headers(settings.DEMO_EMAIL, settings.DEMO_PASSWORD)
        return self.client.get("/programming/workouts", headers=headers).json()["workouts"]

    def test_schedule_needs_a_release_time(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("No Release Box")
        workout_id = self._create(admin_headers, (security.now_utc().date() + timedelta(days=3)).isoformat())
        response = self.client.post("/programming/workouts/schedule", headers=admin_headers, json={"id": workout_id})
        self.assertEqual(response.status_code, 400, response.text)

    def test_only_owners_change_the_release_time(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("Owner Box")
        self.add_active_membership(settings.DEMO_EMAIL, gym_id)
        athlete_headers = self.auth_headers(settings.DEMO_EMAIL, settings.DEMO_PASSWORD)
        denied = self.client.patch("/programming/settings", headers=athlete_headers, json={"release_time": "20:00"})
        self.assertIn(denied.status_code, (401, 403))
        bad = self.client.patch("/programming/settings", headers=admin_headers, json={"release_time": "25:00"})
        self.assertEqual(bad.status_code, 400)
        ok = self.client.patch(
            "/programming/settings", headers=admin_headers, json={"release_time": "6:30", "release_day_before": False}
        )
        self.assertEqual(ok.status_code, 200, ok.text)
        self.assertEqual(ok.json(), {"release_time": "06:30", "release_day_before": False})

    def test_scheduled_wod_stays_hidden_until_release_then_notifies_once(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("Release Box")
        self.add_active_membership(settings.DEMO_EMAIL, gym_id)
        self.client.patch("/programming/settings", headers=admin_headers, json={"release_time": "20:00"})
        wod_date = security.now_utc().date() + timedelta(days=3)
        workout_id = self._create(admin_headers, wod_date.isoformat())

        scheduled = self.client.post("/programming/workouts/schedule", headers=admin_headers, json={"id": workout_id})
        self.assertEqual(scheduled.status_code, 200, scheduled.text)
        workout = scheduled.json()["workout"]
        self.assertEqual(workout["status"], "scheduled")
        day_before = wod_date - timedelta(days=1)
        expected = datetime(day_before.year, day_before.month, day_before.day, 20, 0, tzinfo=ZoneInfo("Europe/Berlin"))
        self.assertEqual(datetime.fromisoformat(workout["release_at"]), expected)
        self.assertEqual(self._athlete_workouts(), [])
        self.assertEqual(self.count_rows("notifications", "type = 'wod_posted'"), 0)

        # The release moment passes.
        connection = db.get_connection()
        try:
            with connection:
                connection.execute(
                    "update daily_workouts set release_at = ? where id = ?",
                    ((security.now_utc() - timedelta(minutes=1)).isoformat(timespec="seconds"), workout_id),
                )
        finally:
            connection.close()

        released = self._athlete_workouts()
        self.assertEqual([w["id"] for w in released], [workout_id])
        self.assertEqual(released[0]["status"], "published")
        sent = self.count_rows("notifications", "type = 'wod_posted'")
        self.assertEqual(sent, 2)  # owner and athlete, once each
        self._athlete_workouts()
        self.assertEqual(self.count_rows("notifications", "type = 'wod_posted'"), sent)

    def test_scheduling_after_the_release_moment_publishes_now(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("Late Box")
        self.client.patch("/programming/settings", headers=admin_headers, json={"release_time": "20:00"})
        workout_id = self._create(admin_headers, security.now_utc().date().isoformat())
        response = self.client.post("/programming/workouts/schedule", headers=admin_headers, json={"id": workout_id})
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()["workout"]["status"], "published")

    def test_new_release_time_moves_scheduled_wods_and_off_returns_them_to_draft(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("Switch Box")
        self.client.patch("/programming/settings", headers=admin_headers, json={"release_time": "20:00"})
        wod_date = security.now_utc().date() + timedelta(days=4)
        workout_id = self._create(admin_headers, wod_date.isoformat())
        self.client.post("/programming/workouts/schedule", headers=admin_headers, json={"id": workout_id})

        self.client.patch(
            "/programming/settings", headers=admin_headers, json={"release_time": "06:00", "release_day_before": False}
        )
        workout = self.client.get("/programming/workouts", headers=admin_headers).json()["workouts"][0]
        expected = datetime(wod_date.year, wod_date.month, wod_date.day, 6, 0, tzinfo=ZoneInfo("Europe/Berlin"))
        self.assertEqual(datetime.fromisoformat(workout["release_at"]), expected)

        self.client.patch("/programming/settings", headers=admin_headers, json={"release_time": None})
        workout = self.client.get("/programming/workouts", headers=admin_headers).json()["workouts"][0]
        self.assertEqual(workout["status"], "draft")
        self.assertIsNone(workout["release_at"])

    def test_publish_now_clears_the_schedule(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("Now Box")
        self.add_active_membership(settings.DEMO_EMAIL, gym_id)
        self.client.patch("/programming/settings", headers=admin_headers, json={"release_time": "20:00"})
        workout_id = self._create(admin_headers, (security.now_utc().date() + timedelta(days=3)).isoformat())
        self.client.post("/programming/workouts/schedule", headers=admin_headers, json={"id": workout_id})
        published = self.client.post("/programming/workouts/publish", headers=admin_headers, json={"id": workout_id})
        self.assertEqual(published.json()["workout"]["status"], "published")
        self.assertIsNone(published.json()["workout"]["release_at"])
        self.assertEqual(len(self._athlete_workouts()), 1)
