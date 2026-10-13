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
- `backend/db.py` — PostgreSQL connection wrapper, schema init, seed/bootstrap logic
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
The backend uses PostgreSQL. The simplest way to get a database is via Compose:

```bash
docker compose up -d db
```

This exposes Postgres on `localhost:5432` with user/password/db `boxos` — matching the
default `BOXOS_DATABASE_URL`. Then start the FastAPI backend:

```bash
python3 -m pip install -r backend/requirements-fastapi.txt
sh backend/run-fastapi-dev.sh
```

The backend starts on `http://127.0.0.1:8080` and creates its schema and seed users on
first launch. Point it at a different database with `BOXOS_DATABASE_URL`.

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

Backend (tests spin up a throwaway PostgreSQL container via testcontainers, so a running
Docker daemon is required; suites skip automatically when it is unavailable):
```bash
python3 -m pip install -r backend/requirements-dev.txt
python3 -m unittest discover -s backend -p "test_*.py"
```

## Docker

Frontend und Backend lassen sich zusammen per Docker Compose starten (aus dem Projekt-Root):

```bash
docker compose up --build
```

Danach erreichbar unter:
- Frontend: `http://localhost:3000`
- Backend: `http://localhost:8080`

### Development-Umgebung

Für die Weiterentwicklung gibt es zusätzliche Compose-Services mit dem Profil `dev`:

```bash
docker compose --profile dev up --build backend-dev frontend-dev
```

Danach erreichbar unter:
- Frontend Dev Server: `http://localhost:3001`
- Backend Dev Server: `http://localhost:8081`

#### Demo-Daten (Mock-Box)

Damit Dashboard, Members, Analytics, Schedule, Programming, Tracking und Community
mit realistischen Zahlen statt leeren Zero-States rendern, gibt es ein Seed-Skript.
Es legt eine komplette Demo-Box an (ca. 120 Mitglieder, 4 offene Beitrittsanfragen,
~170 Klassen über 40 Tage inkl. Buchungen/Attendance/Waitlist, veröffentlichte WODs
mit Whiteboard-Ergebnissen sowie Progress-Daten für den Demo-Athleten):

```bash
docker compose --profile dev exec backend-dev python -m backend.seed_demo
```

Das Skript ist idempotent (mehrfaches Ausführen baut die Demo-Box neu auf). Danach
als Owner einloggen, um auf dem gefüllten Dashboard zu landen:

- E-Mail: `owner@boxos.dev`
- Passwort: `BoxOS!demo1`

Dev-Setup:
- `backend-dev` startet Uvicorn mit `--reload`
- `frontend-dev` startet Flutter Web per `flutter run -d web-server` (offizielles `cirruslabs/flutter:stable` Image)
- Der Quellcode wird per Bind-Mount direkt aus `./backend` und `./app` eingebunden
- Dev-Daten und Uploads landen in separaten Volumes, damit Prod/Dev getrennt bleiben
- Der Flutter-Pub-Cache wird im Volume `flutter_pub_cache` gehalten, um wiederholte `pub get`-Läufe zu beschleunigen

Enthalten:
- `backend/Dockerfile` für FastAPI/Uvicorn
- `app/Dockerfile` für Flutter Web Build + Nginx Serving
- `app/nginx.conf` mit SPA-Fallback für `go_router`
- `docker-compose.yml` für Prod + Dev

Die Datenbank läuft als eigener `db`-Service (`postgres:16-alpine`); der Dev-Stack nutzt
einen getrennten `db-dev`-Service. Persistente Backend-Daten liegen in Docker-Volumes:
- `backend_db` für die PostgreSQL-Datenbank (Prod)
- `backend_uploads` für Upload-Dateien (Prod)
- `backend_dev_db` für die PostgreSQL-Datenbank (Dev)
- `backend_dev_uploads` für Upload-Dateien (Dev)

Wichtige Build-Args für das Frontend in `docker-compose.yml`:
- `APP_ENV`
- `API_BASE_URL`
- `AUTH_REDIRECT_URL`

Wichtige Backend-Umgebungsvariablen:
- `BOXOS_HOST`
- `BOXOS_PORT`
- `BOXOS_DATABASE_URL` – PostgreSQL-Verbindung (Default: `postgresql://boxos:boxos@localhost:5432/boxos`)
- `BOXOS_UPLOADS_ROOT`
- `BOXOS_ANNOUNCEMENT_UPLOADS_DIR`
- `BOXOS_CORS_ALLOW_ORIGINS` – kommaseparierte erlaubte Origins (Default: `http://localhost:3000,http://localhost:3001`)
- `BOXOS_LOG_DELIVERY_TOKENS` – `1` (Default) loggt Verifizierungs-/Reset-Tokens; in Produktion auf `0` setzen
- `BOXOS_RATE_LIMIT_ENABLED` – `1` (Default) aktiviert das Rate-Limiting der Auth-Endpunkte; `0` deaktiviert es

## Migration von SQLite zu PostgreSQL

Frühere Versionen nutzten SQLite. Eine vorhandene SQLite-Datenbank lässt sich mit dem
mitgelieferten Skript nach PostgreSQL übertragen (aus dem Projekt-Root, Ziel sollte leer
sein):

```bash
python scripts/migrate_sqlite_to_postgres.py \
  --sqlite backend/boxos_dev.db \
  --postgres postgresql://boxos:boxos@localhost:5432/boxos
```

Das Skript legt das Schema an, kopiert alle Tabellen (Eltern vor Kindern) und setzt die
Identity-Sequenzen zurück, sodass neue Einträge hinter den kopierten IDs weiterzählen.

## Notes
- Supabase is no longer the active backend path for the app.
- The legacy `supabase/` project files have been removed from this repository.
- Signup, login, logout, password reset, change password, and account deletion now target the local REST backend.
- Signup verification and password reset tokens are printed in the backend terminal for local development flows.
