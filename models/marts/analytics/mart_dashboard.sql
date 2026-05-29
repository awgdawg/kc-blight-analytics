{{ config(materialized='table') }}

-- Wide, denormalized serving table: ONE row per violation, with the property's
-- lifecycle attributes joined on. This is the "one big table" that lets a single
-- council_district filter control drive every dashboard visual from one shared
-- data source. Grain = fact_violation (one row per violation, ~972K).
-- All joins are many-to-one (to dims / per-property tables), so the row count and
-- violation_pk uniqueness are preserved (no fan-out).

SELECT
    f.violation_pk,
    f.violation_id,
    f.source_system,
    f.date_found,
    EXTRACT(YEAR FROM f.date_found)                          AS year,
    f.date_resolved,
    f.days_open,
    f.is_resolved,

    -- violation type
    vt.violation_code,
    vt.short_label,
    vt.chapter,
    vt.violation_description,

    -- geography (the violation's council district)
    cd.council_district,
    cd.district_label,

    -- property + lifecycle attributes (denormalized for filtering/aggregation)
    p.pin,
    p.street_address,
    p.neighborhood,
    p.latitude,
    p.longitude,
    CASE
        WHEN p.latitude IS NOT NULL AND p.longitude IS NOT NULL
        THEN CONCAT(CAST(p.latitude AS STRING), ',', CAST(p.longitude AS STRING))
    END                                                     AS lat_lng,
    lc.current_stage,
    lc.ever_dangerous_building,
    lc.total_violations
FROM {{ ref('fact_violation') }} f
LEFT JOIN {{ ref('dim_violation_type') }}      vt ON f.violation_type_sk   = vt.violation_type_sk
LEFT JOIN {{ ref('dim_council_district') }}    cd ON f.council_district_sk = cd.council_district_sk
LEFT JOIN {{ ref('dim_property') }}            p  ON f.property_sk         = p.property_sk
LEFT JOIN {{ ref('fact_property_lifecycle') }} lc ON f.property_sk         = lc.property_sk
