{{ config(materialized='view') }}

-- Property Violations [Historical] (2009 - mid 2021).
-- Column order MUST match stg_violations__current (they are UNION ALL'd).

SELECT
    CAST(id AS STRING)                                   AS violation_id,
    CAST(case_id AS STRING)                              AS case_number,
    TRIM(pin)                                            AS pin,
    'historical'                                         AS source_system,
    address                                              AS street_address,
    address                                              AS full_address,
    zip_code                                             AS zip_code,
    TRIM(council_district)                               AS council_district,
    neighborhood                                         AS neighborhood,
    SAFE_CAST(latitude AS FLOAT64)                       AS latitude,
    SAFE_CAST(longitude AS FLOAT64)                      AS longitude,
    chapter                                              AS chapter,
    ordinance                                            AS ordinance,
    {{ normalize_ordinance('ordinance') }}              AS violation_code,
    violation_description                                AS violation_description,
    COALESCE({{ to_date('violation_entry_date') }}, {{ to_date('case_opened') }}) AS date_found,
    CAST(NULL AS DATE)                                   AS date_to_comply,
    {{ to_date('case_closed') }}                         AS date_resolved,
    status                                               AS status_raw,
    ({{ to_date('case_closed') }} IS NOT NULL OR LOWER(status) = 'closed') AS is_resolved
FROM {{ source('kc_blight_raw', 'historical_violations') }}
WHERE id IS NOT NULL
