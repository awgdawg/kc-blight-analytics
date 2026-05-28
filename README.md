# KC Blight Lifecycle Analytics

Tracing **two decades of Kansas City property blight** — from a property's first
code violation, through repeat violations, to a "dangerous building" designation
and demolition — by combining three KCMO open-data sources into one dimensional
model on BigQuery.

## Stack

Python (Socrata extract-load) → BigQuery → **dbt** (staging → intermediate →
marts) → Looker Studio. Continuous integration and a scheduled source refresh
run on GitHub Actions.

## Data sources (KCMO Socrata, `data.kcmo.org`)

| Dataset | ID | Rows | Role |
|---|---|---|---|
| Property Violations [Historical] | `nhtf-e75a` | ~800K | Violations 2009–2021 |
| EG NPD Violations (EnerGov) | `vq3e-m9ge` | ~175K | Violations 2021–present |
| Dangerous Buildings List | `ax3m-jhxx` | ~400 | Escalation endpoint |

All three join on **PIN** (parcel id). The raw layer is landed as all-STRING to
tolerate dirty, mixed-type columns; dbt staging casts to proper types.

## Model

- `fact_violation` — one row per violation (transaction grain, ~972K rows)
- `fact_property_lifecycle` — one row per property (**accumulating snapshot**;
  the funnel: `current_stage` ∈ single_violation / repeat_violations /
  dangerous_building / demolition)
- Dimensions: `dim_property` (KC-bounds-cleaned geocodes), `dim_council_district`,
  `dim_violation_type` (ordinance unified across eras), `dim_date`

## Selected findings (2005–2026)

- **79,892** properties cited; **85.6%** are repeat offenders, yet only **0.4%**
  reach the dangerous-buildings list and **0.03%** active demolition.
- **971,708** violations; **87.9%** resolved; **median 230 days** to resolve.
- **Council District 3** carries the most blight (380K violations, highest
  escalation rate) and the slowest response (260-day median) — vs District 2's
  134 days, a near-2× gap.
- Most common violation: **animal feces (48-25, 21%)**, then weeds and trash.

## Run it

```powershell
py -3.10 -m venv .venv; .venv\Scripts\Activate.ps1
pip install -r requirements.txt
dbt deps
python ingest/extract_load.py --include-frozen   # land raw tables in BigQuery
dbt build                                         # transform + test
dbt docs generate; dbt docs serve                 # browse lineage
```

CI runs `dbt build --target ci` on push; a weekly Action refreshes the live
sources and rebuilds the `prod` datasets the dashboard reads.
