# Scheduling Waitlist And Booking Notifications Design

**Date:** 2026-05-17
**Repo:** `C:\GitHub\BoxOS`
**Baseline commit:** `1bf323c`

## Goal

Complete the current scheduling loop by adding waitlist support for full classes and by generating in-app notifications for booking confirmations, waitlist promotions, and relevant schedule changes.

## Scope

This design covers:

- `US-B1-04` Waitlist handling
- the notification-completion slice of `US-F1-01` Booking and schedule notifications
- related schedule payload and UI updates required to expose the new state
- targeted role-access verification within the affected scheduling flows

This design does not cover:

- memberships and payments
- external push notification delivery
- email delivery
- advanced recurring scheduling beyond the existing `US-B1-03` partial flow

## Current Context

The codebase already has:

- backend schedule storage in `backend/server.py`
- class booking and cancellation flows
- attendance tracking from bookings
- in-app notification storage and inbox display
- notification preference fields for booking confirmations and waitlist promotions
- a Flutter schedule screen backed by `ApiScheduleRepository`

Current gaps:

- a full class can only reject a booking attempt
- there is no waitlist record or promotion workflow
- booking confirmations are not written to the notification inbox
- schedule updates do not notify affected athletes
- the schedule payload does not expose waitlist state

## Recommended Approach

Use the existing local REST backend and in-app notification model instead of introducing a new messaging abstraction.

This keeps the feature aligned with the current architecture:

- backend remains the source of truth for booking, waitlist, and promotion decisions
- Flutter consumes richer schedule payloads and exposes a small number of new actions
- notification delivery continues to use the existing inbox and preference model

## Data Model Changes

Add a new backend table for class waitlist entries.

Proposed table:

- `class_waitlist_entries`
  - `id`
  - `class_schedule_id`
  - `user_id`
  - `created_at`
  - unique `(class_schedule_id, user_id)`

Behavior rules:

- only active gym members can join the waitlist for a future class
- a user cannot be both booked and waitlisted for the same class
- waitlist order is FIFO by `created_at`
- when a booking is cancelled, the first eligible waitlist entry is promoted automatically
- promotion removes the waitlist entry and creates a normal booking

## API Changes

### New endpoints

- `POST /schedule/waitlist`
  - joins the current user to the waitlist for a class
- `DELETE /schedule/waitlist`
  - removes the current user from the waitlist for a class

### Existing endpoint behavior changes

- `GET /schedule/classes`
  - add `waitlist_count`
  - add `is_waitlisted`
  - keep current booking fields
- `DELETE /schedule/bookings`
  - after cancellation, attempt waitlist promotion
- `PATCH /schedule/classes`
  - after a schedule change, notify affected booked athletes and affected waitlisted athletes when appropriate

### Promotion rules

On cancellation:

1. remove the current booking
2. fetch the oldest waitlist entry for that class
3. create a booking for that athlete if capacity is now available
4. create a waitlist-promotion notification if that athlete has the preference enabled

No background worker is needed for this slice. Promotion can happen synchronously inside the cancellation flow.

## Notification Rules

### Booking confirmation

Create an in-app notification when a user successfully books a class, if `notify_booking_confirmations` is enabled.

### Waitlist promotion

Create an in-app notification when a waitlisted athlete is promoted into the class, if `notify_waitlist_promotions` is enabled.

### Schedule changes

When a trainer or admin updates a class:

- notify booked athletes when the start time, duration, assigned trainer, title, or cancellation-relevant schedule details change
- notify waitlisted athletes for meaningful schedule updates using the same event family

For this first slice, message content should stay simple and factual. No additional preference category needs to be introduced yet; booking confirmations covers schedule-related booking changes for now.

## Flutter Client Changes

### Repository layer

Update `ApiScheduleRepository` and the schedule models to parse:

- `waitlist_count`
- `is_waitlisted`

Add repository methods:

- `joinWaitlist`
- `leaveWaitlist`

### Schedule UI

Update the schedule card behavior:

- if the user is booked, show cancel booking
- if the user is not booked and spots remain, show book class
- if the user is not booked, no spots remain, and the user is not waitlisted, show join waitlist
- if the user is waitlisted, show leave waitlist

Update summary text to show:

- booked count and capacity
- waitlist count when greater than zero
- current user state: booked, waitlisted, attended, or no-show where applicable

The UI should stay simple and mobile-first. No advanced calendar redesign is needed.

## Role And Access Rules

- athletes can book, cancel, join waitlists, and leave their own waitlist entries
- trainers and admins continue to manage classes and attendance
- athletes cannot inspect other athletes’ waitlist entries if the backend does not already expose them
- schedule manager endpoints stay restricted to trainer/admin roles

While implementing this slice, verify that the new waitlist endpoints reject unauthorized roles consistently.

## Error Handling

The backend should return clear errors for:

- class not found in active gym
- class already started
- already booked
- already waitlisted
- no waitlist entry to remove
- attempting to join waitlist when spots are still available only if that rule is chosen

Recommended rule:

- only allow waitlist join when the class is full

This keeps the feature understandable for the first release.

## Testing Strategy

Backend tests in `backend/test_server.py` should cover:

- joining waitlist for a full future class
- rejecting duplicate waitlist entries
- rejecting waitlist join when already booked
- removing waitlist entry
- auto-promotion on booking cancellation
- booking confirmation notification creation
- waitlist promotion notification creation
- schedule update notification creation for affected athletes
- role/access rejection for unauthorized operations

Flutter tests should focus on repository parsing and widget behavior for:

- full class shows waitlist action
- waitlisted class shows leave waitlist action
- booked class still shows cancel booking

Given the current environment, backend tests are the main verification path and Flutter tests should stay narrow.

## Risks

- Notification fan-out on schedule updates can become noisy if every minor edit triggers alerts.
- Waitlist promotion inside the cancellation request adds more logic to a path that is currently simple.
- The current `flutter test` environment is unstable, so backend verification carries more weight for now.

## Decision Summary

- Implement waitlists in the existing backend, not via a new service
- Promote waitlisted athletes synchronously on cancellation
- Reuse the existing in-app notification system and user preferences
- Keep the Flutter UI minimal and state-driven
- Use backend tests as the primary safety net for this slice
