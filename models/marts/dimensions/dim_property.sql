{{ config(materialized='table') }}

-- One row per PIN seen in violations OR on the dangerous-buildings list, plus an
-- UNKNOWN member. lat/lng are cleaned to a Kansas City bounding box so the
-- hotspot map ignores sentinel/garbage coordinates in the source data.

WITH props AS (
    SELECT pin, street_address, full_address, zip_code, council_district,
           neighborhood, latitude, longitude
    FROM {{ ref('int_property_rollup') }}

    UNION DISTINCT

    SELECT d.pin, d.street_address, d.full_address, d.zip_code, d.council_district,
           d.neighborhood, d.latitude, d.longitude
    FROM {{ ref('stg_dangerous_buildings') }} d
    LEFT JOIN {{ ref('int_property_rollup') }} p USING (pin)
    WHERE p.pin IS NULL

    UNION DISTINCT

    SELECT 'UNKNOWN',
           CAST(NULL AS STRING), CAST(NULL AS STRING), CAST(NULL AS STRING),
           'UNKNOWN', CAST(NULL AS STRING),
           CAST(NULL AS FLOAT64), CAST(NULL AS FLOAT64)
)

SELECT
    {{ dbt_utils.generate_surrogate_key(['pin']) }} AS property_sk,
    pin, street_address, full_address, zip_code, council_district, neighborhood,
    IF(latitude BETWEEN 38.8 AND 39.5 AND longitude BETWEEN -94.9 AND -94.3,
       latitude, NULL)  AS latitude,
    IF(latitude BETWEEN 38.8 AND 39.5 AND longitude BETWEEN -94.9 AND -94.3,
       longitude, NULL) AS longitude
FROM props
