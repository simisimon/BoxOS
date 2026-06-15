from __future__ import annotations

from datetime import timedelta

from backend import db, security, settings, validation
from backend.tests.support import FastApiTestCase


class ScheduleApiTests(FastApiTestCase):
    def test_recurring_schedule_creation_creates_multiple_classes(self) -> None:
        admin_headers, _ = self.create_gym_as_admin("Recurring Box")

        created = self.client.post(
            "/schedule/classes",
            headers=admin_headers,
            json={
                "title": "Lunch WOD",
                "class_type": "WOD",
                "start_time": security.isoformat(security.now_utc() + timedelta(days=1)),
                "duration_minutes": 60,
                "capacity": 12,
                "wod_description": "Intervals",
                "recurrence_frequency": "daily",
                "occurrence_count": 3,
            },
        )
        self.assertEqual(created.status_code, 201, created.text)
        payload = created.json()
        self.assertEqual(payload["created_count"], 3)
        self.assertEqual(len(payload["classes"]), 3)
        self.assertEqual(payload["classes"][0]["title"], "Lunch WOD")

    def test_import_creates_multiple_classes(self) -> None:
        admin_headers, _ = self.create_gym_as_admin("Import Box")

        response = self.client.post(
            "/schedule/classes/import",
            headers=admin_headers,
            json={
                "rows": [
                    {
                        "start_time": security.isoformat(
                            security.now_utc() + timedelta(days=1)
                        ),
                        "title": "Morning WOD",
                        "duration_minutes": 60,
                        "capacity": 12,
                    },
                    {
                        "start_time": security.isoformat(
                            security.now_utc() + timedelta(days=2)
                        ),
                        "title": "Evening WOD",
                        "class_type": "Open Gym",
                        "duration_minutes": 45,
                        "capacity": 10,
                        "recurrence_frequency": "weekly",
                        "occurrence_count": 2,
                    },
                ]
            },
        )
        self.assertEqual(response.status_code, 200, response.text)
        payload = response.json()
        # 1 single + 2 weekly occurrences.
        self.assertEqual(payload["created_count"], 3)

        listed = self.client.get("/schedule/classes", headers=admin_headers)
        titles = sorted(item["title"] for item in listed.json()["classes"])
        self.assertEqual(titles, ["Evening WOD", "Evening WOD", "Morning WOD"])

    def test_import_is_atomic_when_a_row_is_invalid(self) -> None:
        admin_headers, _ = self.create_gym_as_admin("Atomic Import Box")

        response = self.client.post(
            "/schedule/classes/import",
            headers=admin_headers,
            json={
                "rows": [
                    {
                        "start_time": security.isoformat(
                            security.now_utc() + timedelta(days=1)
                        ),
                        "title": "Valid WOD",
                        "duration_minutes": 60,
                        "capacity": 12,
                    },
                    {
                        # Past start time -> invalid.
                        "start_time": security.isoformat(
                            security.now_utc() - timedelta(days=1)
                        ),
                        "title": "Past WOD",
                        "duration_minutes": 60,
                        "capacity": 12,
                    },
                ]
            },
        )
        self.assertEqual(response.status_code, 422, response.text)
        payload = response.json()
        self.assertEqual(payload["created_count"], 0)
        self.assertEqual(payload["errors"][0]["row"], 2)

        # Nothing was created (atomic).
        listed = self.client.get("/schedule/classes", headers=admin_headers)
        self.assertEqual(listed.json()["classes"], [])

    def test_cannot_join_waitlist_while_class_has_open_capacity(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("Open Spot Box")
        self.add_active_membership(settings.DEMO_EMAIL, gym_id)

        created = self.client.post(
            "/schedule/classes",
            headers=admin_headers,
            json={
                "title": "Open Gym",
                "class_type": "Open Gym",
                "start_time": security.isoformat(security.now_utc() + timedelta(days=1)),
                "duration_minutes": 60,
                "capacity": 2,
                "wod_description": None,
                "recurrence_frequency": "none",
            },
        )
        class_id = created.json()["class"]["id"]

        response = self.client.post(
            "/schedule/waitlist",
            headers=self.auth_headers(settings.DEMO_EMAIL, settings.DEMO_PASSWORD),
            json={"class_id": class_id},
        )
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.json()["detail"], "This class still has open spots.")

    def test_full_class_rejects_duplicate_bookings_and_supports_waitlist_promotion(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("Full Class Box")
        self.add_active_membership(settings.DEMO_EMAIL, gym_id)
        self.create_verified_user("waiter@boxos.app")
        self.add_active_membership("waiter@boxos.app", gym_id)

        created = self.client.post(
            "/schedule/classes",
            headers=admin_headers,
            json={
                "title": "Cap One",
                "class_type": "WOD",
                "start_time": security.isoformat(security.now_utc() + timedelta(days=1)),
                "duration_minutes": 45,
                "capacity": 1,
                "wod_description": "Sprint",
                "recurrence_frequency": "none",
            },
        )
        class_id = created.json()["class"]["id"]

        athlete_headers = self.auth_headers(settings.DEMO_EMAIL, settings.DEMO_PASSWORD)
        first_booking = self.client.post("/schedule/bookings", headers=athlete_headers, json={"class_id": class_id})
        self.assertEqual(first_booking.status_code, 201, first_booking.text)

        duplicate_booking = self.client.post("/schedule/bookings", headers=athlete_headers, json={"class_id": class_id})
        self.assertEqual(duplicate_booking.status_code, 409)
        self.assertEqual(duplicate_booking.json()["detail"], "You have already booked this class.")

        waiter_headers = self.auth_headers("waiter@boxos.app", "BoxOS123!")
        full_booking = self.client.post("/schedule/bookings", headers=waiter_headers, json={"class_id": class_id})
        self.assertEqual(full_booking.status_code, 409)
        self.assertEqual(full_booking.json()["detail"], "This class is already full.")

        waitlisted = self.client.post("/schedule/waitlist", headers=waiter_headers, json={"class_id": class_id})
        self.assertEqual(waitlisted.status_code, 201, waitlisted.text)

        cancelled = self.client.request("DELETE", "/schedule/bookings", headers=athlete_headers, json={"class_id": class_id})
        self.assertEqual(cancelled.status_code, 200, cancelled.text)

        listed = self.client.get("/schedule/classes", headers=waiter_headers)
        self.assertEqual(listed.status_code, 200)
        promoted_class = listed.json()["classes"][0]
        self.assertTrue(promoted_class["is_booked"])
        self.assertEqual(promoted_class["waitlist_count"], 0)

    def test_cannot_reduce_capacity_below_existing_bookings(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("Capacity Box")
        self.add_active_membership(settings.DEMO_EMAIL, gym_id)
        self.create_verified_user("second-booking@boxos.app")
        self.add_active_membership("second-booking@boxos.app", gym_id)

        created = self.client.post(
            "/schedule/classes",
            headers=admin_headers,
            json={
                "title": "Busy Class",
                "class_type": "WOD",
                "start_time": security.isoformat(security.now_utc() + timedelta(days=1)),
                "duration_minutes": 60,
                "capacity": 2,
                "wod_description": "Chipper",
                "recurrence_frequency": "none",
            },
        )
        schedule_class = created.json()["class"]
        class_id = schedule_class["id"]

        athlete_headers = self.auth_headers(settings.DEMO_EMAIL, settings.DEMO_PASSWORD)
        booking = self.client.post("/schedule/bookings", headers=athlete_headers, json={"class_id": class_id})
        self.assertEqual(booking.status_code, 201, booking.text)

        second_headers = self.auth_headers("second-booking@boxos.app", "BoxOS123!")
        second_booking = self.client.post("/schedule/bookings", headers=second_headers, json={"class_id": class_id})
        self.assertEqual(second_booking.status_code, 201, second_booking.text)

        updated = self.client.patch(
            "/schedule/classes",
            headers=admin_headers,
            json={
                "id": class_id,
                "title": schedule_class["title"],
                "class_type": schedule_class["class_type"],
                "start_time": schedule_class["start_time"],
                "duration_minutes": schedule_class["duration_minutes"],
                "capacity": 1,
                "trainer_user_id": None if schedule_class["assigned_trainer"] is None else schedule_class["assigned_trainer"]["id"],
                "wod_description": schedule_class["wod_description"],
            },
        )
        self.assertEqual(updated.status_code, 400)
        self.assertEqual(updated.json()["detail"], "Capacity cannot be lower than the current booking count.")

    def test_attendance_cannot_be_recorded_before_class_starts(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("Attendance Box")
        athlete_user_id = self.add_active_membership(settings.DEMO_EMAIL, gym_id)

        created = self.client.post(
            "/schedule/classes",
            headers=admin_headers,
            json={
                "title": "Evening Class",
                "class_type": "WOD",
                "start_time": security.isoformat(security.now_utc() + timedelta(hours=2)),
                "duration_minutes": 60,
                "capacity": 10,
                "wod_description": "EMOM",
                "recurrence_frequency": "none",
            },
        )
        class_id = created.json()["class"]["id"]

        athlete_headers = self.auth_headers(settings.DEMO_EMAIL, settings.DEMO_PASSWORD)
        booking = self.client.post("/schedule/bookings", headers=athlete_headers, json={"class_id": class_id})
        self.assertEqual(booking.status_code, 201, booking.text)

        attendance = self.client.patch(
            "/schedule/bookings/attendance",
            headers=admin_headers,
            json={"class_id": class_id, "user_id": athlete_user_id, "attendance_status": "attended"},
        )
        self.assertEqual(attendance.status_code, 400)
        self.assertEqual(attendance.json()["detail"], "Attendance can only be recorded after the class has started.")

    def test_sections_are_persisted_and_returned(self) -> None:
        admin_headers, _ = self.create_gym_as_admin("Sections Box")

        created = self.client.post(
            "/schedule/classes",
            headers=admin_headers,
            json={
                "title": "Sectioned WOD",
                "class_type": "WOD",
                "start_time": security.isoformat(security.now_utc() + timedelta(days=1)),
                "duration_minutes": 60,
                "capacity": 12,
                "wod_description": "",
                "recurrence_frequency": "none",
                "sections": [
                    {"title": "Warm Up", "description": "500m row"},
                    {"title": "Strength", "description": "Back Squat 5x5", "score_type": "time"},
                    {"title": "AMRAP", "description": "12 min", "score_type": "rounds_reps"},
                ],
            },
        )
        self.assertEqual(created.status_code, 201, created.text)
        sections = created.json()["class"]["sections"]
        self.assertEqual([section["title"] for section in sections], ["Warm Up", "Strength", "AMRAP"])
        self.assertEqual([section["score_type"] for section in sections], [None, "time", "rounds_reps"])

        listed = self.client.get("/schedule/classes", headers=admin_headers)
        listed_sections = listed.json()["classes"][0]["sections"]
        self.assertEqual(len(listed_sections), 3)
        self.assertEqual(listed_sections[1]["description"], "Back Squat 5x5")

    def test_section_score_type_is_validated(self) -> None:
        admin_headers, _ = self.create_gym_as_admin("Section Score Box")

        response = self.client.post(
            "/schedule/classes",
            headers=admin_headers,
            json={
                "title": "Bad Score",
                "class_type": "WOD",
                "start_time": security.isoformat(security.now_utc() + timedelta(days=1)),
                "duration_minutes": 60,
                "capacity": 12,
                "recurrence_frequency": "none",
                "sections": [
                    {"title": "Mystery", "score_type": "calories"},
                ],
            },
        )
        self.assertEqual(response.status_code, 400, response.text)
        self.assertIn("score", response.json()["detail"].lower())

    def test_sections_are_imported_via_csv_endpoint(self) -> None:
        admin_headers, _ = self.create_gym_as_admin("Sections Import Box")

        response = self.client.post(
            "/schedule/classes/import",
            headers=admin_headers,
            json={
                "rows": [
                    {
                        "start_time": security.isoformat(
                            security.now_utc() + timedelta(days=1)
                        ),
                        "title": "Morning WOD",
                        "duration_minutes": 60,
                        "capacity": 12,
                        "sections": [
                            {"title": "Warm Up"},
                            {"title": "Strength", "score_type": "time"},
                        ],
                    },
                ]
            },
        )
        self.assertEqual(response.status_code, 200, response.text)

        listed = self.client.get("/schedule/classes", headers=admin_headers)
        sections = listed.json()["classes"][0]["sections"]
        self.assertEqual(len(sections), 2)
        self.assertEqual(sections[1]["score_type"], "time")

    def test_assigning_non_trainer_to_schedule_class_is_rejected(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("Trainer Validation Box")
        athlete_user_id = self.add_active_membership(settings.DEMO_EMAIL, gym_id, roles=["athlete"], active_role="athlete")

        created = self.client.post(
            "/schedule/classes",
            headers=admin_headers,
            json={
                "title": "Coach Needed",
                "class_type": "WOD",
                "start_time": security.isoformat(security.now_utc() + timedelta(days=1)),
                "duration_minutes": 60,
                "capacity": 10,
                "trainer_user_id": athlete_user_id,
                "wod_description": "Heavy day",
                "recurrence_frequency": "none",
            },
        )
        self.assertEqual(created.status_code, 400)
        self.assertEqual(created.json()["detail"], "Selected trainer is not active in this gym.")
