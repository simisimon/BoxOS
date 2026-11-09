# BoxOS core design

Scope: the core loop of running one CrossFit box. A box publishes classes and
WODs, athletes book and train, results are logged, and the owner keeps the
roster healthy. Everything outside that loop (personal workouts, timers,
analytics depth, deeper community) is out of scope for this document.

Status legend: `[x]` implemented end to end (backend + UI) · `[~]` partial
(see note) · `[ ]` missing.

## Roles

| Role | Who | How they get it |
| --- | --- | --- |
| **Owner** (`admin`) | Runs the box | Owner sign-up, then creates a box |
| **Trainer** | Coaches classes, writes programming | Owner assigns the role to a member |
| **Athlete** | Trains at the box | Public sign-up, then join request |

A person can hold several roles in a box and switches the active one in the
app. Backend checks are the security boundary: owner-only endpoints use
`require_admin_gym_session`, owner + trainer endpoints use
`require_schedule_manager_session` (`backend/fastapi_app.py`).

## Shared (every role)

- [x] Sign up, log in, log out, change password, delete account
- [~] Verify e-mail and reset password: flow works, but tokens are written to
  the backend log. **No e-mail is sent.**
- [x] Edit profile (name, nickname, avatar)
- [x] Switch active role and active box
- [x] In-app notifications and notification preferences
- [ ] Push notifications (devices register, nothing is delivered)

## Athlete

| Task | Status | Note |
| --- | --- | --- |
| Find a box and send a join request | [x] | Gym directory, "my requests" |
| See the week schedule (classes + WOD) | [x] | One week view for all roles |
| Book / cancel a class | [x] | Future classes only, capacity enforced |
| Join / leave the waitlist, auto-promotion on cancel | [x] | In-app notification on promotion |
| See today's WOD and next booking on Home | [x] | |
| Log a score for a WOD (with PR flag) | [x] | Logged from the WOD in the schedule |
| Browse own history in the Logbook | [x] | History only, per-WOD scores |
| Read announcements, like and comment | [x] | |
| Box chat | [x] | |
| Buy / see own membership and payment state | [ ] | No plans, no billing |
| Booking blocked without a valid membership | [ ] | Only `active` gym membership is checked |
| Booking / cancellation window rules | [ ] | No booking window or cancellation cutoff |

## Trainer

| Task | Status | Note |
| --- | --- | --- |
| Create / edit / delete classes and weekly templates | [x] | Types WOD, Open Gym, Skill, PT |
| Assign a trainer to a class | [x] | |
| Write the daily WOD with sections, publish / unpublish | [x] | One WOD per box per day |
| Duplicate a WOD, import WODs from CSV | [x] | See `docs/wod-import.md` |
| See the booking roster of a class | [x] | |
| Mark attendance (attended / no-show) | [x] | |
| Post and edit announcements, moderate chat | [x] | |
| "My classes" view (only the classes I coach) | [ ] | Trainer sees the athlete tab set |

## Owner

| Task | Status | Note |
| --- | --- | --- |
| Create the box (name, logo, timezone) | [x] | |
| Edit box identity after creation | [x] | Box configuration → Box Identity (name, logo, timezone) via `PATCH /gyms/current`; slug stays fixed, a timezone change re-plans recurring classes |
| Review join requests (Members → Requests, nav badge) | [x] | |
| Manage members: roles, status (active / paused / removed), notes | [x] | Paused members lose box access |
| Everything a trainer can do | [x] | Same endpoints |
| Dashboard: attendance, fill rate, no-shows, waitlist pressure | [x] | 7 / 14 / 30-day windows |
| Audit log of critical changes | [~] | Recorded and served by `/audit-logs`; no screen |
| Box settings: booking and notification rules | [~] | Screen exists, values are kept only for the session (no backend) |
| Define membership plans and prices | [ ] | |
| Assign a plan to a member, see who is paid / overdue | [ ] | |
| Collect payments (provider integration) | [ ] | `notify_payment_issues` preference exists, nothing uses it |
| Revenue on the dashboard | [ ] | Depends on payments |

## What to build next

The gaps above fall into four core features, in the order they unblock each
other:

1. **Transactional e-mail.** Verification and password reset do not work for
   real users yet. Small, and a prerequisite for launch.
2. **Persisted box settings.** Booking rules
   (booking window, cancellation cutoff, late-cancel / no-show handling) stored
   on the gym and enforced by `POST/DELETE /schedule/bookings`.
3. **Memberships and payments.** Plans (unlimited, N per week, punch card),
   member ↔ plan assignment, payment state on the Members tab, booking gated
   by an active plan, then a payment provider and revenue on the dashboard.
   This is the largest missing piece of the core.
4. **Push delivery.** Device registration already exists; send the existing
   in-app notifications (booking, waitlist promotion, WOD published) as push.

Smaller follow-ups: a trainer "My classes" view and an audit-log screen for
the owner.
