from __future__ import annotations

from datetime import timedelta

from backend import security, settings
from backend.tests.support import FastApiTestCase


def _day(days_ago: int) -> str:
    return (security.now_utc().date() - timedelta(days=days_ago)).isoformat()


class PersonalResultTests(FastApiTestCase):
    def setUp(self) -> None:
        super().setUp()
        self.admin, self.gym_id = self.create_gym_as_admin("Logbook Box")
        self.add_active_membership(settings.DEMO_EMAIL, self.gym_id)
        self.athlete = self.auth_headers(settings.DEMO_EMAIL, settings.DEMO_PASSWORD)

    def _log(self, body: dict, status: int = 200) -> dict:
        response = self.client.post("/results/personal", headers=self.athlete, json=body)
        self.assertEqual(response.status_code, status, response.text)
        return response.json()

    def test_benchmark_catalog_has_girls_and_heroes(self) -> None:
        response = self.client.get("/benchmarks", headers=self.athlete)
        self.assertEqual(response.status_code, 200, response.text)
        benchmarks = {b["id"]: b for b in response.json()["benchmarks"]}
        self.assertGreaterEqual(len(benchmarks), 30)
        self.assertEqual(benchmarks["fran"]["score_type"], "time")
        self.assertIn("21-15-9 Thruster (43/30 kg)", benchmarks["fran"]["description"])
        self.assertEqual(benchmarks["cindy"]["score_type"], "rounds_reps")
        self.assertTrue(benchmarks["cindy"]["description"].startswith("AMRAP 20 min:"))
        self.assertEqual(benchmarks["the_seven"]["category"], "hero")

    def test_benchmark_results_build_history_and_prs(self) -> None:
        first = self._log({"kind": "benchmark", "benchmark_id": "fran", "performed_on": _day(30), "score": "5:10"})
        self.assertFalse(first["result"]["is_pr"])
        self.assertEqual(first["result"]["source"], "personal")
        self.assertEqual(first["result"]["workout_name"], "Fran")
        self.assertIsNone(first["result"]["section_id"])
        second = self._log({"kind": "benchmark", "benchmark_id": "fran", "performed_on": _day(5), "score": "4:40"})
        self.assertTrue(second["result"]["is_pr"])

        mine = self.client.get("/results/me", headers=self.athlete, params={"workout_name": "Fran"}).json()
        self.assertEqual([r["score_label"] for r in mine["results"]], ["4:40", "5:10"])
        self.assertEqual([r["is_pr"] for r in mine["results"]], [True, False])

        # A gym Fran counts against the personal ones.
        today = security.now_utc().date().isoformat()
        workout = self.client.post(
            "/programming/workouts",
            headers=self.admin,
            json={
                "scheduled_date": today,
                "title": "WOD",
                "status": "published",
                "sections": [{"title": "Metcon", "description": "21-15-9", "score_type": "time", "workout_name": "Fran"}],
            },
        ).json()["workout"]
        section = workout["sections"][0]
        logged = self.client.put("/results", headers=self.athlete, json={"section_id": section["id"], "score": "4:20"})
        self.assertTrue(logged.json()["result"]["is_pr"])
        history = self.client.get("/results/history", headers=self.athlete, params={"section_id": section["id"]}).json()
        self.assertEqual(len(history["results"]), 3)

        # Personal results stay off the leaderboard.
        board = self.client.get(f"/programming/workouts/{workout['id']}/leaderboard", headers=self.admin).json()
        self.assertEqual(sum(len(s["entries"]) for s in board["sections"]), 1)
        # And out of the coach's view of the member.
        user_id = board["sections"][0]["entries"][0]["user_id"]
        member = self.client.get(f"/membership/members/{user_id}/results", headers=self.admin)
        self.assertEqual(member.status_code, 200, member.text)
        self.assertEqual([r["score_label"] for r in member.json()["results"]], ["4:20"])

    def test_movement_result_takes_sets(self) -> None:
        self._log(
            {"kind": "movement", "movement_name": "back squat", "performed_on": _day(10), "sets": [{"reps": 5, "kg": 100}]}
        )
        heavier = self._log(
            {"kind": "movement", "movement_name": "Back Squat", "performed_on": _day(1), "sets": [{"reps": 3, "kg": 110}]}
        )["result"]
        self.assertTrue(heavier["is_pr"])
        self.assertEqual(heavier["section_title"], "Back Squat")
        self.assertEqual(heavier["score_label"], "110 kg")
        mine = self.client.get("/results/me", headers=self.athlete, params={"movement_id": heavier["movement_id"]}).json()
        self.assertEqual(mine["best_sets"], [{"reps": 3, "kg": 110}, {"reps": 5, "kg": 100}])
        self._log({"kind": "movement", "movement_name": "Not A Lift", "performed_on": _day(1), "sets": [{"reps": 1, "kg": 1}]}, 400)

    def test_custom_workout_and_validation(self) -> None:
        result = self._log(
            {
                "kind": "custom",
                "title": "Hotel  Chain",
                "description": "5 rounds: 400 m run, 20 burpees",
                "score_type": "rounds_reps",
                "performed_on": _day(0),
                "score": "4+12",
                "division": "scaled",
            }
        )["result"]
        self.assertEqual(result["workout_name"], "Hotel Chain")
        self.assertEqual(result["description"], "5 rounds: 400 m run, 20 burpees")
        self.assertEqual(result["score_label"], "4+12")
        self._log({"kind": "custom", "title": "", "score_type": "time", "performed_on": _day(0), "score": "3:00"}, 400)
        self._log({"kind": "custom", "title": "X", "score_type": "none", "performed_on": _day(0), "score": "3"}, 400)
        self._log({"kind": "benchmark", "benchmark_id": "fran", "performed_on": _day(-5), "score": "3:00"}, 400)
        self._log({"kind": "benchmark", "benchmark_id": "nope", "performed_on": _day(0), "score": "3:00"}, 400)

    def test_edit_delete_and_csv(self) -> None:
        result = self._log({"kind": "benchmark", "benchmark_id": "grace", "performed_on": _day(2), "score": "3:00"})["result"]
        updated = self.client.put(
            f"/results/personal/{result['id']}",
            headers=self.athlete,
            json={"kind": "benchmark", "benchmark_id": "grace", "performed_on": _day(3), "score": "2:45", "notes": "Touch and go"},
        )
        self.assertEqual(updated.status_code, 200, updated.text)
        self.assertEqual(updated.json()["result"]["score_label"], "2:45")
        self.assertEqual(updated.json()["result"]["performed_on"], _day(3))

        csv_text = self.client.get("/results/me.csv", headers=self.athlete).text
        self.assertIn("Personal,Grace,,Grace,time,2:45", csv_text)

        # Someone else can't edit or delete it.
        self.create_verified_user("other@boxos.app")
        other = self.auth_headers("other@boxos.app", "BoxOS123!")
        self.assertEqual(
            self.client.delete(f"/results/personal/{result['id']}", headers=other).status_code, 404
        )
        self.assertEqual(self.client.delete(f"/results/personal/{result['id']}", headers=self.athlete).status_code, 200)
        self.assertEqual(self.client.get("/results/me", headers=self.athlete).json()["results"], [])

    def test_gym_results_cannot_be_edited_as_personal(self) -> None:
        today = security.now_utc().date().isoformat()
        workout = self.client.post(
            "/programming/workouts",
            headers=self.admin,
            json={"scheduled_date": today, "title": "WOD", "status": "published",
                  "sections": [{"title": "Metcon", "description": "For time", "score_type": "time"}]},
        ).json()["workout"]
        gym_result = self.client.put(
            "/results", headers=self.athlete, json={"section_id": workout["sections"][0]["id"], "score": "5:00"}
        ).json()["result"]
        self.assertEqual(gym_result["source"], "gym")
        response = self.client.put(
            f"/results/personal/{gym_result['id']}",
            headers=self.athlete,
            json={"kind": "custom", "title": "X", "score_type": "time", "performed_on": today, "score": "1:00"},
        )
        self.assertEqual(response.status_code, 404)
