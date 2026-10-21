# BoxOS

Gym management app for CrossFit boxes: Flutter client in `app/`, FastAPI +
PostgreSQL backend in `backend/`, wired together by `docker-compose.yml`.

## Dev environment

- `docker compose up -d --build` starts `db-dev` (Postgres, :5432),
  `backend-dev` (FastAPI, :8081, reloads on save) and `frontend-dev`
  (Flutter web, http://localhost:3001).
- `frontend-dev` runs `flutter run -d web-server` and does **not** pick up file
  changes. After editing `app/`, run `docker compose restart frontend-dev`, wait
  for "is being served" in its logs, then hard-reload the browser (Cmd+Shift+R).
- The container runs `flutter pub get` on start and rewrites
  `app/.dart_tool/package_config.json` to container paths. Run
  `cd app && flutter pub get` before local `flutter test` / `flutter analyze`.
- Demo data: `docker compose exec backend-dev python -m backend.seed_demo`.
  The login screen has a "Demo Owner" quick login for local testing.

## Checks

- App: `cd app && flutter analyze lib test` — one known warning
  (`change_password_screen.dart`, unused `danger` parameter).
- App tests: `cd app && flutter test`. 14 tests are known red (12 in
  `test/widget_test.dart` lag the redesign, 2 goldens in `test/preview/`).
  Compare the failing set against that baseline instead of expecting green.
- Golden PNGs in `app/test/preview/` were rendered on Windows. Never regenerate
  them on macOS. A test run rewrites `app/test/preview/failures/`; restore it
  with `git checkout -- app/test/preview/failures/`.
- Backend: `python3 -m unittest discover -s backend -p "test_*.py"` (needs
  `backend/requirements-dev.txt`; testcontainers starts its own Postgres).
  `test_dashboard_returns_stats_and_newest_prs_for_members` is known red.

## Conventions

- Format only the Dart files you changed (`dart format <file>`). Many files are
  unformatted at HEAD; `dart format lib` floods the diff.
- Every dialog uses `AppFormDialog` (`app/lib/core/presentation/app_form_dialog.dart`,
  fixed 520×640); yes/no questions use `showAppConfirmDialog`. No new
  `AlertDialog` / `SimpleDialog`.
- All tabs share one content column (`contentMaxWidth`). Only the schedule week
  (My Box branch) renders full-bleed.
- The app theme makes `FilledButton`/`OutlinedButton` full-width: inside a
  `Row` give them `minimumSize: Size(0, 44)` or use `OverflowBar`. Widget tests
  pump with `theme: buildBoxOsTheme()` (see `app/test/schedule_views_test.dart`)
  so this shows up in tests.
- Scroll listeners fire before layout; measure positions in a post-frame
  callback.
- Backend SQL uses `?` placeholders (the psycopg wrapper translates them).

## Product decisions

- Schedule: one week view for every role; classes are templates (types WOD,
  Open Gym, Skill, PT), one WOD per gym per day.
- The whiteboard feature was removed on purpose — do not re-add it.
- Logbook is history only (logged WODs, score, PR, the WOD's sections). Scores
  are stored per WOD, not per exercise.
- Join requests live in the Members tab (Requests segment); the Members nav
  item shows the open count as a badge.
