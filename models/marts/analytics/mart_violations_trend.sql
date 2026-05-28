{{ config(materialized='table') }}

-- Violations per year, split by source system, with median resolution time.

SELECT
    EXTRACT(YEAR FROM date_found)               AS year,
    source_system,
    COUNT(*)                                    AS total_violations,
    COUNTIF(is_resolved)                        AS resolved_violations,
    APPROX_QUANTILES(days_open, 2)[OFFSET(1)]   AS median_days_open
FROM {{ ref('fact_violation') }}
GROUP BY year, source_system
ORDER BY year, source_system
