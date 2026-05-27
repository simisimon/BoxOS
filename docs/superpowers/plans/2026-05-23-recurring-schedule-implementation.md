# Recurring Schedule Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add recurring class creation for daily, weekly, and monthly (every 4 weeks) schedules with required occurrence counts, while keeping schedule edits and deletes instance-based.

**Architecture:** Extend the existing schedule create endpoint and schedule repository contract with optional recurrence fields, then generate multiple normal `class_schedules` rows on create. Keep the current instance-based model for bookings, waitlists, attendance, edits, and deletes so the feature fits the current production-core design without adding a series table.

**Tech Stack:** Python backend with SQLite, Flutter with Riverpod, existing widget tests and backend `unittest`

---

### Task 1: Backend recurring creation contract and validation

**Files:**
- Modify: `backend/test_server.py`
- Modify: `backend/server.py`

- [ ] **Step 1: Write the failing backend test for daily recurring class creation**

```python
    def test_admin_can_create_daily_recurring_schedule_classes(self) -> None:
        login_response = self.post_json(
            "/auth/login",
            {
                "email": server.ADMIN_EMAIL,
                "password": server.ADMIN_PASSWORD,
            },
        )
        self.post_json_with_auth(
            "/gyms",
            {
                "name": "Recurring Daily Gym",
                "logo_url": "https://example.com/recurring-daily.png",
                "timezone": "Europe/Berlin",
            },
            access_token=login_response["access_token"],
        )
        start_time = server.now_utc() + timedelta(days=1)
        created = self.post_json_with_auth(
            "/schedule/classes",
            {
                "title": "Daily WOD",
                "class_type": "WOD",
                "start_time": server.isoformat(start_time),
                "capacity": 12,
                "duration_minutes": 60,
                "recurrence_frequency": "daily",
                "occurrence_count": 3,
            },
            access_token=login_response["access_token"],
        )

        self.assertEqual(created["created_count"], 3)
        self.assertEqual(len(created["classes"]), 3)
        self.assertEqual(created["class"]["title"], "Daily WOD")
        self.assertEqual(
            created["classes"][1]["start_time"],
            server.isoformat(start_time + timedelta(days=1)),
        )
        self.assertEqual(
            created["classes"][2]["start_time"],
            server.isoformat(start_time + timedelta(days=2)),
        )
```

- [ ] **Step 2: Run the backend test to verify it fails**

Run: `python -m unittest backend.test_server.BoxOsServerTests.test_admin_can_create_daily_recurring_schedule_classes`
Expected: `FAIL` because the create response does not yet return recurring classes or counts.

- [ ] **Step 3: Write minimal recurring validation and multi-row creation in `backend/server.py`**

```python
def require_recurrence_frequency(value: Any) -> str:
    frequency = str(value or "none").strip().lower()
    allowed = {"none", "daily", "weekly", "monthly"}
    if frequency not in allowed:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Invalid recurrence frequency.")
    return frequency


def require_occurrence_count(value: Any, *, recurrence_frequency: str) -> int:
    if recurrence_frequency == "none":
        return 1
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        raise ApiError(HTTPStatus.BAD_REQUEST, "Occurrence count must be a whole number.")
    if parsed < 1:
        raise ApiError(HTTPStatus.BAD_REQUEST, "Occurrence count must be at least 1.")
    return parsed


def recurrence_delta_for(frequency: str) -> timedelta:
    if frequency == "daily":
        return timedelta(days=1)
    if frequency == "weekly":
        return timedelta(days=7)
    if frequency == "monthly":
        return timedelta(days=28)
    return timedelta(days=0)
```

Add recurrence parsing at the top of `handle_create_schedule_class`, generate `occurrence_count` start times, insert one row per occurrence, and return:

```python
        self.send_json(
            HTTPStatus.CREATED,
            {
                "class": payloads[0],
                "classes": payloads,
                "created_count": len(payloads),
            },
        )
```

- [ ] **Step 4: Run the backend test to verify it passes**

Run: `python -m unittest backend.test_server.BoxOsServerTests.test_admin_can_create_daily_recurring_schedule_classes`
Expected: `OK`

- [ ] **Step 5: Commit**

```bash
git add backend/test_server.py backend/server.py
git commit -m "feat: add recurring daily schedule creation"
```

### Task 2: Backend recurrence edge cases

**Files:**
- Modify: `backend/test_server.py`
- Modify: `backend/server.py`

- [ ] **Step 1: Write failing backend tests for weekly, monthly, and invalid recurrence input**

```python
    def test_admin_can_create_weekly_recurring_schedule_classes(self) -> None:
        login_response = self.post_json(
            "/auth/login",
            {
                "email": server.ADMIN_EMAIL,
                "password": server.ADMIN_PASSWORD,
            },
        )
        self.post_json_with_auth(
            "/gyms",
            {
                "name": "Recurring Weekly Gym",
                "logo_url": "https://example.com/recurring-weekly.png",
                "timezone": "Europe/Berlin",
            },
            access_token=login_response["access_token"],
        )
        start_time = server.now_utc() + timedelta(days=1)
        created = self.post_json_with_auth(
            "/schedule/classes",
            {
                "title": "Weekly WOD",
                "class_type": "WOD",
                "start_time": server.isoformat(start_time),
                "capacity": 12,
                "duration_minutes": 60,
                "recurrence_frequency": "weekly",
                "occurrence_count": 3,
            },
            access_token=login_response["access_token"],
        )

        self.assertEqual(
            created["classes"][1]["start_time"],
            server.isoformat(start_time + timedelta(days=7)),
        )
        self.assertEqual(
            created["classes"][2]["start_time"],
            server.isoformat(start_time + timedelta(days=14)),
        )

    def test_admin_can_create_monthly_recurring_schedule_classes(self) -> None:
        login_response = self.post_json(
            "/auth/login",
            {
                "email": server.ADMIN_EMAIL,
                "password": server.ADMIN_PASSWORD,
            },
        )
        self.post_json_with_auth(
            "/gyms",
            {
                "name": "Recurring Monthly Gym",
                "logo_url": "https://example.com/recurring-monthly.png",
                "timezone": "Europe/Berlin",
            },
            access_token=login_response["access_token"],
        )
        start_time = server.now_utc() + timedelta(days=1)
        created = self.post_json_with_auth(
            "/schedule/classes",
            {
                "title": "Monthly WOD",
                "class_type": "WOD",
                "start_time": server.isoformat(start_time),
                "capacity": 12,
                "duration_minutes": 60,
                "recurrence_frequency": "monthly",
                "occurrence_count": 3,
            },
            access_token=login_response["access_token"],
        )

        self.assertEqual(
            created["classes"][1]["start_time"],
            server.isoformat(start_time + timedelta(days=28)),
        )
        self.assertEqual(
            created["classes"][2]["start_time"],
            server.isoformat(start_time + timedelta(days=56)),
        )

    def test_schedule_creation_rejects_invalid_recurrence_inputs(self) -> None:
        login_response = self.post_json(
            "/auth/login",
            {
                "email": server.ADMIN_EMAIL,
                "password": server.ADMIN_PASSWORD,
            },
        )
        self.post_json_with_auth(
            "/gyms",
            {
                "name": "Recurring Validation Gym",
                "logo_url": "https://example.com/recurring-validation.png",
                "timezone": "Europe/Berlin",
            },
            access_token=login_response["access_token"],
        )
        start_time = server.now_utc() + timedelta(days=1)

        invalid_frequency = requests.post(
            f"{self.base_url}/schedule/classes",
            json={
                "title": "Broken Recurrence",
                "class_type": "WOD",
                "start_time": server.isoformat(start_time),
                "capacity": 12,
                "duration_minutes": 60,
                "recurrence_frequency": "hourly",
                "occurrence_count": 2,
            },
            headers={"Authorization": f"Bearer {login_response['access_token']}"},
            timeout=5,
        )
        self.assertEqual(invalid_frequency.status_code, HTTPStatus.BAD_REQUEST)
        self.assertIn("Invalid recurrence frequency", invalid_frequency.json()["error"])

        invalid_count = requests.post(
            f"{self.base_url}/schedule/classes",
            json={
                "title": "Broken Count",
                "class_type": "WOD",
                "start_time": server.isoformat(start_time),
                "capacity": 12,
                "duration_minutes": 60,
                "recurrence_frequency": "weekly",
                "occurrence_count": 0,
            },
            headers={"Authorization": f"Bearer {login_response['access_token']}"},
            timeout=5,
        )
        self.assertEqual(invalid_count.status_code, HTTPStatus.BAD_REQUEST)
        self.assertIn("Occurrence count must be at least 1", invalid_count.json()["error"])
```

- [ ] **Step 2: Run the backend tests to verify they fail**

Run: `python -m unittest backend.test_server.BoxOsServerTests.test_admin_can_create_weekly_recurring_schedule_classes backend.test_server.BoxOsServerTests.test_admin_can_create_monthly_recurring_schedule_classes backend.test_server.BoxOsServerTests.test_schedule_creation_rejects_invalid_recurrence_inputs`
Expected: `FAIL` on missing recurrence behavior or validation.

- [ ] **Step 3: Finish recurrence handling and audit detail updates**

Extend the create audit details with:

```python
                details={
                    "title": title,
                    "class_type": class_type,
                    "start_time": isoformat(start_times[0]),
                    "duration_minutes": duration_minutes,
                    "capacity": capacity,
                    "trainer_user_id": trainer_user_id,
                    "recurrence_frequency": recurrence_frequency,
                    "occurrence_count": occurrence_count,
                },
```

Ensure the row generation uses:

```python
        delta = recurrence_delta_for(recurrence_frequency)
        start_times = [
            start_time + (delta * index)
            for index in range(occurrence_count)
        ]
```

and validates every generated start time with:

```python
        for generated_start_time in start_times:
            if generated_start_time <= now_utc():
                connection.close()
                raise ApiError(
                    HTTPStatus.BAD_REQUEST,
                    "Recurring classes must all be scheduled in the future.",
                )
```

- [ ] **Step 4: Run the backend tests to verify they pass**

Run: `python -m unittest backend.test_server.BoxOsServerTests.test_admin_can_create_weekly_recurring_schedule_classes backend.test_server.BoxOsServerTests.test_admin_can_create_monthly_recurring_schedule_classes backend.test_server.BoxOsServerTests.test_schedule_creation_rejects_invalid_recurrence_inputs`
Expected: `OK`

- [ ] **Step 5: Commit**

```bash
git add backend/test_server.py backend/server.py
git commit -m "feat: validate recurring schedule frequencies"
```

### Task 3: Flutter repository contract and create-form recurrence UI

**Files:**
- Modify: `app/lib/features/calendar/domain/repositories/schedule_repository.dart`
- Modify: `app/lib/features/calendar/data/repositories/api_schedule_repository.dart`
- Modify: `app/test/widget_test.dart`

- [ ] **Step 1: Write the failing widget test for recurring schedule creation controls**

```dart
  testWidgets('Trainer can create a recurring class from schedule screen', (
    tester,
  ) async {
    final scheduleRepository = RecordingScheduleRepository();
    await tester.pumpWidget(
      buildTestApp(
        role: UserRole.trainer,
        scheduleRepository: scheduleRepository,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Class'));
    await tester.pumpAndSettle();

    expect(find.text('Repeat'), findsOneWidget);
    expect(find.text('Does not repeat'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weekly').last);
    await tester.pumpAndSettle();

    expect(find.text('Occurrences'), findsOneWidget);
  });
```

- [ ] **Step 2: Run the widget test to verify it fails**

Run: `flutter test app/test/widget_test.dart --plain-name "Trainer can create a recurring class from schedule screen"`
Expected: `FAIL` because recurrence controls do not exist yet.

- [ ] **Step 3: Extend the schedule repository create contract with recurrence fields**

Update the repository interface and API implementation to accept:

```dart
  Future<ScheduleClass> createClass({
    required String title,
    required String classType,
    required DateTime startTime,
    required int durationMinutes,
    required int capacity,
    required int trainerUserId,
    required String wodDescription,
    String recurrenceFrequency = 'none',
    int occurrenceCount = 1,
  });
```

and send:

```dart
      'recurrence_frequency': recurrenceFrequency,
      'occurrence_count': occurrenceCount,
```

in the API request body.

- [ ] **Step 4: Run the widget test again to verify it still fails for the expected UI gap**

Run: `flutter test app/test/widget_test.dart --plain-name "Trainer can create a recurring class from schedule screen"`
Expected: `FAIL` because the create form still lacks the recurrence fields.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/calendar/domain/repositories/schedule_repository.dart app/lib/features/calendar/data/repositories/api_schedule_repository.dart app/test/widget_test.dart
git commit -m "refactor: extend schedule repository for recurrence"
```

### Task 4: Flutter recurring form submission

**Files:**
- Modify: `app/lib/features/calendar/presentation/screens/calendar_screen.dart`
- Modify: `app/test/widget_test.dart`

- [ ] **Step 1: Write the failing widget expectation for recurrence submission**

```dart
    await tester.enterText(find.byType(TextFormField).at(0), 'Recurring WOD');
    await tester.tap(find.text('Does not repeat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weekly').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Occurrences'), '4');
    await tester.tap(find.text('Save Class'));
    await tester.pumpAndSettle();

    expect(scheduleRepository.lastRecurrenceFrequency, 'weekly');
    expect(scheduleRepository.lastOccurrenceCount, 4);
```

- [ ] **Step 2: Run the widget test to verify it fails**

Run: `flutter test app/test/widget_test.dart --plain-name "Trainer can create a recurring class from schedule screen"`
Expected: `FAIL` because recurrence values are not yet captured or submitted.

- [ ] **Step 3: Add recurrence controls to the create form and submit them**

Add create-form state like:

```dart
  static const _recurrenceOptions = {
    'none': 'Does not repeat',
    'daily': 'Daily',
    'weekly': 'Weekly',
    'monthly': 'Monthly (every 4 weeks)',
  };

  late String _selectedRecurrenceFrequency;
  late final TextEditingController _occurrenceCountController;
```

Initialize:

```dart
    _selectedRecurrenceFrequency = 'none';
    _occurrenceCountController = TextEditingController(text: '4');
```

Render:

```dart
            DropdownButtonFormField<String>(
              initialValue: _selectedRecurrenceFrequency,
              decoration: const InputDecoration(labelText: 'Repeat'),
              items: _recurrenceOptions.entries
                  .map(
                    (entry) => DropdownMenuItem<String>(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedRecurrenceFrequency = value);
                }
              },
            ),
            if (_selectedRecurrenceFrequency != 'none') ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _occurrenceCountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Occurrences'),
                validator: (value) {
                  final parsed = int.tryParse((value ?? '').trim());
                  if (parsed == null || parsed <= 0) {
                    return 'Enter a valid occurrence count';
                  }
                  return null;
                },
              ),
            ],
```

and submit:

```dart
            recurrenceFrequency: _selectedRecurrenceFrequency,
            occurrenceCount: _selectedRecurrenceFrequency == 'none'
                ? 1
                : int.parse(_occurrenceCountController.text.trim()),
```

- [ ] **Step 4: Run the widget test to verify it passes**

Run: `flutter test app/test/widget_test.dart --plain-name "Trainer can create a recurring class from schedule screen"`
Expected: `PASS`

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/calendar/presentation/screens/calendar_screen.dart app/test/widget_test.dart
git commit -m "feat: add recurring class creation controls"
```

### Task 5: Verification and story documentation

**Files:**
- Modify: `requirements.md`
- Modify: `user_stories.md`
- Modify: `status.md`

- [ ] **Step 1: Run focused verification**

Run: `python -m unittest backend.test_server`
Expected: `OK`

Run: `flutter test app/test/widget_test.dart --plain-name "Trainer can create a recurring class from schedule screen"`
Expected: `PASS`

Run: `flutter analyze`
Expected: `No issues found`

- [ ] **Step 2: Update product and story documentation**

Update `requirements.md` to include recurring scheduling support in the scheduling section:

```md
- Future classes can be created individually or as recurring schedule instances
```

Update `user_stories.md`:

```md
#### US-B1-03 - Recurring class schedule management
**Status:** Complete
```

and replace the delivery notes with:

```md
**Delivery Notes**
- Live schedule create, edit, and delete flows exist for future classes.
- Recurring class creation now supports daily, weekly, and monthly schedules.
- Monthly recurrence is implemented as every 4 weeks on the same weekday and time.
- Recurring creation requires an explicit occurrence count.
- Edit and delete behavior remains instance-based for this slice.
```

Update `status.md` current focus to remove recurring scheduling and keep role hardening as the next active item.

- [ ] **Step 3: Run a final quick verification after doc updates**

Run: `python -m unittest backend.test_server.BoxOsServerTests.test_admin_can_create_daily_recurring_schedule_classes`
Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add requirements.md user_stories.md status.md
git commit -m "docs: mark recurring scheduling complete"
```
