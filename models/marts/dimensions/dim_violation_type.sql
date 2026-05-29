{{ config(materialized='table') }}

-- One row per normalized violation code (unified ordinance across eras) plus an
-- UNKNOWN member. A representative description is picked per code.

WITH types AS (
    SELECT DISTINCT violation_code, chapter, violation_description
    FROM {{ ref('int_violations_unioned') }}
    WHERE violation_code IS NOT NULL
),

ranked AS (
    SELECT
        violation_code, chapter, violation_description,
        ROW_NUMBER() OVER (PARTITION BY violation_code ORDER BY violation_description) AS rn
    FROM types
),

picked AS (
    SELECT violation_code, chapter, violation_description
    FROM ranked WHERE rn = 1

    UNION ALL
    SELECT 'UNKNOWN', CAST(NULL AS STRING), 'Unknown / uncoded'
)

SELECT
    {{ dbt_utils.generate_surrogate_key(['p.violation_code']) }} AS violation_type_sk,
    p.violation_code,
    p.chapter,
    p.violation_description,
    -- short 2-3 word label for charts; falls back to the raw code if unmapped
    COALESCE(lbl.short_label, p.violation_code) AS short_label
FROM picked p
LEFT JOIN {{ ref('violation_labels') }} lbl ON p.violation_code = lbl.violation_code
