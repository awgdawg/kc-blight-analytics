{{ config(materialized='table') }}

-- Transaction grain: one row per distinct violation record. The source has no
-- reliable unique id (historical `id` repeats; npd has ~2,926 exact-duplicate
-- rows), so we SELECT DISTINCT to collapse true duplicates and derive
-- violation_pk from a full-row hash. FKs use COALESCE(..., 'UNKNOWN') so every
-- key resolves; date_found is bounded to the dim_date spine.

WITH deduped AS (
    SELECT DISTINCT *
    FROM {{ ref('int_violations_unioned') }}
    WHERE date_found IS NOT NULL
      AND date_found >= DATE '2005-01-01'
      AND date_found <= CURRENT_DATE()
)

SELECT
    TO_HEX(MD5(TO_JSON_STRING(d)))                                                            AS violation_pk,
    {{ dbt_utils.generate_surrogate_key(["COALESCE(NULLIF(d.pin, ''), 'UNKNOWN')"]) }}        AS property_sk,
    {{ dbt_utils.generate_surrogate_key(["COALESCE(d.violation_code, 'UNKNOWN')"]) }}         AS violation_type_sk,
    {{ dbt_utils.generate_surrogate_key(["COALESCE(NULLIF(d.council_district, ''), 'UNKNOWN')"]) }} AS council_district_sk,
    {{ dbt_utils.generate_surrogate_key(['d.date_found']) }}                                  AS date_sk,
    d.violation_id,
    d.source_system,
    d.date_found,
    d.date_resolved,
    d.days_open,
    d.is_resolved
FROM deduped d
