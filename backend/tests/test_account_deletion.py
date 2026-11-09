from __future__ import annotations

from backend import settings
from backend.tests.support import FastApiTestCase


class AccountDeletionOwnershipTests(FastApiTestCase):
    def delete_account(self, headers: dict[str, str], password: str, **extra):
        return self.client.request(
            "DELETE",
            "/auth/account",
            headers=headers,
            json={"current_password": password, **extra},
        )

    def test_sole_owner_must_add_owner_before_deleting_account(self) -> None:
        owner_id = self.create_verified_user("owner@example.com", account_type="admin")
        owner_headers = self.auth_headers("owner@example.com", "BoxOS123!")
        created = self.client.post(
            "/gyms",
            headers=owner_headers,
            json={"name": "Solo Box", "logo_url": "https://example.com/solo.png", "timezone": "Europe/Berlin"},
        )
        self.assertEqual(created.status_code, 201, created.text)
        gym_id = created.json()["gym"]["id"]
        member_id = self.add_active_membership(settings.DEMO_EMAIL, gym_id)

        check = self.client.get("/auth/account/deletion-check", headers=owner_headers)
        self.assertEqual(check.status_code, 200, check.text)
        self.assertEqual(check.json()["empty_gyms"], [])
        [blocking] = check.json()["gyms_needing_owner"]
        self.assertEqual(blocking["id"], gym_id)
        self.assertEqual([member["id"] for member in blocking["members"]], [member_id])

        blocked = self.delete_account(owner_headers, "BoxOS123!")
        self.assertEqual(blocked.status_code, 409, blocked.text)
        self.assertIn("Solo Box", blocked.json()["detail"])

        member_headers = self.auth_headers(settings.DEMO_EMAIL, settings.DEMO_PASSWORD)
        forbidden = self.client.post(f"/gyms/{gym_id}/owners", headers=member_headers, json={"user_id": member_id})
        self.assertEqual(forbidden.status_code, 403, forbidden.text)

        promoted = self.client.post(f"/gyms/{gym_id}/owners", headers=owner_headers, json={"user_id": member_id})
        self.assertEqual(promoted.status_code, 200, promoted.text)

        check = self.client.get("/auth/account/deletion-check", headers=owner_headers)
        self.assertEqual(check.json(), {"gyms_needing_owner": [], "empty_gyms": []})

        deleted = self.delete_account(owner_headers, "BoxOS123!")
        self.assertEqual(deleted.status_code, 200, deleted.text)

        self.assertEqual(self.count_rows("gyms", "id = ? and created_by_user_id = ?", (gym_id, member_id)), 1)
        self.assertEqual(
            self.count_rows(
                "gym_memberships",
                "gym_id = ? and user_id = ? and active_role = 'admin' and roles_json = ?",
                (gym_id, member_id, '["admin", "athlete"]'),
            ),
            1,
        )
        self.assertEqual(self.count_rows("users", "id = ? and account_type = 'admin'", (member_id,)), 1)
        self.assertEqual(self.count_rows("users", "id = ? and deleted_at is not null", (owner_id,)), 1)

    def test_owner_of_empty_box_must_confirm_box_deletion(self) -> None:
        owner_id = self.create_verified_user("solo@example.com", account_type="admin")
        owner_headers = self.auth_headers("solo@example.com", "BoxOS123!")
        created = self.client.post(
            "/gyms",
            headers=owner_headers,
            json={"name": "Empty Box", "logo_url": "https://example.com/empty.png", "timezone": "Europe/Berlin"},
        )
        gym_id = created.json()["gym"]["id"]

        check = self.client.get("/auth/account/deletion-check", headers=owner_headers)
        self.assertEqual(check.json(), {"gyms_needing_owner": [], "empty_gyms": [{"id": gym_id, "name": "Empty Box"}]})

        unconfirmed = self.delete_account(owner_headers, "BoxOS123!")
        self.assertEqual(unconfirmed.status_code, 409, unconfirmed.text)
        self.assertEqual(self.count_rows("gyms", "id = ?", (gym_id,)), 1)

        deleted = self.delete_account(owner_headers, "BoxOS123!", delete_empty_gyms=True)
        self.assertEqual(deleted.status_code, 200, deleted.text)
        self.assertEqual(self.count_rows("gyms", "id = ?", (gym_id,)), 0)
        self.assertEqual(self.count_rows("users", "id = ? and deleted_at is not null", (owner_id,)), 1)

    def test_co_owned_box_does_not_block_deletion(self) -> None:
        _, gym_id = self.create_gym_as_admin("Shared Box")
        self.create_verified_user("coowner@example.com", account_type="admin")
        self.add_active_membership("coowner@example.com", gym_id, roles=["admin"], active_role="admin")
        coowner_headers = self.auth_headers("coowner@example.com", "BoxOS123!")

        check = self.client.get("/auth/account/deletion-check", headers=coowner_headers)
        self.assertEqual(check.json(), {"gyms_needing_owner": [], "empty_gyms": []})
        deleted = self.delete_account(coowner_headers, "BoxOS123!")
        self.assertEqual(deleted.status_code, 200, deleted.text)
        self.assertEqual(self.count_rows("gyms", "id = ?", (gym_id,)), 1)
