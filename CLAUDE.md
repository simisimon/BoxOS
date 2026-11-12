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
- Port 3001 answers before the compile is done; a page opened then stays blank
  until reloaded. `docker compose up -d --build --wait` returns only once
  `frontend-dev` is healthy (its healthcheck greps for "is being served").
- The container runs `flutter pub get` on start and rewrites
  `app/.dart_tool/package_config.json` to container paths. Run
  `cd app && flutter pub get` before local `flutter test` / `flutter analyze`.
- Payments (Stripe Connect, test mode): put `BOXOS_STRIPE_SECRET_KEY=sk_test_...`
  in a git-ignored `.env` next to `docker-compose.yml`. Without it payments are
  hidden. All Stripe calls go through `backend/payment_service.py` (`client`
  is swapped for a fake in `backend/tests/test_payments.py`).
  Webhooks locally (Stripe CLI via Docker, no install needed):
  ```
  docker run --rm -it stripe/stripe-cli listen \
    --api-key "$(grep BOXOS_STRIPE_SECRET_KEY .env | cut -d= -f2)" \
    --events checkout.session.completed,invoice.paid,invoice.finalized,invoice.payment_failed,customer.subscription.deleted \
    --forward-connect-to host.docker.internal:8081/stripe/webhook
  ```
  Put the printed `whsec_...` in `.env` as `BOXOS_STRIPE_WEBHOOK_SECRET`, then
  `docker compose up -d backend-dev` (`restart` does not reload `.env`). Keep
  the listener running; events sent while it is down are not replayed. Add new
  event types to `--events` when `payment_service.handle_event` learns them.
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
  `test_dashboard_returns_stats_for_members` is known red.

## Conventions

- Format only the Dart files you changed (`dart format <file>`). Many files are
  unformatted at HEAD; `dart format lib` floods the diff.
- Layout target: `docs/admin-ui-reference.md` (left sidebar, right-side panels
  for detail and create flows, full-width pages, BoxOS colours from
  `app_chrome.dart`). Views are being migrated to it one by one; a view not yet
  migrated keeps `AppFormDialog` (fixed 520×640) and the `contentMaxWidth`
  column. Yes/no questions always use `showAppConfirmDialog`. No new
  `AlertDialog` / `SimpleDialog`.
- The app theme makes `FilledButton`/`OutlinedButton` full-width: inside a
  `Row` give them `minimumSize: Size(0, 44)` or use `OverflowBar`. Widget tests
  pump with `theme: buildBoxOsTheme()` (see `app/test/schedule_views_test.dart`)
  so this shows up in tests.
- Scroll listeners fire before layout; measure positions in a post-frame
  callback.
- Backend SQL uses `?` placeholders (the psycopg wrapper translates them).

## Product decisions

- Schedule: one week view for every role; classes are templates, one WOD per
  gym per day. Types: the built-ins WOD, Open Gym, Skill, PT plus custom types
  an owner adds in Settings › Class types (`/class-types`, `gym_class_types`).
- The whiteboard feature was removed on purpose — do not re-add it.
- Workout logging was removed on purpose (2026-11-12): no logbook, scores,
  PRs or tracking in the app — do not re-add it. The `workout_logs` tables
  still exist so old data is kept.
- Join requests live in the Members tab (Requests segment); the Members nav
  item shows the open count as a badge.
