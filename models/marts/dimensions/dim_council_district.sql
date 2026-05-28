{{ config(materialized='table') }}

-- Council districts 1-6 plus an UNKNOWN member so fact FKs always resolve.

WITH districts AS (
    SELECT DISTINCT council_district
    FROM {{ ref('int_violations_unioned') }}
    WHERE council_district IS NOT NULL AND council_district != ''

    UNION DISTINCT
    SELECT 'UNKNOWN'
)

SELECT
    {{ dbt_utils.generate_surrogate_key(['council_district']) }} AS council_district_sk,
    council_district,
    CASE WHEN council_district = 'UNKNOWN'
         THEN 'Unknown'
         ELSE CONCAT('District ', council_district) END AS district_label
FROM districts
