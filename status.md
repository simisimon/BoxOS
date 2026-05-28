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
- Ship Admin Analytics v1, then continue with community/performance product gaps, memberships/payments, real email delivery, push infrastructure, and backend deployment posture

## Validation State
- `python3 -m unittest backend.test_server`: passed (72 tests)
- Targeted Flutter analyze for the new admin analytics surface/routing completed with only existing `deprecated_member_use` infos (`withOpacity`) in already-polished UI files
- Frontend polish slices committed across home, programming, calendar, profile, shell, logbook, notifications, edit profile, security, and auth flows
- Local Flutter toolchain is available in the workspace; broad Flutter-side validation cleanup is still uncommitted in the app tree

## Current Risks / Gaps
1. Verification and password-reset tokens are still printed to the backend terminal for local development instead of being emailed.
2. External push delivery is not implemented yet; current notification coverage is primarily in-app.
3. Memberships, billing, deeper community features, stronger athlete performance tracking, and follow-on analytics slices beyond v1 are still unimplemented core modules.
4. The broad UI redesign still has uncommitted Flutter-side validation cleanup in the app tree.
5. Profile photo upload remains out of scope for the current profile slice; only display name and nickname are implemented.

## Recommended Next Steps
1. Extend Admin Analytics beyond v1 with date filters, waitlist/fill-rate pressure, membership status visibility, and revenue placeholders only once real billing exists.
2. Commit the remaining Flutter-side validation fixes separately once the app-side test/analyze cleanup is ready.
3. Continue production hardening: real email delivery, push infrastructure, secret management, and deployment posture.

## Local Development Notes
- Supabase is no longer the active backend for the Flutter app.
- The active backend is the local REST service in `backend/server.py`.
- Permanent dev logins:
  - athlete `demo@boxos.app` / `BoxOS123!`
  - admin `admin@boxos.app` / `BoxOS123!`
  - trainer `trainer@boxos.app` / `BoxOS123!`
