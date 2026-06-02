# Backend Architecture

## Overview

The BoxOS backend is now fully FastAPI-based.

There is no legacy HTTP runtime layer anymore.
The backend is organized into three layers:

1. **Route/runtime layer**
2. **Core infrastructure layer**
3. **Domain service layer**

---

## 1. Route/runtime layer

### `fastapi_app.py`

This is the only HTTP entrypoint.

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
Shared constants and runtime configuration values.

Examples:
- database path
- uploads path
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
Database bootstrap and persistence infrastructure.

Responsibilities:
- SQLite connection creation
- schema initialization
- migrations/column checks
- seed/bootstrap logic
- default/demo user seeding

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
Gym membership and active-context logic.

### `schedule_service.py`
Schedule, bookings, waitlist, recurrence, and schedule-notification helpers.

### `announcement_service.py`
Announcements, comments, permissions, and announcement-activity notifications.

### `workout_service.py`
Workout/logbook/whiteboard payload shaping and PR-related workout helpers.

### `programming_service.py`
Programming/admin-analytics helpers and composition over workout-related helpers.

---

## Dependency direction

Preferred dependency direction:

- `fastapi_app.py` -> core modules + domain services
- domain services -> core modules
- core modules -> other small core modules only when necessary

Avoid:
- domain services depending on FastAPI
- core modules depending on FastAPI
- reintroducing a monolithic catch-all module

---

## Removed legacy pieces

The following legacy runtime files are gone:
- `server.py`
- `core.py`
- `legacy_http.py`

FastAPI is the only supported backend runtime.

---

## Testing

### `test_fastapi_app.py`
Covers FastAPI flows for:
- auth/session flows
- profile updates
- gyms/memberships/roles
- scheduling/bookings/waitlist
- announcements/notifications
- programming/logbook/personal workouts
- audit logs and admin analytics

---

## Maintenance guidance

When adding new backend features:

1. add validation to `validation.py` if needed
2. add shared infra logic only to the relevant core module
3. add feature logic to the appropriate service module
4. keep `fastapi_app.py` thin
5. add/update FastAPI tests

If a new feature grows large, prefer a new focused service module over expanding unrelated modules.
