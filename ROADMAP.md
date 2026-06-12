# BoxOS Roadmap

> Diese Datei ist die zentrale Produkt-, Delivery- und Readiness-Übersicht für BoxOS. Sie fasst die bisher auf mehrere Markdown-Dateien verteilten Kerninformationen zusammen, damit `ROADMAP.md` neben der Standard-`README.md` als primäres Projektdokument bestehen kann.

---

## 1. Produktmission

**BoxOS** ist die produktionsreife Kernplattform für den Betrieb einer einzelnen CrossFit- bzw. Functional-Fitness-Box.

### Mission
Eine Box soll ihre täglichen Kernprozesse und das Athlete-Erlebnis zuverlässig in einem verbundenen System abbilden können:
- Gym-Betrieb
- Klassenplanung und Buchung
- Workout-Programmierung
- Workout-Logging und Fortschritt
- Kommunikation und Community
- Memberships und Zahlungen
- operative Kennzahlen für Admins

### Leitbild
- **Single-gym first**
- **Athlete-first mobile experience**
- **Admin-focused backoffice** als zentrale Produktsäule
- **Wichtige Admin-Workflows auch mobil verfügbar**
- **Production core vor Feature-Sprawl**
- **Modulare Expansion nach einer starken Kernplattform**

### Positionierung
BoxOS ist kein MVP mehr. Das Ziel ist eine **production-ready core platform** für **ein einzelnes Gym**, nicht eine breite Multi-Location- oder Enterprise-Suite im ersten Schritt.

---

## 2. Zielgruppen

### Admin / Owner
- betreibt oder verwaltet eine Box
- braucht Planungssicherheit, Mitgliederverwaltung, Zahlungsübersicht und betriebliche Transparenz
- will ein System, das im Alltag stabil funktioniert

### Trainer / Coach
- programmiert Workouts und betreut Klassen
- braucht Zugriff auf Schedule, Attendance, Programming und Athlete-Kontext
- arbeitet innerhalb klar definierter, delegierter Berechtigungen

### Athlete / Member
- will schnell Klassen buchen, WODs sehen, Ergebnisse loggen und Fortschritt erkennen
- erwartet eine moderne, motivierende Mobile Experience
- profitiert stark von Community-, Feedback- und Recognition-Loops

---

## 3. Produktprinzipien und Grenzen

### Produktprinzipien
- Athlete-Flows müssen schnell, motivierend und mobile-native sein.
- Operative Gym-Flows müssen zuverlässig, klar und reibungsarm sein.
- Reale Nutzbarkeit im Gym-Alltag ist wichtiger als Demo-Eindruck.
- Klarheit und Wartbarkeit sind wichtiger als unnötige Architektur-Komplexität.
- Neue Produktbereiche sollen modular ergänzt werden.

### Produktgrenzen
- Single-gym first
- Multi-location ist aktuell **nicht** Teil des Kernplans
- Mobile ist der Primärkanal für Athleten
- Admin-Workflows sollen perspektivisch auch ein stärkeres dediziertes Backoffice erhalten
- Datenschutz/GDPR muss von Anfang an mitgedacht werden

---

## 4. Aktueller Projektstatus

### Snapshot
- Status: **In Progress**
- Repository-Fokus: Flutter-App plus containerisiertes REST-Backend
- Frontend: `app/`
- Backend: `backend/fastapi_app.py` (FastAPI)
- Aktive Datenbank: **PostgreSQL 16** (Docker Container)
- Backend-Runtime: **FastAPI + uvicorn**
- Datenbankzugriff: **psycopg** (raw PostgreSQL driver, kein ORM)

### Aktuelle Entwicklungsrichtung
- production-ready core platform für ein einzelnes Gym
- mobile Athlete-App plus Admin-Funktionen
- Community-/Engagement-Slice ist bereits teilweise ausgeliefert
- Backend-Modernisierung (PostgreSQL + FastAPI): **✅ ABGESCHLOSSEN**
- nächste Hauptinitiative: **Production Blockers** adressieren

### Aktueller Validierungsstand
- Backend-Tests: `pytest backend/tests/` läuft gegen PostgreSQL
- Flutter-Tests: `cd app && flutter test`
- Docker-Setup: `docker compose up` für vollständigen Stack
- Analytics-bezogene Flutter-Analyse hatte nur geringe Info-Level-Hinweise (`deprecated_member_use` / `withOpacity`)

### Wichtige aktuelle Risiken
1. Verifikations- und Reset-Tokens gehen lokal noch über Backend-Logs statt E-Mail.
2. Externe Push-Zustellung fehlt noch.
3. Memberships & Billing sind noch nicht implementiert.
4. Tiefere Community- und Progress-Module sind noch nicht abgeschlossen.
5. Profilfoto-/Avatar-Upload fehlt noch.
6. Kein Schema-Migrations-Tool (kein Alembic) - Schema wird direkt in `db.py` definiert.
7. Production-Deployment-Setup fehlt noch.

---

## 5. Bereits umgesetzte Kernfunktionen

### 5.1 Accounts, Auth & Identity
Bereits vorhanden:
- Signup
- Login
- Logout
- E-Mail-Verifikation
- Passwort-Reset
- Passwort ändern
- Account-Löschung
- kontrollierter Admin-Onboarding-Pfad
- rollenbasierte Navigation
- Notification Preferences
- Device Registration
- Rollenwechsel
- Profilbearbeitung für Name/Nickname

### 5.2 Gym Setup & Membership Context
Bereits vorhanden:
- Admin-only Gym Creation
- Gym Discovery / Directory
- Join Request Workflow
- Approve / Reject Join Requests
- Active Gym Switching
- Gym-Mitgliederliste für Admins
- Trainer-Promotion durch Admins

### 5.3 Scheduling, Booking & Attendance
Bereits vorhanden:
- Class Creation / Edit / Delete
- Recurring Class Creation
- Booking und Cancellation
- Waitlist
- Attendance Tracking
- Booking-bezogene In-App-Notifications

### 5.4 Programming, Whiteboard & Logging
Bereits vorhanden:
- Daily WOD Creation / Edit
- Programming Calendar
- Whiteboard Submission
- Workout Logging
- Workout History
- Basic PR Detection
- WOD-/PR-bezogene In-App-Notifications

### 5.5 Admin & Audit
Bereits vorhanden:
- Admin-only Member-/Role-Management
- Audit Logs für kritische Änderungen
- Admin Analytics v1 als aktiver Ausbaupfad

### 5.6 Community / Engagement (aktueller Zwischenstand)
Bereits zumindest teilweise ausgeliefert bzw. im Status dokumentiert:
- Announcements
- Likes
- Comments
- Booking Quick Access
- In-App Announcement Activity Notifications

Hinweis: Die Community-Ebene ist noch nicht vollständig als starke tägliche Habit-/Feedback-Schleife ausgeprägt.

---

## 6. Rollen- und Berechtigungsmodell

### Rollen
- **Athlete**
- **Trainer**
- **Admin**

### Grundregeln
- Standard-Signup erzeugt **Athlete**-Accounts.
- **Trainer** ist kein öffentlicher Signup-Pfad.
- **Admin-Onboarding** ist kontrolliert.
- Gym-Erstellung ist nur für **Admins** erlaubt.
- Ein Account kann mehrere Rollen tragen.
- Rollen sind gym-bezogen, wo sinnvoll.
- Athlete-Trainingshistorie bleibt an den User-Account gebunden.

### Globaler Zugriff
| Fähigkeit | Athlete | Trainer | Admin |
| --- | --- | --- | --- |
| Standard Signup | Ja | Nein | Nein |
| Kontrollierter Admin Signup | Nein | Nein | Ja |
| Login / Logout / Session / Profil | Ja | Ja | Ja |
| Passwort ändern / Account löschen | Ja | Ja | Ja |
| Gym erstellen | Nein | Nein | Ja |

### Aktives Gym erforderlich für
- Schedule Listing
- Booking / Cancellation / Waitlist
- Programming Calendar
- Whiteboard Viewing / Submission
- Logbook-Flows
- gym-bezogene Notifications

### Gym-spezifische Rechte
| Fähigkeit | Athlete | Trainer | Admin |
| --- | --- | --- | --- |
| Schedule im aktiven Gym sehen | Ja | Ja | Ja |
| Booking-Roster sehen | Nein | Ja | Ja |
| Future Classes erstellen/bearbeiten/löschen | Nein | Ja | Ja |
| Attendance erfassen | Nein | Ja | Ja |
| Programming Calendar sehen | Ja | Ja | Ja |
| Daily WODs erstellen/bearbeiten | Nein | Ja | Ja |
| Whiteboard Result submitten | Ja | Ja | Ja |
| Eigenes Workout loggen | Ja | Ja | Ja |
| Eigenes Logbook sehen | Ja | Ja | Ja |
| Join Request absenden | Ja | Ja | Ja |
| Eigene Join Requests sehen | Ja | Ja | Ja |
| Join Requests prüfen | Nein | Nein | Ja |
| Gym-Mitgliederrollen sehen | Nein | Nein | Ja |
| Athlete/Trainer-Rollen zuweisen | Nein | Nein | Ja |
| Audit Logs sehen | Nein | Nein | Ja |

### Rollenprinzip
- Trainer sind absichtlich auf delegierte Coaching-Workflows begrenzt: **Scheduling, Programming, Attendance**.
- Client-seitiges Verstecken ist nur UX; **Backend-Authorization ist die Sicherheitsgrenze**.
- Membership-/Payment-Enforcement muss nach Epic C zusätzlich in dieses Modell integriert werden.

---

## 7. Produktionskern: fachliche Soll-Funktionen

Die folgenden Bereiche definieren die produktionsreife Kernplattform.

### 7.1 Accounts, Identity & Access
Soll umfassen:
- Signup, Login, Verification, Logout
- Password Reset / Change Password
- Account Deletion inkl. Retention-/Anonymisierungsregeln
- Profile Management
- Notification Preferences
- Device Registration für Push
- rollenbewusste Navigation und Berechtigungen

### 7.2 Gym Setup & Membership Context
Soll umfassen:
- Admin-only Gym Creation
- Gym Discovery
- Join Request Flow
- Approval / Rejection
- Active Gym Context Switching

### 7.3 Scheduling, Booking & Attendance
Soll umfassen:
- Class Schedule Management
- Booking und Cancellation
- Capacity Enforcement
- Waitlist inkl. Promotion
- Attendance Lifecycle

### 7.4 Memberships & Payments
Soll umfassen:
- Membership Plans
- Billing Provider Integration
- Payment State Visibility
- Booking Restrictions auf Basis aktiver Entitlements

### 7.5 Workout Programming & Whiteboard
Soll umfassen:
- Daily WOD Authoring
- Programming Calendar
- Track Variants, wo sinnvoll
- Whiteboard- und Leaderboard-Workflows

### 7.6 Workout Logging & Performance
Soll umfassen:
- strukturierte Result Logs
- Workout History
- PR Detection
- Progress Visibility

### 7.7 Notifications & Communication
Soll umfassen:
- Push Notifications
- Transactional Email
- Event-based Alerts für operative und motivationale Events

### 7.8 Basic Admin Analytics
Soll umfassen:
- Attendance Overview
- Revenue Snapshot
- Membership State Visibility

---

## 8. Delivery-Status nach Modulen

### ✅ Fertig
- **Backend-Modernisierung**
  - PostgreSQL 16 als primäre Datenbank
  - FastAPI als Backend-Runtime
  - psycopg als PostgreSQL-Treiber
  - Service-Layer-Architektur (auth, membership, schedule, programming, announcements, workout)
  - Docker-basiertes Setup (db, backend, frontend)
  - Tests laufen gegen PostgreSQL
- **Core Features**
  - Accounts & Authentication
  - Profile / Notification Preferences / Device Registration
  - Gym Creation / Discovery / Join Requests / Active Gym Switching
  - Schedule Booking / Waitlists / Attendance Tracking
  - Programming Calendar / Digital Whiteboard
  - Workout Logging / Workout History / Basic PR Detection
  - In-App WOD- und PR-Notifications
  - Role Switching
  - Gym Member Management / Trainer Promotion
  - Audit Log Basis

### 🚧 In Arbeit
- **Admin Analytics v1**
  - Attendance / Utilization Overview
  - Review Windows 7 / 14 / 30 Tage
  - Full / Waitlist Pressure
  - Low-fill / High-no-show Drilldowns
  - Membership Health Basissicht

### ❌ Noch nicht gestartet oder nicht fertig
- Memberships & Payments
- produktive E-Mail-Zustellung
- echte Push-Infrastruktur
- production-grade Backend-Deployment (Hosted PostgreSQL, Secrets Management, etc.)
- tiefere Community-Loops
- erweiterte Performance-Analysen
- coach-grade Programming Workflows
- Revenue Snapshot
- dediziertes stärkeres Admin-Backoffice
- Schema-Migrations-Tool (Alembic oder Alternative)

---

## 9. Screen- und UX-Status

### Auth
Vorhanden:
- LoginScreen
- SignUpScreen
- AdminSignUpScreen
- VerifyEmailScreen
- ForgotPasswordScreen
- ResetPasswordScreen
- ChangePasswordScreen
- DeleteAccountScreen
- AuthCallbackScreen

Offene Punkte:
- produktive E-Mail-Zustellung für Verify/Reset
- Deep-Link-/Callback-Tests auf realen Geräten
- Review von legal/compliance copy für Account Deletion

### Shell & Home
Vorhanden:
- mobiler App-Shell mit Header, Footer-Navigation, Role Switcher und Notifications-Zugriff

Offene Punkte:
- News ist teils noch placeholderhaft
- Today soll reale nächste Buchung zeigen
- Today soll realen WOD zeigen
- stärkere rollenabhängige Home-Inhalte

### Profile & Account
Vorhanden:
- User Details
- Gym- und Rollen-Kontext
- Admin-/Gym-Aktionen
- Edit Profile für Display Name und Nickname
- Notification Settings

Offene Punkte:
- Avatar / Profile Photo Upload
- bessere Multi-Gym-/Multi-Role-Kontextdarstellung

### Gym
Vorhanden:
- Create Gym
- Gym Directory / Search
- Join Requests Review

Offene Punkte:
- bessere Empty States
- weitere Onboarding-Politur
- durchgehendes Role-/Gym-Scoping auf allen Pfaden weiter validieren

### Schedule / MyBox
Vorhanden:
- starker Kern für Schedule, Booking, Recurrence, Waitlist, Attendance

Offene Punkte:
- Membership-basierte Booking Restrictions
- dichte Kalender-Usability für viele Klassen
- QA für Timezone / DST
- Konfliktvermeidung für Doppelungen und Trainer-Overlaps

### Programming
Vorhanden:
- tägliche WOD-Erstellung und Bearbeitung
- Programming Calendar
- Whiteboard
- Workout Log Submission

Offene Punkte:
- Templates
- Score-Type-Validierung
- stärker strukturierte Felder
- Edit-History / Review-Flows
- UX für textlastige Workouts

### Logbook
Vorhanden:
- Workout History
- PR Chips / PR-Erkennung
- Logged Results

Offene Punkte:
- bessere Filter / Suche
- Benchmark-Historie
- Vergleich mit früheren Attempts
- Progress Charts
- stärkere Empty States für neue Athleten

### Notifications
Vorhanden:
- In-App Notifications für Booking, Waitlist, Schedule Updates, WOD, PR, Announcement Activity

Offene Punkte:
- externe Push-Zustellung
- Transactional Email
- reale Deep Links aus Push / Email

### Fehlende Kernoberflächen
- Membership Plan Management
- Member Subscription / Payment State
- Booking Eligibility / Entitlement UI
- Revenue Snapshot
- erweitertes Analytics Dashboard
- Community Feed / Discussion Layer
- Coach Programming Templates / Publishing Workflow
- Benchmark / Performance Analytics Views
- dediziertes operationales Backoffice jenseits der mobilen Admin-Screens

---

## 10. Technische Zielarchitektur

### Backend-Architektur ✅
**Aktueller Stack:**
- **Runtime**: FastAPI + uvicorn
- **Datenbank**: PostgreSQL 16
- **Treiber**: psycopg (raw SQL, kein ORM)
- **Deployment**: Docker Compose
- **Architektur**: Service-Layer-Pattern

**Schichten:**
1. **Route-Layer**: `fastapi_app.py` - HTTP-Endpunkte
2. **Core Infrastructure**: `db.py`, `settings.py`, `security.py`, `session_auth.py`, `validation.py`, `notifications_core.py`, `audit.py`
3. **Domain Services**: `auth_service.py`, `membership_service.py`, `schedule_service.py`, `announcement_service.py`, `workout_service.py`, `programming_service.py`

**Besonderheiten:**
- Raw SQL statt ORM (bewusste Entscheidung)
- Schema direkt in `db.py` (kein Alembic)
- ManagedConnection-Wrapper für psycopg

### Frontend-Richtung
- Flutter Mobile App für Athleten
- mobile Admin-Zugriffe bleiben wichtig
- später dedizierte Admin-Backoffice-Oberfläche

### Empfohlene Flutter-Architektur
- feature-first Struktur
- leichte Clean-Architecture-Grenzen
- `presentation / application / domain / data`
- State Management mit **Riverpod**
- Routing mit **go_router**

### Empfohlene App-Struktur
```text
lib/
  main.dart
  bootstrap.dart
  app.dart
  core/
  shared/
  features/
```

### Wichtige Core-Bausteine
- `core/config/` für Environments und Flags
- `core/routing/` für Router, Guards, Deep Links
- `core/di/` für Providers und Shared Services
- `core/errors/` für Error Mapping

### Networking
- bevorzugt **Dio**
- Interceptors für:
  - Auth Header
  - Request ID
  - Dev Logging
  - Token Refresh

### Offline- / Local-Data-Richtung
- empfohlen: lokales App-Storage mit **Drift (SQLite)**
- relevante lokale Tabellen:
  - `wods`
  - `classes`
  - `bookings`
  - `results`
  - perspektivisch Outbox für Offline-Aktionen

**Wichtig:** Die App kann lokal weiterhin SQLite/Drift für Offline-Caching nutzen. Das Backend verwendet PostgreSQL.

---

## 11. Backend-Modernisierung: SQLite -> PostgreSQL -> FastAPI ✅

### Status: **ABGESCHLOSSEN**

Die Backend-Modernisierung wurde erfolgreich umgesetzt.

### Umgesetzter Stack
- ✅ **FastAPI** als HTTP-Runtime
- ✅ **uvicorn** als ASGI-Server
- ✅ **PostgreSQL 16** (Docker Container)
- ✅ **psycopg** als PostgreSQL-Treiber (raw driver, kein ORM)
- ✅ **Docker Compose** Setup für Dev und Production
- ❌ **SQLAlchemy** - bewusst NICHT verwendet (stattdessen raw SQL)
- ❌ **Alembic** - bewusst NICHT verwendet (Schema direkt in `db.py`)

### Architektur-Entscheidungen

**Raw SQL statt ORM:**
Das Projekt verwendet bewusst raw SQL mit psycopg statt SQLAlchemy ORM. Die `db.py` enthält einen `ManagedConnection`-Wrapper, der die SQLite-ähnliche API auf psycopg abbildet.

**Schema-Management:**
Das Schema wird direkt in `db.py` als `SCHEMA_SQL` definiert und bei Startup angewendet. Es gibt kein separates Migrations-Tool wie Alembic.

**Service-Layer:**
Das Backend ist in eine klare Schichtenarchitektur aufgeteilt:
1. **Route-Layer**: `fastapi_app.py`
2. **Core Infrastructure**: `db.py`, `settings.py`, `security.py`, `session_auth.py`, `validation.py`, `notifications_core.py`, `audit.py`
3. **Domain Services**: `auth_service.py`, `membership_service.py`, `schedule_service.py`, `announcement_service.py`, `workout_service.py`, `programming_service.py`

### Was erreicht wurde

✅ **Alle Phasen 1-4 abgeschlossen:**
1. SQLite-Abhängigkeiten entfernt
2. Lokale PostgreSQL-Entwicklungsumgebung (Docker)
3. PostgreSQL-Migration mit psycopg
4. FastAPI-Migration mit Service-Layer

✅ **Tests:**
- Alle Tests laufen gegen PostgreSQL
- Test-Suite unter `backend/tests/`
- Coverage-Reporting eingerichtet

✅ **Docker-Setup:**
- Production: `docker compose up` (db, backend, frontend)
- Development: `docker compose --profile dev up` (db-dev, backend-dev, frontend-dev)

### Verbleibende technische Schulden

1. **Type Hints:** Einige Service-Module verwenden noch `sqlite3.Connection` Type Hints statt psycopg-Typen (technische Schuld, funktioniert aber)
2. **Kein Alembic:** Schema-Änderungen müssen manuell in `db.py` gepflegt werden
3. **Kein ORM:** Alle Datenbankzugriffe erfolgen via raw SQL

### Nächste Schritte

Die Backend-Modernisierung ist abgeschlossen. Der Fokus liegt jetzt auf:
1. **Production Deployment** (Hosted PostgreSQL, Secrets, SSL)
2. **Schema-Migrations-Strategie** evaluieren (Alembic hinzufügen oder manuell weiterführen)
3. **Production Blockers** adressieren (siehe Sektion 12)

---

## 12. Production Blockers

Diese Punkte müssen vor echtem Produktionsbetrieb für ein reales Gym erfüllt sein.

**Status-Update:** Die Backend-Modernisierung (PostgreSQL + FastAPI) ist abgeschlossen (siehe Sektion 11). Die verbleibenden Blocker sind primär Feature-basiert, nicht technologiebasiert.

### 12.1 Rollen- und Rechte-Härtung abschließen
Erforderlich:
- Audit aller Backend-Endpunkte auf Rollen- und Active-Gym-Autorisierung
- sicherstellen, dass Trainer nur delegierte Workflows steuern können
- sicherstellen, dass Athleten keine Admin-/Trainer-Daten per API bekommen
- Frontend-Navigation und Backend-Enforcement parallel absichern
- gezielte Regressionstests für sensible Pfade

Exit-Kriterien:
- kritische Rollenmatrix dokumentiert
- Tests decken Admin / Trainer / Athlete / No-Gym / Wrong-Gym für kritische Endpunkte ab
- keine sichtbaren unautorisierten Aktionen in relevanten Screens

### 12.2 Memberships & Payments umsetzen
Erforderlich:
- Plan-CRUD
- Member-Zuordnung zu Plänen
- Billing Provider Integration
- Lifecycle States:
  - active
  - trialing
  - past due
  - canceled
  - paused
  - expired
- Member View für Membership Status
- Admin View für Payment/Membership Status
- Booking Restrictions anhand aktiver Entitlements
- Payment-Issue-Notifications
- Webhook-Verifikation und Idempotenz

Exit-Kriterien:
- Gym kann reale Memberships definieren und verwalten
- Buchungsberechtigung hängt zuverlässig am Membership-Status
- Admins sehen aktive, überfällige, pausierte und gekündigte Zustände

### 12.3 Transactional Email einführen
Erforderlich:
- E-Mail-Provider-Integration
- Verify-Email-Zustellung
- Password-Reset-Zustellung
- operative Mail-Templates
- Retry-/Fehlerbehandlung
- production-sichere Deep Links

Exit-Kriterien:
- kein produktiver Auth-Flow hängt an Backend-Logs
- Verify/Reset funktionieren auf realen Geräten Ende-zu-Ende
- Versand ist beobachtbar und ausfallsicher

### 12.4 Reale Push Notifications einführen
Erforderlich:
- FCM/APNs-Integration
- echte Device Tokens
- Push für Booking, Waitlist, Schedule, WOD, PR, Payments
- Respektierung von Preferences
- Token Refresh, Permission Prompt, Logout-/Delete-Cleanup

Exit-Kriterien:
- Push funktioniert auf iOS und Android real
- deaktivierte Präferenzen unterdrücken Zustellung korrekt
- Device Cleanup funktioniert

### 12.5 Production-Grade Backend-Deployment
Erforderlich:
- Produktions-Stack und Hosting definieren
- HTTPS, CORS, Secrets, Config-Trennung, Logging, Monitoring, Backups
- Demo-User und Dev-Credentials isolieren oder entfernen
- Health Checks bereitstellen

Exit-Kriterien:
- Deployment reproduzierbar
- Secrets nicht im Source Control
- Backup-/Restore-Prozess dokumentiert und getestet
- Dev-Annahmen blockieren Produktion nicht

### 12.6 Admin Analytics abschließen
Bereits geliefert:
- `/admin/analytics`
- Active Members
- Active Trainers
- Pending Join Requests
- Attendance Snapshot
- Utilization
- No-shows
- Forward Load
- Daily Timeline
- Review Windows 7/14/30
- Pressure Lists
- Drilldowns für schlechte Attendance-Qualität
- Membership-Health-Basissicht

Verbleibend:
- tiefere Membership Activity
- Revenue Snapshot
- Custom Date Ranges
- Programming Engagement
- Workout Logging Engagement
- Drill-through bis auf Member-Ebene

Exit-Kriterium:
- Admin kann Attendance, Utilization, aktive Mitglieder, Druckstellen, Revenue und Engagement belastbar beurteilen

### 12.7 Community- und Engagement-Loops
Erforderlich:
- Workout Comments
- Reactions / Cheers / Fist-bumps
- Coach Comments auf Results
- Gym Announcements / Feed
- Recognition-Flows für PRs, Streaks, Consistency
- Moderation und rollenabhängige Sichtbarkeit
- Notification Events für relevante Interaktionen

Exit-Kriterium:
- Athleten und Coaches können Workouts und Results sinnvoll in-app diskutieren und feiern

### 12.8 Performance Tracking vertiefen
Erforderlich:
- Benchmark History
- movement-spezifische PR-Views
- Progress Charts
- Since-last-time-Vergleiche
- Filter nach Movement, Workout Type, Score Type, Zeitraum
- Retest-Prompts

Exit-Kriterium:
- Athleten sehen echten Fortschritt über Zeit statt nur Einzel-Logs

### 12.9 Coach-Grade Programming Workflows
Erforderlich:
- Templates
- Copy / Duplicate Day / Week / Block
- Movement Library
- Warm-up / Scaling / Stimulus / Coach Notes
- Draft / Scheduled / Published
- Coach/Admin Review Flows
- Support für Partner / Team / Relay / Interval / Phase

Exit-Kriterium:
- tägliche Programmierung ist strukturiert, schnell und coach-tauglich

### 12.10 Mobile Release Readiness
Erforderlich:
- App IDs, Signing, Icons, Splash, Store Metadata
- Produktions-API-URLs je Flavor
- Real Device QA
- Poor-Network-/Offline-Verhalten prüfen
- Crash Reporting / Analytics
- Accessibility Pass

Exit-Kriterium:
- reproduzierbare iOS-/Android-Builds und verifizierte Kernflows auf physischen Geräten

---

## 13. Hohe Prioritäten vor Launch

### Home Screen
- echte Announcements statt statischer News
- reale nächste Buchung anzeigen
- realen WOD anzeigen
- stärkere Engagement-Prompts
- rollenabhängige Home-Zuschnitte für Athlete / Trainer / Admin

### Schedule / MyBox
- bessere Navigation bei dichten Schedules
- klarere Selected-Day- und Date-Range-Navigation
- bessere UX für wiederkehrende Klasseninstanzen
- Membership Restriction Messaging
- stärkere Konfliktvermeidung

### Programming / Whiteboard
- Templates und strukturierte Abschnitte
- bessere Score-Validation
- Whiteboard-Filter / Sorting
- Edit History / Audit Visibility
- strukturierte Felder für Warm-up / Scaling / Stimulus / Intent
- Publishing States und Multi-Day-Workflows

### Logbook
- Filter / Suche
- PR-History-Details
- Benchmark-History
- Since-last-time-Vergleiche
- Progress Trends
- bessere Empty States

### Profile / Account
- Avatar Upload
- bessere Multi-Gym-/Multi-Role-Kontextdarstellung
- Review von Account-Deletion-Copy und Compliance-Texten

---

## 14. Wettbewerbs- und Differenzierungs-Roadmap

### Was ein SugarWOD-ähnlicher Markt sichtbar betont
- Workout Experience
- Community Engagement
- Coach Workflow / Programming
- Programming Marketplace / Ökosystem

### Wo BoxOS heute stark ist
- Auth und Rollenmodell
- Gym-Kontext
- Scheduling / Booking / Waitlists / Attendance
- Daily Programming
- Whiteboard
- Logging / Logbook
- In-App Notifications
- mobile UI-Basis

### Wichtigste Differenzierungs-Lücken
1. Memberships & Payments
2. Push / Email Delivery
3. Community Loops
4. deeper Performance Tracking
5. coach-grade Programming
6. Owner Reporting / Analytics
7. Coach Enablement jenseits reiner Programming
8. Marketplace / Partner Ecosystem (später)

### Strategische Reihenfolge
#### Phase A — Production Core Gaps
1. Memberships & Payments
2. Push & Email Delivery
3. Admin Analytics v1+
4. Community Interactions v1

#### Phase B — Athlete & Coach Differentiation
5. deeper Performance Tracking
6. Programming Templates & Publishing Workflow
7. Coach Workflow Improvements

#### Phase C — Strategische Expansion
8. Marketplace / Third-party Programming Ecosystem
9. Retention & Business Intelligence Expansion
10. Extended Challenges / Events / Community Systems

---

## 15. Nicht-funktionale Anforderungen

### Performance
- Kernflüsse sollen auf typischen mobilen Netzen responsiv bleiben
- Scheduling, Booking und Result Logging dürfen keine spürbaren Hänger zeigen
- die App soll mit temporärer Backend-Latenz sinnvoll umgehen

### Reliability
- produktive Kernabläufe müssen alltagstauglich stabil sein
- Fehler müssen verständlich und recoverable sein
- kritische Aktionen brauchen Auditierbarkeit

### Security
- OAuth2-/JWT-kompatibles Auth-Modell
- sichere Token-Behandlung
- verschlüsselte Datenübertragung
- rollen- und gym-bewusste Access Control
- Rate Limiting auf sensible Flows

### Compliance
- GDPR-aware Datenhaltung
- klare Prozesse für Delete / Export / Retention
- PCI-bewusste Payment-Integration, sobald Billing aktiv ist

### Scalability
- Architektur darf spätere Erweiterung nicht blockieren
- der Deployment-Target bleibt zunächst ein einzelnes Gym je Deployment-Kontext

---

## 16. Testing- und QA-Strategie

### Automatisiert
- Backend-Test-Suite vollständig grün
- Flutter Widget-/Unit-Tests stabilisieren
- Rollen-/Rechte-Regressionstests
- Migrations- und Datenbanktests für PostgreSQL

### End-to-End Smoke Tests
Mindestens für:
1. Signup / Verification / Login
2. Gym Creation
3. Join Request Approval
4. Class Creation / Booking / Waitlist / Attendance
5. WOD Creation / Logging / Whiteboard
6. Notifications
7. Membership / Payment Flows nach Implementierung

### Manuell
- iOS- und Android-QA
- Narrow Phone / Large Phone / Tablet-/Desktop-Debug-Widths
- Deep Links
- Timezone / DST
- Poor Network / Offline
- Accessibility

---

## 17. Empfohlene Delivery-Reihenfolge

### ✅ Abgeschlossen
1. ✅ PostgreSQL lokal aufsetzen
2. ✅ `DATABASE_URL` einführen
3. ✅ SQLite-Abhängigkeiten entfernen
4. ✅ Postgres-Schema implementieren
5. ✅ Tests gegen Postgres migrieren
6. ✅ FastAPI-Migration abschließen
7. ✅ Service-Layer-Architektur implementieren
8. ✅ Docker-Setup für Dev und Production

### 🎯 Hohe Priorität (Production Blockers)
9. **Rollen-/Rechte-Härtung finalisieren**
   - Backend-Autorisierung für alle Endpoints auditieren
   - Regressionstests für Rechte-Matrix
10. **Memberships & Payments implementieren**
    - Plan-CRUD
    - Billing-Provider-Integration
    - Booking Restrictions
11. **Produktive E-Mail-Zustellung**
    - E-Mail-Provider-Integration
    - Verify/Reset-Flow ohne Logs
12. **Reale Push Notifications**
    - FCM/APNs-Integration
    - Device Token Management
13. **Production Deployment vorbereiten**
    - Hosted PostgreSQL auswählen
    - Secrets Management
    - SSL/HTTPS
    - Monitoring & Logging

### 📊 Mittlere Priorität (Produktdifferenzierung)
14. Admin Analytics vervollständigen (Revenue Snapshot)
15. Community Interactions v1 ausbauen
16. Performance Tracking vertiefen
17. Coach Programming Workflows ausbauen
18. Avatar/Profile Photo Upload

### 🔮 Später (Expansion)
19. Dediziertes Admin-Backoffice stärken
20. Marketplace / Partner-Ecosystem evaluieren
21. Erweiterte Business Intelligence / Retention-Module
22. Multi-Location Support (nach starker Single-Gym-Basis)

### 🔧 Technische Verbesserungen (Optional)
- Alembic für Schema-Migrationen einführen
- Type Hints von sqlite3 auf psycopg migrieren
- SQLAlchemy evaluieren (falls ORM gewünscht)

---

## 18. Definition von Erfolg

BoxOS erreicht das aktuelle Zielbild, wenn ein einzelnes Gym die Plattform **ohne Entwicklerintervention** produktiv einsetzen kann und dabei:
- Admins Gyms, Mitglieder und Rollen sicher verwalten können
- Klassen geplant, gebucht und attendance-seitig sauber betrieben werden können
- WODs veröffentlicht, geloggt und am Whiteboard genutzt werden können
- Athleten sinnvolle Benachrichtigungen erhalten
- Memberships und Zahlungen Buchungslogik steuern
- Admins operative Kennzahlen, Revenue und Druckstellen sehen
- Coaches und Athleten über die App sinnvolle Community- und Feedback-Loops nutzen
- Backend, Mobile App und Betriebssetup release- und production-tauglich sind

---

## 19. Was neben ROADMAP.md bewusst übrig bleiben kann

Wenn die Dokumentation reduziert werden soll, sollten neben dieser Datei idealerweise nur bleiben:
- `README.md` als Einstieg / Setup / Dev-Usage
- `ROADMAP.md` als Master-Dokument

Alles andere ist inhaltlich durch diese Roadmap abgedeckt oder kann daraus später neu abgeleitet werden.
