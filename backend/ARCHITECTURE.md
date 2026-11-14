# Backend Architecture

## Overview

The BoxOS backend is a FastAPI application on PostgreSQL. It is organized into three layers,
one folder each:

```
backend/
  fastapi_app.py      # entrypoint: creates the app, middleware, error handlers, includes routers
  api/                # 1. HTTP layer
    deps.py           #    auth/session dependencies (require_session, …) and the rate limiter
    common.py         #    the few request models and helpers shared by several routers
    routes/           #    one APIRouter per feature area, with its request models
    validators/       #    request validators used by a single router
  core/               # 2. shared infrastructure (no FastAPI)
  services/           # 3. domain logic, one module per feature area (no FastAPI)
  scripts/            # command-line entry points: manage, seed_demo, seed_results, test_data
  data/               # bundled seed data (movements, benchmark workouts)
  tests/
```

Uvicorn still starts `backend.fastapi_app:app`.

---

## 1. HTTP layer — `api/`

### `fastapi_app.py`
Creates the `FastAPI` app (lifespan runs `db.init_db()`), CORS, the `ApiError` and catch-all
exception handlers, and includes every router from `api/routes/`.

The include order matters: when two routers have overlapping paths, the one included first
wins (e.g. `results` with `/results/me` before `result_social` with `/results/{result_id}`).
Add a new router at the end unless it needs to win such a match.

### `api/routes/`
One module per feature area, each exposing `router = APIRouter()`:

| Router | Paths |
| --- | --- |
| `auth` | `/auth/*` (login, sign-up, tokens, password, account deletion) |
| `profile` | `/profile/*` (except results privacy) |
| `notifications` | `/notifications/*`, `/devices/*` |
| `gyms` | `/gyms/*` (gyms, logo, join requests, owners) |
| `members` | `/roles/*` (member list, roles, membership status) |
| `membership` | `/membership/*`, `/payments/*`, `/stripe/webhook` |
| `announcements` | `/announcements/*` |
| `schedule` | `/schedule/*`, `/class-types` |
| `programming` | `/programming/*` (daily WODs) |
| `movements` | `/movements/*`, `/gym-movements`, `/exercises`, `/workout-names` |
| `results` | `/results` logging, history, logbook, CSV export, `/benchmarks`, leaderboards |
| `result_social` | a single result: detail, fist bumps, comments, photo |
| `follows` | `/follows/*`, `/feed`, `/profile/results-privacy` |
| `community` | `/community/*` |
| `admin` | `/admin/*`, `/audit-logs` |
| `system` | `/health`, `/uploads/*` |

Routes map HTTP requests to service calls, check permissions and translate errors into
HTTP responses. Request models (`pydantic.BaseModel`) live in the router that uses them.

### `api/deps.py`
FastAPI dependencies shared by every router: `require_bearer_token`, `require_session`,
`require_admin_session`, `require_active_gym_member_session`,
`require_schedule_manager_session`, `require_admin_gym_session`, `require_gym_owner_session`,
and the in-memory `rate_limit` (tests call `reset_rate_limits()`).

### `api/validators/`
`require_*` validators that only one router uses, in a module of the same name
(`validators/schedule.py` for `routes/schedule.py`). Routers import it as `validators`.
Validators used by several routers, services or scripts stay in `core/validation.py`.

### `api/common.py`
Request models and helpers needed by more than one router (`GymIdRequest`,
`EntityIdRequest`, `get_gym_timezone`, `class_type_names`). Keep it small: if something is
only used by one router, it belongs in that router.

---

## 2. Core infrastructure — `core/`

These modules provide shared backend building blocks.
They should stay generic and reusable across domain areas.

### `core/settings.py`
Runtime configuration (mostly from `BOXOS_*` environment variables) and constants.

Examples:
- database URL
- uploads paths
- seed file paths
- token TTLs
- size limits
- role/account-type constants

### `core/security.py`
Security and time helpers.

Responsibilities:
- password hashing and verification
- token hashing and creation
- UTC timestamp helpers

### `core/db.py`
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

### `core/session_auth.py`
Session/token persistence helpers.

Responsibilities:
- create/delete sessions
- issue verification tokens
- issue password-reset tokens

### `core/validation.py`
`ApiError` and the validators shared across features.

Responsibilities:
- `ApiError`, raised by services and validators and turned into an HTTP response by
  `fastapi_app.py`
- role/account normalization and encoding (`encode_roles`, `decode_roles`, …)
- generic input checks: email, password, tokens, user ids, upload filenames, base64 data

### `core/notifications.py`
Shared notification primitives and related helpers.

Responsibilities:
- create notifications
- notification payload helpers
- shared schedule/programming notification support

### `core/audit.py`
Audit logging helpers.

Responsibilities:
- write audit logs
- shape audit log payloads

---

## 3. Domain service layer — `services/`

These modules contain business/domain logic grouped by feature area.

### `auth_service.py`
Reusable auth/session-related service helpers.

### `membership_service.py`
Gyms, memberships, roles and the active-gym context, plus the user/profile payloads.

### `plan_service.py` and `payment_service.py`
Membership plans and tokens; Stripe Connect. All Stripe calls go through
`payment_service.client`.

### `schedule_service.py`
Classes, bookings, waitlist, recurrence and schedule notifications.

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
WOD blocks (`replace_workout_sections`) and workout payload shaping.

### `programming_service.py`
Daily WODs (one per gym and day), programming and admin-analytics helpers.

### `movement_service.py`
The movement list (bundled plus a gym's own), renaming, archiving and merging.

### `results_service.py`, `result_social_service.py`, `follow_service.py`
Logged results, leaderboards and PRs; fist bumps, comments and photos; follows and the
friends feed.

---

## Dependency direction

Preferred dependency direction:

- `fastapi_app.py` -> `api/routes/`
- `api/routes/` -> `api/deps.py`, `api/common.py`, `api/validators/`, services, core
- services -> core (and other services where needed)
- core -> other small core modules only when necessary

Services and `core/validation.py` import `ManagedConnection` and `Row` from `core/db.py`
for type hints only (under `TYPE_CHECKING`), because `core/db.py` itself imports
`core/validation.py`.

Avoid:
- services or core depending on FastAPI or on `api/`
- one router importing from another router (move the shared piece to `api/common.py`
  or a service)
- reintroducing a monolithic catch-all module

---

## Scripts — `scripts/`

- `manage.py` — account administration: `python -m backend.scripts.manage create-user …`
- `seed_demo.py` — a complete demo box (members, weekly classes with bookings, WODs,
  results, community content) for local development:
  `docker compose exec backend-dev python -m backend.scripts.seed_demo`
- `test_data.py` — test members for a real box (`manage seed-test-data`)
- `seed_results.py` — logged results used by both of the above

---

## Testing

Tests run against a throwaway PostgreSQL container started via testcontainers
(`tests/pg.py`). Every test starts from an empty schema.

- `tests/` — tests per feature area (`test_auth.py`, `test_schedule.py`, …), sharing the
  `FastApiTestCase` base and helpers in `tests/support.py`
- `tests/test_fastapi_app.py` — longer end-to-end flows across several features

Run all of them with:

```bash
python3 -m unittest discover -s backend -p "test_*.py"
```

---

## Maintenance guidance

When adding new backend features:

1. add the endpoint to the router for its feature area in `api/routes/` (or a new router,
   included in `fastapi_app.py`)
2. put request validators used only by that router in `api/validators/<router>.py`, shared
   ones in `core/validation.py`
3. add feature logic to the appropriate service module in `services/`
4. add shared infra logic only to the relevant core module
5. add/update tests in `tests/`

If a new feature grows large, prefer a new focused router and service module over expanding
unrelated ones.
