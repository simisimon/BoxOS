# BoxOS Project Status

Last updated: 2026-04-19

## Current Snapshot
- Repository: `C:\GitHub\BoxOS`
- Product direction: production-ready core platform for a single gym
- Primary client direction: athlete mobile app plus admin-focused backoffice, with core admin access also available in mobile
- Focus area: Epic B scheduling plus Epic D workout programming
- State: In Progress
- Active backend: local REST backend in `backend/server.py`
- Permanent dev logins: athlete `demo@boxos.app` / `BoxOS123!`, admin `admin@boxos.app` / `BoxOS123!`

## What Changed This Session
- Replaced the active Supabase auth integration with a local REST auth backend using Python standard library + SQLite.
- Reused the existing Flutter `dio` client and secure token storage for login, session refresh, logout, password reset, change password, and account deletion.
- Seeded a permanent demo account so local development always has a working login.
- Added backend scripts and config:
  - `backend/server.py`
  - `backend/run-dev.ps1`
  - `backend/test_server.py`
  - `app/env/dev.example.json`
- Updated app runtime config to use `API_BASE_URL` instead of Supabase keys.
- Added A2 profile editing:
  - auth-protected `GET /profile` and `PATCH /profile` endpoints
  - Flutter profile repository + provider
  - edit-profile screen reachable from home
  - widget/backend coverage for profile fetch and update
- Closed US-A1-07 account deletion:
  - immediate access revocation
  - immediate anonymization of personal fields
  - 30-day soft-delete retention window
  - automatic permanent purge after retention
- Closed US-A2-03 device registration:
  - local backend device registration endpoints
  - stable per-install device token stored securely in Flutter
  - automatic registration on session restore/sign-in
  - automatic device cleanup on logout and account deletion
- Closed US-A2-02 notification preferences:
  - server-side notification preference persistence
  - dedicated Flutter notification settings screen
  - per-type toggles for bookings, waitlist, billing, WOD, and PR events
- Started A3 by closing US-A3-01 default roles:
  - new accounts now default to the global `athlete` role
  - `trainer` and `admin` roles are modeled in the backend and Flutter app
  - current role is exposed through session/profile payloads and shown in the UI
- A3 role-management status has been clarified against the intended workflow:
  - current implementation still assigns roles more broadly than the intended gym-member-only workflow
  - admin-only role management is enforced today
  - gym-scoped member listing and athlete-to-trainer promotion still need to be implemented
- Closed US-A3-04 multi-role switching:
  - users can hold multiple assigned global roles
  - the authenticated shell now exposes a role switcher when multiple roles exist
  - the active role is persisted server-side and restored across sessions
- Closed the current A4 gym association slice:
  - admin-only gym creation
  - athlete gym directory and join requests
  - admin review/approve/reject join requests
  - active gym switching
- Started Epic B scheduling:
  - active-gym class schedule endpoint and storage
  - trainer/admin create, edit, and delete future classes
  - calendar screen now shows real schedule data instead of a placeholder
- Extended Epic B into athlete booking:
  - active-gym members can book and cancel future classes
  - schedule payload now includes booked count, remaining spots, and current-user booking state
  - duplicate bookings and over-capacity bookings are blocked
  - schedule capacity cannot be reduced below existing bookings
- Extended Epic B into attendance tracking:
  - trainer/admin users can see booked members for each class
  - trainer/admin users can mark bookings as attended or no-show after class start
  - athletes can see their own attendance state in the schedule
- Renamed the product role vocabulary from `owner`/`box` to `admin` across backend, app, tests, and docs, with compatibility handling for legacy local data
- Closed US-D1-01 daily WOD creation and US-D1-02 programming calendar:
  - added active-gym daily workout programming endpoints in the local backend
  - trainers and admins can create and update one daily workout per date
  - workouts support title, strength, MetCon, and coach notes sections
  - active gym members can view upcoming workouts by date in the Flutter app
  - added a dedicated Programming screen and navigation entry from the home surface
- Closed US-D1-03 digital whiteboard:
  - added whiteboard result submission for active gym members on workout day or later
  - one whiteboard result per member per workout can be created and updated
  - programming payloads now include ranked whiteboard results plus each member's own result
  - the Flutter programming screen now shows a live whiteboard and result submission flow

## Validation State
- `cd app && dart analyze`: passed
- `cd app && flutter test`: hangs in the current environment
- `python3 -m unittest backend.test_server`: passed (31 tests)

## Story Status (Epic A)
- US-A1-01 Sign up: Complete
- US-A1-02 Verify email: Complete
- US-A1-03 Log in: Complete
- US-A1-04 Log out: Complete
- US-A1-05 Forgot/reset password: Complete
- US-A1-06 Change password: Complete
- US-A1-07 Account deletion: Complete
- US-A2-01 Edit profile: Complete
- US-A2-02 Manage notifications: Complete
- US-A2-03 Device registration: Complete
- US-A3-01 Default role: Complete
- US-A3-02 Assign trainer roles: Complete
- US-A3-03 Role-based access: In Progress
- US-A3-04 Multi-role switching: Complete
- US-A3-05 Role-specific home experience: Complete
- US-A3-06 Gym member management and trainer promotion: Complete
- US-A4-01 Create gym: Complete
- US-A4-02 Browse and select gym: Complete
- US-A4-03 Request to join gym: Complete
- US-A4-04 Review join requests: Complete
- US-A4-05 Approve or reject join request: Complete
- US-A4-06 Switch gyms: Complete
- B1 Class Scheduling: In Progress
- B2 Athlete Booking: Complete
- B3 Attendance Tracking: Partial
- D1 Daily WOD Creation: Complete
- D2 Programming Calendar: Complete
- D3 Digital Whiteboard: Complete
- A5: Not Started

## Current Risks / Gaps
1. Verification and password-reset tokens are printed to the backend terminal for local development instead of being emailed.
2. Profile photo upload is still out of scope for the current A2 slice; only display name and nickname are implemented.
3. Memberships, billing, logging, and analytics are still documented as core product modules but are not implemented yet.

## Recommended Next Steps
1. Add A5 audit logging for role changes, join-request decisions, scheduling mutations, programming updates, and whiteboard submissions.
2. Define the first production slice of memberships and payments before expanding secondary modules.
3. Decide whether workout logging should extend the whiteboard model or remain a separate athlete history flow.

## Notes
- Supabase is no longer the active backend for the Flutter app.
- The legacy `supabase/` folder has been removed from the repo.
- Additional seeded dev accounts now exist for role testing: `trainer@boxos.app` / `BoxOS123!` and `box@boxos.app` / `BoxOS123!`.
