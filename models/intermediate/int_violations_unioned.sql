{{ config(materialized='view') }}

-- The single source of truth for "a violation": current + historical stacked
-- into one transaction-grain table (identical column order makes UNION ALL safe).

WITH unioned AS (
    SELECT * FROM {{ ref('stg_violations__current') }}
    UNION ALL
    SELECT * FROM {{ ref('stg_violations__historical') }}
),

cleaned AS (
    -- ~0.1% of rows have a resolution date before the found date (source
    -- data-entry errors). Null those out and treat the violation as unresolved
    -- so days_open is never negative and resolution-time stats stay accurate.
    SELECT
        * EXCEPT (date_resolved, is_resolved),
        IF(date_resolved >= date_found, date_resolved, NULL)        AS date_resolved,
        (date_resolved IS NOT NULL AND date_resolved >= date_found) AS is_resolved
    FROM unioned
)

SELECT
    *,
    {{ days_between('date_found', 'COALESCE(date_resolved, CURRENT_DATE())') }} AS days_open
FROM cleaned
