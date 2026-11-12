# Admin UI reference (gym owner / admin web app)

A view-by-view spec of a CrossFit gym admin app, written as input for a coding
agent. Source: the public 5-minute demo video "Boxbase Demo Admin App"
(youtube.com/watch?v=BmstJOUiQCs).

Every section is tagged:

- **[video]**: seen in the demo; layout, fields and example values are as shown.
- **[inferred]**: never opened in the video (only the menu entry or tab label
  is visible). Written in the same style so the app feels consistent; treat it
  as a proposal, not a copy.

Example numbers and names are demo data, not requirements. **Layout and
structure follow the video; colours are BoxOS's current palette** (§0).

---

## 0. Global patterns [video]

Apply these everywhere; the per-view sections assume them.

### Shell
- **Left sidebar** (fixed width):
  - Top: gym switcher (gym logo/initials, gym name, role "Box Owner", chevron).
  - Nav items, each icon + label, active item highlighted:
    Dashboard, Classes, Programs, Members, Reports, Messages, Memberships,
    Payments ▸, Products ▸, Settings ▸ (▸ = expandable submenu).
  - Bottom: Notifications, then the user card (avatar with initials, name,
    email, chevron for the account menu).
- **Top bar** per page: collapse-sidebar icon, page title; on the right a global
  search field with a `⌘K` hint and a square accent **+** quick-create button.

### Visual language
- Content area with cards: thin borders, small radius.
- One accent colour (primary buttons, active toggles, focused inputs, chart
  bars, links such as "Manage programs", the active tab, "today" markers).
- Status pills: small rounded labels — success (Active, Paid, Open, Sent),
  warning (Unread, Pending, Unpaid), danger (Failed), neutral (Voided, Ended).
- Trend badges on KPIs: `↑ 77%` success / `↓ 100%` danger.
- Avatars: circle with initials when no photo.
- Dates formatted short: `Nov 25, 25`, `Dec 01, 25`.

### Colours (BoxOS palette)
Use the existing tokens in `app/lib/core/presentation/app_chrome.dart`; never
inline hex values. Wherever this document says "accent", "success", etc.,
use this table.

| Role in the reference | BoxOS token |
|---|---|
| Page background | `appPageBackground` (near-black) |
| Sidebar background | `appPageBackgroundSoft` |
| Cards, panels, table background | `appSurface` |
| Nested rows, inputs, hovered rows, selected nav item background | `appSurfaceAlt` |
| Popovers, dropdown menus, side panels | `appSurfaceElevated` |
| Borders / dividers | `appBorder`; emphasised borders `appBorderStrong` |
| Primary text / secondary text / labels, column headers, hints | `appText` / `appMutedText` / `appSubtleText` |
| **Accent** (reference's orange) | `appPrimary` (cyan); text on it `appInverseText` |
| Accent tint (selected chip, hover, active nav item, soft badge) | `appPrimarySoft` |
| Accent border (focused input, selected filter chip) | `appPrimaryHairline` |
| Success (Active, Paid, Sent, Read, ↑ trend) | `appSuccess` |
| Warning (Pending, Unread, Unpaid, Waiting list, low stock) | `appWarning` |
| Danger (Failed, Cancelled, ↓ trend, current-time line, delete) | `appDanger`; tint `appDangerSoft` |
| Info / neutral highlight | `appInfo` |
| Neutral pill (Voided, Ended, Archived) | `appSubtleText` on `appSurfaceAlt` |
| Charts | bars/area `appPrimary`, second stack part `appPrimaryHairline`, gridlines `appBorder`, axis labels `appSubtleText` |
| Class-type colours in calendar and programs | `classTypeColor()` in `features/calendar/presentation/widgets/class_type_badge.dart` |
| Status pills | `AppPill` intents (success / warning / danger / neutral / primary) |
| Dimmed page behind a side panel | black at ~60 % opacity |

### Interaction patterns
- **Detail and create flows open as a right-side panel** over the current page
  (page behind is dimmed, stays visible). Panel header: title, optional status
  pill, `⋯` menu, `×` close. Panels can have tabs (underlined, active in the
  accent colour, count badge after the label, e.g. `Program 2`).
- **Multi-step forms** show steps in the panel header: `① Schedule  ② Details`.
- **Tables**: column headers in small muted text, sortable columns show an
  arrow, row click opens the detail. Toolbar above the table: filter chips
  (`⊕ Status`, `⊕ Payment method`, funnel icon), date-range picker, export icon.
  Footer: "Showing x of y" + pagination.
- **Segmented control** for sub-lists of a page (e.g. `Members | Pending invites 1`).
- **Toasts** top-centre, success check: "Schedule successfully created."
- **Popovers** for compact settings on a row (limit, deadline), with a
  "copy to all" icon next to each value.
- Searchable dropdowns: search field on top, options with a secondary muted
  line (e.g. plan price).

---

## 1. Dashboard [video]

**Metrics** (row of 5 small KPI cards, each with an expand icon top-right):
| Card | Example |
|---|---|
| Members at risk | 19 |
| Churned members | 0 `↑0%` |
| Expiring memberships | 11 |
| Trials in {current month} | 0 `↓0%` |
| Birthdays | 1 (cake icon) |

**Charts** (row of 4 cards; headline number + trend badge + small chart of the
last 6 months, Jun–Nov):
| Card | Chart |
|---|---|
| New members | bar |
| New memberships | bar |
| Class utilisation (%) | area |
| Class registrations | stacked bar, filter icon top-right |

**Activity** section, header with `Today` button and `‹ ›` day navigation:
- **Upcoming classes {count}** card (left, wide), filter dropdown "All classes".
  Each row: `06:00 – 07:00`, class name (bold), colour dot + "CrossFit in Main
  room", booked/capacity pill (`0 of ∞`, `3 of 3`), "≡ 2 programs", status on the
  right ("Ended" / "Starts later today ⓘ"). Scrollable.
- **Programs** card (right): programs scheduled today, grouped by track
  (CrossFit → 1 Strength, 2 Beep Test). Link "Manage programs" (accent) → Programs.

---

## 2. Classes – class calendar [video]

- Header: date label "Nov. 24, 25", dropdown "Class schedules" (filter by
  schedule), filter icon, `‹` calendar-picker `›`, accent **+** (create recurring
  classes).
- **Week grid** Mon–Sun, hour rows (~05:00–20:00), today's date in an accent
  circle, danger-coloured line = current time.
- **Class block**: time, name, `booked/limit` (`0/12`, `3/3`, `0/∞`). Colour by
  class type (`classTypeColor()`). Past classes faded. Parallel
  classes share the column side by side. Block may show a "≡" icon when a
  program is attached.

### 2.1 Class detail panel
Header: class name + status pill (`Open`), `⋯`, `×`.
Meta row (small caps labels): DATE `Tue Nov 25 · 14:00 – 15:00`, CLASS TYPE
(colour dot + name), LIMIT `2 participants`, AUTO-CANCEL `OFF`.
Tabs: **Overview | Program {n} | Details**.

- **Overview [video]**
  - Coach: dropdown "Select a coach".
  - Registrations {n}: list of avatar + name (+ "You" tag, check-in icon).
    Below: "+ Add member" (accent) or "Unregister yourself".
  - Right column: Waiting list {n}, Cancellations {n} (each expands to a list).
- **Program [video]**: the workout blocks programmed for this class's track on
  that day, read-only, in order. Structured blocks show numbered set rows
  `1. [3] Reps @ [60] %`; collapsible "Member notes ▾". Free-text blocks show
  their text (e.g. "10 rounds / 10 Burpees over rower / 500m row").
- **Details [inferred]**: editable settings of this single occurrence,
  overriding the recurring schedule.
  - Name, Class type (dropdown with colour dot), Room/location (dropdown).
  - Start / end time.
  - Participation limit (toggle + number), Waiting list (toggle + max size).
  - Registration deadline and Cancellation deadline (`hr(s)` / `min(s)`, showing
    "Time of deadline: 13:45").
  - Auto-cancel (toggle + minimum participants + "check X min before start").
  - Notice text: "Changes apply to this class only. [Edit schedule]" link.
  - Footer: secondary "Cancel class" (danger outline, confirm dialog: notify
    registered members via email / in-app) and primary "Save".

### 2.2 Create recurring classes panel [video]
Steps: **① Schedule → ② Details**.

Step 1 – Schedule:
- Name* (text).
- Limit period ⓘ: toggle, off = chip "Unlimited"; on = date range.
- Recurs: dropdown "Every week" (also every 2 weeks, …).
- One row per weekday MON…SUN, each with a toggle and a copy icon. When on,
  the day lists **time slots**:
  - `[07:00] – [08:00]` time inputs, trash icon on hover, `+` adds a slot.
  - Coach avatar button (assign coach per slot).
  - Participants chip `0/12` → popover: "Participation limit" toggle + number
    (copy icon), "Auto cancellation" toggle `OFF` (copy icon).
  - Two deadline chips `🕒 15m` → popover "Cancellation deadline" / "Registration
    deadline": `[0] hr(s) [15] min(s)` (copy icon), "Time of deadline: 06:45".
- Copy icon on a day copies all its slots to the selected other days; copied
  days stay editable individually.

Step 2 – Details [inferred]:
- Class type (dropdown with colour dots; types are managed in Settings).
- Room / location.
- Description (rich text, shown in the member app).
- Booking rules: who may book (memberships / class types that grant access),
  booking window ("bookable from 7 days before"), waiting list toggle.
- Default program track (which Programs track feeds this class's Program tab).
- Footer: "Back", primary "Create schedule" → toast "Schedule successfully
  created." and the classes appear in the calendar.

---

## 3. Programs – workout programming [video]

- Header: track selector (colour dot + "CrossFit" ▾), date range "Nov 24 – 30,
  25", `‹ Today ›`, view dropdown "Week".
- **Board**: one column per day (`MON 24` … `SUN 30`, today in accent), `+` per
  column. Columns hold **block cards** in order:
  - Title (bold), then either free text or a set table (`REPS | %`, rows
    `3 @ 60`), "+2 more sets…".
  - Footer: drag handle, track colour pill, attachment/notes count, `⋯` menu
    (Edit, Duplicate, Copy to day…, Delete).
  - Cards drag to reorder within a day and between days.

### 3.1 Create / edit block panel [video]
- Block name.
- Segmented: **Workout** (free text) | **Exercise** (structured).
- Exercise: "Exercise name" picks from the movement library (search).
- Sets: header with unit toggle **RPE | %**. Numbered rows
  `[n] [5] reps @ [80] %`; an empty row with `→` is always appended.
- Settings: chips "Coach notes" (coaches only) and "Member notes" (shown in the
  member app) → each opens a text field.
- Link at the bottom: "✨ Try our Magic Set Builder (Ctrl + A)" — generates sets
  from a short text like `5x5 @ 80%`.
- Footer: Cancel, Save.

---

## 4. Members [video]

### 4.1 Members list
- Segmented: **Members | Pending invites {n}**; right: "Search member" field.
- Table: Name (avatar initials + full name, sortable ↑), Email, Date joined.
  Row click → Member details.
- Pending invites [inferred]: same table with Email, Invited on, Invited by,
  status pill (Pending / Expired), row actions Resend · Revoke.

### 4.2 Member details page
Header card: avatar, name, role pill (`Member`), email (copy icon),
"Joined 7 months ago", birthday, gender.
Tabs: **Overview | Memberships | Payments | Classes**.

- **Overview [video]**
  - Memberships card: table Plan · Status · Start date · End date, "+ Create".
  - Payments card: table Subject · Amount · Status · Billing date, "View all",
    "+ Create".
  - KPI cards: **Front end revenue**, **Lifetime value**.
  - Class registrations chart (monthly bars, filter icon).
  - Right column **Profile**: Phone, Address, Injuries ("Not provided"),
    Emergency contact. **Payment methods**: Stripe `✓ Added`, SEPA mandate
    `✕ No mandate`.
- **Memberships [video]**: full table Plan · Type (Membership / Punchcard /
  Drop-in) · Status · Start · End · Next billing. "+ Create" → §6. Row click →
  Membership detail panel (§7).
- **Payments [inferred]**: the Sales-report table (§8) pre-filtered to this
  member: Subject · Amount · Status · Payment method · Billing date. Toolbar:
  Status filter, date range, "+ Create" (one-off charge: subject, amount,
  method, date). Row `⋯`: Mark as paid, Retry charge, Refund, Void, Download
  invoice.
- **Classes [inferred]**: two segments **Upcoming | History**. Table: Date ·
  Time · Class (colour dot) · Coach · Status pill (Registered / Waiting list /
  Attended / No-show / Cancelled / Late cancel). Upcoming rows have
  "Unregister". Above: small KPIs "Attended (30 days)", "No-shows", "Avg per
  week".

---

## 5. Messages [video]

- Left column: search "Search by subject or recipient", list of sent messages
  (`Recipients {n}` small grey, date right, subject bold), footer
  "10 of 10 messages" + `‹ ›`.
- Right reading pane: toolbar `× ‹ ›` + expand, subject, `To: Recipients {n}`
  chip, timestamp, body.
- Clicking the recipients chip opens a **Recipients dialog**: rows of avatar,
  name, email, **In-app** pill (Unread warning / Read success), **Mail** pill (Sent, success).
- Accent **+** → **Compose** (full-width card):
  - From: sender address chip.
  - To: picker with search and FILTER segments with live counts — Active
    Members, Inactive Members, All Members, All Coaches, All Admins, All
    Owners, All Team Members — or individual people.
  - Subject.
  - Channel: ☑ Email ☑ In-app notification.
  - Rich-text toolbar: H, B, I, bullet list, numbered list, link, undo/redo.
  - Footer: "Cancel Esc", primary "Send message".

---

## 6. Create membership panel [video]

Two columns: form (left), **Payment timeline** preview (right).

Form:
- Member (prefilled, avatar + email).
- Membership plan: searchable dropdown, each option name + price
  (`Drop-In €20.00`, `Hyrox 2/week €120.00`, `Free punchcard €0.00`); link
  "👁 View plan configuration".
- Payment method: Automated (Stripe) / SEPA / Credit card (on site) / Cash.
- Billing day ⓘ: 1st of the month / 15th of the month / Start date.
- Prorate first payment? ⓘ toggle → "↳ Proration payment method" dropdown.
- Start date (date picker).
- Options chips: ✓ Auto-renew, ⊕ Discount.
- Footer: Cancel, primary "Create membership".

Payment timeline (vertical stepper, live):
- Start · Today · "Membership starts"
- €24.00 · "Prorated payment · 6 days"
- New cycle · Dec 01, 25 · "New full cycle starts · 1 months"
- €120.00 · "First full payment"
- Summary: Plan price €120.00/mo · Discount N/A · **Total prorated €24.00**.
- Empty state before selection: magnifier icon, "No selection — Select a member
  and plan to continue."

## 7. Membership detail panel

Header: plan name + `Active` pill, member name, email (copy), `⋯`
(Pause, Cancel membership, Change plan, Delete), `×`.
Tabs: **Overview | Periods {n}**.

- **Overview [video]**: grid Auto renews (Yes) · Billed on (1st of the month) ·
  Payment method (Automated (Stripe) `⋯`) · Check-ins (2 per week) · Class types
  (chips). **Timeline**: Membership started (Prorated period) · Cancellation
  deadline passed · Membership renewed · ◌ New cycle will start (Duration: +1
  month), each with a date. **Notes**: "✎ Update note". Bottom: Monthly payment
  · Plan price.
- **Periods [inferred]**: one row per billing cycle: `#` · Period
  (`Nov 25 – Nov 30, 25`) · Type (Prorated / Full) · Amount · Payment status
  pill · Check-ins used (`3 / 8`). Current period highlighted; future period
  shown faded as "Upcoming".

---

## 8. Reports – Sales report [video]

- Summary cards:
  - **Total sales volume** (big number, e.g. €17,960.65).
  - **Payment category**: Memberships / Custom items / Products, each a bar + %.
  - **Payment status**: Paid / Unpaid / Pending / Failed / Refunded / Voided,
    each a coloured bar + %.
- Toolbar: `⊕ Status`, `⊕ Payment method`, funnel (member filter), date-range
  picker with presets (This month, Current quarter, …) showing
  "1 Oct, 25 – 31 Dec, 25", export icon (**CSV**).
- Table: Subject (plan + period, truncated) · Amount · Member · Status pill ·
  Payment method · Billing date (sortable).
- [inferred] Reports may have a sub-switcher at the top for further reports in
  the same layout (cards + filters + table): **Sales | Attendance |
  Memberships**. Attendance: cards Check-ins, Avg utilisation, No-show rate;
  table per class occurrence. Memberships: cards Active, New, Cancelled,
  Churn rate; table per membership change.

---

## 9. Memberships – plan catalogue [inferred]

Sidebar item "Memberships": the plans members can buy (what §6 picks from).

- Segmented: **Plans | Archived**; search; accent **+** "Create plan".
- Table: Name · Type pill (Membership / Punchcard / Drop-in / Trial) · Price
  (`€120.00 / month`) · Access (class-type chips) · Active members (count) ·
  Visibility (Public / Hidden).
- **Plan panel** (create / edit, tabs **General | Pricing | Access**):
  - General: name, description (shown in member app), type, visible in member
    app toggle.
  - Pricing: price, billing interval (week / month / year / one-off), contract
    term + notice period, setup fee, trial length, allowed payment methods
    (checkboxes).
  - Access: class types (multi-select chips), check-in limit (`[2] per week`
    or unlimited), punchcard credits + validity.
  - Footer: Archive (secondary), Save.

## 10. Payments ▸ [inferred]

Submenu: **Transactions**, **Payouts**, **Dunning**.

- **Transactions**: same layout as the Sales report table without summary
  cards, plus row `⋯` actions (Mark as paid, Retry, Refund, Void, Download
  invoice). Row click → panel with amount, status timeline (Created →
  Finalized → Paid / Failed), payment method, Stripe reference (copy), linked
  membership.
- **Payouts**: cards Available balance, In transit, Next payout date; table
  Date · Amount · Status pill (Paid / In transit / Failed) · Bank account
  (`•••• 1234`).
- **Dunning**: failed / overdue payments. KPI cards Overdue amount, Members
  affected. Table Member · Amount · Days overdue · Attempts · Last attempt ·
  action "Retry" and "Send reminder" (opens Compose prefilled).

## 11. Products ▸ [inferred]

Submenu: **Products**, **Orders**.

- **Products**: card grid or table: image thumbnail, name, category chip
  (Drinks, Apparel, Supplements), price, stock (warning colour when low), status
  (Active / Hidden). **+** → panel: name, image upload, category, price, tax
  rate, stock tracking toggle + quantity, visible in member app toggle.
- **Orders**: table Order # · Date · Member · Items (count) · Total · Payment
  method · Status pill (Paid / Unpaid / Refunded). "+ New sale" opens a quick
  point-of-sale panel: pick member, add products (qty steppers), payment
  method, total, "Charge".

## 12. Settings ▸ [inferred]

Submenu, each a page in the content column with grouped cards and a sticky
"Save changes" bar that appears when something changed:

- **Gym profile**: logo upload, gym name, address, contact email/phone, time
  zone, currency, opening hours per weekday.
- **Locations & rooms**: table Room · Capacity · Location; **+** panel.
- **Class types**: table colour dot · Name · Default duration · Default limit;
  **+** panel with colour picker. (Feeds calendar colours and plan access.)
- **Team**: table avatar · Name · Role pill (Owner / Admin / Coach) · Email ·
  Status; "Invite member" panel (email, role).
- **Booking rules**: defaults for registration deadline, cancellation deadline,
  late-cancel policy, no-show policy, waiting list auto-promote toggle.
- **Payments**: Stripe Connect status card (`✓ Connected` / "Connect Stripe"
  button), enabled methods (Stripe card, SEPA, on-site card, cash), invoice
  prefix, tax rate.
- **Notifications**: matrix of events (class cancelled, payment failed,
  membership expiring, new member, birthday) × channels (Email / In-app), per
  audience (members / staff).

## 13. Notifications [inferred]

Sidebar bottom item → right-side panel (not a page).
- Header "Notifications", segmented **All | Unread {n}**, "Mark all as read".
- Items grouped by Today / Earlier: icon (by type), one-line text ("Cecil
  Rempel's payment of €120.00 failed"), relative time, unread dot. Click
  navigates to the related member / class / payment.

---

## Notes when implementing this in BoxOS

These product decisions in `CLAUDE.md` take precedence over the reference:

- Schedule: one week view for every role; class types are **WOD, Open Gym,
  Skill, PT** (not CrossFit/Hyrox); **one WOD per gym per day**.
- Join requests live in the Members tab as a **Requests** segment (the
  reference's "Pending invites"), with an open-count badge on the nav item.
- **Layout deliberately departs from current `CLAUDE.md` conventions**: the
  left sidebar replaces the navigation rail / bottom bar, right-side panels
  replace `AppFormDialog` for detail and create flows, and pages use the full
  content width instead of `contentMaxWidth` (`CLAUDE.md` points here; views
  not yet migrated keep the old pattern). Yes/no confirmations stay
  `showAppConfirmDialog`.
- Keep BoxOS's current colours (§0), not the reference's orange.
- Whiteboard stays removed; workout logging (logbook, PRs) was removed too.
- Roles are Owner / Trainer / Athlete (`docs/DESIGN.md`): the admin views here
  are owner-only; trainers get Classes and Programs.
