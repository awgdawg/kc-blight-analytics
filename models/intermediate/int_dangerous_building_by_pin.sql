{{ config(materialized='view') }}

-- One row per PIN that appears on the Dangerous Buildings list (already deduped
-- in staging). The escalation endpoint of the blight funnel.

SELECT
    pin,
    case_opened AS dangerous_building_date,
    status_of_case,
    is_demolition_status
FROM {{ ref('stg_dangerous_buildings') }}
