{{ config(materialized='table') }}

-- Top repeat-offender properties for the hotspot map / drill-down table.

SELECT
    lc.pin,
    pr.street_address,
    pr.council_district,
    pr.neighborhood,
    pr.latitude,
    pr.longitude,
    lc.total_violations,
    lc.ever_dangerous_building,
    lc.current_stage
FROM {{ ref('fact_property_lifecycle') }} lc
JOIN {{ ref('dim_property') }} pr ON lc.property_sk = pr.property_sk
ORDER BY lc.total_violations DESC
LIMIT 200
