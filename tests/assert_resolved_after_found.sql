-- A violation should not be resolved before it was found.
SELECT *
FROM {{ ref('int_violations_unioned') }}
WHERE date_resolved IS NOT NULL
  AND date_found IS NOT NULL
  AND date_resolved < date_found
