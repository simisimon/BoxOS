from __future__ import annotations

from datetime import timedelta

from backend import security, settings
from backend.tests.support import FastApiTestCase


def _blocks() -> list[dict]:
    return [
        {"title": "Warm Up", "description": "500m row", "score_type": "none"},
        {
            "title": "Strength",
            "description": "Back Squat 5x5",
            "score_type": "weight",
            "kind": "exercise",
            "exercise_name": "back squat",
            "sets": [{"reps": 5, "value": 75}] * 5,
        },
        {
            "title": "Metcon",
            "description": "21-15-9 Thrusters, Pull-ups",
            "score_type": "time",
            "workout_name": "Fran",
        },
    ]


class StableBlockTests(FastApiTestCase):
    def _create(self, headers: dict[str, str], sections: list[dict], days: int = 0) -> dict:
        response = self.client.post(
            "/programming/workouts",
            headers=headers,
            json={
                "scheduled_date": (security.now_utc().date() + timedelta(days=days)).isoformat(),
                "title": "Test WOD",
                "sections": sections,
            },
        )
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()["workout"]

    def test_editing_keeps_ids_of_blocks_sent_back(self) -> None:
        headers, _ = self.create_gym_as_admin("Stable Box")
        workout = self._create(headers, _blocks())
        warm_up, strength, metcon = workout["sections"]

        # Reorder, edit one block, drop the warm-up, add a new block.
        edited = [
            {**metcon, "description": "21-15-9 Thrusters 43/30, Pull-ups"},
            strength,
            {"title": "Accessory", "description": "3x12 GHD", "score_type": "none"},
        ]
        response = self.client.patch(
            "/programming/workouts",
            headers=headers,
            json={
                "id": workout["id"],
                "scheduled_date": workout["scheduled_date"],
                "title": workout["title"],
                "sections": edited,
            },
        )
        self.assertEqual(response.status_code, 200, response.text)
        sections = response.json()["workout"]["sections"]
        self.assertEqual([s["title"] for s in sections], ["Metcon", "Strength", "Accessory"])
        self.assertEqual(sections[0]["id"], metcon["id"])
        self.assertEqual(sections[0]["description"], "21-15-9 Thrusters 43/30, Pull-ups")
        self.assertEqual(sections[1]["id"], strength["id"])
        self.assertNotIn(sections[2]["id"], {warm_up["id"], strength["id"], metcon["id"]})

    def test_duplicate_gets_new_block_ids(self) -> None:
        headers, _ = self.create_gym_as_admin("Copy Box")
        workout = self._create(headers, _blocks())
        response = self.client.post(
            "/programming/workouts/duplicate",
            headers=headers,
            json={
                "source_date": workout["scheduled_date"],
                "target_date": (security.now_utc().date() + timedelta(days=1)).isoformat(),
            },
        )
        self.assertEqual(response.status_code, 200, response.text)
        copy = response.json()["workout"]["sections"]
        self.assertEqual(len(copy), 3)
        self.assertTrue({s["id"] for s in copy}.isdisjoint({s["id"] for s in workout["sections"]}))
        self.assertEqual(copy[1]["movement_id"], workout["sections"][1]["movement_id"])
        self.assertEqual(copy[2]["workout_name"], "Fran")

    def test_new_score_types_and_invalid_one(self) -> None:
        headers, _ = self.create_gym_as_admin("Units Box")
        sections = [
            {"description": f"Block {score}", "score_type": score}
            for score in ("reps", "calories", "distance", "none", "rounds_reps")
        ]
        workout = self._create(headers, sections)
        self.assertEqual(
            [s["score_type"] for s in workout["sections"]],
            ["reps", "calories", "distance", "none", "rounds_reps"],
        )
        bad = self.client.post(
            "/programming/workouts",
            headers=headers,
            json={
                "scheduled_date": (security.now_utc().date() + timedelta(days=3)).isoformat(),
                "title": "Bad",
                "sections": [{"description": "x", "score_type": "points"}],
            },
        )
        self.assertEqual(bad.status_code, 400)


class MovementTests(FastApiTestCase):
    def test_exercise_names_resolve_to_one_movement(self) -> None:
        headers, _ = self.create_gym_as_admin("Movement Box")
        found = self.client.get("/movements", headers=headers, params={"query": "back squat"})
        self.assertEqual(found.status_code, 200, found.text)
        back_squat = found.json()["movements"][0]
        self.assertEqual(back_squat["name"], "Back Squat")
        self.assertTrue(back_squat["built_in"])

        sections = [
            {"description": "a", "score_type": "weight", "kind": "exercise", "exercise_name": name, "sets": [{"reps": 1}]}
            for name in ("Back Squat", "  back   SQUAT ", "BS", "Zercher Squat")
        ]
        response = self.client.post(
            "/programming/workouts",
            headers=headers,
            json={"scheduled_date": security.now_utc().date().isoformat(), "title": "Squats", "sections": sections},
        )
        self.assertEqual(response.status_code, 200, response.text)
        ids = [s["movement_id"] for s in response.json()["workout"]["sections"]]
        self.assertEqual(ids[:3], [back_squat["id"]] * 3)
        self.assertNotEqual(ids[3], back_squat["id"])

        zercher = self.client.get("/movements", headers=headers, params={"query": "zercher"}).json()["movements"]
        self.assertEqual([(m["name"], m["built_in"]) for m in zercher], [("Zercher Squat", False)])

        # Another gym does not see this gym's own movement.
        other_headers, other_gym = self.create_gym_as_admin("Other Box")
        self.add_active_membership(settings.DEMO_EMAIL, other_gym)
        athlete = self.auth_headers(settings.DEMO_EMAIL, settings.DEMO_PASSWORD)
        self.assertEqual(
            self.client.get("/movements", headers=athlete, params={"query": "zercher"}).json()["movements"],
            [],
        )

    def test_workout_names_offer_benchmarks_and_used_names(self) -> None:
        headers, _ = self.create_gym_as_admin("Names Box")
        self.client.post(
            "/programming/workouts",
            headers=headers,
            json={
                "scheduled_date": security.now_utc().date().isoformat(),
                "title": "Test",
                "sections": [{"description": "x", "score_type": "time", "workout_name": "Box Test 1"}],
            },
        )
        names = self.client.get("/workout-names", headers=headers, params={"query": "fr"}).json()["workout_names"]
        self.assertIn("Fran", names)
        used = self.client.get("/workout-names", headers=headers, params={"query": "box"}).json()["workout_names"]
        self.assertEqual(used, ["Box Test 1"])

    def test_linked_movement_has_instructions(self) -> None:
        headers, _ = self.create_gym_as_admin("How-to Box")
        squat = self.client.get("/movements", headers=headers, params={"query": "back squat"}).json()["movements"][0]
        detail = self.client.get(f"/movements/{squat['id']}", headers=headers)
        self.assertEqual(detail.status_code, 200, detail.text)
        movement = detail.json()["movement"]
        self.assertEqual(movement["name"], "Back Squat")
        self.assertTrue(movement["instructions"])
        self.assertIn("quadriceps", movement["primary_muscles"])

        workout = StableBlockTests._create(self, headers, [{**_blocks()[1], "exercise_name": "Banded Zercher Thing"}])
        own = self.client.get(f"/movements/{workout['sections'][0]['movement_id']}", headers=headers).json()["movement"]
        self.assertEqual(own["instructions"], [])
        self.assertEqual(self.client.get("/movements/999999", headers=headers).status_code, 404)


class MovementSettingsTests(FastApiTestCase):
    def setUp(self) -> None:
        super().setUp()
        self.admin, self.gym_id = self.create_gym_as_admin("Settings Box")
        self.add_active_membership(settings.DEMO_EMAIL, self.gym_id)
        self.athlete = self.auth_headers(settings.DEMO_EMAIL, settings.DEMO_PASSWORD)

    def _block(self, name: str, days: int = 0) -> dict:
        response = self.client.post(
            "/programming/workouts",
            headers=self.admin,
            json={
                "scheduled_date": (security.now_utc().date() + timedelta(days=days)).isoformat(),
                "title": "WOD",
                "status": "published",
                "sections": [{**_blocks()[1], "exercise_name": name}],
            },
        )
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()["workout"]["sections"][0]

    def test_rename_archive_and_merge(self) -> None:
        typo = self._block("Bak Squat")
        listed = self.client.get("/gym-movements", headers=self.admin).json()["movements"]
        self.assertEqual([(m["name"], m["block_count"]) for m in listed], [("Bak Squat", 1)])
        own_id = listed[0]["id"]

        clash = self.client.patch(f"/movements/{own_id}", headers=self.admin, json={"name": "back squat"})
        self.assertEqual(clash.status_code, 409, clash.text)
        renamed = self.client.patch(f"/movements/{own_id}", headers=self.admin, json={"name": "Banded Squat"})
        self.assertEqual(renamed.status_code, 200, renamed.text)
        self.assertEqual(renamed.json()["movement"]["name"], "Banded Squat")

        archived = self.client.patch(f"/movements/{own_id}", headers=self.admin, json={"archived": True})
        self.assertTrue(archived.json()["movement"]["archived"])
        search = self.client.get("/movements", headers=self.admin, params={"query": "banded squat"}).json()["movements"]
        self.assertEqual(search, [])

        # Built-ins can't be changed; the athlete can't manage movements.
        squat = self.client.get("/movements", headers=self.admin, params={"query": "back squat"}).json()["movements"][0]
        self.assertEqual(self.client.patch(f"/movements/{squat['id']}", headers=self.admin, json={"name": "X"}).status_code, 404)
        self.assertEqual(self.client.get("/gym-movements", headers=self.athlete).status_code, 403)

        self.client.put("/results", headers=self.athlete, json={"section_id": typo["id"], "sets": [{"reps": 5, "kg": 100}]})
        merged = self.client.post(f"/movements/{own_id}/merge", headers=self.admin, json={"into_id": squat["id"]})
        self.assertEqual(merged.status_code, 200, merged.text)
        self.assertEqual(self.client.get("/gym-movements", headers=self.admin).json()["movements"], [])
        mine = self.client.get("/results/me", headers=self.athlete, params={"movement_id": squat["id"]}).json()
        self.assertEqual(len(mine["results"]), 1)
        # The old name now resolves to the movement it was merged into.
        again = self._block("Banded Squat", days=1)
        self.assertEqual(again["movement_id"], squat["id"])

    def test_owner_sees_a_members_results_at_this_gym(self) -> None:
        block = self._block("Back Squat")
        self.client.put("/results", headers=self.athlete, json={"section_id": block["id"], "sets": [{"reps": 3, "kg": 90}]})
        me = self.client.get("/profile", headers=self.athlete).json()
        user_id = me.get("user", me).get("id")
        response = self.client.get(f"/membership/members/{user_id}/results", headers=self.admin)
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual([r["score_label"] for r in response.json()["results"]], ["90 kg"])
        self.assertEqual(self.client.get(f"/membership/members/{user_id}/results", headers=self.athlete).status_code, 403)
        self.assertEqual(self.client.get("/membership/members/999999/results", headers=self.admin).status_code, 404)
