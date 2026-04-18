# BoxOS (Flutter) – Project Blueprint

This document describes a recommended project structure, conventions, and tooling for **BoxOS**, optimized for:
- Cross-platform (iOS + Android)
- Feature scalability (production core platform first, additional modules over time)
- Offline-first where it matters (logging, WODs, schedule)
- Testability and maintainability

---

## 1. High-Level Architecture

**Recommended approach:** Feature-first with lightweight Clean Architecture boundaries.

Each feature follows a consistent internal structure:
- **presentation/**: UI (screens, widgets), navigation, view models/controllers
- **application/**: state management + use-cases (or “services” for the feature)
- **domain/**: entities, value objects, domain rules (pure Dart, no Flutter)
- **data/**: repositories, API clients, local DB DAOs, mappers

Use **Riverpod** for state management and **go_router** for navigation.

---

## 2. Repository Layout

### 2.1 Monorepo (single repository)
Recommended if you only ship mobile:

```
boxos/
  app/
    android/
    ios/
    lib/
    test/
    integration_test/
    assets/
    pubspec.yaml
  docs/
  tools/
  .github/
```

### 2.2 “App-only” repo (simplest)
If you’re strictly Flutter only:

```
boxos_app/
  android/
  ios/
  lib/
  test/
  integration_test/
  assets/
  pubspec.yaml
```

---

## 3. `lib/` Folder Structure (Feature-First)

```
lib/
  main.dart
  bootstrap.dart
  app.dart

  core/
    config/
    routing/
    theme/
    di/
    logging/
    errors/
    utils/

  shared/
    widgets/
    extensions/
    formatting/
    validators/

  features/
    auth/
      presentation/
      application/
      domain/
      data/
    gyms/
      ...
    scheduling/
      ...
    programming/
      ...
    logging/
      ...
    leaderboard/
      ...
    notifications/
      ...
```

### 3.1 Core vs Shared
- **core/**: cross-cutting concerns, app initialization, routing, error handling
- **shared/**: reusable UI widgets, validators, formatting, extensions
- **features/**: all product functionality, grouped by business domain

---

## 4. Core Modules (What Lives Where)

### 4.1 `core/config/`
- Environment configuration (dev/staging/prod)
- API base URLs, feature flags (client-side)
- Build flavor constants

Recommended files:
- `env.dart` (immutable config model)
- `env_loader.dart` (loads from compile-time defines)

### 4.2 `core/routing/`
- `router.dart` (go_router setup)
- route guards (auth required, gym selected, role checks)
- deep link handlers (invite links, email verification)

### 4.3 `core/di/`
- Riverpod providers for shared services:
  - HTTP client (Dio)
  - auth token store
  - database
  - repositories (top-level)
  - analytics/crash reporting

### 4.4 `core/errors/`
- unified error types (NetworkError, AuthError, ValidationError)
- mapping from API errors → domain/application errors
- UI error presentation helpers

---

## 5. Feature Blueprint (Template)

Each feature should look like:

```
features/<feature_name>/
  presentation/
    screens/
    widgets/
    controllers/
    <feature>_routes.dart
  application/
    usecases/
    state/
    <feature>_service.dart
  domain/
    entities/
    value_objects/
    repositories/
  data/
    api/
      <feature>_api.dart
      dto/
    local/
      dao/
      tables/
    repositories/
      <feature>_repository_impl.dart
    mappers/
```

### Example: Auth Feature
```
features/auth/
  presentation/
    screens/login_screen.dart
    screens/signup_screen.dart
    controllers/auth_controller.dart
  application/
    state/auth_state.dart
    usecases/login.dart
    usecases/logout.dart
  domain/
    entities/user.dart
    repositories/auth_repository.dart
  data/
    api/auth_api.dart
    repositories/auth_repository_impl.dart
```

---

## 6. State Management Conventions (Riverpod)

### 6.1 Use AsyncNotifier for server state
- Use `AsyncNotifier<T>` (or `Notifier<T>`) for feature controllers
- Keep controllers thin: call use-cases/services

Naming:
- `SomethingController` for stateful controllers
- `somethingControllerProvider` for the provider

Example naming pattern:
- `authControllerProvider`
- `scheduleControllerProvider`
- `wodDetailControllerProvider`

### 6.2 Separate “Server State” from “UI State”
- Server state: data loaded from API/local DB (AsyncValue)
- UI state: local flags (form validation, selected filters)

---

## 7. Networking Layer

### 7.1 HTTP Client
- **Dio** as the base client
- Interceptors:
  - auth header injection
  - request ID
  - logging (dev only)
  - automatic token refresh (refresh token flow)

### 7.2 DTO + Mapping
- API responses → DTOs (json_serializable)
- DTOs → domain entities (mappers)
- Never leak DTOs into presentation layer

---

## 8. Local Database (Offline Support)

**Recommended:** Drift (SQLite)

### 8.1 Tables (typical production-core platform)
- `wods` (cached WODs)
- `classes` (schedule)
- `bookings`
- `results` (workout logs)
- `outbox` (offline actions queue)

### 8.2 Outbox Pattern (must-have)
When offline:
- write user intent into `outbox` table (e.g., “submit_result”)
- UI behaves as if completed (optimistic)
When online:
- sync worker processes outbox and resolves conflicts
- retry with backoff
- mark item as “failed” with reason when permanently failing

---

## 9. Navigation & Deep Links (go_router)

### 9.1 Route Organization
- Each feature provides a `<feature>_routes.dart`
- Main router composes all feature routes

### 9.2 Guards (examples)
- Must be logged in
- Must have active gym selected
- Must have admin role to access admin-only screens (even if minimal in mobile)

### 9.3 Deep Links (examples)
- `boxos://invite/<code>`
- `boxos://verify-email/<token>`
- Push notifications link to WOD detail, booking detail

---

## 10. Build Flavors & Environment Setup

### 10.1 Flavors
- `dev`
- `staging`
- `prod`

Each flavor defines:
- API base URL
- Firebase project config
- Sentry DSN
- Stripe keys (if used)

### 10.2 Passing environment values
Use `--dart-define`:
- `--dart-define=ENV=dev`
- `--dart-define=API_BASE_URL=https://...`

---

## 11. Testing Strategy

### 11.1 Unit Tests
- domain rules (pure Dart)
- mappers
- use-cases
- controllers (with mocked repositories)

### 11.2 Widget Tests
- form validation
- critical UI states (loading/error/success)

### 11.3 Integration Tests
Cover the core production path:
1. Sign up / login
2. Join gym via invite link
3. View schedule + book class
4. View WOD + log result
5. View leaderboard

---

## 12. Code Quality & Tooling

### 12.1 Linting & Formatting
- `flutter_lints`
- `dart format` enforced in CI

### 12.2 Code Generation
Common generators:
- `freezed` (immutable models)
- `json_serializable` (DTOs)
- `build_runner`

### 12.3 Error Reporting
- `sentry_flutter` for crash reporting
- capture breadcrumbs for auth, API failures, navigation

---

## 13. CI/CD & Release

### 13.1 CI
- Run: analyze, format check, unit tests, basic integration tests
- Build artifacts for `dev` and `staging`

### 13.2 Distribution
- iOS: TestFlight
- Android: Internal Testing track

Use:
- Fastlane (classic) **or** Codemagic (Flutter-friendly)

---

## 14. Recommended Production-Core Feature Modules

- `auth` (signup/login, tokens, roles)
- `gyms` (create/join/switch gym)
- `scheduling` (schedule, booking, attendance)
- `programming` (WOD list/detail)
- `logging` (submit results, history)
- `leaderboard` (daily board, filters)
- `notifications` (push categories, deep link handling)

---

## 15. Naming Conventions (Quick Rules)

- Files: `snake_case.dart`
- Classes: `PascalCase`
- Providers: `<thing>Provider` suffix
- Controllers: `<Feature>Controller`
- DTOs: `<Thing>Dto`
- Repository interfaces live in `domain/repositories/`
- Repository impls live in `data/repositories/`

---

## 16. Starter Checklist (Before Coding Features)

- [ ] Create flavors (dev/staging/prod) for iOS and Android
- [ ] Configure Firebase per flavor (push later is fine)
- [ ] Set up Sentry
- [ ] Implement auth token handling + refresh flow
- [ ] Create base router with auth guard
- [ ] Add Dio + interceptors
- [ ] Add Drift DB + migrations + outbox table
- [ ] Add basic CI pipeline

---

*This blueprint is designed to keep BoxOS maintainable as it grows from a production-ready single-gym platform into a broader gym operating system if needed later.*
