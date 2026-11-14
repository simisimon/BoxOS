from __future__ import annotations

import base64

from backend import db, security, settings
from backend.tests.support import FastApiTestCase

PNG = base64.b64encode(b"\x89PNG\r\n\x1a\n" + b"0" * 64).decode()


class ResultSocialTests(FastApiTestCase):
    def setUp(self) -> None:
        super().setUp()
        self.admin, self.gym_id = self.create_gym_as_admin("Social Box")
        self.add_active_membership(settings.DEMO_EMAIL, self.gym_id)
        self.athlete = self.auth_headers(settings.DEMO_EMAIL, settings.DEMO_PASSWORD)
        self.create_verified_user("friend@boxos.app")
        self.add_active_membership("friend@boxos.app", self.gym_id)
        self.friend = self.auth_headers("friend@boxos.app", "BoxOS123!")
        response = self.client.post(
            "/programming/workouts",
            headers=self.admin,
            json={
                "scheduled_date": security.now_utc().date().isoformat(),
                "title": "WOD",
                "status": "published",
                "sections": [{"title": "Metcon", "description": "Fran", "score_type": "time"}],
            },
        )
        self.workout = response.json()["workout"]
        section = self.workout["sections"][0]
        logged = self.client.put("/results", headers=self.athlete, json={"section_id": section["id"], "score": "4:30"})
        self.result_id = logged.json()["result"]["id"]

    def _board(self, headers: dict) -> dict:
        response = self.client.get(f"/programming/workouts/{self.workout['id']}/leaderboard", headers=headers)
        return response.json()["sections"][0]["entries"][0]

    def _notifications(self) -> list[dict]:
        connection = db.get_connection()
        try:
            return connection.execute(
                "select type, body, entity_id from notifications where type = 'result_activity' order by id"
            ).fetchall()
        finally:
            connection.close()

    def test_bump_is_once_per_person_and_notifies_the_athlete(self) -> None:
        for _ in range(2):
            bumped = self.client.put(f"/results/{self.result_id}/bump", headers=self.friend)
            self.assertEqual(bumped.status_code, 200, bumped.text)
        self.assertEqual(bumped.json()["result"]["bump_count"], 1)
        self.assertTrue(bumped.json()["result"]["bumped_by_me"])
        # Bumping your own result is fine but sends nothing.
        self.client.put(f"/results/{self.result_id}/bump", headers=self.athlete)
        entry = self._board(self.friend)
        self.assertEqual((entry["result_id"], entry["bump_count"], entry["bumped_by_me"]), (self.result_id, 2, True))
        notes = self._notifications()
        self.assertEqual(len(notes), 1)
        self.assertIn("fist bump", notes[0]["body"])
        self.assertEqual(notes[0]["entity_id"], self.result_id)

        unbumped = self.client.delete(f"/results/{self.result_id}/bump", headers=self.friend)
        self.assertEqual(unbumped.json()["result"]["bump_count"], 1)

    def test_comments_and_moderation(self) -> None:
        posted = self.client.post(f"/results/{self.result_id}/comments", headers=self.friend, json={"body": "Beast!"})
        self.assertEqual(posted.status_code, 200, posted.text)
        comment = posted.json()["result"]["comments"][0]
        self.assertEqual(comment["body"], "Beast!")
        self.assertTrue(comment["can_delete"])
        self.assertEqual(self.client.post(f"/results/{self.result_id}/comments", headers=self.friend, json={"body": "  "}).status_code, 400)

        # The athlete can't delete someone else's comment; a coach can.
        as_athlete = self.client.get(f"/results/{self.result_id}", headers=self.athlete).json()["result"]
        self.assertFalse(as_athlete["comments"][0]["can_delete"])
        self.assertEqual(self.client.delete(f"/results/comments/{comment['id']}", headers=self.athlete).status_code, 403)
        self.assertEqual(self.client.delete(f"/results/comments/{comment['id']}", headers=self.admin).status_code, 200)
        self.assertEqual(self.client.get(f"/results/{self.result_id}", headers=self.friend).json()["result"]["comments"], [])
        self.assertEqual(self._board(self.friend)["comment_count"], 0)
        self.assertEqual(len(self._notifications()), 1)

    def test_muted_athlete_gets_no_notification(self) -> None:
        prefs = self.client.get("/profile/notifications", headers=self.athlete).json()
        self.assertTrue(prefs["result_activity"])
        muted = self.client.patch("/profile/notifications", headers=self.athlete, json={**prefs, "result_activity": False})
        self.assertFalse(muted.json()["result_activity"])
        # Clients that don't know the setting keep it.
        older = {k: v for k, v in prefs.items() if k != "result_activity"}
        self.assertFalse(self.client.patch("/profile/notifications", headers=self.athlete, json=older).json()["result_activity"])
        self.client.put(f"/results/{self.result_id}/bump", headers=self.friend)
        self.assertEqual(self._notifications(), [])

    def test_photo_belongs_to_the_athlete_and_coaches_can_remove_it(self) -> None:
        body = {"filename": "fran.png", "content_type": "image/png", "data_base64": PNG}
        self.assertEqual(self.client.put(f"/results/{self.result_id}/photo", headers=self.friend, json=body).status_code, 403)
        uploaded = self.client.put(f"/results/{self.result_id}/photo", headers=self.athlete, json=body)
        self.assertEqual(uploaded.status_code, 200, uploaded.text)
        url = uploaded.json()["result"]["photo_url"]
        self.assertTrue(url.startswith("/uploads/results/"))
        self.assertEqual(self.client.get(url).status_code, 200)
        self.assertEqual(self._board(self.friend)["photo_url"], url)

        self.assertEqual(self.client.delete(f"/results/{self.result_id}/photo", headers=self.friend).status_code, 403)
        removed = self.client.delete(f"/results/{self.result_id}/photo", headers=self.admin)
        self.assertEqual(removed.json()["result"]["photo_url"], "")
        self.assertEqual(self.client.get(url).status_code, 404)

    def test_private_and_other_gym_results_are_not_found(self) -> None:
        self.client.patch("/profile/results-privacy", headers=self.athlete, json={"visibility": "private"})
        self.assertEqual(self.client.put(f"/results/{self.result_id}/bump", headers=self.friend).status_code, 404)
        self.assertEqual(self.client.get(f"/results/{self.result_id}", headers=self.admin).status_code, 200)
        _, other = self.create_gym_as_admin("Other Box")
        self.create_verified_user("stranger@boxos.app")
        self.add_active_membership("stranger@boxos.app", other)
        stranger = self.auth_headers("stranger@boxos.app", "BoxOS123!")
        self.client.patch("/profile/results-privacy", headers=self.athlete, json={"visibility": "gym"})
        self.assertEqual(self.client.get(f"/results/{self.result_id}", headers=stranger).status_code, 404)
