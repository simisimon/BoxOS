# Recurring Schedule Design

## Goal

Finish `US-B1-03` by adding recurring class creation to the existing schedule management flow in BoxOS.

This slice adds support for creating recurring classes with these frequencies:
- `daily`
- `weekly`
- `monthly`

For this product, `monthly` means every 4 weeks on the same weekday and time, not the same calendar day each month.

## Scope

In scope:
- Recurrence selection during class creation
- Required occurrence count for recurring classes
- Backend generation of multiple `class_schedules` rows
- Flutter UI support for recurrence controls
- Backend and Flutter test coverage
- Story documentation updates when implementation is complete

Out of scope:
- Editing an entire recurring series
- Deleting an entire recurring series
- Separate recurring-series database tables
- Background generation of rolling future schedule windows
- Calendar-month recurrence semantics

## Existing Constraints

- The current backend stores classes as individual `class_schedules` rows.
- Bookings, waitlists, attendance, notifications, and edit/delete behavior already operate on individual class rows.
- The current Flutter schedule UI already supports one-off class creation, editing, and deletion.

## Chosen Approach

Use eager instance generation on class creation.

When a schedule manager creates a recurring class, the backend will immediately create the requested number of future class instances as normal `class_schedules` rows. This avoids adding a recurrence engine or a separate parent series model in this slice.

This is the best fit for the current code because:
- it preserves the existing schedule instance model
- it keeps bookings and waitlists attached to stable class rows
- it avoids overengineering for the current single-gym production scope
- it allows future instance-by-instance edits and deletes without extra migration work

## API Design

### Existing endpoint

`POST /schedule/classes`

### New request fields

- `recurrence_frequency`: optional string
  - allowed values: `none`, `daily`, `weekly`, `monthly`
  - omitted values are treated as `none`
- `occurrence_count`: optional integer
  - required when `recurrence_frequency` is not `none`
  - minimum value: `1`

### Recurrence semantics

- `none`: create one class instance
- `daily`: create one instance every 1 day
- `weekly`: create one instance every 7 days
- `monthly`: create one instance every 28 days

### Response shape

The create endpoint will return:
- `class`: the first created class for backward compatibility
- `classes`: the full list of created class instances
- `created_count`: the number of created instances

Keeping `class` avoids breaking current consumers while enabling the Flutter app to understand recurring creation results if needed.

## Backend Behavior

### Creation flow

1. Validate the base class fields using the existing schedule validation.
2. Validate recurrence inputs.
3. Calculate the list of occurrence start times from the requested frequency and occurrence count.
4. Reject any occurrence whose start time is not in the future.
5. Insert one `class_schedules` row per generated occurrence.
6. Return the first created class, the full created list, and the created count.
7. Write audit entries including recurrence metadata.

### Validation rules

- `recurrence_frequency` must be one of the supported values.
- `occurrence_count` must be at least `1` when recurrence is enabled.
- `occurrence_count` is ignored for `none`.
- All generated start times must still be future times.
- Existing trainer validation still applies to every generated instance.

### Edit and delete behavior

Editing and deleting remain instance-based.

That means:
- editing one class changes only that class
- deleting one class removes only that class

This is intentional for this slice. It avoids unintended changes to future classes with existing bookings and matches the current product simplicity goal.

### Data model

No new recurrence table will be added in this slice.

Each generated occurrence is stored as a normal `class_schedules` row with:
- same title
- same class type
- same assigned trainer
- same duration
- same capacity
- same WOD description
- different start and end times

## Flutter UI Design

Recurring scheduling will be added to the class creation flow only.

### Create form changes

Add a recurrence section with:
- `Repeat` dropdown
  - `Does not repeat`
  - `Daily`
  - `Weekly`
  - `Monthly (every 4 weeks)`
- `Occurrences` numeric input
  - shown only when repeat is not `Does not repeat`
  - required for recurring creation

### Existing behavior preserved

- One-off class creation remains available.
- Editing stays single-instance.
- Delete stays single-instance.

### UX intent

Keep the flow explicit and predictable for a gym operator:
- they choose the recurrence frequency
- they choose exactly how many future classes to create
- the system creates those schedule entries immediately

## Testing Strategy

### Backend TDD

Add failing tests for:
- creating a daily recurring series
- creating a weekly recurring series
- creating a monthly recurring series with 28-day intervals
- rejecting invalid recurrence frequencies
- rejecting invalid occurrence counts

### Flutter tests

Add or update tests for:
- recurrence controls rendering in the create form
- occurrence input visibility when repeat is enabled
- recurring class creation submitting recurrence fields to the repository

## Risks and Tradeoffs

### Accepted tradeoff

Without a parent series model, later “edit whole series” behavior will require additional design. That is acceptable because the current user story only requires recurring creation support.

### Main benefit

This slice completes the production need without adding architecture that the current app does not yet need.

## Completion Criteria

`US-B1-03` can be marked complete when:
- recurring class creation works for daily, weekly, and monthly
- monthly uses 28-day intervals
- occurrence count is required for recurring creation
- backend tests pass
- Flutter analysis passes
- Flutter tests for this behavior pass
- `requirements.md` and `user_stories.md` are updated to reflect story completion
