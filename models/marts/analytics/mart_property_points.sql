{{ config(materialized='table') }}

-- One row per geocoded property — feeds the Looker Studio geo heatmap
-- (Heatmap layer weighted by total_violations, optional Bubble layer colored
-- by current_stage). ~79.8K rows (99.8% of properties have valid KC coordinates).
-- lat_lng is a ready-made "latitude,longitude" field for Looker's geo type.

SELECT
    pr.pin,
    pr.street_address,
    pr.council_district,
    pr.neighborhood,
    pr.latitude,
    pr.longitude,
    CONCAT(CAST(pr.latitude AS STRING), ',', CAST(pr.longitude AS STRING)) AS lat_lng,
    lc.total_violations,
    lc.current_stage,
    lc.ever_dangerous_building
FROM {{ ref('fact_property_lifecycle') }} lc
JOIN {{ ref('dim_property') }} pr ON lc.property_sk = pr.property_sk
WHERE pr.latitude IS NOT NULL
  AND pr.longitude IS NOT NULL
