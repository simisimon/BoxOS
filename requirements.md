# BoxOS - Product Requirements Document

## 1. Product Overview

**Product Name:** BoxOS  
**Tagline:** The operating system for your gym and your training

**Vision:**  
BoxOS is a production-ready platform for running a CrossFit box, combining gym operations, workout programming, athlete logging, and community engagement in one system. It is designed for real daily use in a single gym environment first, with room for additional modules later.

**Primary Goal:**  
Enable one CrossFit box to run its core operations and athlete experience reliably from one connected product.

---

## 2. Product Direction

### 2.1 Market Position
- Production-ready application for CrossFit and functional fitness gyms
- Single-gym first
- Multi-location support is not part of the current product plan
- Modular product strategy: launch a strong operational core, then add modules deliberately

### 2.2 Client Surfaces
- Athlete-facing mobile app is a primary product surface
- Admin-focused backoffice is a primary product surface
- Core admin workflows must also remain accessible inside the mobile app for on-the-go management
- The repository currently focuses on the Flutter client application, while the product direction includes a future dedicated web backoffice

---

## 3. Target Users & Personas

### 3.1 Gym Admin
- Owns or manages a CrossFit box
- Needs dependable scheduling, billing, member management, and business visibility
- Cares about operational stability, staff efficiency, and retention

### 3.2 Coach / Trainer
- Programs workouts and runs sessions
- Needs visibility into athlete attendance and performance
- Manages delegated gym workflows inside defined permission boundaries

### 3.3 Athlete / Member
- Trains regularly at a gym
- Wants fast booking, workout visibility, logging, progress tracking, and motivation
- Expects a modern mobile experience

---

## 4. Core Principles & Constraints

### Principles
- Athlete experience must feel fast, motivating, and mobile-native
- Gym operations must feel reliable, predictable, and low-friction
- The product must be usable for real daily box operations, not just demos
- The system should favor clarity and maintainability over premature complexity
- Product expansion should happen through modules, not by bloating the initial core

### Constraints
- Single-gym first
- Mobile-first athlete experience
- Admin backoffice available on web and accessible in mobile
- GDPR-aware by design
- Production-readiness matters more than feature count

---

## 5. Roles & Permissions System

### Roles
- Athlete
- Trainer
- Admin

### Requirements
- Public self-service signup supports athlete accounts
- Admin onboarding is a controlled path
- Trainer is not a standalone public signup role
- Roles are gym-scoped where appropriate
- A single account can hold multiple roles
- Athlete training history remains tied to the user account
- Gym creation is restricted to admins
- Athletes join existing gyms through a request/approval flow
- Admins manage membership, trainer assignment, and operational permissions
- Trainer permissions are limited to delegated coaching and schedule/programming workflows

---

## 6. Production Core Platform

The production core platform is the current delivery target. These modules should be strong enough for real use in one gym before additional modules are expanded.

### 6.1 Accounts, Identity & Access
- Signup, login, verification, logout
- Password reset and password change
- Account deletion and retention handling
- Profile management
- Notification preferences
- Device registration for push delivery
- Role-aware navigation and permissions

### 6.2 Gym Setup & Membership
- Admin-only gym creation
- Gym discovery for athletes
- Join request workflow
- Approval and rejection flow
- Active gym context switching

### 6.3 Scheduling, Booking & Attendance
- Class schedule management
- Booking and cancellation
- Capacity enforcement
- Waitlist support
- Attendance tracking

### 6.4 Memberships & Payments
- Membership plans
- Recurring billing integration
- Payment state visibility
- Booking restrictions based on membership state

### 6.5 Workout Programming & Whiteboard
- Daily WOD creation
- Programming calendar
- Multiple tracks where relevant
- Whiteboard and leaderboard workflows

### 6.6 Workout Logging & Performance
- Result logging
- Workout history
- PR detection
- Progress visibility

### 6.7 Notifications & Communication
- Push notifications
- Transactional email where needed
- Event-based alerts for operations and athlete engagement

### 6.8 Basic Admin Analytics
- Attendance overview
- Revenue snapshot
- Membership state visibility

---

## 7. Expansion Modules (Later, Not Current Core)

These areas remain valid product opportunities, but they are not part of the active production-core target unless explicitly requested.

- POS and retail
- Hardware access control
- Social feed and comments
- Advanced analytics and forecasting
- Programming marketplace
- Wearable integrations
- AI-driven training insights
- Multi-location management

---

## 8. Non-Functional Requirements

### Performance
- Core user journeys should feel responsive on typical mobile networks
- Scheduling, booking, and workout result flows should avoid visible lag
- The app should remain usable during transient backend latency

### Reliability
- Core daily operations must be stable enough for real gym usage
- Errors must be recoverable and clearly communicated
- Critical actions require auditability where appropriate

### Security
- OAuth2 / JWT-compatible authentication model
- Secure token handling
- Encrypted data in transit and at rest
- Role-based access control with gym-aware boundaries

### Compliance
- GDPR-aware data handling
- Payment workflows must be PCI-conscious when payment providers are introduced

### Scalability
- Architecture should not block later expansion
- The current product target remains one gym per deployment context

---

## 9. Platform & Technology Direction

### Frontend Surfaces
- Flutter mobile application for athletes and mobile admin access
- Dedicated admin backoffice surface planned alongside the mobile product direction

### Backend Direction
- REST or GraphQL API
- Relational data model
- Multi-role access control
- Event-driven support for notifications and downstream processing where useful

---

## 10. Delivery Framing

### 10.1 Current Delivery Model
BoxOS is no longer documented as an MVP. The active goal is a **production-ready core platform** for a **single gym**.

### 10.2 Delivery Principle
- Prioritize depth and reliability in the core modules over breadth
- Ship modules in phases when they are operationally credible
- Avoid documenting speculative enterprise scope as if it were current work

---

## 11. Module Status Snapshot

**Status baseline:** 2026-04-14

### 11.1 Accounts, Roles & Authentication
- Authentication and account lifecycle: largely implemented in the current local backend/client flow
- Profile, notification preferences, and device registration: implemented
- Role-based access: in progress
- Gym association flows: implemented
- Security and audit: still incomplete

### 11.2 Scheduling & Bookings
- Schedule management: partial
- Athlete booking: implemented
- Attendance tracking: partial

### 11.3 Memberships & Payments
- Not started

### 11.4 Workout Programming & Whiteboard
- Daily WOD creation and date-based programming management: implemented
- Whiteboard workflows: implemented for in-app result submission and ranked viewing

### 11.5 Workout Logging & PR Tracking
- Not started

### 11.6 Notifications
- Preferences and device registration are implemented
- Production notification delivery is not complete

### 11.7 Admin Analytics
- Not started

---

## 12. Detailed Module Requirements

### 12.1 Accounts, Roles & Authentication
- Email/password authentication
- Verification and recovery flows
- Secure session handling
- Controlled admin onboarding
- Trainer assignment by admins
- Role-specific home and navigation experience

### 12.2 Scheduling & Bookings
- Admin/trainer class management
- Athlete booking and cancellation
- Capacity-aware booking enforcement
- Attendance lifecycle
- Future waitlist support

### 12.3 Memberships & Payments
- Membership plans
- Billing provider integration
- Payment status management
- Booking eligibility tied to active membership

### 12.4 Workout Programming & Whiteboard
- Daily workout authoring
- Programming calendar
- Track variants
- Whiteboard result display

### 12.5 Workout Logging & Performance
- Structured result logging
- Notes and context capture
- History timeline
- Basic PR detection

### 12.6 Notifications & Communication
- Booking and waitlist events
- WOD publication alerts
- Billing issue alerts
- PR and milestone alerts
- User-level preference controls

### 12.7 Admin Analytics
- Attendance overview
- Membership activity
- Revenue snapshot

---

## 13. Success Metrics

- Weekly active athletes
- Booking completion rate
- Workout logging frequency
- Class attendance utilization
- Membership retention
- Revenue visibility for admins

---

## 14. Risks & Mitigations

- **Feature sprawl:** Keep the product framed as a production core platform with phased modules.
- **Admin complexity:** Keep core admin workflows available in mobile, but reserve heavy operations for a dedicated backoffice surface.
- **Operational gaps:** Do not treat partially implemented modules as launch-ready without validation.
- **Architecture drift:** Keep implementation simple and modular so later modules can be added without major rewrites.

---

## 15. Summary

BoxOS is being positioned as a production-ready core platform for one CrossFit box, with a mobile-first athlete experience, admin backoffice direction, and a phased modular roadmap instead of an MVP framing.
