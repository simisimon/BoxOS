# BoxOS Production Readiness Backlog

Last reviewed: 2026-05-28

This backlog is based on the current Flutter client, local REST backend, `requirements.md`, `user_stories.md`, `status.md`, and `SUGARWOD_FEATURE_GAP.md`. The goal is to identify what must be completed before BoxOS can be moved into real production use for a single CrossFit box and what product gaps remain if BoxOS is meant to become a meaningfully better SugarWOD-style platform.

## Current State Summary

BoxOS already has a meaningful production-core foundation:

- Email/password authentication, verification, password reset, password change, logout, and account deletion exist.
- Profile editing, notification preferences, in-app notifications, device registration, and role switching exist.
- Gym creation, gym discovery, join requests, approvals/rejections, and active gym switching exist.
- Scheduling supports class creation, edits, deletion, recurring instance creation, booking, cancellation, waitlists, and attendance tracking.
- Programming supports daily WOD creation/editing, workout calendar views, whiteboard results, workout logging, workout history, and basic PR detection.
- Admin role management and audit logs exist.

The app is not production-ready yet because several core product areas are still missing or not hardened enough: memberships/payments, admin analytics, external email/push delivery, complete role-permission verification, production backend deployment posture, store-ready mobile app polish, deeper community features, stronger performance tracking, and coach-grade programming workflows.

## Screen Review

### Auth Screens

- `LoginScreen`: polished production-style sign-in flow with clearer auth entry hierarchy and navigation.
- `SignUpScreen`: athlete signup exists and now matches the shared auth design system, but production email verification delivery is still missing.
- `AdminSignUpScreen`: admin onboarding exists in a distinct polished path, but this must still be controlled before production so arbitrary public admin creation cannot create operational risk.
- `VerifyEmailScreen`: token-based verification exists in the polished auth surface, but currently depends on backend-log token delivery.
- `ForgotPasswordScreen` and `ResetPasswordScreen`: recovery flows exist in the polished auth surface, but reset delivery currently depends on backend-log token delivery.
- `ChangePasswordScreen`: implemented and polished.
- `DeleteAccountScreen`: implemented and polished, but production policy/legal copy and deletion/audit verification should still be reviewed.
- `AuthCallbackScreen`: exists for callback handling and now matches the auth surface, but production OAuth/deep-link behavior needs device testing.

### Shell And Home

- `AuthenticatedShellScreen` and `AuthenticatedScaffold`: mobile shell with header, role switcher, notification access, and footer navigation exists.
- `HomeScreen`: currently starts with News, then Today, then Quick Access. The current content is still partly placeholder-like:
  - News cards are static summaries rather than real gym news/content.
  - Today does not yet show the real next booking or real WOD.
  - Quick Access now avoids duplicating footer navigation and keeps only role-specific actions.
- UI width constraints are now documented in `docs/ui-guidelines.md`, but other standalone screens still need to be audited against those guidelines.

### Profile And Account Screens

- `ProfileScreen`: shows user details, gym memberships, role/gym context, and admin/gym actions.
- `EditProfileScreen`: supports display name and nickname only. Profile photo/avatar upload is still missing.
- `NotificationSettingsScreen`: preference toggles exist, including future payment issue notifications.
- `NotificationsScreen`: placeholder/list screen exists with constrained width; external push delivery is not implemented.
- `RoleManagementScreen`: admin member role management exists, but full role-permission hardening remains the current active gap.

### Gym Screens

- `CreateGymScreen`: admin gym creation exists.
- `GymDirectoryScreen`: gym discovery/search and join request flow exist.
- `JoinRequestsScreen`: admin approval/rejection exists.
- Production gaps include onboarding polish, clearer empty states, and ensuring all gym actions are correctly role- and gym-scoped on backend and client.

### MyBox / Schedule Screen

- `MyBoxScreen`: class schedule, inline class creation, recurring class creation, class editing/deletion, booking/cancellation, waitlist, and attendance controls exist.
- This is one of the strongest functional areas, but production still needs:
  - full role-permission audit,
  - real membership-based booking restrictions,
  - schedule-change notification delivery beyond in-app inbox,
  - stronger calendar usability for dense schedules,
  - manual QA on timezone and DST behavior.

### Programming Screen

- `ProgrammingScreen`: daily WOD creation/editing, programming calendar, whiteboard, whiteboard submission, and workout log submission exist.
- Production gaps include richer programming templates, stronger validation for score types, coach/admin editing review, UX polish for heavy workout text, and more structured coach authoring fields such as warm-up, scaling, stimulus, and coach notes.

### Logbook Screen

- `LogbookScreen`: workout history, PR tracking chips, and logged result display exist.
- Production gaps include better filtering/search, clearer PR history, benchmark history, richer comparison against previous attempts, and stronger empty states for new athletes.

### Community And Engagement

- BoxOS currently has workout logging and in-app notifications, but it does not yet have a real community layer around workouts.
- Missing capabilities include workout comments, reactions/cheers, coach comments on athlete results, gym announcement/feed content, and broader recognition loops for consistency and PRs.

### Notifications

- In-app notifications exist for booking confirmations, waitlist promotions, schedule updates, WOD events, and PR-related flows.
- External push delivery is not implemented.
- Transactional email delivery is not implemented.
- Device registration currently exists as an app/backend capability, but production push provider integration is still required.

### Missing Core Screens / Modules

- Membership plan management screen is missing.
- Member subscription/payment state screen is missing.
- Booking eligibility/entitlement UI is missing.
- Admin analytics dashboard is missing.
- Revenue snapshot screen is missing.
- Community feed / workout comments surface is missing.
- Coach-facing programming template and publishing workflow surface is missing.
- Benchmark/performance analytics views are missing.
- Production operational/admin backoffice surface is not yet implemented beyond mobile admin workflows.

## Production Blockers

These must be completed before a real production launch.

### 1. Finish Role And Permission Hardening

Current status: substantially completed in backend and client, with regression coverage in place for the most sensitive admin, trainer, athlete, no-gym, and wrong-gym paths.

Required work:

- Audit every backend endpoint for role and active-gym authorization.
- Verify trainer permissions are limited to delegated scheduling/programming/attendance workflows.
- Verify athletes cannot access admin/trainer-only data through direct API calls.
- Verify frontend navigation hides unauthorized actions and backend still enforces every restriction.
- Add targeted tests for each sensitive endpoint and role combination.

Exit criteria:

- A role-permission matrix exists. ✅
- Backend tests cover admin, trainer, athlete, no-gym, and wrong-gym access for critical endpoints. ✅
- The app has no visible unauthorized actions for each role. ✅ on the current guarded admin/schedule/programming/profile surfaces.

Progress note: admin-only endpoint guards, schedule/programming manager restrictions, and no-gym/wrong-gym backend regression coverage are now in place. Primary guarded client surfaces are aligned with backend authorization checks.

### 2. Implement Memberships And Payments

Current status: Epic C is not started.

Required work:

- Membership plan CRUD for admins.
- Member assignment to plans.
- Payment provider integration for recurring billing.
- Payment/subscription lifecycle states: active, trialing, past due, canceled, paused, expired.
- Member-facing membership status view.
- Admin-facing membership and payment status view.
- Booking restrictions based on active membership entitlements.
- Payment issue notification events and preference handling.

Exit criteria:

- A gym can define real plans and assign/sell them.
- Athletes without valid entitlement cannot book restricted classes.
- Admins can see who is active, past due, canceled, or unpaid.
- Payment webhooks are verified and idempotent.

### 3. Implement Transactional Email

Current status: verification and reset tokens are printed to backend logs.

Required work:

- Email provider integration.
- Verification email delivery.
- Password reset email delivery.
- Operational email templates.
- Retry/error handling for failed email delivery.
- Production-safe token links/deep links.

Exit criteria:

- No production auth flow requires reading backend logs.
- Verification and reset flows work end-to-end on real devices.
- Email sending is observable and failure-safe.

### 4. Implement Real Push Notifications

Current status: in-app notifications exist; external push delivery is not implemented.

Required work:

- Integrate FCM/APNs through a provider or direct platform setup.
- Replace generated local device token placeholder behavior with real platform device tokens.
- Send push notifications for booking confirmations, waitlist promotions, schedule changes, WOD posts, PR events, and payment issues.
- Respect notification preferences.
- Handle permission prompts, token refresh, logout cleanup, and failed token cleanup.

Exit criteria:

- Push notifications are delivered to iOS and Android test devices.
- Disabled preferences suppress push delivery.
- Logout/account deletion unregisters devices.

### 5. Replace Local SQLite Backend With Production Deployment Posture

Current status: active backend is `backend/server.py` with local SQLite database.

Required work:

- Decide production backend stack and hosting target.
- Move from local SQLite/dev server to production-grade persistence and migrations.
- Configure HTTPS, CORS, secrets, environment-specific config, logging, monitoring, and backups.
- Remove/guard demo seed users and development credentials.
- Add operational health checks.

Exit criteria:

- Production backend can be deployed repeatably.
- Secrets are not stored in source control.
- Backups and restore process are documented and tested.
- Demo users are disabled or isolated from production.

### 6. Admin Analytics

Current status: Epic G is not started.

Required work:

- Attendance overview.
- Membership activity overview.
- Revenue snapshot.
- Basic date range filters.
- Class fill-rate and waitlist pressure views.
- No-show trend visibility.
- Programming engagement and workout logging engagement views.
- Admin-only backend endpoints and mobile/admin UI.

Exit criteria:

- Admin can answer: attendance trend, utilization, active members, past due members, recurring revenue snapshot, and where operational pressure or engagement drop-off is happening.

### 7. Community And Engagement Loops

Current status: not started.

Required work:

- Workout comments.
- Reactions / cheers / fist-bumps.
- Coach comments on athlete results.
- Gym announcements or feed posts.
- Recognition flows for PRs, streaks, and consistency.
- Moderation and role-aware visibility rules for community content.
- Notification events tied to new comments/reactions where appropriate.

Exit criteria:

- Athletes can react to and discuss workouts/results in-app.
- Coaches can leave contextual feedback on athlete results.
- Admins/coaches can publish real gym announcements instead of relying on placeholder home content.

### 8. Performance Tracking And Athlete Progress

Current status: partially implemented through logbook and basic PR detection.

Required work:

- Benchmark workout history.
- Movement-specific PR views.
- Progress charts and trend summaries.
- Better “since last time” comparison views.
- Filtering by movement, workout type, score type, and date range.
- Retest prompts or benchmark revisit cues.

Exit criteria:

- Athletes can quickly understand progress over time, not just see isolated past entries.
- Coaches can use the recorded data to guide progression and celebrate improvements.

### 9. Coach-Grade Programming Workflows

Current status: partially implemented through daily WOD creation/editing.

Required work:

- Workout templates.
- Copy/duplicate day, week, and block workflows.
- Movement library.
- Warm-up, scaling, stimulus, and coach-note fields.
- Draft / scheduled / published workflow.
- Coach/admin review or approval flow where needed.
- Support for more workout structures such as partner, team, relay, interval, and phased formats.

Exit criteria:

- Coaches can program faster and more consistently than with free-text-only daily authoring.
- Programming quality and structure hold up under real daily gym use.

### 10. Production Mobile Release Readiness

Required work:

- iOS and Android app identifiers, signing, icons, splash screen, and store metadata.
- Production API base URL configuration per build flavor.
- Real device QA on iOS and Android.
- Offline/poor-network behavior for core flows.
- Crash reporting and analytics.
- Accessibility pass for text scaling, contrast, focus order, and tap target sizes.

Exit criteria:

- App builds are reproducible for iOS and Android.
- TestFlight/internal Android test release is installable.
- Critical flows are verified on physical devices.

## High-Priority Improvements Before Launch

These are not all absolute blockers, but they are important for credible production use.

### Home Screen

- Replace static News cards with real gym announcements or recent operational events.
- Show the athlete's actual next booking in Today.
- Show the active gym's actual WOD in Today.
- Add stronger engagement prompts such as comments/reactions highlights, PR celebrations, or consistency nudges.
- Add role-specific home content:
  - Athlete: next class, WOD, recent PR/logging prompt.
  - Trainer: next classes to coach, attendance tasks, today's programming.
  - Admin: pending join requests, membership/payment alerts, attendance snapshot.

### Schedule / MyBox

- Improve dense schedule browsing for gyms with many daily classes.
- Add date range navigation and clearer selected-day context.
- Review recurring class UX for editing/deleting generated instances.
- Add membership restriction messages once membership enforcement exists.
- Add stronger conflict prevention for duplicate classes and overlapping trainer assignments.

### Programming And Whiteboard

- Add reusable WOD templates or structured sections beyond free text where needed.
- Improve score type guidance and validation.
- Add clearer whiteboard filtering/sorting.
- Add better edit history/audit visibility for coaches/admins.
- Add structured programming fields for warm-up, scaling, stimulus, and coach intent.
- Add publishing states and better multi-day/block authoring workflows.

### Logbook

- Add filters/search by workout, date, PR, score type, and movement.
- Add PR history detail view.
- Add benchmark history and “since last time” comparisons.
- Add progress charts/trend views.
- Add clearer empty state and onboarding path for new athletes.

### Community And Announcements

- Add workout comments and reactions.
- Add coach comments on athlete results.
- Add gym announcement/feed content to replace placeholder home-news behavior.
- Add moderation/visibility controls for community content.

### Profile And Account

- Add profile photo/avatar upload or intentionally defer it with clear product decision.
- Improve gym membership context display for users with multiple roles/gyms.
- Review account deletion copy for legal/compliance clarity.

### UI Consistency

- Review the completed polish pass against `docs/ui-guidelines.md` once Flutter tooling is available.
- Run width/device QA across narrow phone width, large phone width, and tablet/desktop debug width.
- Remove remaining demo/placeholder copy from production-facing screens.
- Check shared auth-stage and security surfaces for any compile/layout regressions after the broad redesign.

## Security, Privacy, And Compliance

Required before launch:

- Formal review of authentication/session expiry behavior.
- Rate limiting for login, signup, password reset, verification resend, and other sensitive endpoints.
- GDPR privacy policy, terms, data export/delete process, and retention documentation.
- Audit log coverage review for operationally sensitive actions.
- Payment provider PCI posture review once billing is implemented.
- Backend input validation and error response review.
- Dependency vulnerability scan and update policy.

## Testing And QA

Required before launch:

- Full backend test suite.
- Full Flutter widget/unit test suite stabilized so known off-screen tap failures are fixed.
- Role-permission regression tests.
- End-to-end smoke tests for:
  - signup/verification/login,
  - gym creation,
  - join request approval,
  - class creation/booking/waitlist/attendance,
  - WOD creation/logging/whiteboard,
  - notifications,
  - membership/payment once implemented.
- Manual QA checklist for iOS and Android.

## Suggested Delivery Order

The following order reflects a deliberate product choice: **Memberships & Payments** and **Push/Email Delivery** should be implemented last, after the core workout, community, analytics, and coaching product is stronger.

1. Finish role-permission hardening.
2. Stabilize test suite and fix known widget test fragility.
3. Add admin analytics.
4. Implement first community/engagement loop features: announcements, comments, and reactions.
5. Implement deeper performance tracking: benchmark history, progress comparisons, and richer logbook analytics.
6. Implement coach-grade programming templates and publishing workflow.
7. Harden backend deployment, secrets, monitoring, backups, and production database.
8. Validate the completed UI consistency pass using `docs/ui-guidelines.md` and Flutter/device QA.
9. Run full iOS/Android release QA on the workout/community product.
10. Implement memberships and payment state.
11. Implement transactional email.
12. Implement real push notifications.

## Launch Readiness Definition

BoxOS should not be considered production-ready until:

- All production blockers above are complete.
- The app can be deployed against a production backend without dev tokens, demo credentials, or local database assumptions.
- A real single gym can onboard admins, trainers, and athletes without developer intervention.
- Payments/memberships can control booking access.
- Email and push notifications work on real devices.
- Admins can monitor basic attendance, membership, revenue, and operational pressure state.
- Athletes and coaches have real community/engagement loops instead of placeholder content only.
- Performance tracking goes beyond raw history and supports meaningful progress review.
- Critical flows pass automated tests and manual iOS/Android QA.
