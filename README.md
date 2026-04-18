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
- Backend for local development: Python standard-library HTTP server + SQLite in `backend/server.py`

## Local backend
```powershell
cd C:\GitHub\BoxOS\backend
.\run-dev.ps1
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
```powershell
cd C:\GitHub\BoxOS
python -m unittest backend.test_server
```

## Notes
- Supabase is no longer the active backend path for the app.
- The legacy `supabase/` project files have been removed from this repository.
- Signup, login, logout, password reset, change password, and account deletion now target the local REST backend.
- Signup verification and password reset tokens are printed in the backend terminal for local development flows.
