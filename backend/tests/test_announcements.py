from __future__ import annotations

import base64

from backend import settings
from backend.tests.support import FastApiTestCase


class AnnouncementApiTests(FastApiTestCase):
    def test_non_author_trainer_cannot_edit_or_delete_announcement(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("Announcement Box")
        self.create_verified_user("coach-a@boxos.app")
        self.create_verified_user("coach-b@boxos.app")
        self.add_active_membership("coach-a@boxos.app", gym_id, roles=["trainer"], active_role="trainer")
        self.add_active_membership("coach-b@boxos.app", gym_id, roles=["trainer"], active_role="trainer")

        author_headers = self.auth_headers("coach-a@boxos.app", "BoxOS123!")
        other_trainer_headers = self.auth_headers("coach-b@boxos.app", "BoxOS123!")

        created = self.client.post(
            "/announcements",
            headers=author_headers,
            json={"title": "Coach Note", "description": "Original"},
        )
        self.assertEqual(created.status_code, 201, created.text)
        announcement_id = created.json()["announcement"]["id"]

        updated = self.client.patch(
            "/announcements",
            headers=other_trainer_headers,
            json={"id": announcement_id, "title": "Changed", "description": "Nope", "image_url": None},
        )
        self.assertEqual(updated.status_code, 403)
        self.assertEqual(updated.json()["detail"], "Only the announcement author or an admin can modify this announcement.")

        deleted = self.client.request(
            "DELETE",
            "/announcements",
            headers=other_trainer_headers,
            json={"id": announcement_id},
        )
        self.assertEqual(deleted.status_code, 403)
        self.assertEqual(deleted.json()["detail"], "Only the announcement author or an admin can modify this announcement.")

        admin_delete = self.client.request(
            "DELETE",
            "/announcements",
            headers=admin_headers,
            json={"id": announcement_id},
        )
        self.assertEqual(admin_delete.status_code, 200, admin_delete.text)

    def test_non_author_member_cannot_edit_or_delete_comment(self) -> None:
        _, gym_id = self.create_gym_as_admin("Comment Box")
        self.create_verified_user("member-a@boxos.app")
        self.create_verified_user("member-b@boxos.app")
        self.add_active_membership("member-a@boxos.app", gym_id)
        self.add_active_membership("member-b@boxos.app", gym_id)

        admin_headers = self.auth_headers(settings.ADMIN_EMAIL, settings.ADMIN_PASSWORD)
        announcement = self.client.post(
            "/announcements",
            headers=admin_headers,
            json={"title": "Community Post", "description": "Be nice"},
        )
        self.assertEqual(announcement.status_code, 201, announcement.text)
        announcement_id = announcement.json()["announcement"]["id"]

        author_headers = self.auth_headers("member-a@boxos.app", "BoxOS123!")
        other_member_headers = self.auth_headers("member-b@boxos.app", "BoxOS123!")

        comment = self.client.post(
            "/announcements/comments",
            headers=author_headers,
            json={"announcement_id": announcement_id, "body": "First!"},
        )
        self.assertEqual(comment.status_code, 201, comment.text)
        comment_id = comment.json()["comment"]["id"]

        updated = self.client.patch(
            "/announcements/comments",
            headers=other_member_headers,
            json={"id": comment_id, "body": "Hijacked"},
        )
        self.assertEqual(updated.status_code, 403)
        self.assertEqual(updated.json()["detail"], "Only the comment author or an admin can modify this comment.")

        deleted = self.client.request(
            "DELETE",
            "/announcements/comments",
            headers=other_member_headers,
            json={"id": comment_id},
        )
        self.assertEqual(deleted.status_code, 403)
        self.assertEqual(deleted.json()["detail"], "Only the comment author or an admin can modify this comment.")

    def test_upload_announcement_image_stores_file(self) -> None:
        admin_headers, _ = self.create_gym_as_admin("Upload Box")

        uploaded = self.client.post(
            "/announcements/image",
            headers=admin_headers,
            json={
                "filename": "notice.png",
                "content_type": "image/png",
                "data_base64": base64.b64encode(b"fake-png-data").decode(),
            },
        )
        self.assertEqual(uploaded.status_code, 201, uploaded.text)
        image_url = uploaded.json()["image_url"]
        self.assertTrue(image_url.startswith("/uploads/announcements/announcement_"))

        stored_name = image_url.removeprefix("/uploads/announcements/")
        stored_path = self.temp_dir.name + "/uploads/announcements/" + stored_name
        with open(stored_path, "rb") as handle:
            self.assertEqual(handle.read(), b"fake-png-data")
