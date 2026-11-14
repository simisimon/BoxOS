from __future__ import annotations

from datetime import timedelta

from backend import db, security, settings
from backend.tests.support import FastApiTestCase


def _day(days_ago: int) -> str:
    return (security.now_utc().date() - timedelta(days=days_ago)).isoformat()


class FollowTests(FastApiTestCase):
    def setUp(self) -> None:
        super().setUp()
        self.admin, self.gym_id = self.create_gym_as_admin("Home Box")
        self.add_active_membership(settings.DEMO_EMAIL, self.gym_id)
        self.me = self.auth_headers(settings.DEMO_EMAIL, settings.DEMO_PASSWORD)
        self.my_id = self.lookup_user_id(settings.DEMO_EMAIL)
        # A gym-mate, and a friend at another gym.
        self.mate_id = self.create_verified_user("mate@boxos.app")
        self.add_active_membership("mate@boxos.app", self.gym_id)
        self.mate = self.auth_headers("mate@boxos.app", "BoxOS123!")
        self.friend_id = self.create_verified_user("friend@boxos.app")
        self.friend = self.auth_headers("friend@boxos.app", "BoxOS123!")
        connection = db.get_connection()
        try:
            with connection:
                connection.execute("update users set display_name = 'Mia Mate' where id = ?", (self.mate_id,))
                connection.execute("update users set display_name = 'Fred Friend' where id = ?", (self.friend_id,))
        finally:
            connection.close()

    def _visibility(self, headers: dict, value: str) -> None:
        response = self.client.patch("/profile/results-privacy", headers=headers, json={"visibility": value})
        self.assertEqual(response.status_code, 200, response.text)

    def _personal(self, headers: dict, score: str = "4:00", days_ago: int = 1) -> dict:
        response = self.client.post(
            "/results/personal",
            headers=headers,
            json={"kind": "benchmark", "benchmark_id": "fran", "performed_on": _day(days_ago), "score": score},
        )
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()["result"]

    def _follow(self, follower: dict, followee: dict, followee_id: int, *, code: bool = False) -> None:
        if code:
            invite = self.client.get("/follows", headers=followee).json()["invite_code"]
            body = {"invite_code": invite.lower()}
        else:
            body = {"user_id": followee_id}
        response = self.client.post("/follows", headers=follower, json=body)
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()["status"], "pending")
        follower_id = self.client.get("/follows", headers=follower).json()
        self.assertEqual(len(follower_id["sent"]), 1)
        accepted = self.client.post(f"/follows/requests/{self.my_id}/accept", headers=followee)
        self.assertEqual(accepted.status_code, 200, accepted.text)

    def test_search_finds_gym_mates_only(self) -> None:
        people = self.client.get("/follows/search", headers=self.me, params={"query": "mia"}).json()["people"]
        self.assertEqual([(p["name"], p["status"]) for p in people], [("Mia Mate", "none")])
        self.assertEqual(self.client.get("/follows/search", headers=self.me, params={"query": "fred"}).json()["people"], [])
        # Someone outside my gyms can't be followed by id, only by invite code.
        response = self.client.post("/follows", headers=self.me, json={"user_id": self.friend_id})
        self.assertEqual(response.status_code, 404)
        self.assertEqual(self.client.post("/follows", headers=self.me, json={"invite_code": "NOPE1234"}).status_code, 404)
        self.assertEqual(self.client.post("/follows", headers=self.me, json={"user_id": self.my_id}).status_code, 400)

    def test_follow_needs_approval_and_feed_follows_privacy(self) -> None:
        self._visibility(self.friend, "followers")
        result = self._personal(self.friend, "3:50")
        # Pending: nothing in the feed yet, the friend sees the request.
        self.client.post("/follows", headers=self.me, json={"invite_code": self.client.get("/follows", headers=self.friend).json()["invite_code"]})
        self.assertEqual(self.client.get("/feed", headers=self.me).json()["entries"], [])
        overview = self.client.get("/follows", headers=self.friend).json()
        self.assertEqual([p["user_id"] for p in overview["requests"]], [self.my_id])
        notifications = self.client.get("/notifications", headers=self.friend)
        if notifications.status_code == 200:
            self.assertIn("Follow request", notifications.text)

        self.client.post(f"/follows/requests/{self.my_id}/accept", headers=self.friend)
        feed = self.client.get("/feed", headers=self.me).json()
        self.assertEqual([e["id"] for e in feed["entries"]], [result["id"]])
        entry = feed["entries"][0]
        self.assertEqual(entry["name"], "Fred Friend")
        self.assertEqual(entry["source"], "personal")
        self.assertEqual(entry["bump_count"], 0)

        # Followers can bump and comment across gyms.
        bump = self.client.put(f"/results/{result['id']}/bump", headers=self.me)
        self.assertEqual(bump.status_code, 200, bump.text)
        comment = self.client.post(f"/results/{result['id']}/comments", headers=self.me, json={"body": "Fast!"})
        self.assertEqual(comment.status_code, 200, comment.text)
        self.assertEqual(self.client.get("/feed", headers=self.me).json()["entries"][0]["comment_count"], 1)

        # "My gym": the friend's personal result leaves the feed and the detail.
        self._visibility(self.friend, "gym")
        self.assertEqual(self.client.get("/feed", headers=self.me).json()["entries"], [])
        self.assertEqual(self.client.get(f"/results/{result['id']}", headers=self.me).status_code, 404)

        # Unfollowing ends it too.
        self._visibility(self.friend, "followers")
        self.assertEqual(self.client.delete(f"/follows/following/{self.friend_id}", headers=self.me).status_code, 200)
        self.assertEqual(self.client.get("/feed", headers=self.me).json()["entries"], [])
        self.assertEqual(self.client.get(f"/results/{result['id']}", headers=self.me).status_code, 404)

    def test_gym_level_shows_results_at_shared_gyms(self) -> None:
        workout = self.client.post(
            "/programming/workouts",
            headers=self.admin,
            json={
                "scheduled_date": security.now_utc().date().isoformat(),
                "title": "WOD",
                "status": "published",
                "sections": [{"title": "Metcon", "description": "21-15-9", "score_type": "time", "workout_name": "Fran"}],
            },
        ).json()["workout"]
        gym_result = self.client.put(
            "/results", headers=self.mate, json={"section_id": workout["sections"][0]["id"], "score": "5:00"}
        ).json()["result"]
        self._personal(self.mate, "4:30")
        self.client.post("/follows", headers=self.me, json={"user_id": self.mate_id})
        self.client.post(f"/follows/requests/{self.my_id}/accept", headers=self.mate)
        # Default "My gym": only the gym result.
        feed = self.client.get("/feed", headers=self.me).json()["entries"]
        self.assertEqual([e["id"] for e in feed], [gym_result["id"]])
        self.assertEqual(feed[0]["gym_name"], "Home Box")
        # Only me: nothing, though the leaderboard rules for coaches stay.
        self._visibility(self.mate, "private")
        self.assertEqual(self.client.get("/feed", headers=self.me).json()["entries"], [])

    def test_followers_can_be_declined_and_removed(self) -> None:
        self.client.post("/follows", headers=self.me, json={"user_id": self.mate_id})
        self.assertEqual(self.client.delete(f"/follows/followers/{self.my_id}", headers=self.mate).status_code, 200)
        self.assertEqual(self.client.get("/follows", headers=self.me).json()["sent"], [])
        self.assertEqual(self.client.post(f"/follows/requests/{self.my_id}/accept", headers=self.mate).status_code, 404)
        self.client.post("/follows", headers=self.me, json={"user_id": self.mate_id})
        self.client.post(f"/follows/requests/{self.my_id}/accept", headers=self.mate)
        self.assertEqual(len(self.client.get("/follows", headers=self.mate).json()["followers"]), 1)
        self.assertEqual(len(self.client.get("/follows", headers=self.me).json()["following"]), 1)
        self.client.delete(f"/follows/followers/{self.my_id}", headers=self.mate)
        self.assertEqual(self.client.get("/follows", headers=self.me).json()["following"], [])

    def test_coaches_only_moderate_their_own_gym(self) -> None:
        self._visibility(self.friend, "followers")
        result = self._personal(self.friend)
        self._follow(self.me, self.friend, self.friend_id, code=True)
        comment = self.client.post(f"/results/{result['id']}/comments", headers=self.friend, json={"body": "PR soon"})
        comment_id = comment.json()["result"]["comments"][0]["id"]
        # The owner of my gym follows nobody: they can't see or moderate it.
        self.assertEqual(self.client.get(f"/results/{result['id']}", headers=self.admin).status_code, 404)
        self.assertEqual(self.client.delete(f"/results/comments/{comment_id}", headers=self.admin).status_code, 404)
        # I can't delete the friend's comment either, only see it.
        self.assertEqual(self.client.delete(f"/results/comments/{comment_id}", headers=self.me).status_code, 403)
