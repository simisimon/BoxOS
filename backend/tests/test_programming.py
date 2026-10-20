from __future__ import annotations

from datetime import timedelta

from backend import security, settings
from backend.tests.support import FastApiTestCase


def _sample_sections() -> list[dict[str, str]]:
    return [
        {"title": "Warm Up", "description": "500m row", "score_type": "time"},
        {
            "title": "Strength",
            "description": "Back Squat 5x5",
            "score_type": "weight",
        },
    ]


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
                "sections": _sample_sections(),
            },
        )
        self.assertEqual(first.status_code, 200, first.text)

        duplicate = self.client.post(
            "/programming/workouts",
            headers=admin_headers,
            json={
                "scheduled_date": scheduled_date,
                "title": "Grace",
                "sections": _sample_sections(),
            },
        )
        self.assertEqual(duplicate.status_code, 409)
        self.assertEqual(duplicate.json()["detail"], "A workout already exists for this date.")

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

    def test_create_workout_defaults_to_draft_and_hides_from_athletes(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("Draft Box")
        self.add_active_membership(settings.DEMO_EMAIL, gym_id)
        scheduled_date = security.now_utc().date().isoformat()

        created = self.client.post(
            "/programming/workouts",
            headers=admin_headers,
            json={
                "scheduled_date": scheduled_date,
                "title": "Annie",
                "sections": _sample_sections(),
            },
        )
        self.assertEqual(created.status_code, 200, created.text)
        payload = created.json()["workout"]
        self.assertEqual(payload["status"], "draft")
        self.assertEqual(len(payload["sections"]), 2)
        self.assertEqual(payload["sections"][0]["title"], "Warm Up")
        self.assertEqual(payload["sections"][1]["score_type"], "weight")

        athlete_headers = self.auth_headers(settings.DEMO_EMAIL, settings.DEMO_PASSWORD)
        athlete_list = self.client.get("/programming/workouts", headers=athlete_headers)
        self.assertEqual(athlete_list.status_code, 200, athlete_list.text)
        self.assertEqual(athlete_list.json()["workouts"], [])

        admin_list = self.client.get("/programming/workouts", headers=admin_headers)
        self.assertEqual(len(admin_list.json()["workouts"]), 1)

    def test_publish_unpublish_toggles_visibility_for_athletes(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("Publish Box")
        self.add_active_membership(settings.DEMO_EMAIL, gym_id)
        scheduled_date = security.now_utc().date().isoformat()

        created = self.client.post(
            "/programming/workouts",
            headers=admin_headers,
            json={
                "scheduled_date": scheduled_date,
                "title": "Helen",
                "sections": _sample_sections(),
            },
        )
        self.assertEqual(created.status_code, 200, created.text)
        workout_id = created.json()["workout"]["id"]

        athlete_headers = self.auth_headers(settings.DEMO_EMAIL, settings.DEMO_PASSWORD)
        self.assertEqual(self.client.get("/programming/workouts", headers=athlete_headers).json()["workouts"], [])

        published = self.client.post(
            "/programming/workouts/publish", headers=admin_headers, json={"id": workout_id}
        )
        self.assertEqual(published.status_code, 200, published.text)
        self.assertEqual(published.json()["workout"]["status"], "published")
        self.assertEqual(len(published.json()["workout"]["sections"]), 2)

        athlete_after = self.client.get("/programming/workouts", headers=athlete_headers)
        self.assertEqual(len(athlete_after.json()["workouts"]), 1)
        self.assertEqual(len(athlete_after.json()["workouts"][0]["sections"]), 2)

        unpublished = self.client.post(
            "/programming/workouts/unpublish", headers=admin_headers, json={"id": workout_id}
        )
        self.assertEqual(unpublished.status_code, 200, unpublished.text)
        self.assertEqual(self.client.get("/programming/workouts", headers=athlete_headers).json()["workouts"], [])

    def test_update_replaces_sections(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("Edit Box")
        self.add_active_membership(settings.DEMO_EMAIL, gym_id)
        scheduled_date = security.now_utc().date().isoformat()

        created = self.client.post(
            "/programming/workouts",
            headers=admin_headers,
            json={
                "scheduled_date": scheduled_date,
                "title": "Diane",
                "sections": _sample_sections(),
            },
        )
        workout_id = created.json()["workout"]["id"]

        updated = self.client.patch(
            "/programming/workouts",
            headers=admin_headers,
            json={
                "id": workout_id,
                "scheduled_date": scheduled_date,
                "title": "Diane (revised)",
                "sections": [
                    {
                        "title": "",
                        "description": "21-15-9 deadlifts + HSPU",
                        "score_type": "time",
                    },
                ],
            },
        )
        self.assertEqual(updated.status_code, 200, updated.text)
        sections = updated.json()["workout"]["sections"]
        self.assertEqual(len(sections), 1)
        self.assertEqual(sections[0]["title"], "")
        self.assertEqual(sections[0]["score_type"], "time")

    def test_workout_section_validation_rejects_invalid_score(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("Score Box")
        self.add_active_membership(settings.DEMO_EMAIL, gym_id)
        scheduled_date = security.now_utc().date().isoformat()

        response = self.client.post(
            "/programming/workouts",
            headers=admin_headers,
            json={
                "scheduled_date": scheduled_date,
                "title": "Bad",
                "sections": [
                    {
                        "title": "Mystery",
                        "description": "What",
                        "score_type": "calories",
                    },
                ],
            },
        )
        self.assertEqual(response.status_code, 400, response.text)
        self.assertIn("score", response.json()["detail"].lower())

    def test_workout_section_validation_rejects_empty_list(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("Empty Sections Box")
        self.add_active_membership(settings.DEMO_EMAIL, gym_id)
        scheduled_date = security.now_utc().date().isoformat()

        response = self.client.post(
            "/programming/workouts",
            headers=admin_headers,
            json={
                "scheduled_date": scheduled_date,
                "title": "Empty",
                "sections": [],
            },
        )
        self.assertEqual(response.status_code, 400, response.text)

    def test_workout_section_validation_rejects_blank_description(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("Blank Section Box")
        self.add_active_membership(settings.DEMO_EMAIL, gym_id)
        scheduled_date = security.now_utc().date().isoformat()

        response = self.client.post(
            "/programming/workouts",
            headers=admin_headers,
            json={
                "scheduled_date": scheduled_date,
                "title": "Blanks",
                "sections": [
                    {
                        "title": "Strength",
                        "description": "   ",
                        "score_type": "weight",
                    },
                ],
            },
        )
        self.assertEqual(response.status_code, 400, response.text)
        self.assertIn("description", response.json()["detail"].lower())

    def test_duplicate_workout_copies_sections_to_target_date_as_draft(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("Duplicate Box")
        self.add_active_membership(settings.DEMO_EMAIL, gym_id)
        today = security.now_utc().date()
        source_date = today.isoformat()
        target_date = (today + timedelta(days=7)).isoformat()

        created = self.client.post(
            "/programming/workouts",
            headers=admin_headers,
            json={
                "scheduled_date": source_date,
                "title": "Murph",
                "sections": _sample_sections(),
                "status": "published",
            },
        )
        self.assertEqual(created.status_code, 200, created.text)

        duplicated = self.client.post(
            "/programming/workouts/duplicate",
            headers=admin_headers,
            json={"source_date": source_date, "target_date": target_date},
        )
        self.assertEqual(duplicated.status_code, 200, duplicated.text)
        payload = duplicated.json()["workout"]
        self.assertEqual(payload["scheduled_date"], target_date)
        self.assertEqual(payload["status"], "draft")
        self.assertEqual(len(payload["sections"]), 2)
        self.assertEqual(payload["sections"][0]["title"], "Warm Up")
        self.assertEqual(payload["sections"][1]["score_type"], "weight")

    def test_athlete_cannot_duplicate_or_publish(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("Auth Box")
        self.add_active_membership(settings.DEMO_EMAIL, gym_id)
        today = security.now_utc().date()
        source = today.isoformat()
        target = (today + timedelta(days=2)).isoformat()

        created = self.client.post(
            "/programming/workouts",
            headers=admin_headers,
            json={
                "scheduled_date": source,
                "title": "Fran",
                "sections": _sample_sections(),
                "status": "published",
            },
        )
        workout_id = created.json()["workout"]["id"]

        athlete_headers = self.auth_headers(settings.DEMO_EMAIL, settings.DEMO_PASSWORD)
        dup = self.client.post(
            "/programming/workouts/duplicate",
            headers=athlete_headers,
            json={"source_date": source, "target_date": target},
        )
        self.assertEqual(dup.status_code, 403, dup.text)

        pub = self.client.post(
            "/programming/workouts/publish",
            headers=athlete_headers,
            json={"id": workout_id},
        )
        self.assertEqual(pub.status_code, 403, pub.text)

    def test_import_creates_multiple_workouts(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("Import Box")
        self.add_active_membership(settings.DEMO_EMAIL, gym_id)
        today = security.now_utc().date()

        response = self.client.post(
            "/programming/workouts/import",
            headers=admin_headers,
            json={
                "rows": [
                    {
                        "scheduled_date": today.isoformat(),
                        "title": "Murph",
                        "status": "published",
                        "sections": _sample_sections(),
                    },
                    {
                        "scheduled_date": (today + timedelta(days=1)).isoformat(),
                        "title": "Fran",
                        "sections": [
                            {
                                "title": "MetCon",
                                "description": "21-15-9 thrusters/pull-ups",
                                "score_type": "time",
                            },
                        ],
                    },
                ]
            },
        )
        self.assertEqual(response.status_code, 200, response.text)
        payload = response.json()
        self.assertEqual(payload["created_count"], 2)

        listed = self.client.get("/programming/workouts", headers=admin_headers)
        titles = sorted(item["title"] for item in listed.json()["workouts"])
        self.assertEqual(titles, ["Fran", "Murph"])

    def test_import_is_atomic_when_a_row_is_invalid(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("Atomic Import Box")
        self.add_active_membership(settings.DEMO_EMAIL, gym_id)
        today = security.now_utc().date()

        response = self.client.post(
            "/programming/workouts/import",
            headers=admin_headers,
            json={
                "rows": [
                    {
                        "scheduled_date": today.isoformat(),
                        "title": "Valid WOD",
                        "sections": _sample_sections(),
                    },
                    {
                        # Empty sections -> invalid.
                        "scheduled_date": (today + timedelta(days=1)).isoformat(),
                        "title": "Empty WOD",
                        "sections": [],
                    },
                ]
            },
        )
        self.assertEqual(response.status_code, 422, response.text)
        payload = response.json()
        self.assertEqual(payload["created_count"], 0)
        self.assertEqual(payload["errors"][0]["row"], 2)

        # Nothing created.
        listed = self.client.get("/programming/workouts", headers=admin_headers)
        self.assertEqual(listed.json()["workouts"], [])

    def test_import_rejects_duplicate_dates_within_payload(self) -> None:
        admin_headers, _ = self.create_gym_as_admin("Duplicate Import Box")
        today = security.now_utc().date().isoformat()

        response = self.client.post(
            "/programming/workouts/import",
            headers=admin_headers,
            json={
                "rows": [
                    {
                        "scheduled_date": today,
                        "title": "First",
                        "sections": _sample_sections(),
                    },
                    {
                        "scheduled_date": today,
                        "title": "Second",
                        "sections": _sample_sections(),
                    },
                ]
            },
        )
        self.assertEqual(response.status_code, 422, response.text)
        self.assertEqual(response.json()["errors"][0]["row"], 2)

    def test_import_conflicts_with_existing_wod(self) -> None:
        admin_headers, _ = self.create_gym_as_admin("Conflict Import Box")
        today = security.now_utc().date().isoformat()

        first = self.client.post(
            "/programming/workouts",
            headers=admin_headers,
            json={
                "scheduled_date": today,
                "title": "Already there",
                "sections": _sample_sections(),
            },
        )
        self.assertEqual(first.status_code, 200, first.text)

        response = self.client.post(
            "/programming/workouts/import",
            headers=admin_headers,
            json={
                "rows": [
                    {
                        "scheduled_date": today,
                        "title": "Trying again",
                        "sections": _sample_sections(),
                    }
                ]
            },
        )
        self.assertEqual(response.status_code, 422, response.text)
        self.assertEqual(response.json()["errors"][0]["row"], 1)

    def test_athlete_cannot_import_workouts(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("Import Auth Box")
        self.add_active_membership(settings.DEMO_EMAIL, gym_id)
        athlete_headers = self.auth_headers(settings.DEMO_EMAIL, settings.DEMO_PASSWORD)
        # Silence the unused-headers lint while keeping the admin gym set up.
        _ = admin_headers
        today = security.now_utc().date().isoformat()

        response = self.client.post(
            "/programming/workouts/import",
            headers=athlete_headers,
            json={
                "rows": [
                    {
                        "scheduled_date": today,
                        "title": "Sneaky",
                        "sections": _sample_sections(),
                    }
                ]
            },
        )
        self.assertEqual(response.status_code, 403, response.text)

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
                "sections": [
                    {
                        "title": "MetCon",
                        "description": "20 min AMRAP",
                        "score_type": "rounds_reps",
                    },
                ],
                "status": "published",
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
