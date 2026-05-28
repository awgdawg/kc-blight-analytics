{{ config(materialized='view') }}

-- One row per property (PIN): violation milestones + counters + most-recent
-- attributes. Feeds both dim_property and the accumulating-snapshot fact.

WITH base AS (
    SELECT * FROM {{ ref('int_violations_unioned') }}
    WHERE pin IS NOT NULL AND pin != ''
),

attrs AS (
    SELECT
        pin, street_address, full_address, zip_code, council_district,
        latitude, longitude,
        ROW_NUMBER() OVER (PARTITION BY pin ORDER BY date_found DESC) AS rn
    FROM base
),

recent AS (
    SELECT pin, street_address, full_address, zip_code, council_district, latitude, longitude
    FROM attrs WHERE rn = 1
),

agg AS (
    SELECT
        pin,
        MIN(date_found)                AS first_violation_date,
        MAX(date_found)                AS last_violation_date,
        COUNT(*)                       AS total_violations,
        COUNT(DISTINCT violation_code) AS distinct_violation_types,
        COUNTIF(is_resolved)           AS resolved_violations,
        AVG(days_open)                 AS avg_days_open,
        MAX(neighborhood)              AS neighborhood
    FROM base
    GROUP BY pin
)

SELECT
    a.pin,
    a.first_violation_date,
    a.last_violation_date,
    a.total_violations,
    a.distinct_violation_types,
    a.resolved_violations,
    a.avg_days_open,
    r.street_address, r.full_address, r.zip_code, r.council_district,
    a.neighborhood, r.latitude, r.longitude
FROM agg a
JOIN recent r USING (pin)
