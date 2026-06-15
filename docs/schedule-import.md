# Schedule CSV Import

Owners and trainers can bulk-create classes in the **Schedule** view from a CSV
file. This is the same format you get when you export a spreadsheet from Excel,
Numbers, or Google Sheets ("File → Download → Comma-separated values").

A ready-to-use example lives next to this doc: [`sample-classes.csv`](./sample-classes.csv).

## How to import

1. Open **Schedule** (the calendar) as an owner or trainer.
2. Click the **import icon** (⬆️) in the calendar header, next to *Today* and the
   month arrows.
3. Provide your rows in one of two ways:
   - **Upload CSV file** — pick a `.csv` file (web). Its contents are loaded into
     the box and checked against the schema below, or
   - **Paste** — paste the contents of a `.csv` file, or a range copied straight
     from Google Sheets / Excel (tab-separated is also accepted).

   Either way, each row is parsed and previewed live with a green check (ready)
   or a red error (with the reason and line number). A file whose header is
   missing required columns is rejected before anything is imported.
4. The import is **atomic** — if any row has an error, nothing is created. Fix the
   text and the preview updates instantly.
5. When every row is valid, click **Import N classes**. The calendar refreshes
   automatically.

> Tip: use **Insert example** to drop a working template into the box, or **Copy
> template** to put it on your clipboard. The first pasted row must be the header.

## Columns

The header row is required and column order does not matter (matching is by name,
case-insensitive). Empty cells are allowed for optional columns.

| Column | Required | Description |
|---|---|---|
| `date` | ✅ | Class date, `YYYY-MM-DD` (e.g. `2026-06-22`). |
| `start_time` | ✅ | Start time, 24-hour `HH:MM` (e.g. `18:00`). Interpreted in your device's local time zone. |
| `title` | ✅ | Class title, max 80 characters. |
| `duration_minutes` | ✅ | Whole number of minutes (e.g. `60`). |
| `capacity` | ✅ | Whole number, 1–200. |
| `class_type` | optional | One of `WOD`, `Open Gym`, `Specialty`, `PT`. Defaults to `WOD`. |
| `trainer_email` | optional | Email of an **active trainer** in your gym. Leave blank for no assigned trainer. |
| `wod_description` | optional | Free text, max 2000 characters. Wrap values containing commas in double quotes. Use this for classes with a single block of programming; for multi-block classes prefer the section columns below. |
| `repeat` | optional | `none` (default), `daily`, `weekly`, or `monthly` (every 4 weeks). |
| `occurrences` | optional | Number of repetitions when `repeat` is not `none`. Caps: daily ≤ 365, weekly ≤ 53, monthly ≤ 14. |

### Section columns

Classes can be broken down into up to **10 sections** — for example *Warm Up*,
*Strength*, *AMRAP*, *Cool Down*. Add one block of three columns per section,
numbered from 1 upwards:

| Column | Required | Description |
|---|---|---|
| `section_N_title` | ✅ for the section | Section name, max 80 characters. Leave blank to skip the section. |
| `section_N_description` | optional | Section programming / notes, max 1000 characters. Wrap values containing commas in double quotes. |
| `section_N_score` | optional | Expected score format for the section. One of `time`, `rounds_reps`, or `weight` (weight in kg). Leave blank when the section has no score. |

A section is created whenever `section_N_title` is non-empty. Empty section
columns are ignored, so a row with just `section_1_title` defines a one-section
class, and gaps (e.g. `section_1_title` set, `section_2_title` empty,
`section_3_title` set) are allowed — sections are persisted in numeric order.

## Rules & validation

- **Future only** — `date`/`start_time` must be in the future. Past entries are
  rejected (consistent with the "no classes on past days" rule in the UI). For a
  recurring row, **every** generated occurrence must be in the future.
- **Trainer resolution** — `trainer_email` is matched against active trainers of
  your gym. An unknown email fails that row (and, since the import is atomic, the
  whole import).
- **Recurrence** — a row with `repeat=weekly, occurrences=6` creates 6 weekly
  classes from `date`. With `repeat=none` (or blank), `occurrences` is ignored and
  a single class is created.
- **Sections** — `section_N_score` must be one of `time`, `rounds_reps`,
  `weight`, or empty. All recurring occurrences inherit the same set of
  sections.
- **Quoting** — standard CSV quoting applies; put double quotes around any field
  that contains a comma, e.g. `"21-15-9 Thrusters, Pull-ups"`.
- **Limit** — up to 500 rows per import.

## Example

```csv
date,start_time,title,class_type,duration_minutes,capacity,trainer_email,wod_description,repeat,occurrences,section_1_title,section_1_description,section_1_score,section_2_title,section_2_description,section_2_score
2026-06-22,06:00,Morning WOD,WOD,60,14,,,weekly,6,Warm Up,"500m row + dynamic stretching",,Strength,"Back Squat 5x5 @ 75%",time
2026-06-22,18:00,Evening WOD,WOD,60,16,,,,,Metcon,"Fran: 21-15-9 Thrusters, Pull-ups",time,,,
2026-06-23,12:00,Lunch Open Gym,Open Gym,90,20,,Open training — coach on the floor,,,,,,,,
```

The first row above creates **6** weekly *Morning WOD* classes, each with a
*Warm Up* (no score) and a *Strength* section scored by time. The second row
creates a single *Evening WOD* with one *Metcon* section. The third row uses
`wod_description` only — no sections.

## Google Sheets

Build the sheet with the columns above (including the header row), then either:

- **select the range, copy (Ctrl/Cmd+C) and paste** it straight into the import
  box — pasted spreadsheet cells are tab-separated, which the importer detects
  automatically; or
- **File → Download → Comma-separated values (.csv)**, open the file, and paste
  its contents.

(Importing directly from a Google Sheets *link* is not yet supported — see the
roadmap.)

## API

The dialog calls `POST /schedule/classes/import` (owner/trainer session). Body:

```json
{
  "rows": [
    {
      "start_time": "2026-06-22T04:00:00.000Z",
      "title": "Morning WOD",
      "class_type": "WOD",
      "duration_minutes": 60,
      "capacity": 14,
      "trainer_email": null,
      "wod_description": "",
      "sections": [
        { "title": "Warm Up", "description": "500m row + dynamic stretching" },
        { "title": "Strength", "description": "Back Squat 5x5 @ 75%", "score_type": "time" }
      ],
      "recurrence_frequency": "weekly",
      "occurrence_count": 6
    }
  ]
}
```

- The client converts each CSV `date` + `start_time` into a UTC ISO-8601
  `start_time` before sending.
- `sections` is optional; when omitted the class has no sections.
- Each section accepts `title` (required), `description` (optional, ≤ 1000
  chars), and `score_type` (optional, `"time"`, `"rounds_reps"`, or
  `"weight"`).
- Success → `200 { "created_count": N, "row_count": M }`.
- Any invalid row → `422 { "created_count": 0, "errors": [{ "row": 2, "message": "…" }] }`
  and nothing is created.

The same `sections` array is accepted by `POST /schedule/classes` (single create)
and `PATCH /schedule/classes` (update). The class payload returned by
`GET /schedule/classes` now includes a `sections` field with the same shape.
