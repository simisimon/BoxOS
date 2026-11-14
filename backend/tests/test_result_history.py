from __future__ import annotations

from datetime import timedelta

from backend import db, security, settings
from backend.tests.support import FastApiTestCase


def _metcon(name: str = "Fran") -> dict:
    return {"title": "Metcon", "description": "21-15-9", "score_type": "time", "workout_name": name}


def _squat(sets: list[dict]) -> dict:
    return {
        "title": "Strength",
        "description": "Back Squat",
        "score_type": "weight",
        "kind": "exercise",
        "exercise_name": "Back Squat",
        "sets": sets,
    }


class ResultHistoryTests(FastApiTestCase):
    def setUp(self) -> None:
        super().setUp()
        self.admin, self.gym_id = self.create_gym_as_admin("History Box")
        self.add_active_membership(settings.DEMO_EMAIL, self.gym_id)
        self.athlete = self.auth_headers(settings.DEMO_EMAIL, settings.DEMO_PASSWORD)
        self.create_verified_user("second@boxos.app")
        self.add_active_membership("second@boxos.app", self.gym_id)
        self.second = self.auth_headers("second@boxos.app", "BoxOS123!")

    def _workout(self, days_ago: int, sections: list[dict]) -> dict:
        """A published WOD dated ``days_ago`` days back (moved there in the
        database, since the API only programs today and later)."""
        today = security.now_utc().date()
        response = self.client.post(
            "/programming/workouts",
            headers=self.admin,
            json={"scheduled_date": today.isoformat(), "title": "WOD", "status": "published", "sections": sections},
        )
        self.assertEqual(response.status_code, 200, response.text)
        workout = response.json()["workout"]
        if days_ago:
            connection = db.get_connection()
            try:
                with connection:
                    connection.execute(
                        "update daily_workouts set scheduled_date = ? where id = ?",
                        ((today - timedelta(days=days_ago)).isoformat(), workout["id"]),
                    )
            finally:
                connection.close()
        return workout

    def _log(self, headers: dict, body: dict) -> dict:
        response = self.client.put("/results", headers=headers, json=body)
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()["result"]

    def test_faster_time_is_a_pr_and_first_is_baseline(self) -> None:
        first = self._workout(20, [_metcon()])["sections"][0]
        second = self._workout(10, [_metcon()])["sections"][0]
        third = self._workout(0, [_metcon("fran")])["sections"][0]

        self.assertFalse(self._log(self.athlete, {"section_id": first["id"], "score": "4:30"})["is_pr"])
        self.assertTrue(self._log(self.athlete, {"section_id": second["id"], "score": "4:10"})["is_pr"])
        self.assertFalse(self._log(self.athlete, {"section_id": third["id"], "score": "4:20"})["is_pr"])
        # Scaled is its own baseline.
        self.assertFalse(
            self._log(self.athlete, {"section_id": third["id"], "score": "3:00", "division": "scaled"})["is_pr"]
        )

        history = self.client.get("/results/history", headers=self.athlete, params={"section_id": third["id"]}).json()
        self.assertEqual([r["score_label"] for r in history["results"]], ["3:00", "4:10", "4:30"])
        self.assertEqual([r["is_pr"] for r in history["results"]], [False, True, False])
        self.assertEqual(history["best"]["rx"], history["results"][1]["id"])

    def test_back_logging_moves_the_pr(self) -> None:
        older = self._workout(10, [_metcon()])["sections"][0]
        newer = self._workout(0, [_metcon()])["sections"][0]
        self.assertFalse(self._log(self.athlete, {"section_id": newer["id"], "score": "4:00"})["is_pr"])
        # Logging an older, slower Fran makes today's result a PR.
        self._log(self.athlete, {"section_id": older["id"], "score": "5:00"})
        history = self.client.get("/results/history", headers=self.athlete, params={"section_id": newer["id"]}).json()
        self.assertEqual([r["is_pr"] for r in history["results"]], [True, False])

    def test_lifts_compare_per_rep_count(self) -> None:
        base = self._workout(20, [_squat([{"reps": 5}])])["sections"][0]
        heavier_single = self._workout(10, [_squat([{"reps": 1}])])["sections"][0]
        lighter_triple = self._workout(0, [_squat([{"reps": 3}])])["sections"][0]
        self._log(self.athlete, {"section_id": base["id"], "sets": [{"reps": 5, "kg": 100}]})
        self.assertTrue(
            self._log(self.athlete, {"section_id": heavier_single["id"], "sets": [{"reps": 1, "kg": 120}]})["is_pr"]
        )
        # 3 reps at 105: heavier than any earlier set of 3+ reps (the 5 @ 100).
        self.assertTrue(
            self._log(self.athlete, {"section_id": lighter_triple["id"], "sets": [{"reps": 3, "kg": 105}]})["is_pr"]
        )
        history = self.client.get("/results/history", headers=self.athlete, params={"section_id": base["id"]}).json()
        self.assertEqual(history["best_sets"], [{"reps": 1, "kg": 120}, {"reps": 3, "kg": 105}, {"reps": 5, "kg": 100}])

    def test_leaderboard_ranks_rx_first_and_capped_last(self) -> None:
        workout = self._workout(0, [_metcon(), {"title": "AMRAP", "description": "Cindy", "score_type": "rounds_reps"}])
        metcon, amrap = workout["sections"]
        self.create_verified_user("third@boxos.app")
        self.add_active_membership("third@boxos.app", self.gym_id)
        third = self.auth_headers("third@boxos.app", "BoxOS123!")

        self._log(self.athlete, {"section_id": metcon["id"], "score": "4:30", "notes": "Felt slow"})
        self._log(self.second, {"section_id": metcon["id"], "score": "120", "time_capped": True})
        self._log(third, {"section_id": metcon["id"], "score": "3:50", "division": "scaled"})
        self._log(self.second, {"section_id": amrap["id"], "score": "15+3"})
        self._log(third, {"section_id": amrap["id"], "score": "15+3"})

        board = self.client.get(f"/programming/workouts/{workout['id']}/leaderboard", headers=self.second)
        self.assertEqual(board.status_code, 200, board.text)
        sections = {s["section_id"]: s["entries"] for s in board.json()["sections"]}
        fran = sections[metcon["id"]]
        self.assertEqual([e["score_label"] for e in fran], ["4:30", "CAP · 120 reps", "3:50"])
        self.assertEqual([e["rank"] for e in fran], [1, 2, 3])
        self.assertEqual([e["is_me"] for e in fran], [False, True, False])
        # Other athletes' notes stay private.
        self.assertEqual(fran[0]["notes"], "")
        self.assertEqual([e["rank"] for e in sections[amrap["id"]]], [1, 1])

        staff = self.client.get(f"/programming/workouts/{workout['id']}/leaderboard", headers=self.admin).json()
        staff_fran = {s["section_id"]: s["entries"] for s in staff["sections"]}[metcon["id"]]
        self.assertEqual(staff_fran[0]["notes"], "Felt slow")

    def test_draft_leaderboard_is_hidden_from_athletes(self) -> None:
        response = self.client.post(
            "/programming/workouts",
            headers=self.admin,
            json={
                "scheduled_date": (security.now_utc().date() + timedelta(days=1)).isoformat(),
                "title": "Draft",
                "sections": [_metcon()],
            },
        )
        workout_id = response.json()["workout"]["id"]
        self.assertEqual(self.client.get(f"/programming/workouts/{workout_id}/leaderboard", headers=self.athlete).status_code, 404)
        self.assertEqual(self.client.get(f"/programming/workouts/{workout_id}/leaderboard", headers=self.admin).status_code, 200)

    def test_my_results_filters_by_movement_or_workout(self) -> None:
        old = self._workout(5, [_metcon(), _squat([{"reps": 5}])])["sections"]
        new = self._workout(0, [_metcon(), _squat([{"reps": 5}])])["sections"]
        self._log(self.athlete, {"section_id": old[0]["id"], "score": "4:30"})
        self._log(self.athlete, {"section_id": new[0]["id"], "score": "4:00"})
        self._log(self.athlete, {"section_id": old[1]["id"], "sets": [{"reps": 5, "kg": 100}]})
        self._log(self.second, {"section_id": new[0]["id"], "score": "3:00"})

        everything = self.client.get("/results/me", headers=self.athlete).json()
        self.assertEqual(len(everything["results"]), 3)
        labels = {f["label"]: f for f in everything["filters"]}
        self.assertEqual(labels["Fran"]["count"], 2)
        self.assertEqual(labels["Back Squat"]["count"], 1)

        fran = self.client.get("/results/me", headers=self.athlete, params={"workout_name": "fran"}).json()
        self.assertEqual([r["score_label"] for r in fran["results"]], ["4:00", "4:30"])
        self.assertEqual([r["is_pr"] for r in fran["results"]], [True, False])
        squat = self.client.get(
            "/results/me", headers=self.athlete, params={"movement_id": labels["Back Squat"]["movement_id"]}
        ).json()
        self.assertEqual(squat["best_sets"], [{"reps": 5, "kg": 100}])

    def test_private_results_leave_the_gym_leaderboard(self) -> None:
        workout = self._workout(0, [_metcon()])
        metcon = workout["sections"][0]
        self.assertEqual(self.client.get("/profile/results-privacy", headers=self.second).json(), {"visibility": "gym"})
        self._log(self.athlete, {"section_id": metcon["id"], "score": "4:30"})
        self._log(self.second, {"section_id": metcon["id"], "score": "4:00"})
        changed = self.client.patch("/profile/results-privacy", headers=self.second, json={"visibility": "private"})
        self.assertEqual(changed.status_code, 200, changed.text)
        self.assertEqual(
            self.client.patch("/profile/results-privacy", headers=self.second, json={"visibility": "world"}).status_code,
            400,
        )

        def board(headers: dict) -> list[dict]:
            response = self.client.get(f"/programming/workouts/{workout['id']}/leaderboard", headers=headers)
            return response.json()["sections"][0]["entries"]

        def count(headers: dict) -> int:
            workouts = self.client.get("/programming/workouts", headers=headers).json()["workouts"]
            return workouts[0]["sections"][0]["result_count"]

        self.assertEqual([e["score_label"] for e in board(self.athlete)], ["4:30"])
        self.assertEqual(count(self.athlete), 1)
        self.assertEqual([e["score_label"] for e in board(self.second)], ["4:00", "4:30"])
        self.assertEqual([e["score_label"] for e in board(self.admin)], ["4:00", "4:30"])
        self.assertEqual(count(self.admin), 2)

    def test_results_export_as_csv(self) -> None:
        old = self._workout(5, [_metcon(), _squat([{"reps": 5}])])["sections"]
        new = self._workout(0, [_metcon()])["sections"]
        self._log(self.athlete, {"section_id": old[0]["id"], "score": "4:30", "notes": "=cmd"})
        self._log(self.athlete, {"section_id": new[0]["id"], "score": "4:00", "division": "rx"})
        self._log(self.athlete, {"section_id": old[1]["id"], "sets": [{"reps": 5, "kg": 100}, {"reps": 5, "kg": 102.5}]})

        response = self.client.get("/results/me.csv", headers=self.athlete)
        self.assertEqual(response.status_code, 200, response.text)
        self.assertTrue(response.headers["content-type"].startswith("text/csv"))
        lines = response.text.strip().splitlines()
        self.assertEqual(lines[0], "date,gym,block,movement,workout,score_type,result,division,time_capped,sets,pr,notes")
        self.assertEqual(len(lines), 4)
        self.assertIn("History Box,Strength,Back Squat,,weight,102.5 kg,Rx,,5 x 100 kg; 5 x 102.5 kg,,", response.text)
        self.assertTrue(lines[-1].endswith(",Metcon,,Fran,time,4:00,Rx,,,yes,"))
        self.assertIn("'=cmd", response.text)
