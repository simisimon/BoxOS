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
- Complete the remaining production hardening around memberships/payments, real email delivery, push infrastructure, and backend deployment posture

## Validation State
- `python3 -m unittest backend.test_server`: passed (66 tests)
- Frontend polish slices committed across home, programming, calendar, profile, shell, logbook, notifications, edit profile, security, and auth flows
- `cd app && flutter test ...`: [blocked in this environment] `flutter` binary is currently not available in PATH
- `flutter analyze`: [blocked in this environment] `flutter` binary is currently not available in PATH

## Current Risks / Gaps
1. Verification and password-reset tokens are still printed to the backend terminal for local development instead of being emailed.
2. External push delivery is not implemented yet; current notification coverage is primarily in-app.
3. Memberships, billing, and admin analytics are still unimplemented core modules.
4. Flutter validation is still blocked in this environment, so the full UI polish pass has not yet been verified with `flutter test` / `flutter analyze` here.
5. Profile photo upload remains out of scope for the current profile slice; only display name and nickname are implemented.

## Recommended Next Steps
1. Run Flutter validation once the toolchain is available in this environment and fix any UI regressions from the completed polish pass.
2. Define and implement the first production slice of memberships and payments.
3. Tighten production hardening: real email delivery, secret management, push infrastructure, and deployment posture.

## Local Development Notes
- Supabase is no longer the active backend for the Flutter app.
- The active backend is the local REST service in `backend/server.py`.
- Permanent dev logins:
  - athlete `demo@boxos.app` / `BoxOS123!`
  - admin `admin@boxos.app` / `BoxOS123!`
  - trainer `trainer@boxos.app` / `BoxOS123!`
