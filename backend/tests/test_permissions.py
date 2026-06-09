from __future__ import annotations

from backend import settings
from backend.tests.support import FastApiTestCase


class PermissionApiTests(FastApiTestCase):
    def test_athlete_cannot_create_gym(self) -> None:
        athlete_headers = self.auth_headers(settings.DEMO_EMAIL, settings.DEMO_PASSWORD)
        response = self.client.post(
            "/gyms",
            headers=athlete_headers,
            json={
                "name": "Forbidden Box",
                "logo_url": "https://example.com/forbidden.png",
                "timezone": "Europe/Berlin",
            },
        )
        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.json()["detail"], "The owner role is required for this action.")

    def test_member_without_active_gym_cannot_access_schedule(self) -> None:
        athlete_headers = self.auth_headers(settings.DEMO_EMAIL, settings.DEMO_PASSWORD)
        response = self.client.get("/schedule/classes", headers=athlete_headers)
        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.json()["detail"], "An active gym context is required.")

    def test_admin_can_assign_trainer_role_but_member_cannot_switch_to_unassigned_role(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("Permission Box")
        self.add_active_membership(settings.DEMO_EMAIL, gym_id, roles=["athlete"], active_role="athlete")

        role_users = self.client.get("/roles/users", headers=admin_headers)
        self.assertEqual(role_users.status_code, 200, role_users.text)
        demo_member = next(user for user in role_users.json()["users"] if user["email"] == settings.DEMO_EMAIL)

        invalid_switch = self.client.patch(
            "/profile/active-role",
            headers=self.auth_headers(settings.DEMO_EMAIL, settings.DEMO_PASSWORD),
            json={"role": "trainer"},
        )
        self.assertEqual(invalid_switch.status_code, 400)
        self.assertEqual(invalid_switch.json()["detail"], "The selected role is not assigned to this user.")

        promoted = self.client.patch(
            "/roles/users",
            headers=admin_headers,
            json={"user_id": demo_member["id"], "roles": ["athlete", "trainer"]},
        )
        self.assertEqual(promoted.status_code, 200, promoted.text)
        self.assertEqual(promoted.json()["available_roles"], ["athlete", "trainer"])

        valid_switch = self.client.patch(
            "/profile/active-role",
            headers=self.auth_headers(settings.DEMO_EMAIL, settings.DEMO_PASSWORD),
            json={"role": "trainer"},
        )
        self.assertEqual(valid_switch.status_code, 200)
        self.assertEqual(valid_switch.json()["role"], "trainer")

    def test_duplicate_join_request_returns_conflict(self) -> None:
        _, gym_id = self.create_gym_as_admin("Join Request Box")
        athlete_headers = self.auth_headers(settings.DEMO_EMAIL, settings.DEMO_PASSWORD)

        first = self.client.post("/gyms/join-requests", headers=athlete_headers, json={"gym_id": gym_id})
        self.assertEqual(first.status_code, 201, first.text)

        second = self.client.post("/gyms/join-requests", headers=athlete_headers, json={"gym_id": gym_id})
        self.assertEqual(second.status_code, 409)
        self.assertEqual(second.json()["detail"], "A join request is already pending.")

    def test_admin_membership_cannot_be_changed_from_role_management_screen(self) -> None:
        admin_headers, _ = self.create_gym_as_admin("Admin Lock Box")
        users = self.client.get("/roles/users", headers=admin_headers)
        self.assertEqual(users.status_code, 200, users.text)
        admin_member = next(user for user in users.json()["users"] if user["email"] == settings.ADMIN_EMAIL)

        response = self.client.patch(
            "/roles/users",
            headers=admin_headers,
            json={"user_id": admin_member["id"], "roles": ["athlete"]},
        )
        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.json()["detail"], "Owner memberships cannot be changed from this screen.")
