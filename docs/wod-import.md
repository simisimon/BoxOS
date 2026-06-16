# WOD CSV Import

Owners and trainers can bulk-create daily WODs from a CSV file. This is the
same format you get when you export a spreadsheet from Excel, Numbers, or
Google Sheets ("File → Download → Comma-separated values").

A ready-to-use example lives next to this doc:
[`sample-wods.csv`](./sample-wods.csv).

## How to import

1. Open **Schedule** (the calendar) as an owner or trainer.
2. Click the **import icon** (⬆️) in the calendar header — same place the
   previous class import lived.
3. Provide your rows in one of two ways:
   - **Upload CSV file** — pick a `.csv` file (web). Its contents are loaded
     into the box and checked against the schema below, or
   - **Paste** — paste the contents of a `.csv` file, or a range copied
     straight from Google Sheets / Excel (tab-separated is also accepted).

   Either way, each row is parsed and previewed live with a green check (ready)
   or a red error (with the reason and line number). A file whose header is
   missing required columns is rejected before anything is imported.
4. The import is **atomic** — if any row has an error, nothing is created.
5. When every row is valid, click **Import N WODs**. The calendar refreshes
   automatically.

> Tip: use **Insert example** to drop a working template into the box, or
> **Copy template** to put it on your clipboard. The first pasted row must be
> the header.

## Columns

The header row is required and column order does not matter (matching is by
name, case-insensitive). Empty cells are allowed for optional columns.

| Column | Required | Description |
|---|---|---|
| `date` | ✅ | WOD date, `YYYY-MM-DD` (e.g. `2026-06-22`). |
| `title` | ✅ | WOD title, max 80 characters. |
| `status` | optional | `draft` (default) or `published`. Drafts are hidden from athletes until published. |
| `section_1_description` | ✅ | The first section needs at least a description. |
| `section_1_score` | ✅ | Score unit for the first section: `time`, `rounds_reps`, or `weight`. |
| `section_1_title` | optional | Section label, max 80 characters (e.g. *Warm Up*, *Strength*, *MetCon*). Falls back to "Section 1" in the UI when empty. |
| `section_N_title` / `section_N_description` / `section_N_score` | optional (per section) | Additional sections. `N` runs from 2 upwards, up to 20. A section is created whenever both `section_N_description` and `section_N_score` are set; both are required together. |

## Rules & validation

- **Future or today only** — `date` must be today or later. Past dates are
  rejected (consistent with the "no WODs in the past" rule in the UI).
- **One WOD per date** — within the same import payload and against existing
  WODs in the gym. A date conflict fails that row (and the whole import).
- **Section score values** — must be one of `time`, `rounds_reps`, or `weight`.
- **At least one section** — every WOD needs at least the first section filled
  in (`section_1_description` and `section_1_score`).
- **Quoting** — standard CSV quoting applies; put double quotes around any
  field that contains a comma, e.g. `"21-15-9 Thrusters, Pull-ups"`.
- **Limit** — up to 500 rows per import.

## Example

```csv
date,title,status,section_1_title,section_1_description,section_1_score,section_2_title,section_2_description,section_2_score
2026-06-22,Murph,published,Warm Up,"500m row + dynamic stretching",time,Strength,"Back Squat 5x5 @ 75%",weight
2026-06-23,Open Gym,draft,Skill,"Handstand walk practice",rounds_reps,,,
2026-06-24,Cindy,published,Metcon,"20 min AMRAP: 5 pull-ups, 10 push-ups, 15 squats",rounds_reps,,,
```

The first row creates a *Murph* WOD with two sections (warm-up scored by time,
strength scored by weight) and publishes it immediately. The second and third
rows each create one-section WODs.

## Google Sheets

Build the sheet with the columns above (including the header row), then
either:

- **select the range, copy (Ctrl/Cmd+C) and paste** it straight into the
  import box — pasted spreadsheet cells are tab-separated, which the importer
  detects automatically; or
- **File → Download → Comma-separated values (.csv)**, open the file, and
  paste its contents.

(Importing directly from a Google Sheets *link* is not yet supported — see the
roadmap.)

## API

The dialog calls `POST /programming/workouts/import` (owner/trainer session).
Body:

```json
{
  "rows": [
    {
      "scheduled_date": "2026-06-22",
      "title": "Murph",
      "status": "published",
      "sections": [
        {
          "title": "Warm Up",
          "description": "500m row + dynamic stretching",
          "score_type": "time"
        },
        {
          "title": "Strength",
          "description": "Back Squat 5x5 @ 75%",
          "score_type": "weight"
        }
      ]
    }
  ]
}
```

- Success → `200 { "created_count": N, "row_count": M }`.
- Any invalid row → `422 { "created_count": 0, "errors": [{ "row": 2, "message": "…" }] }`
  and nothing is created.
