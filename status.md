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
- Complete the remaining production hardening around admin analytics, community/performance product gaps, memberships/payments, real email delivery, push infrastructure, and backend deployment posture

## Validation State
- `python3 -m unittest backend.test_server`: passed (70 tests)
- Frontend polish slices committed across home, programming, calendar, profile, shell, logbook, notifications, edit profile, security, and auth flows
- Local Flutter toolchain is available in the workspace and widget-test stabilization work is in progress in the app tree

## Current Risks / Gaps
1. Verification and password-reset tokens are still printed to the backend terminal for local development instead of being emailed.
2. External push delivery is not implemented yet; current notification coverage is primarily in-app.
3. Memberships, billing, admin analytics, deeper community features, and stronger athlete performance tracking are still unimplemented core modules.
4. The broad UI redesign still has uncommitted Flutter-side validation cleanup in the app tree.
5. Profile photo upload remains out of scope for the current profile slice; only display name and nickname are implemented.

## Recommended Next Steps
1. Commit the remaining Flutter-side validation fixes separately once the app-side test/analyze cleanup is ready.
2. Start the next planned product slice after role hardening: admin analytics.
3. Continue production hardening: real email delivery, push infrastructure, secret management, and deployment posture.

## Local Development Notes
- Supabase is no longer the active backend for the Flutter app.
- The active backend is the local REST service in `backend/server.py`.
- Permanent dev logins:
  - athlete `demo@boxos.app` / `BoxOS123!`
  - admin `admin@boxos.app` / `BoxOS123!`
  - trainer `trainer@boxos.app` / `BoxOS123!`
