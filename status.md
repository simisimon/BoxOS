# BoxOS Project Status

Last updated: 2026-05-28

## Current Snapshot
- Repository: `C:\GitHub\BoxOS`
- Product direction: production-ready core platform for a single gym
- Primary client direction: athlete mobile app plus admin-focused backoffice, with core admin access also available in mobile
- State: In Progress
- Progress source of truth: `user_stories.md`
- Active backend: local REST backend in `backend/server.py`

## Current Focus
- Finish `US-A3-03` role-based access hardening and document the production permission matrix

## Validation State
- `python3 -m unittest backend.test_server`: passed (61 tests)
- `cd app && flutter test test/widget_test.dart --plain-name "Trainer can create a recurring class from schedule screen"`: passed
- `flutter analyze`: passed with no issues found

## Current Risks / Gaps
1. Verification and password-reset tokens are still printed to the backend terminal for local development instead of being emailed.
2. External push delivery is not implemented yet; current notification coverage is primarily in-app.
3. Memberships, billing, and admin analytics are still unimplemented core modules.
4. Profile photo upload remains out of scope for the current profile slice; only display name and nickname are implemented.

## Recommended Next Steps
1. Finish backend role-hardening coverage for admin-only endpoints and mirror the same restrictions across app surfaces.
2. Define and implement the first production slice of memberships and payments.
3. Tighten production hardening: real email delivery, secret management, push infrastructure, and deployment posture.

## Local Development Notes
- Supabase is no longer the active backend for the Flutter app.
- The active backend is the local REST service in `backend/server.py`.
- Permanent dev logins:
  - athlete `demo@boxos.app` / `BoxOS123!`
  - admin `admin@boxos.app` / `BoxOS123!`
  - trainer `trainer@boxos.app` / `BoxOS123!`
