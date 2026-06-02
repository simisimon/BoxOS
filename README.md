# BoxOS

Production-oriented platform for running a CrossFit box and supporting athlete training.

## Product direction
- Single-gym first
- Athlete-first mobile experience built with Flutter
- Admin-focused backoffice surface for operations and configuration
- Admin workflows remain accessible in the mobile app for on-the-go management
- Additional modules can be added in phases after the production core platform is in place

## Current development stack
- Frontend: Flutter client in `app/`
- Backend runtime: FastAPI in `backend/fastapi_app.py`
- Shared backend logic lives in focused modules under `backend/` (for example `db.py`, `validation.py`, `security.py`, and service modules)

## Backend structure

### Runtime
- `backend/fastapi_app.py` — FastAPI entrypoint and route layer

### Core infrastructure
- `backend/settings.py` — shared constants, paths, seed file locations, limits, runtime settings
- `backend/security.py` — password hashing, token hashing/creation, timestamp helpers
- `backend/db.py` — SQLite connection, schema init, migrations, seed/bootstrap logic
- `backend/session_auth.py` — session creation/deletion and verification/reset token issuance
- `backend/validation.py` — request/domain validation and normalization helpers
- `backend/notifications_core.py` — notification creation and shared notification/schedule helper logic
- `backend/audit.py` — audit-log payload shaping and audit-log writes

### Domain services
- `backend/auth_service.py` — auth/session-related reusable service helpers
- `backend/membership_service.py` — gyms, memberships, active-gym/user-context helpers
- `backend/schedule_service.py` — scheduling and waitlist-related helper logic
- `backend/announcement_service.py` — announcements/comments/announcement notifications
- `backend/workout_service.py` — workout/logbook/whiteboard payload and PR helper logic
- `backend/programming_service.py` — programming/admin-analytics-related helpers and workout-service composition

### Tests
- `backend/test_fastapi_app.py` — FastAPI backend tests

### Removed legacy layer
- The old HTTP transport (`server.py`, `legacy_http.py`) has been removed.
- FastAPI is now the only backend runtime.

## Local backend
FastAPI backend:
```bash
cd /data/.openclaw/workspace/github/BoxOS
python3 -m pip install -r backend/requirements-fastapi.txt
sh backend/run-fastapi-dev.sh
```

The backend starts on `http://127.0.0.1:8080`.

Permanent dev logins:
- Athlete: `demo@boxos.app` / `BoxOS123!`
- Admin: `admin@boxos.app` / `BoxOS123!`

## Local app
```powershell
cd C:\GitHub\BoxOS\app
copy env\dev.example.json env\dev.json
.\run-dev.ps1
```

`env/dev.json` should contain:

```json
{
  "ENV": "dev",
  "API_BASE_URL": "http://127.0.0.1:8080",
  "AUTH_REDIRECT_URL": "http://localhost:3000/auth/callback"
}
```

## Validation

Flutter app:
```powershell
cd C:\GitHub\BoxOS\app
dart analyze
flutter test
```

Backend:
```bash
cd /data/.openclaw/workspace/github/BoxOS
python3 -m unittest backend.test_fastapi_app
```

## Notes
- Supabase is no longer the active backend path for the app.
- The legacy `supabase/` project files have been removed from this repository.
- Signup, login, logout, password reset, change password, and account deletion now target the local REST backend.
- Signup verification and password reset tokens are printed in the backend terminal for local development flows.
