# BoxOS Role Permission Matrix

Last reviewed: 2026-05-28

This matrix documents the currently intended production-core access rules for the local REST backend and Flutter client.

## Global account rules

| Capability | Athlete | Trainer | Admin |
| --- | --- | --- | --- |
| Standard signup | Yes | No | No |
| Controlled admin signup path | No | No | Yes |
| Login/logout/session/profile | Yes | Yes | Yes |
| Change password / delete account | Yes | Yes | Yes |
| Create gym | No | No | Yes (admin account only) |

## Active gym required

The following areas require an active gym membership in the selected gym context:

- Schedule listing
- Booking / cancellation / waitlist
- Programming calendar
- Whiteboard submission and viewing
- Logbook entries
- Notifications scoped to gym events

## Gym-scoped permissions

| Capability | Athlete | Trainer | Admin |
| --- | --- | --- | --- |
| View schedule in active gym | Yes | Yes | Yes |
| View booking roster for classes | No | Yes | Yes |
| Create / edit / delete future classes | No | Yes | Yes |
| Record class attendance | No | Yes | Yes |
| View programming calendar | Yes | Yes | Yes |
| Create / edit daily WODs | No | Yes | Yes |
| Submit whiteboard results | Yes | Yes | Yes |
| Submit own workout log | Yes | Yes | Yes |
| View own logbook | Yes | Yes | Yes |
| Submit join request | Yes | Yes | Yes |
| View own join requests | Yes | Yes | Yes |
| Review join requests | No | No | Yes |
| View gym member role list | No | No | Yes |
| Assign athlete/trainer roles | No | No | Yes |
| View audit logs | No | No | Yes |

## Notes

- Trainers are intentionally limited to delegated coaching workflows: scheduling, programming, and attendance.
- Admin-only operational surfaces must remain protected in both the client and backend.
- Backend authorization is the source of truth; client-side hiding is a usability layer, not a security boundary.
- Membership/payment enforcement is not part of this matrix yet and should be added once Epic C is implemented.
