# KC Blight Lifecycle — Walkthrough (the new patterns)

A teaching companion to the CMS Medicare walkthrough
(`cms-medicare-analytics/docs/walkthrough.md`). That doc explains the dbt
fundamentals — models, `ref()`, staging → intermediate → marts, surrogate keys,
tests, materializations. **This doc only covers what's new in this project**, so
read the CMS one first if those basics are fuzzy.

What's new here, and why each thing exists:

1. An **extract-load (EL) layer** — the data wasn't already in BigQuery
2. Landing the raw layer as **all-STRING** to survive dirty data
3. **Reconciling two schemas** (a frozen archive + a live feed) into one history
4. An **accumulating-snapshot fact** (the funnel) alongside a transaction fact
5. **Three dbt targets** (dev / ci / prod) + a **scheduled refresh**
6. **Real-world data-cleaning** lessons (the bugs that actually happened)
7. The **Looker dashboard** build (table + steps) and a wireframe mockup

---

## 1. The extract-load layer — getting data *into* BigQuery

The CMS project queried data that already lived in `bigquery-public-data`. Here
the data lives in Kansas City's **Socrata** open-data portal (`data.kcmo.org`),
so step zero is getting it into BigQuery. That's the "EL" (extract-load) of ELT.

`ingest/extract_load.py` does three things:
1. **Pages** through each Socrata dataset's API (`$limit`/`$offset`, 50k rows per
   page) with **retry/backoff** — anonymous Socrata throttles aggressively.
2. **Cleans** each record: sanitizes column names (Socrata's `:@computed_region_*`
   fields aren't valid BigQuery column names) and coerces values to strings.
3. **Loads** each table into a fixed `kc_blight_raw` dataset with one BigQuery
   load job, then dbt sources from there.

```python
def load_dataset(socrata, bq, project, cfg, skip_fetch=False):
    path = cache_path_for(cfg["table"])          # cache the fetch on disk
    if not (skip_fetch and os.path.exists(path)):
        fetch_to_file(socrata, cfg, path)         # paged fetch w/ retry → NDJSON
    schema = [bigquery.SchemaField(k, "STRING") for k in all_keys]  # see §2
    job = bigquery.LoadJobConfig(schema=schema, write_disposition="WRITE_TRUNCATE",
                                 source_format="NEWLINE_DELIMITED_JSON")
    bq.load_table_from_file(open(path, "rb"), table_id, job_config=job).result()
```

**Why a cache file?** The fetch (≈1M throttled rows) is the slow part. Writing the
pulled NDJSON to a temp file and adding a `--skip-fetch` flag means you can
iterate on the *load* without re-pulling the data — which mattered a lot while
debugging (see §6).

**Why dbt never calls Socrata:** dbt only reads `kc_blight_raw`. Keeping the API
out of the transform layer makes `dbt build` fast and deterministic, and lets CI
run without hitting an external service.

---

## 2. The all-STRING raw layer (the most important trick here)

KCMO's data is dirty. The clearest example: `inspection_area` is *usually* a
number ("12", "7") but occasionally a street name ("East 23rd St Pac").

When you let BigQuery **autodetect** column types from JSON, it samples the early
rows of `inspection_area`, decides it's an INTEGER, and then the whole load fails
the moment it hits the one text value. Quoting the values doesn't help —
autodetect inspects string *contents* and still guesses INTEGER.

**The fix:** land the raw layer as **all-STRING** with an explicit schema
(`autodetect=False`). Every column is text; nothing can be mis-typed; dirty values
load fine. Then **dbt staging casts** each column to its proper type
(`SAFE_CAST`, `to_date`, etc.). This is the standard ELT division of labor:

> **Raw = land it exactly as text. Staging = type it and clean it.**

This one decision is why the load is bulletproof, and it's a pattern worth
reusing for *any* messy source.

---

## 3. Reconciling two schemas into one history

The violations come from two datasets with **different schemas**:

| | Historical (`nhtf-e75a`, 2009–2021) | Current / EnerGov (`vq3e-m9ge`, 2021–present) |
|---|---|---|
| Found date | `violation_entry_date` | `date_found` |
| Resolved date | `case_closed` | `date_resolved` |
| Council district | `council_district` (1–6) | `computed_region_9t2m_phkm` |
| Violation code | `violation_code` + `ordinance` | only `ordinance` |
| Neighborhood | present | absent |

Two staging models (`stg_violations__current`, `stg_violations__historical`) map
each source onto **one identical column shape**, so the intermediate layer can
`UNION ALL` them into a single 15-year history (`int_violations_unioned`). This is
the same idea as the CMS inpatient/outpatient union, but harder because the
schemas diverge more. Two reconciliation moves worth noting:

- **Dates** arrive as ISO strings (`2022-07-25T00:00:00.000`), so a `to_date`
  macro does `SAFE_CAST(SUBSTR(col, 1, 10) AS DATE)`.
- **Violation type** is unified on a `normalize_ordinance` macro that strips the
  historical `" C.O."` suffix, so `48-30 C.O.` and `48-30` map to one code — letting
  the violation-type dimension line up across both eras.

---

## 4. The accumulating-snapshot fact (the funnel)

This is the marquee new modeling pattern. The CMS project had one transaction-grain
fact (one row per claim-year). Here there are **two** facts:

- **`fact_violation`** — *transaction grain*, one row per violation (~972K rows).
  Powers volume, trends, resolution-time. Same idea as CMS.
- **`fact_property_lifecycle`** — *accumulating snapshot*, **one row per property
  (PIN)**. Each row summarizes that property's entire journey, and a single
  `current_stage` column places it in the funnel:

```sql
CASE
  WHEN COALESCE(d.is_demolition_status, FALSE) THEN 'demolition'
  WHEN d.pin IS NOT NULL                       THEN 'dangerous_building'
  WHEN p.total_violations >= 2                 THEN 'repeat_violations'
  ELSE 'single_violation'
END AS current_stage
```

**Why two facts?** Different grains answer different questions. "How many
violations in 2018?" needs the transaction fact. "What share of properties ever
escalate to demolition?" needs one row per property — exactly what the
accumulating snapshot gives you. Trying to answer the second question from the
transaction fact means wrestling with `COUNT(DISTINCT pin)` and window functions
on every query; the snapshot bakes it in. The funnel mart then just counts rows
per `current_stage`.

> **Accumulating snapshot = one row per *thing*, with milestone columns and a
> stage. The textbook choice for funnel / pipeline analysis.**

---

## 5. Three targets + a scheduled refresh

CMS had two dbt targets (`dev`, `ci`). This project adds a third — `prod` — and a
clear job for each:

| Target | Dataset prefix | Who builds it | Purpose |
|---|---|---|---|
| `dev` | `kc_blight_dev_*` | you, locally | experimentation |
| `ci` | `kc_blight_ci_*` | GitHub Actions on push | validate every change |
| `prod` | `kc_blight_prod_*` | the scheduled Action | **what Looker reads** |

The dashboard points at `kc_blight_prod_marts`, and a **weekly GitHub Action**
(`refresh-sources.yml`, cron Mondays 09:00 UTC) re-pulls the two live datasets and
rebuilds `prod`. So the board stays fresh without you touching it, while your
local edits and CI never disturb what the public sees. (The frozen historical
table is skipped on refresh — it never changes.)

---

## 6. Real-world data-cleaning (the bugs that actually happened)

These are the kinds of problems that don't show up in tutorials. Each was found
because a **dbt test failed** — which is the whole point of having tests.

- **Resolved-before-found:** 946 violations had a resolution date *earlier* than
  the found date (data-entry errors). They produced negative `days_open`. Fix in
  the intermediate layer: null the bad resolution date and treat the row as
  unresolved, so `days_open` is never negative and resolution stats stay honest.
- **No reliable unique key:** the historical `id` repeats across distinct rows,
  and the current feed has ~2,900 exact-duplicate rows. So `violation_id` can't be
  the grain key. Fix: `SELECT DISTINCT` to collapse true duplicates, then derive
  `violation_pk` from a full-row hash (`MD5(TO_JSON_STRING(...))`).
- **Date dimension type mismatch:** `dbt_utils.date_spine` returns **DATETIME** on
  BigQuery, so its surrogate key hashed `2020-06-01T00:00:00` while the fact hashed
  the DATE `2020-06-01` — every join failed. Fix: cast `date_day` to DATE before
  hashing. (Surrogate keys only match if both sides hash *identical* strings.)
- **Junk geocoordinates:** historical lat/lng often holds a sentinel far outside KC.
  Fix: a Kansas-City bounding-box filter in `dim_property` nulls out-of-range points
  so the map only plots real ones.

The lesson: **tests turn silent data problems into loud build failures.** Every
one of these would have quietly corrupted a chart if the model had no tests.

**Readable chart labels via a seed.** The ordinance descriptions are unusable as
chart labels ("Did cause or permit rank weeds or unattended growth to stand upon
premises..."). A **seed** — `seeds/violation_labels.csv`, a hand-curated
`violation_code → short_label` lookup — is left-joined in `dim_violation_type`,
producing a `short_label` column (`COALESCE(seed.short_label, violation_code)`, so
unmapped codes fall back to the code). A seed is dbt's idiomatic way to inject a
small curated lookup: it's version-controlled, editable as a CSV without touching
SQL, and `dbt build`/`dbt seed` loads it automatically (so CI picks it up). The
charts then use `short_label` ("Animal feces", "Weeds / overgrowth", ...).

---

## 7. The Looker Studio dashboard

The board reads the `mart_*` tables in `kc_blight_prod_marts`, laid out as a
**two-page, map-centric report** on a 1200×900 canvas. Build order: **add a data
source per mart, then drop each chart and bind its dimension + metric.**

A geo map can only carry *spatial* facts — so hotspots and council-district
geography live on the map, while the *non-spatial* views (violation-type mix, a
time trend) get their own page. A **report-level** date/district control drives
both pages from one place.

### Page 1 — overview + hotspot heatmap (the hero)

| Row | Chart type | Data source (mart) | Dimension | Metric / setup |
|---|---|---|---|---|
| 1a | Scorecard | `mart_blight_funnel` | — | `property_count`; filter `stage_order = 1` → **Properties cited** (79,892) |
| 1b | Scorecard | `mart_blight_funnel` | — | `pct_of_violation_properties`; filter `stage = 'Repeat violations'`, % → **Repeat rate** (85.6%) |
| 1c | Scorecard | `mart_blight_funnel` | — | `pct_of_violation_properties`; filter `stage = 'Dangerous building'`, % → **% escalated** (0.4%) |
| 1d | Scorecard | `mart_council_district` | — | `SUM(total_violations)` → **Total violations** (~972K) |
| 2 left | Bar chart | `mart_blight_funnel` | `stage` (sort by `stage_order` asc) | `property_count` → the **funnel** |
| 2 right | Time series | `mart_violations_trend` | `year` | `total_violations`; **Breakdown** = `source_system` |
| 3 (hero) | **Google Maps → Heatmap layer** | `mart_property_points` | geo = `lat_lng` (type: Latitude,Longitude) | **weight** = `total_violations` (~79.8K points). Optional **Bubble layer** over `mart_blight_hotspots`, color = `current_stage`, for the worst offenders |

### Page 2 — what & when (non-spatial)

| Row | Chart type | Data source (mart) | Dimension | Metric / setup |
|---|---|---|---|---|
| 1 | Bar chart (horizontal) | `mart_top_violation_types` | `short_label` | `violation_count` (sort desc, limit 20). `short_label` = 2-3 word names (from the `violation_labels` seed); use it instead of the unreadable full ordinance text |
| 2 | Time series (line) | `mart_resolution_time` | `year` | `median_days_to_resolve`; **Breakdown** = `council_district` (this is where the 134-vs-260-day district gap shows) |

> Note: Looker Studio has no built-in KC council-district boundaries, so you
> **can't** shade district polygons (a true choropleth). District shows up as the
> heatmap's geography and as the breakdown on the page-2 resolution line.

### Single council-district filter for the whole board (`mart_dashboard`)

A Looker filter control only filters charts that use **its own data source** — so
to make one council-district chip reslice *every* visual, every chart must read
from **one shared source**. `mart_dashboard` is that source: one wide,
denormalized row per violation (~972K) carrying both the violation facts and the
property's lifecycle attributes (`current_stage`, `total_violations`, `lat_lng`,
`council_district`, …). Point every chart at it, add a single **report-level**
`council_district` control, and the whole board reslices together — with
percentages and medians computed *after* the filter (so they're correct per
district), because Looker aggregates the raw rows live.

| Visual | Dimension | Metric on `mart_dashboard` |
|---|---|---|
| Funnel (cumulative) | — (4 metrics) | `COUNT_DISTINCT(pin)` · `COUNT_DISTINCT(IF(total_violations>=2,pin,NULL))` · `COUNT_DISTINCT(IF(ever_dangerous_building,pin,NULL))` · `COUNT_DISTINCT(IF(current_stage='demolition',pin,NULL))` |
| KPI · properties | — | `COUNT DISTINCT pin` |
| KPI · % escalated | — | calc: `COUNT_DISTINCT(IF(ever_dangerous_building, pin, NULL)) / COUNT_DISTINCT(pin)` |
| KPI · total violations | — | record `COUNT` (one row = one violation) |
| Trend | `year` | `COUNT` (one record = one violation) |
| Top types | `short_label` | `COUNT` |
| Resolution | `year` | `MEDIAN(days_open)` (computed live) |
| Heatmap | `lat_lng` | record `COUNT` (violation density) or `COUNT_DISTINCT(pin)` |

**Caution:** `total_violations` is a *property* attribute denormalized onto every
violation row — never `SUM` it on this table (that multiplies each property's
count by its number of rows). For total violations use record `COUNT`;
`total_violations` is only meaningful per-property (e.g. sorting hotspots, or as
the weight on the property-grain `mart_property_points`).

For the funnel, a bar chart with **no dimension** and those four cumulative
metrics reproduces 79,892 → 68,384 → 318 → 21. (Grouping by `current_stage`
instead gives a *mutually-exclusive* stage distribution — a different, also-valid
view, but not the cumulative funnel.)

Trade-off: it's the BI "one big table" pattern — denormalized and ~972K rows, but
BigQuery/Looker aggregate it fine, and it's what makes a single global filter
possible. The narrow per-question marts still exist for anyone who wants a
pre-aggregated source.

### Theme
Match the portfolio: page background `#0a0a0b`, accent `#f5a623` (amber), secondary
`#4ec9b0` (teal), font **IBM Plex Sans**. Then **Share → "Anyone with the link can
view"**, and **File → Embed report** to get the iframe URL used on the homepage.

A static wireframe of this layout lives at
`portfolio/tools/kc-blight-looker-mockup.html` — open it in a browser as a visual
target before building in Looker.

---

## 8. Reuse checklist for the next Socrata → BigQuery project

1. Copy `ingest/extract_load.py` + `datasets.yml`; change the Socrata IDs.
2. Land raw as **all-STRING** (don't trust autodetect on civic data).
3. One `stg_` model per source; reconcile schemas onto a common shape; cast there.
4. Pick the grain deliberately — add an **accumulating snapshot** if the story is a
   funnel/lifecycle.
5. Write tests *first-class* — they're how you find the dirty data.
6. dev / ci / prod targets; point the dashboard at prod; schedule the refresh.
7. `gh` isn't installed here — create the repo + secret via the GitHub web UI;
   `git push` works through the credential manager.
