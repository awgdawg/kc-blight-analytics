-- Not materialized; exploration only. The properties driving the most blight.
SELECT
    pin,
    street_address,
    council_district,
    total_violations,
    current_stage,
    ever_dangerous_building
FROM {{ ref('fact_property_lifecycle') }}
ORDER BY total_violations DESC
LIMIT 50
