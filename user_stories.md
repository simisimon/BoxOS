# BoxOS - User Stories

This file tracks the delivery status of the production core platform for BoxOS.

## Product framing
- Single-gym first
- Athlete-first mobile application
- Admin-focused backoffice as a core product surface
- Admin workflows must also remain accessible inside the mobile app
- Additional modules may be added later, but this file prioritizes the production core platform first

---

## Epic A - Accounts, Roles & Authentication

### A1. Authentication & Account Lifecycle

#### US-A1-01 - Sign up (email/password)
**Status:** Complete

**As a user**, I want to create an account with email and password so I can use BoxOS.

**Acceptance Criteria**
- Email must be unique case-insensitively.
- Password policy is enforced.
- Verification is required before full account activation.

#### US-A1-02 - Verify email
**Status:** Complete

**As a user**, I want to verify my email so my account is activated and secure.

**Acceptance Criteria**
- Verification link or token expires.
- User can request a resend.
- Invalid or expired verification state is handled clearly.

#### US-A1-03 - Log in
**Status:** Complete

**As a user**, I want to log in so I can access my gym and training data.

**Acceptance Criteria**
- Email/password login is supported.
- Failed attempt protection exists.
- Session token is issued securely.

#### US-A1-04 - Log out
**Status:** Complete

**As a user**, I want to log out to secure my account.

**Acceptance Criteria**
- Session is revoked or invalidated.
- Device registration cleanup is supported where needed.

#### US-A1-05 - Forgot password
**Status:** Complete

**As a user**, I want to reset my password if I forget it.

**Acceptance Criteria**
- Reset flow expires appropriately.
- Password policy remains enforced.
- User can revoke other sessions if configured.

#### US-A1-06 - Change password
**Status:** Complete

**As a logged-in user**, I want to change my password.

**Acceptance Criteria**
- Current password is required.
- User can optionally revoke other sessions.

#### US-A1-07 - Account deletion
**Status:** Complete

**As a user**, I want to delete my account and personal data.

**Acceptance Criteria**
- Deletion follows retention and purge rules.
- Required anonymization is applied.

#### US-A1-08 - Distinct admin onboarding
**Status:** Complete

**As the system**, I want admin onboarding to stay separate from standard athlete signup so gym creation remains controlled.

**Acceptance Criteria**
- Public signup creates athlete accounts only.
- Admin onboarding follows a controlled path.
- Trainer is not a public signup role.

### A2. Identity, Profile & Devices

#### US-A2-01 - Edit profile
**Status:** Complete

**As a user**, I want to edit my profile information.

**Acceptance Criteria**
- Name and nickname are editable.
- Profile media support can be phased if not yet implemented.

#### US-A2-02 - Manage notifications
**Status:** Complete

**As a user**, I want to control notification preferences.

**Acceptance Criteria**
- Preferences can be toggled by notification type.
- Settings persist server-side.

#### US-A2-03 - Device registration
**Status:** Complete

**As a user**, I want my device to be registered for push notifications.

**Acceptance Criteria**
- Device token is stored securely.
- Device token can be removed on logout or account deletion.

### A3. Roles & Permissions

#### US-A3-01 - Default role
**Status:** Complete

**As a new user**, I want a default athlete role.

**Acceptance Criteria**
- Public standard signup creates athlete accounts by default.
- Trainer is not a public signup path.
- Additional roles are assigned through controlled workflows.

#### US-A3-02 - Assign trainer roles
**Status:** Complete

**As an admin**, I want to assign trainer access to members of my gym.

**Acceptance Criteria**
- Admin can view members of the active gym.
- Admin can assign trainer role within that gym.
- Assignment remains gym-scoped.

#### US-A3-03 - Role-based access
**Status:** In Progress

**As the system**, I want feature access to be restricted by role.

**Acceptance Criteria**
- Admin-only endpoints are protected.
- Trainers can manage delegated gym workflows.
- Athletes cannot access admin-only operations.

#### US-A3-04 - Multi-role switching
**Status:** Complete

**As a user with multiple roles**, I want to switch context.

**Acceptance Criteria**
- A role switcher is available where needed.
- The last active role is remembered.

#### US-A3-05 - Role-specific home experience
**Status:** Complete

**As a user**, I want my home experience to reflect whether I am acting as an athlete, trainer, or admin.

**Acceptance Criteria**
- Athlete home is athlete-focused.
- Admin home is management-focused.
- Role and gym context determine what is shown.

#### US-A3-06 - Gym member management and trainer promotion
**Status:** Complete

**As an admin**, I want to see members of my gym and promote eligible athletes to trainer.

**Acceptance Criteria**
- Active gym member list is visible to admins.
- Member role is shown.
- Admin can promote eligible athlete members to trainer.

### A4. Gym Association

#### US-A4-01 - Create gym (admin only)
**Status:** Complete

**As an admin**, I want to create a gym so I can set up my box in BoxOS.

**Acceptance Criteria**
- Only admins can create gyms.
- Name and timezone are required.
- Creator becomes admin for that gym.

#### US-A4-02 - Browse and select gym
**Status:** Complete

**As an athlete**, I want to browse available gyms and choose the correct one before requesting access.

**Acceptance Criteria**
- User can browse gyms.
- User can search or filter gyms.
- Gym details are sufficient to distinguish the correct gym.

#### US-A4-03 - Request to join gym
**Status:** Complete

**As an athlete**, I want to request to join an existing gym.

**Acceptance Criteria**
- Logged-in athletes can submit a join request.
- Duplicate active requests are prevented.
- Existing members cannot request the same gym again.

#### US-A4-04 - Review join requests
**Status:** Complete

**As an admin**, I want to review pending join requests.

**Acceptance Criteria**
- Pending requests are listed in an admin-only view.
- Request details and timestamps are visible.
- Only admins of that gym can access the flow.

#### US-A4-05 - Approve or reject join request
**Status:** Complete

**As an admin**, I want to approve or reject join requests so membership stays controlled.

**Acceptance Criteria**
- Approval creates the gym membership.
- Rejection stores a final rejected state.
- Processed requests leave the pending queue.

#### US-A4-06 - Switch gyms
**Status:** Complete

**As a user in multiple gyms**, I want to switch active gym context.

**Acceptance Criteria**
- A gym switcher is available when needed.
- Selected context persists.

### A5. Security & Audit

#### US-A5-01 - Secure tokens
**Status:** Complete

**As the system**, I want secure session token handling.

**Acceptance Criteria**
- Access tokens are short-lived where applicable.
- Refresh token rotation is supported.
- Session revocation is supported.

#### US-A5-02 - Audit log
**Status:** Complete

**As an admin**, I want an audit log of critical operational changes.

**Acceptance Criteria**
- Actor, action, and timestamp are recorded.
- Role changes and approval decisions are auditable.

---

## Epic B - Scheduling, Booking & Attendance

#### US-B1-01 - Athlete booking and cancellation
**Status:** Complete

**As an athlete**, I want to book and cancel classes so I can manage my training schedule.

**Acceptance Criteria**
- Athlete can view classes for the active gym.
- Athlete can book a future class when capacity is available.
- Duplicate bookings are prevented.
- Athlete can cancel a future booking.
- Booking status and remaining spots are visible.

#### US-B1-02 - Attendance tracking from bookings
**Status:** Complete

**As a trainer or admin**, I want to mark attendance from class bookings so the gym can track who actually showed up.

**Acceptance Criteria**
- Trainer or admin can view booked members for a class.
- Attendance can be set to attended or no-show.
- Attendance can be reset back to booked.
- Athletes cannot update attendance for themselves or others.

#### US-B1-03 - Recurring class schedule management
**Status:** In Progress

**As an admin or trainer**, I want to manage the class schedule so recurring operations are easy to maintain.

**Acceptance Criteria**
- Future classes can be created and updated.
- Capacity and timing can be managed safely.
- Recurring schedule support is available or explicitly phased.

#### US-B1-04 - Waitlist handling
**Status:** Not Started

**As an athlete**, I want to join a waitlist when a class is full.

**Acceptance Criteria**
- Athlete can join a waitlist for a full class.
- Promotion rules are applied consistently.
- Notifications are sent on promotion.

---

## Epic C - Memberships & Payments

#### US-C1-01 - Membership plan management
**Status:** Not Started

**As an admin**, I want to create and manage membership plans.

**Acceptance Criteria**
- Recurring and limited-use plans can be defined.
- Access rules can be attached to a plan.

#### US-C1-02 - Payment lifecycle visibility
**Status:** Not Started

**As an admin**, I want to see payment state clearly so I can act on failed or inactive memberships.

**Acceptance Criteria**
- Payment status is visible per member.
- Failed payment state is distinguishable from canceled or paused membership.

#### US-C1-03 - Booking enforcement from membership state
**Status:** Not Started

**As the system**, I want booking access to depend on valid membership state.

**Acceptance Criteria**
- Inactive memberships cannot book restricted classes.
- Booking rules reflect active plan entitlements.

---

## Epic D - Workout Programming & Whiteboard

#### US-D1-01 - Create daily WOD
**Status:** Complete

**As a trainer or admin**, I want to create a daily workout for my gym.

**Acceptance Criteria**
- Workout supports common sections such as strength and MetCon.
- Workout can be assigned to a date.
- Appropriate gym roles can edit future workouts.

#### US-D1-02 - Programming calendar
**Status:** Complete

**As a trainer or admin**, I want to manage workouts on a calendar.

**Acceptance Criteria**
- Upcoming workouts are visible by date.
- Future programming can be updated cleanly.

#### US-D1-03 - Digital whiteboard
**Status:** Complete

**As an athlete**, I want to submit results to a gym whiteboard.

**Acceptance Criteria**
- Results can be submitted for the active workout.
- Whiteboard results are visible to gym members.
- Sorting or ranking is available where relevant.

---

## Epic E - Workout Logging & Performance

#### US-E1-01 - Log workout result
**Status:** Complete

**As an athlete**, I want to log my workout result.

**Acceptance Criteria**
- Common score types are supported.
- Notes can be added.

#### US-E1-02 - Workout history
**Status:** Complete

**As an athlete**, I want to review my workout history.

**Acceptance Criteria**
- Logged workouts are shown chronologically.
- Entries can be tied back to workouts or classes where appropriate.

#### US-E1-03 - Basic PR detection
**Status:** Not Started

**As an athlete**, I want personal records to be detected automatically.

**Acceptance Criteria**
- Best performances can be identified for supported movement or score types.
- PR events can feed notification or celebration flows later.

---

## Epic F - Notifications & Communication

#### US-F1-01 - Booking and schedule notifications
**Status:** In Progress

**As a user**, I want important booking and schedule events to trigger notifications.

**Acceptance Criteria**
- Booking confirmation can trigger a notification.
- Schedule changes can trigger a notification where appropriate.
- User preferences are respected.

#### US-F1-02 - WOD and performance notifications
**Status:** Not Started

**As a user**, I want workout and PR events to trigger useful alerts.

**Acceptance Criteria**
- WOD publication alerts are supported.
- PR or milestone alerts are supported.
- User preferences are respected.

---

## Epic G - Admin Analytics

#### US-G1-01 - Attendance overview
**Status:** Not Started

**As an admin**, I want a clear attendance overview.

**Acceptance Criteria**
- Daily attendance can be summarized.
- Data aligns with booking and attendance records.

#### US-G1-02 - Revenue snapshot
**Status:** Not Started

**As an admin**, I want a basic revenue snapshot.

**Acceptance Criteria**
- Active memberships are visible.
- Basic recurring revenue view is available.
