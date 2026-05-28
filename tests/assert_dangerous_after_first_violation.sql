{{ config(severity='warn') }}
-- A property's dangerous-building designation should not predate its first
-- recorded violation. WARN (not error): the two datasets are independent and a
-- building can be flagged dangerous before a violation was logged here.
SELECT *
FROM {{ ref('fact_property_lifecycle') }}
WHERE dangerous_building_date IS NOT NULL
  AND first_violation_date IS NOT NULL
  AND dangerous_building_date < first_violation_date
