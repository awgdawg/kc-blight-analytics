{{ config(materialized='table') }}

-- The hero comparison: volume, escalation rate, and response time by district.

WITH v AS (
    SELECT
        council_district_sk,
        COUNT(*)                    AS total_violations,
        COUNT(DISTINCT property_sk) AS distinct_properties,
        APPROX_QUANTILES(IF(is_resolved, days_open, NULL), 2)[OFFSET(1)] AS median_days_to_resolve
    FROM {{ ref('fact_violation') }}
    GROUP BY council_district_sk
),
lc AS (
    SELECT
        council_district_sk,
        COUNTIF(ever_dangerous_building) AS dangerous_building_count,
        SAFE_DIVIDE(COUNTIF(ever_dangerous_building), COUNT(*)) AS pct_escalated_to_dangerous
    FROM {{ ref('fact_property_lifecycle') }}
    GROUP BY council_district_sk
)
SELECT
    d.council_district,
    d.district_label,
    v.total_violations,
    v.distinct_properties,
    lc.dangerous_building_count,
    lc.pct_escalated_to_dangerous,
    v.median_days_to_resolve
FROM {{ ref('dim_council_district') }} d
LEFT JOIN v  ON d.council_district_sk = v.council_district_sk
LEFT JOIN lc ON d.council_district_sk = lc.council_district_sk
ORDER BY v.total_violations DESC
