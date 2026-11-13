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
`require_schedule_manager_session` (`backend/fastapi_app.py`). Classes and
weekly templates are owner-only; trainers keep attendance, programming and
announcements.

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
| See own plan, request or change a plan | [x] | Profile → Membership; a plan can also be picked with the join request. No online payment |
| Booking blocked without a valid plan | [x] | When the box turns it on, each booking spends a token; plan dates, class types and tokens left are checked on booking, waitlist join and waitlist promotion |
| Booking / cancellation window rules | [ ] | No booking window or cancellation cutoff |

## Trainer

| Task | Status | Note |
| --- | --- | --- |
| Create / edit / delete classes and weekly templates | n/a | Owner only since 2026-11-13; trainers see the timetable read-only |
| Assign a trainer to a class | n/a | Owner only |
| Write the daily WOD with sections, publish / unpublish | [x] | One WOD per box per day |
| Duplicate a WOD, import WODs from CSV | [x] | See `docs/wod-import.md` |
| See the booking roster of a class | [x] | Members are visible here; trainers have no Members tab |
| Mark attendance (attended / no-show) | [x] | |
| Post and edit announcements, moderate chat | [x] | |
| "My classes" view (only the classes I coach) | [x] | "Coached by me" filter on Classes |

## Owner

| Task | Status | Note |
| --- | --- | --- |
| Create the box (name, logo, timezone) | [x] | |
| Edit box identity after creation | [x] | Box configuration → Box Identity (name, logo, timezone) via `PATCH /gyms/current`; slug stays fixed, a timezone change re-plans recurring classes |
| Review join requests (Members → Requests, nav badge) | [x] | |
| Manage members: roles, status (active / paused / removed), notes | [x] | Paused members lose box access |
| Everything a trainer can do | [x] | Same endpoints, plus owning the timetable |
| Create / edit / delete classes and weekly templates, assign trainers, remove a member from a class | [x] | Owner only |
| Dashboard: attendance, fill rate, no-shows, waitlist pressure | [x] | 7 / 14 / 30-day windows |
| Audit log of critical changes | [~] | Recorded and served by `/audit-logs`; no screen |
| Box settings: booking and notification rules | [~] | Screen exists, values are kept only for the session (no backend) |
| Define membership plans and prices | [x] | Box configuration → Memberships: token-based (unlimited, N tokens per week/month/year, one-off token pack); price, billing period, class types; archive instead of delete |
| Assign a plan to a member, see who is paid / overdue | [x] | Plan requests in Members → Requests (badge counts them); assign, end and set payment state (paid / due / overdue, by hand) in the member detail |
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
3. **Payments.** Plans, plan requests, manual payment state and the booking
   gate are in (see "Membership plans" below). Still missing: a payment
   provider, "pay to activate" for plans, and revenue on the dashboard.
4. **Push delivery.** Device registration already exists; send the existing
   in-app notifications (booking, waitlist promotion, WOD published) as push.

## Membership plans

- **Tokens:** plans are token-based. Every booked class spends one token, on
  any class type the plan includes. Plan types: *unlimited* tokens; *N tokens
  per week / month / year*; a one-off *token pack* (N tokens, optionally valid
  for X days from the start). Each plan has a price (one currency per box), a
  billing period (monthly, yearly, one-off) and the class types its tokens can
  be spent on.
- **Periods:** token periods run from the member plan's start date (a plan
  starting on the 9th refills on the 9th). Unused tokens expire at the end of
  the period. A class spends a token of the period its date falls in, so
  booking ahead uses the next period's tokens. Cancelling gives the token back;
  a no-show keeps it spent.
- **Getting a plan:** the athlete requests a plan (Profile → Membership, or
  with the join request) and the owner approves it with a start date and,
  if needed, a different price. The owner can also assign a plan directly.
  Price and tokens are copied onto the member's plan, so editing a plan only
  affects new members.
- **One plan at a time:** a new plan ends the current one the day before it
  starts.
- **Booking gate:** off by default (Box configuration → Memberships). Owners
  and trainers are never checked. Code: `backend/plan_service.py`,
  `app/lib/features/memberships/`.

Smaller follow-ups: a trainer "My classes" view and an audit-log screen for
the owner.
