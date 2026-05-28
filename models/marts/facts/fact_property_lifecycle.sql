{{ config(materialized='table') }}

-- Accumulating snapshot: one row per property (PIN). Encodes the blight funnel
-- via current_stage and the milestone dates/counters behind it.

WITH p AS (
    SELECT * FROM {{ ref('int_property_rollup') }}
),
d AS (
    SELECT * FROM {{ ref('int_dangerous_building_by_pin') }}
)

SELECT
    {{ dbt_utils.generate_surrogate_key(['p.pin']) }}                                        AS property_sk,
    {{ dbt_utils.generate_surrogate_key(["COALESCE(NULLIF(p.council_district, ''), 'UNKNOWN')"]) }} AS council_district_sk,
    p.pin,
    p.first_violation_date,
    p.last_violation_date,
    p.total_violations,
    p.distinct_violation_types,
    p.resolved_violations,
    p.avg_days_open,
    (d.pin IS NOT NULL)                                                                      AS ever_dangerous_building,
    d.dangerous_building_date,
    COALESCE(d.is_demolition_status, FALSE)                                                  AS is_demolition_status,
    {{ days_between('p.first_violation_date', 'd.dangerous_building_date') }}                AS days_first_violation_to_dangerous,
    CASE
        WHEN COALESCE(d.is_demolition_status, FALSE) THEN 'demolition'
        WHEN d.pin IS NOT NULL                        THEN 'dangerous_building'
        WHEN p.total_violations >= 2                  THEN 'repeat_violations'
        ELSE 'single_violation'
    END                                                                                     AS current_stage
FROM p
LEFT JOIN d ON p.pin = d.pin
