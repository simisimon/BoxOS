from __future__ import annotations

from datetime import timedelta

from backend import db, notifications_core, security, settings, validation
from backend.tests.support import FastApiTestCase


class NotificationCoreTests(FastApiTestCase):
    def create_schedule_class(self, headers: dict[str, str], *, title: str = "Noon WOD") -> int:
        created = self.client.post(
            "/schedule/classes",
            headers=headers,
            json={
                "title": title,
                "class_type": "WOD",
                "start_time": security.isoformat(security.now_utc() + timedelta(days=1)),
                "duration_minutes": 60,
                "capacity": 10,
                "recurrence_frequency": "none",
            },
        )
        self.assertEqual(created.status_code, 201, created.text)
        return int(created.json()["class"]["id"])

    def test_booking_confirmation_and_schedule_update_notifications_respect_preferences(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("Notify Box")
        self.add_active_membership(settings.DEMO_EMAIL, gym_id)
        self.create_verified_user("silent@boxos.app")
        silent_user_id = self.add_active_membership("silent@boxos.app", gym_id)
        class_id = self.create_schedule_class(admin_headers)

        connection = db.get_connection()
        try:
            with connection:
                connection.execute(
                    "update users set notify_booking_confirmations = 0 where id = ?",
                    (silent_user_id,),
                )
                notifications_core.create_booking_confirmation_notification(
                    connection,
                    user_id=self.lookup_user_id(settings.DEMO_EMAIL),
                    gym_id=gym_id,
                    class_schedule_id=class_id,
                )
                notifications_core.create_booking_confirmation_notification(
                    connection,
                    user_id=silent_user_id,
                    gym_id=gym_id,
                    class_schedule_id=class_id,
                )
                notifications_core.create_schedule_update_notifications(
                    connection,
                    gym_id=gym_id,
                    class_schedule_id=class_id,
                    user_ids=[self.lookup_user_id(settings.DEMO_EMAIL), self.lookup_user_id(settings.DEMO_EMAIL), silent_user_id],
                )

            rows = connection.execute(
                "select user_id, type, title from notifications order by id asc"
            ).fetchall()
        finally:
            connection.close()

        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0]["type"], "booking_confirmed")
        self.assertEqual(rows[1]["type"], "schedule_updated")
        self.assertTrue(all(row["user_id"] == self.lookup_user_id(settings.DEMO_EMAIL) for row in rows))

    def test_waitlist_promotion_creates_booking_and_notification(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("Waitlist Notify Box")
        self.create_verified_user("wait-promote@boxos.app")
        promoted_user_id = self.add_active_membership("wait-promote@boxos.app", gym_id)
        class_id = self.create_schedule_class(admin_headers, title="Evening Burner")

        connection = db.get_connection()
        try:
            timestamp = security.isoformat(security.now_utc())
            with connection:
                connection.execute(
                    "insert into class_waitlist_entries (class_schedule_id, user_id, created_at) values (?, ?, ?)",
                    (class_id, promoted_user_id, timestamp),
                )
                user_id = notifications_core.promote_next_waitlisted_user(connection, class_schedule_id=class_id)
                self.assertEqual(user_id, promoted_user_id)
                notifications_core.create_waitlist_promotion_notification(
                    connection,
                    user_id=promoted_user_id,
                    gym_id=gym_id,
                    class_schedule_id=class_id,
                )

            booking_count = connection.execute(
                "select count(*) as count from class_bookings where class_schedule_id = ? and user_id = ?",
                (class_id, promoted_user_id),
            ).fetchone()["count"]
            waitlist_count = connection.execute(
                "select count(*) as count from class_waitlist_entries where class_schedule_id = ?",
                (class_id,),
            ).fetchone()["count"]
            notification = connection.execute(
                "select type, title from notifications where user_id = ? order by id desc limit 1",
                (promoted_user_id,),
            ).fetchone()
        finally:
            connection.close()

        self.assertEqual(booking_count, 1)
        self.assertEqual(waitlist_count, 0)
        self.assertEqual(notification["type"], "waitlist_promoted")
        self.assertEqual(notification["title"], "You are in the class")

    def test_wod_and_pr_notifications_respect_membership_and_preferences(self) -> None:
        admin_headers, gym_id = self.create_gym_as_admin("Wod Notify Box")
        athlete_user_id = self.add_active_membership(settings.DEMO_EMAIL, gym_id)
        self.create_verified_user("no-wod@boxos.app")
        muted_user_id = self.add_active_membership("no-wod@boxos.app", gym_id)
        self.create_verified_user("other-gym@boxos.app")
        other_user_id = self.lookup_user_id("other-gym@boxos.app")

        connection = db.get_connection()
        try:
            with connection:
                connection.execute("update users set notify_wod_posted = 0 where id = ?", (muted_user_id,))
                connection.execute("update users set notify_pr_achievements = 0 where id = ?", (muted_user_id,))
                notifications_core.create_wod_notifications(
                    connection,
                    gym_id=gym_id,
                    workout_id=11,
                    scheduled_date=security.now_utc().date().isoformat(),
                    title="Fran",
                    is_update=False,
                )
                notifications_core.create_pr_achievement_notification(
                    connection,
                    user_id=athlete_user_id,
                    gym_id=gym_id,
                    workout_id=11,
                    workout_title="Fran",
                    score_label="5:55",
                )
                notifications_core.create_pr_achievement_notification(
                    connection,
                    user_id=muted_user_id,
                    gym_id=gym_id,
                    workout_id=11,
                    workout_title="Fran",
                    score_label="6:10",
                )
                notifications_core.create_pr_achievement_notification(
                    connection,
                    user_id=other_user_id,
                    gym_id=gym_id,
                    workout_id=11,
                    workout_title="Fran",
                    score_label="4:50",
                )

            wod_notifications = connection.execute(
                "select user_id from notifications where type = 'wod_posted' order by user_id"
            ).fetchall()
            pr_notifications = connection.execute(
                "select user_id, body from notifications where type = 'pr_achieved' order by user_id"
            ).fetchall()
        finally:
            connection.close()

        wod_user_ids = [row["user_id"] for row in wod_notifications]
        self.assertIn(athlete_user_id, wod_user_ids)
        self.assertNotIn(muted_user_id, wod_user_ids)

        self.assertEqual([row["user_id"] for row in pr_notifications], [athlete_user_id, other_user_id])
        self.assertEqual(pr_notifications[0]["body"], "Fran: 5:55")

    def test_announcement_activity_notifications_skip_self_and_truncate_comments(self) -> None:
        _, gym_id = self.create_gym_as_admin("Announcement Notify Box")
        self.create_verified_user("author@boxos.app")
        self.create_verified_user("actor@boxos.app")
        author_id = self.add_active_membership("author@boxos.app", gym_id, roles=["trainer"], active_role="trainer")
        actor_id = self.add_active_membership("actor@boxos.app", gym_id)

        connection = db.get_connection()
        try:
            with connection:
                notifications_core.create_announcement_like_notification(
                    connection,
                    recipient_user_id=author_id,
                    actor_user_id=actor_id,
                    gym_id=gym_id,
                    announcement_id=7,
                    announcement_title="Gym Party",
                )
                notifications_core.create_announcement_like_notification(
                    connection,
                    recipient_user_id=author_id,
                    actor_user_id=author_id,
                    gym_id=gym_id,
                    announcement_id=7,
                    announcement_title="Gym Party",
                )
                notifications_core.create_announcement_comment_notification(
                    connection,
                    recipient_user_id=author_id,
                    actor_user_id=actor_id,
                    gym_id=gym_id,
                    announcement_id=7,
                    announcement_title="Gym Party",
                    comment_body="x" * 100,
                )

            rows = connection.execute(
                "select type, body from notifications where user_id = ? order by id asc",
                (author_id,),
            ).fetchall()
        finally:
            connection.close()

        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0]["type"], "announcement_liked")
        self.assertIn('actor@boxos.app liked "Gym Party".', rows[0]["body"])
        self.assertEqual(rows[1]["type"], "announcement_commented")
        self.assertTrue(rows[1]["body"].endswith("..."))

    def test_notification_payload_helpers_map_database_rows(self) -> None:
        connection = db.get_connection()
        try:
            user = connection.execute("select * from users where email = ?", (settings.DEMO_EMAIL,)).fetchone()
            with connection:
                connection.execute(
                    "insert into notifications (user_id, gym_id, type, title, body, entity_type, entity_id, created_at) values (?, NULL, 'demo', 'Hello', 'World', 'thing', 9, ?)",
                    (user["id"], security.isoformat(security.now_utc())),
                )
            row = connection.execute("select * from notifications order by id desc limit 1").fetchone()
        finally:
            connection.close()

        payload = notifications_core.notification_payload(row)
        prefs = notifications_core.notification_preferences_payload(user)
        self.assertEqual(payload["type"], "demo")
        self.assertEqual(payload["entity_id"], 9)
        self.assertIn("booking_confirmations", prefs)
        self.assertIn("announcement_activity", prefs)
