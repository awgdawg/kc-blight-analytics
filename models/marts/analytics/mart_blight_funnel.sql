{{ config(materialized='table') }}

-- The blight funnel: how many properties reach each stage.

WITH lc AS (
    SELECT * FROM {{ ref('fact_property_lifecycle') }}
),
totals AS (
    SELECT
        COUNT(*)                          AS properties_any,
        COUNTIF(total_violations >= 2)    AS properties_repeat,
        COUNTIF(ever_dangerous_building)  AS properties_dangerous,
        COUNTIF(is_demolition_status)     AS properties_demolition
    FROM lc
)
SELECT 1 AS stage_order, 'Any violation'     AS stage, properties_any        AS property_count, 1.0 AS pct_of_violation_properties FROM totals
UNION ALL
SELECT 2, 'Repeat violations',  properties_repeat,     SAFE_DIVIDE(properties_repeat,     properties_any) FROM totals
UNION ALL
SELECT 3, 'Dangerous building', properties_dangerous,  SAFE_DIVIDE(properties_dangerous,  properties_any) FROM totals
UNION ALL
SELECT 4, 'Demolition',         properties_demolition, SAFE_DIVIDE(properties_demolition, properties_any) FROM totals
