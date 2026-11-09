from __future__ import annotations

from datetime import datetime
from zoneinfo import ZoneInfo

from backend import db, settings
from backend.tests.support import FastApiTestCase


class EditGymIdentityApiTests(FastApiTestCase):
    def _template_body(self) -> dict[str, object]:
        return {
            "title": "CrossFit",
            "class_type": "WOD",
            "weekdays": [1, 2, 3, 4, 5, 6, 7],
            "start_time": "18:00",
            "duration_minutes": 60,
            "capacity": 12,
        }

    def _template_sessions(self, headers: dict[str, str], template_id: int) -> list[dict[str, object]]:
        response = self.client.get("/schedule/classes", headers=headers)
        self.assertEqual(response.status_code, 200, response.text)
        return [item for item in response.json()["classes"] if item["class_template_id"] == template_id]

    def test_owner_can_edit_name_logo_and_timezone(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("Identity Box")

        updated = self.client.patch(
            "/gyms/current",
            headers=admin_headers,
            json={"name": "  Renamed Box  ", "logo_url": "/uploads/gym_logos/new.png", "timezone": "America/New_York"},
        )
        self.assertEqual(updated.status_code, 200, updated.text)
        self.assertEqual(
            updated.json()["gym"],
            {
                "id": gym_id,
                "name": "Renamed Box",
                "slug": "identity-box",
                "logo_url": "/uploads/gym_logos/new.png",
                "timezone": "America/New_York",
            },
        )

        profile = self.client.get("/profile", headers=admin_headers)
        self.assertEqual(profile.status_code, 200, profile.text)
        self.assertEqual(profile.json()["active_gym"]["name"], "Renamed Box")
        self.assertEqual(profile.json()["active_gym"]["timezone"], "America/New_York")

        audit = self.client.get("/audit-logs", headers=admin_headers).json()["logs"]
        entry = next(item for item in audit if item["action"] == "gym_updated")
        self.assertEqual(entry["details"]["changes"]["name"], {"from": "Identity Box", "to": "Renamed Box"})
        self.assertEqual(set(entry["details"]["changes"]), {"name", "logo_url", "timezone"})

    def test_partial_update_keeps_other_fields_and_empty_logo_clears_it(self) -> None:
        admin_headers, _ = self.create_gym_as_admin("Partial Box")

        updated = self.client.patch("/gyms/current", headers=admin_headers, json={"logo_url": ""})
        self.assertEqual(updated.status_code, 200, updated.text)
        gym = updated.json()["gym"]
        self.assertEqual(gym["name"], "Partial Box")
        self.assertEqual(gym["timezone"], "Europe/Berlin")
        self.assertEqual(gym["logo_url"], "")

        unchanged = self.client.patch("/gyms/current", headers=admin_headers, json={})
        self.assertEqual(unchanged.status_code, 200, unchanged.text)
        self.assertEqual(self.count_rows("audit_logs", "action = ?", ("gym_updated",)), 1)

    def test_rejects_invalid_input(self) -> None:
        admin_headers, _ = self.create_gym_as_admin("Invalid Box")

        blank = self.client.patch("/gyms/current", headers=admin_headers, json={"name": "   "})
        self.assertEqual(blank.status_code, 400)
        self.assertEqual(blank.json()["detail"], "Gym name is required.")

        too_long = self.client.patch("/gyms/current", headers=admin_headers, json={"name": "x" * 81})
        self.assertEqual(too_long.status_code, 400)

        for zone in ("Mars/Olympus", "../etc/passwd", ""):
            bad_zone = self.client.patch("/gyms/current", headers=admin_headers, json={"timezone": zone})
            self.assertEqual(bad_zone.status_code, 400, zone)

        gym = self.client.get("/profile", headers=admin_headers).json()["active_gym"]
        self.assertEqual(gym["name"], "Invalid Box")
        self.assertEqual(gym["timezone"], "Europe/Berlin")

    def test_only_the_owner_can_edit(self) -> None:
        _, gym_id = self.create_gym_as_admin("Owner Only Box")
        self.add_active_membership(settings.DEMO_EMAIL, gym_id, roles=["athlete", "trainer"], active_role="trainer")
        trainer_headers = self.auth_headers(settings.DEMO_EMAIL, settings.DEMO_PASSWORD)

        forbidden = self.client.patch("/gyms/current", headers=trainer_headers, json={"name": "Hijacked"})
        self.assertEqual(forbidden.status_code, 403)

        unauthenticated = self.client.patch("/gyms/current", json={"name": "Hijacked"})
        self.assertEqual(unauthenticated.status_code, 401)

        # An owner account whose membership in the active gym is paused is not the owner any more.
        owner_email = "second-owner@example.com"
        self.create_verified_user(owner_email, account_type="admin")
        self.add_active_membership(owner_email, gym_id, roles=["admin"], active_role="admin")
        owner_headers = self.auth_headers(owner_email, "BoxOS123!")
        self.assertEqual(
            self.client.patch("/gyms/current", headers=owner_headers, json={"name": "Co-owned"}).status_code,
            200,
        )
        connection = db.get_connection()
        try:
            with connection:
                connection.execute(
                    "update gym_memberships set status = 'paused' where user_id = ? and gym_id = ?",
                    (self.lookup_user_id(owner_email), gym_id),
                )
        finally:
            connection.close()
        paused = self.client.patch("/gyms/current", headers=owner_headers, json={"name": "Paused"})
        self.assertEqual(paused.status_code, 403)
        self.assertEqual(self.count_rows("gyms", "id = ? and name = ?", (gym_id, "Co-owned")), 1)

    def test_timezone_change_replans_template_sessions_and_keeps_booked_ones(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("Timezone Box")
        self.add_active_membership(settings.DEMO_EMAIL, gym_id)
        template = self.client.post("/schedule/templates", headers=admin_headers, json=self._template_body()).json()["template"]
        booked = self._template_sessions(admin_headers, template["id"])[0]
        athlete_headers = self.auth_headers(settings.DEMO_EMAIL, settings.DEMO_PASSWORD)
        booking = self.client.post("/schedule/bookings", headers=athlete_headers, json={"class_id": booked["id"]})
        self.assertEqual(booking.status_code, 201, booking.text)

        updated = self.client.patch("/gyms/current", headers=admin_headers, json={"timezone": "America/New_York"})
        self.assertEqual(updated.status_code, 200, updated.text)
        self.assertEqual(updated.json()["detached_sessions"], 1)

        new_zone = ZoneInfo("America/New_York")
        sessions = self._template_sessions(admin_headers, template["id"])
        self.assertTrue(sessions)
        for item in sessions:
            local = datetime.fromisoformat(str(item["start_time"]).replace("Z", "+00:00")).astimezone(new_zone)
            self.assertEqual((local.hour, local.minute), (18, 0))

        all_classes = self.client.get("/schedule/classes", headers=admin_headers).json()["classes"]
        kept = next(item for item in all_classes if item["id"] == booked["id"])
        self.assertIsNone(kept["class_template_id"])
        self.assertEqual(kept["start_time"], booked["start_time"])
        self.assertEqual(kept["booked_count"], 1)
