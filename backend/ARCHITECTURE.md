# Backend Architecture

## Overview

The BoxOS backend is a FastAPI application on PostgreSQL. It is organized into three layers:

1. **Route layer** — `fastapi_app.py`
2. **Core infrastructure layer** — settings, security, database, validation, notifications, audit
3. **Domain service layer** — one module per feature area

---

## 1. Route layer

### `fastapi_app.py`

The only HTTP entrypoint.

Responsibilities:
- define FastAPI routes
- map HTTP requests to domain/service operations
- handle auth/session dependencies
- translate validation/domain errors into HTTP responses

This file should stay focused on transport concerns and endpoint orchestration.

---

## 2. Core infrastructure layer

These modules provide shared backend building blocks.
They should stay generic and reusable across domain areas.

### `settings.py`
Runtime configuration (mostly from `BOXOS_*` environment variables) and constants.

Examples:
- database URL
- uploads paths
- seed file paths
- token TTLs
- size limits
- role/account-type constants

### `security.py`
Security and time helpers.

Responsibilities:
- password hashing and verification
- token hashing and creation
- UTC timestamp helpers

### `db.py`
Database access and bootstrap.

Responsibilities:
- `ManagedConnection`, a thin psycopg wrapper: `?` placeholders, `with connection:` as a
  transaction, rows as dicts (the `Row` type)
- schema creation (`SCHEMA_SQL`, applied idempotently on every start)
- seeding exercises, benchmark workouts and the default test accounts
- purging accounts whose deletion grace period has passed

There is no migration tool yet. The schema only uses `create table/index if not exists`,
so a new column on an existing table needs an explicit `alter table` until a migration tool
(e.g. Alembic) is introduced.

### `session_auth.py`
Session/token persistence helpers.

Responsibilities:
- create/delete sessions
- issue verification tokens
- issue password-reset tokens

### `validation.py`
Input validation and normalization.

Responsibilities:
- `require_*` request/domain validators
- role/account normalization
- scheduling/programming validation helpers
- parsing helpers for structured inputs

### `notifications_core.py`
Shared notification primitives and related helpers.

Responsibilities:
- create notifications
- notification payload helpers
- shared schedule/programming notification support

### `audit.py`
Audit logging helpers.

Responsibilities:
- write audit logs
- shape audit log payloads

---

## 3. Domain service layer

These modules contain business/domain logic grouped by feature area.

### `auth_service.py`
Reusable auth/session-related service helpers.

### `membership_service.py`
Gyms, memberships, roles and the active-gym context.

### `schedule_service.py`
Classes, bookings, waitlist and schedule notifications.

Weekly classes are stored as templates in `class_templates`. Their bookable sessions are
generated into `class_schedules` (linked via `class_template_id`) when the schedule is
fetched, for a rolling horizon of `TEMPLATE_HORIZON_DAYS`. `generated_until` records how far
a template has been generated, so a session deleted by an owner is not re-created. One-off
sessions have no template.

### `announcement_service.py`
Announcements, comments, permissions, and announcement-activity notifications.

### `community_service.py`
Community chat message payloads.

### `workout_service.py`
Workout/logbook payload shaping and PR-related workout helpers.

### `programming_service.py`
Daily WODs (one per gym and day), programming and admin-analytics helpers.

---

## Dependency direction

Preferred dependency direction:

- `fastapi_app.py` -> core modules + domain services
- domain services -> core modules
- core modules -> other small core modules only when necessary

Domain services and `validation.py` import `ManagedConnection` and `Row` from `db.py` for
type hints only (under `TYPE_CHECKING`), because `db.py` itself imports `validation.py`.

Avoid:
- domain services depending on FastAPI
- core modules depending on FastAPI
- reintroducing a monolithic catch-all module

---

## Demo data

`seed_demo.py` builds a complete demo box (members, weekly classes with bookings, WODs,
community content) for local development:

```bash
docker compose exec backend-dev python -m backend.seed_demo
```

---

## Testing

Tests run against a throwaway PostgreSQL container started via testcontainers
(`tests/pg.py`). Every test starts from an empty schema.

- `tests/` — tests per feature area (`test_auth.py`, `test_schedule.py`, …), sharing the
  `FastApiTestCase` base and helpers in `tests/support.py`
- `test_fastapi_app.py` — longer end-to-end flows across several features

Run all of them with:

```bash
python3 -m unittest discover -s backend -p "test_*.py"
```

---

## Maintenance guidance

When adding new backend features:

1. add validation to `validation.py` if needed
2. add shared infra logic only to the relevant core module
3. add feature logic to the appropriate service module
4. keep `fastapi_app.py` thin
5. add/update tests in `tests/`

If a new feature grows large, prefer a new focused service module over expanding unrelated modules.
