{{ config(materialized='table') }}

-- The 20 most common violation types (UNKNOWN/uncoded excluded).

WITH counts AS (
    SELECT
        violation_type_sk,
        COUNT(*)       AS violation_count,
        AVG(days_open) AS avg_days_open
    FROM {{ ref('fact_violation') }}
    GROUP BY violation_type_sk
),
grand AS (SELECT SUM(violation_count) AS grand_total FROM counts)
SELECT
    t.violation_code,
    t.chapter,
    t.violation_description,
    c.violation_count,
    SAFE_DIVIDE(c.violation_count, (SELECT grand_total FROM grand)) AS pct_of_total,
    c.avg_days_open
FROM counts c
JOIN {{ ref('dim_violation_type') }} t ON c.violation_type_sk = t.violation_type_sk
WHERE t.violation_code != 'UNKNOWN'
ORDER BY c.violation_count DESC
LIMIT 20
