# Scheduling Waitlist And Booking Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add class waitlists, automatic promotion on cancellation, and in-app booking-related notifications to the existing BoxOS scheduling flow.

**Architecture:** Extend the existing SQLite-backed scheduling model in `backend/server.py` with a waitlist table and synchronous promotion logic. Reuse the current in-app `notifications` table and Flutter schedule repository so the client only needs richer schedule state plus two new waitlist actions.

**Tech Stack:** Python standard library HTTP server + SQLite, Flutter, Riverpod, Dio, unittest

---

## File Structure

**Create**
- `docs/superpowers/specs/2026-05-17-scheduling-waitlist-and-booking-notifications-design.md`
- `docs/superpowers/plans/2026-05-17-scheduling-waitlist-and-booking-notifications.md`

**Modify**
- `backend/server.py`
- `backend/test_server.py`
- `app/lib/features/calendar/domain/models/schedule_class.dart`
- `app/lib/features/calendar/domain/repositories/schedule_repository.dart`
- `app/lib/features/calendar/data/repositories/api_schedule_repository.dart`
- `app/lib/features/calendar/presentation/screens/calendar_screen.dart`

---

### Task 1: Backend Waitlist Persistence And Payload

**Files:**
- Modify: `backend/server.py`
- Test: `backend/test_server.py`

- [ ] **Step 1: Write failing backend tests for waitlist creation and schedule payload**

Add tests that prove:
- a full future class accepts a waitlist join
- duplicate waitlist joins are rejected
- schedule payload exposes `waitlist_count` and `is_waitlisted`

- [ ] **Step 2: Run targeted tests to verify they fail**

Run:
```powershell
python -m unittest backend.test_server.BackendServerTests.test_waitlist_join_for_full_class backend.test_server.BackendServerTests.test_schedule_payload_includes_waitlist_state
```

Expected:
- failing assertions or missing endpoint behavior

- [ ] **Step 3: Implement minimal backend waitlist storage and payload fields**

Update `backend/server.py` to:
- create `class_waitlist_entries`
- expose waitlist state from `schedule_class_payload`
- add `POST /schedule/waitlist`
- add `DELETE /schedule/waitlist`

- [ ] **Step 4: Re-run targeted tests**

Run:
```powershell
python -m unittest backend.test_server.BackendServerTests.test_waitlist_join_for_full_class backend.test_server.BackendServerTests.test_schedule_payload_includes_waitlist_state
```

Expected:
- PASS

---

### Task 2: Promotion On Cancellation

**Files:**
- Modify: `backend/server.py`
- Test: `backend/test_server.py`

- [ ] **Step 1: Write failing backend test for promotion on cancellation**

Add a test that proves:
- when an athlete cancels a full class
- the oldest waitlisted athlete becomes booked
- the waitlist entry is removed

- [ ] **Step 2: Run the targeted test to verify it fails**

Run:
```powershell
python -m unittest backend.test_server.BackendServerTests.test_cancelling_booking_promotes_next_waitlisted_athlete
```

Expected:
- FAIL because promotion logic does not exist yet

- [ ] **Step 3: Implement minimal synchronous promotion logic**

Update `backend/server.py` to:
- look up the oldest waitlist entry after a cancellation
- convert that entry into a booking when space opens
- keep FIFO ordering

- [ ] **Step 4: Re-run the targeted test**

Run:
```powershell
python -m unittest backend.test_server.BackendServerTests.test_cancelling_booking_promotes_next_waitlisted_athlete
```

Expected:
- PASS

---

### Task 3: Booking And Schedule Notifications

**Files:**
- Modify: `backend/server.py`
- Test: `backend/test_server.py`

- [ ] **Step 1: Write failing backend tests for booking confirmation, waitlist promotion, and schedule-change notifications**

Add tests that prove:
- successful booking writes a notification when preference is enabled
- auto-promotion writes a waitlist promotion notification when preference is enabled
- schedule updates write notifications for affected booked athletes

- [ ] **Step 2: Run the targeted tests to verify they fail**

Run:
```powershell
python -m unittest backend.test_server.BackendServerTests.test_booking_confirmation_notification backend.test_server.BackendServerTests.test_waitlist_promotion_notification backend.test_server.BackendServerTests.test_schedule_update_notifies_affected_athletes
```

Expected:
- FAIL because notification fan-out is incomplete

- [ ] **Step 3: Implement minimal notification writes**

Update `backend/server.py` to:
- reuse the existing notifications table
- respect `notify_booking_confirmations` and `notify_waitlist_promotions`
- write simple schedule-change notifications for affected users

- [ ] **Step 4: Re-run the targeted tests**

Run:
```powershell
python -m unittest backend.test_server.BackendServerTests.test_booking_confirmation_notification backend.test_server.BackendServerTests.test_waitlist_promotion_notification backend.test_server.BackendServerTests.test_schedule_update_notifies_affected_athletes
```

Expected:
- PASS

---

### Task 4: Flutter Schedule Waitlist Support

**Files:**
- Modify: `app/lib/features/calendar/domain/models/schedule_class.dart`
- Modify: `app/lib/features/calendar/domain/repositories/schedule_repository.dart`
- Modify: `app/lib/features/calendar/data/repositories/api_schedule_repository.dart`
- Modify: `app/lib/features/calendar/presentation/screens/calendar_screen.dart`

- [ ] **Step 1: Add client-side failing expectations**

Use the existing widget or repository coverage surface if available; otherwise add the smallest focused coverage that proves:
- schedule parsing reads `waitlist_count` and `is_waitlisted`
- the screen shows `Join Waitlist` for a full class
- the screen shows `Leave Waitlist` for a waitlisted class

- [ ] **Step 2: Run the smallest relevant Flutter tests**

Run:
```powershell
cd app
flutter test test/widget_test.dart
```

Expected:
- failure in schedule waitlist expectations or an existing environment hang that must be noted

- [ ] **Step 3: Implement minimal client changes**

Update Flutter code to:
- parse the new backend fields
- add `joinWaitlist` and `leaveWaitlist`
- update the schedule card button state and labels

- [ ] **Step 4: Re-run the smallest relevant Flutter tests**

Run:
```powershell
cd app
flutter test test/widget_test.dart
```

Expected:
- PASS if the environment allows it, otherwise document the hang and rely on manual/static verification plus backend coverage

---

### Task 5: Final Verification And Documentation Sync

**Files:**
- Modify: `requirements.md`
- Modify: `user_stories.md`
- Modify: `status.md`

- [ ] **Step 1: Run backend verification**

Run:
```powershell
python -m unittest backend.test_server
```

Expected:
- PASS

- [ ] **Step 2: Run app analysis**

Run:
```powershell
cd app
dart analyze
```

Expected:
- PASS

- [ ] **Step 3: Update project tracking docs for delivered story progress**

Reflect:
- `US-B1-04` progress
- `US-F1-01` progress
- current remaining gaps if any

- [ ] **Step 4: Summarize residual risks**

Call out:
- missing external push delivery
- any remaining recurring scheduling work
- any Flutter test instability that prevented stronger client verification
