{{ config(materialized='view') }}

-- Dangerous Buildings List (current active designations; ~few hundred rows).
-- Deduped to one row per PIN. No neighborhood column exists in this dataset.

WITH ranked AS (
    SELECT
        TRIM(pin)                                       AS pin,
        CAST(casenumber AS STRING)                      AS case_number,
        address                                         AS street_address,
        location                                        AS full_address,
        zip_code                                        AS zip_code,
        TRIM(council_district)                          AS council_district,
        CAST(NULL AS STRING)                            AS neighborhood,
        {{ point_coord('case_location', 1) }}          AS latitude,
        {{ point_coord('case_location', 0) }}          AS longitude,
        {{ to_date('case_opened') }}                    AS case_opened,
        statusofcase                                    AS status_of_case,
        ROW_NUMBER() OVER (
            PARTITION BY TRIM(pin)
            ORDER BY {{ to_date('case_opened') }} DESC, casenumber DESC
        )                                               AS rn
    FROM {{ source('kc_blight_raw', 'dangerous_buildings') }}
    WHERE pin IS NOT NULL AND TRIM(pin) != ''
)
SELECT
    pin, case_number, street_address, full_address, zip_code,
    council_district, neighborhood, latitude, longitude,
    case_opened, status_of_case,
    (LOWER(status_of_case) LIKE '%demolition%'
     OR LOWER(status_of_case) LIKE '%demolish%')        AS is_demolition_status
FROM ranked
WHERE rn = 1
