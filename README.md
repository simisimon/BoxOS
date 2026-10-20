# BoxOS

Plattform für den Betrieb einer CrossFit-Box: Klassenplanung und Buchung, WOD-Programmierung,
Workout-Logging, Community und Mitgliederverwaltung. Mobile-first für Athleten, mit
Admin-Funktionen für Owner und Trainer.

- **App:** Flutter (`app/`), läuft als Web-App und mobil
- **Backend:** FastAPI mit PostgreSQL (`backend/`), Aufbau siehe [`backend/ARCHITECTURE.md`](backend/ARCHITECTURE.md)
- **Produktplanung:** [`ROADMAP.md`](ROADMAP.md)

## Schnellstart mit Docker

Die komplette Entwicklungsumgebung startet aus dem Projekt-Root:

```bash
docker compose up -d --build
```

| Dienst | Adresse |
|---|---|
| App (Flutter-Web-Dev-Server) | http://localhost:3001 |
| Backend (FastAPI mit Auto-Reload) | http://localhost:8081 |
| PostgreSQL | `localhost:5432`, User/Passwort/DB `boxos` |

- Backend-Code (`./backend`) und App-Code (`./app`) sind eingebunden. Backend-Änderungen
  greifen sofort, nach App-Änderungen `docker compose restart frontend-dev`.
- Stoppen mit `docker compose stop`. Datenbank und Uploads bleiben in den Volumes
  `backend_dev_db` und `backend_dev_uploads` erhalten.
- `frontend-dev` führt beim Start `flutter pub get` aus und überschreibt dabei
  `app/.dart_tool`. Lokale Flutter-Befehle danach mit `flutter pub get` wieder lauffähig machen.

### Demo-Daten

Ein Seed-Skript legt eine vollständige Demo-Box an: rund 120 Mitglieder, offene
Beitrittsanfragen, ein Wochenplan mit Classes inkl. Buchungen, Attendance und Warteliste,
veröffentlichte WODs sowie Community-Inhalte.

```bash
docker compose exec backend-dev python -m backend.seed_demo
```

Jeder Lauf löscht die Demo-Box „Iron Forge CrossFit“ und baut sie neu auf. Danach als Owner
anmelden (in der App auch per „Quick Login“):

- E-Mail: `owner@boxos.dev`
- Passwort: `BoxOS!demo1`

Zusätzlich legt das Backend bei jedem Start diese Accounts ohne Box an, die vor allem die
Tests nutzen: `demo@boxos.app`, `trainer@boxos.app` und `admin@boxos.app`, jeweils mit
Passwort `BoxOS123!`.

## Ohne Docker entwickeln

Die Datenbank kommt weiterhin aus Compose:

```bash
docker compose up -d db-dev
```

Backend (startet auf http://127.0.0.1:8080 und legt Schema und Standard-Accounts beim
ersten Start an):

```bash
python3 -m pip install -r backend/requirements-fastapi.txt
sh backend/run-fastapi-dev.sh        # Windows: .\backend\run-dev.ps1
```

App (Windows/PowerShell):

```powershell
cd app
copy env\dev.example.json env\dev.json
.\run-dev.ps1
```

`env/dev.json` setzt `ENV`, `API_BASE_URL` (Standard `http://127.0.0.1:8080`) und
`AUTH_REDIRECT_URL`.

## Tests

Backend: Die Tests starten per testcontainers eine eigene PostgreSQL-Instanz, ein laufender
Docker-Daemon ist also nötig. Ohne Docker werden die Suites übersprungen.

```bash
python3 -m pip install -r backend/requirements-dev.txt
python3 -m unittest discover -s backend -p "test_*.py"
```

App:

```bash
cd app
flutter analyze
flutter test
```

Die Golden-Tests in `app/test/preview/` wurden unter Windows erzeugt und schlagen auf
macOS wegen abweichender Schriften fehl.

## Konfiguration

Backend-Umgebungsvariablen:

| Variable | Bedeutung | Standard |
|---|---|---|
| `BOXOS_DATABASE_URL` | PostgreSQL-Verbindung | `postgresql://boxos:boxos@localhost:5432/boxos` |
| `BOXOS_HOST`, `BOXOS_PORT` | Bind-Adresse des Servers | `127.0.0.1`, `8080` |
| `BOXOS_UPLOADS_ROOT` | Ablage für Uploads | `backend/uploads` |
| `BOXOS_ANNOUNCEMENT_UPLOADS_DIR` | Ablage für Announcement-Bilder | `<UPLOADS_ROOT>/announcements` |
| `BOXOS_GYM_LOGOS_DIR`, `BOXOS_AVATARS_DIR` | Ablage für Box-Logos und Profilbilder | `<UPLOADS_ROOT>/gym_logos`, `<UPLOADS_ROOT>/avatars` |
| `BOXOS_CORS_ALLOW_ORIGINS` | Erlaubte Origins, kommasepariert | `http://localhost:3000,http://localhost:3001` |
| `BOXOS_LOG_DELIVERY_TOKENS` | `1` schreibt Verifizierungs- und Reset-Tokens ins Backend-Log | `1` |
| `BOXOS_RATE_LIMIT_ENABLED` | `1` aktiviert das Rate-Limiting der Auth-Endpunkte | `1` |

Verifizierungs- und Passwort-Reset-Links werden noch nicht per E-Mail verschickt. Die Tokens
stehen im Backend-Log (`docker compose logs backend-dev`).

Die App bekommt `ENV`, `API_BASE_URL` und `AUTH_REDIRECT_URL` per `--dart-define`, in
Docker über den Befehl von `frontend-dev` in `docker-compose.yml`.

## Weitere Dateien

- `docs/wod-import.md` und `docs/sample-wods.csv`: Format für den CSV-Import von WODs
- `app/Dockerfile` und `app/nginx.conf`: Release-Build der Web-App mit Nginx. Derzeit nicht
  in Compose eingebunden, Grundlage für ein späteres Deployment.
