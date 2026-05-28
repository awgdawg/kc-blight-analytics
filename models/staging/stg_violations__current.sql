{{ config(materialized='view') }}

-- EnerGov / NPD violations (current era, ~mid-2021 onward).
-- Column order MUST match stg_violations__historical (they are UNION ALL'd).
-- Council district for NPD lives in computed_region_9t2m_phkm (pre-2023
-- boundaries, consistent with the historical feed); there is no plain
-- council_district or neighborhood-name column here.

SELECT
    CAST(violationid AS STRING)                          AS violation_id,
    CAST(casenumber AS STRING)                           AS case_number,
    TRIM(pin)                                            AS pin,
    'energov'                                            AS source_system,
    street_address                                       AS street_address,
    full_address                                         AS full_address,
    postalcode                                           AS zip_code,
    TRIM(computed_region_9t2m_phkm)                      AS council_district,
    CAST(NULL AS STRING)                                 AS neighborhood,
    {{ point_coord('incident_location', 1) }}           AS latitude,
    {{ point_coord('incident_location', 0) }}           AS longitude,
    chapter                                              AS chapter,
    ordinance                                            AS ordinance,
    {{ normalize_ordinance('ordinance') }}              AS violation_code,
    description                                          AS violation_description,
    {{ to_date('date_found') }}                          AS date_found,
    {{ to_date('date_to_comply') }}                      AS date_to_comply,
    {{ to_date('date_resolved') }}                       AS date_resolved,
    COALESCE(vio_status, case_status)                    AS status_raw,
    ({{ to_date('date_resolved') }} IS NOT NULL)         AS is_resolved
FROM {{ source('kc_blight_raw', 'npd_violations') }}
WHERE violationid IS NOT NULL
