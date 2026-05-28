-- days_open must never be negative.
SELECT *
FROM {{ ref('fact_violation') }}
WHERE days_open < 0
