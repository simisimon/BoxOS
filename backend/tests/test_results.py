from __future__ import annotations

from datetime import timedelta

from backend import security, settings
from backend.tests.support import FastApiTestCase


def _blocks() -> list[dict]:
    return [
        {"title": "Warm Up", "description": "Row", "score_type": "none"},
        {
            "title": "Strength",
            "description": "Back Squat",
            "score_type": "weight",
            "kind": "exercise",
            "exercise_name": "Back Squat",
            "sets": [{"reps": 5, "value": 75}, {"reps": 5, "value": 80}],
        },
        {"title": "Metcon", "description": "Fran", "score_type": "time", "workout_name": "Fran"},
        {"title": "AMRAP", "description": "Cindy", "score_type": "rounds_reps"},
    ]


class ResultTests(FastApiTestCase):
    def setUp(self) -> None:
        super().setUp()
        self.admin, self.gym_id = self.create_gym_as_admin("Results Box")
        self.add_active_membership(settings.DEMO_EMAIL, self.gym_id)
        self.athlete = self.auth_headers(settings.DEMO_EMAIL, settings.DEMO_PASSWORD)

    def _workout(self, *, days: int = 0, status: str = "published") -> dict:
        response = self.client.post(
            "/programming/workouts",
            headers=self.admin,
            json={
                "scheduled_date": (security.now_utc().date() + timedelta(days=days)).isoformat(),
                "title": "Results WOD",
                "status": status,
                "sections": _blocks(),
            },
        )
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()["workout"]

    def _log(self, headers: dict, body: dict):
        return self.client.put("/results", headers=headers, json=body)

    def _sections_for(self, headers: dict) -> list[dict]:
        workouts = self.client.get("/programming/workouts", headers=headers).json()["workouts"]
        return workouts[0]["sections"]

    def test_athlete_logs_each_score_type(self) -> None:
        _, strength, metcon, amrap = self._workout()["sections"]

        timed = self._log(self.athlete, {"section_id": metcon["id"], "score": "4:12", "division": "rx", "notes": "Unbroken thrusters"})
        self.assertEqual(timed.status_code, 200, timed.text)
        self.assertEqual(timed.json()["result"]["score_label"], "4:12")
        self.assertEqual(timed.json()["result"]["score_value"], 252)
        self.assertEqual(timed.json()["result"]["workout_name"], "Fran")

        rounds = self._log(self.athlete, {"section_id": amrap["id"], "score": "7+14", "division": "scaled"})
        self.assertEqual(rounds.json()["result"]["score_label"], "7+14")
        self.assertEqual(rounds.json()["result"]["score_value"], 7014)

        lifted = self._log(
            self.athlete,
            {"section_id": strength["id"], "sets": [{"reps": 5, "kg": 90}, {"reps": 5, "kg": "97,5"}]},
        )
        self.assertEqual(lifted.status_code, 200, lifted.text)
        self.assertEqual(lifted.json()["result"]["score_label"], "97.5 kg")
        self.assertEqual(lifted.json()["result"]["movement_id"], strength["movement_id"])

        sections = self._sections_for(self.athlete)
        self.assertIsNone(sections[0]["my_result"])
        self.assertEqual(sections[2]["my_result"]["notes"], "Unbroken thrusters")
        self.assertEqual(sections[3]["my_result"]["division"], "scaled")
        self.assertEqual([s["result_count"] for s in sections], [0, 1, 1, 1])

    def test_logging_again_replaces_and_capped_time_counts_reps(self) -> None:
        metcon = self._workout()["sections"][2]
        self._log(self.athlete, {"section_id": metcon["id"], "score": "5:00"})
        capped = self._log(self.athlete, {"section_id": metcon["id"], "score": "80", "time_capped": True})
        self.assertEqual(capped.status_code, 200, capped.text)
        self.assertEqual(capped.json()["result"]["score_label"], "CAP · 80 reps")
        self.assertTrue(capped.json()["result"]["time_capped"])
        self.assertEqual(self._sections_for(self.athlete)[2]["result_count"], 1)

    def test_bad_scores_and_blocks_are_refused(self) -> None:
        warm_up, strength, metcon, amrap = self._workout()["sections"]
        for body in (
            {"section_id": warm_up["id"], "score": "1"},
            {"section_id": metcon["id"], "score": "4:75"},
            {"section_id": amrap["id"], "score": "seven"},
            {"section_id": strength["id"], "sets": [{"reps": 5}]},
            {"section_id": metcon["id"], "score": "4:00", "division": "elite"},
        ):
            self.assertEqual(self._log(self.athlete, body).status_code, 400, body)

    def test_drafts_and_future_workouts_cannot_be_logged(self) -> None:
        future = self._workout(days=2)["sections"][2]
        self.assertEqual(self._log(self.athlete, {"section_id": future["id"], "score": "4:00"}).status_code, 400)
        draft = self._workout(days=3, status="draft")["sections"][2]
        self.assertEqual(self._log(self.athlete, {"section_id": draft["id"], "score": "4:00"}).status_code, 404)

    def test_other_gyms_block_is_not_found(self) -> None:
        metcon = self._workout()["sections"][2]
        _, other_gym = self.create_gym_as_admin("Other Box")
        self.create_verified_user("other@boxos.app")
        self.add_active_membership("other@boxos.app", other_gym)
        other = self.auth_headers("other@boxos.app", "BoxOS123!")
        self.assertEqual(self._log(other, {"section_id": metcon["id"], "score": "4:00"}).status_code, 404)

    def test_my_result_is_only_mine_and_can_be_deleted(self) -> None:
        metcon = self._workout()["sections"][2]
        self._log(self.athlete, {"section_id": metcon["id"], "score": "4:00"})
        coach_view = self._sections_for(self.admin)
        self.assertIsNone(coach_view[2]["my_result"])
        self.assertEqual(coach_view[2]["result_count"], 1)

        deleted = self.client.request("DELETE", "/results", headers=self.athlete, json={"section_id": metcon["id"]})
        self.assertEqual(deleted.status_code, 200, deleted.text)
        self.assertIsNone(self._sections_for(self.athlete)[2]["my_result"])
        again = self.client.request("DELETE", "/results", headers=self.athlete, json={"section_id": metcon["id"]})
        self.assertEqual(again.status_code, 404)

    def test_logged_blocks_keep_their_shape(self) -> None:
        workout = self._workout()
        sections = workout["sections"]
        self._log(self.athlete, {"section_id": sections[2]["id"], "score": "4:00"})

        def save(new_sections: list[dict]):
            return self.client.patch(
                "/programming/workouts",
                headers=self.admin,
                json={
                    "id": workout["id"],
                    "scheduled_date": workout["scheduled_date"],
                    "title": workout["title"],
                    "status": "published",
                    "sections": new_sections,
                },
            )

        removed = save([s for s in sections if s["id"] != sections[2]["id"]])
        self.assertEqual(removed.status_code, 409, removed.text)
        rescored = save([{**s, "score_type": "reps"} if s["id"] == sections[2]["id"] else s for s in sections])
        self.assertEqual(rescored.status_code, 409, rescored.text)
        reworded = save([{**s, "description": "Fran, 43/30 kg"} if s["id"] == sections[2]["id"] else s for s in sections])
        self.assertEqual(reworded.status_code, 200, reworded.text)
        self.assertEqual(self._sections_for(self.athlete)[2]["my_result"]["score_label"], "4:00")
