{{ config(materialized='table') }}

-- Median/avg days-to-resolve over time, by council district.

SELECT
    EXTRACT(YEAR FROM f.date_found)             AS year,
    d.council_district,
    APPROX_QUANTILES(IF(f.is_resolved, f.days_open, NULL), 2)[OFFSET(1)] AS median_days_to_resolve,
    AVG(IF(f.is_resolved, f.days_open, NULL))   AS avg_days_to_resolve
FROM {{ ref('fact_violation') }} f
JOIN {{ ref('dim_council_district') }} d ON f.council_district_sk = d.council_district_sk
GROUP BY year, council_district
ORDER BY year, council_district
