{{ config(materialized='view') }}

-- The single source of truth for "a violation": current + historical stacked
-- into one transaction-grain table (identical column order makes UNION ALL safe).

WITH unioned AS (
    SELECT * FROM {{ ref('stg_violations__current') }}
    UNION ALL
    SELECT * FROM {{ ref('stg_violations__historical') }}
)
SELECT
    *,
    {{ days_between('date_found', 'COALESCE(date_resolved, CURRENT_DATE())') }} AS days_open
FROM unioned
