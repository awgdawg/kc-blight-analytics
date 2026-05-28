{{ config(materialized='table') }}

WITH days AS (
    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('2009-01-01' as date)",
        end_date="date_add(current_date(), interval 1 day)"
    ) }}
)

SELECT
    {{ dbt_utils.generate_surrogate_key(['date_day']) }} AS date_sk,
    date_day,
    EXTRACT(YEAR    FROM date_day) AS year,
    EXTRACT(QUARTER FROM date_day) AS quarter,
    EXTRACT(MONTH   FROM date_day) AS month,
    FORMAT_DATE('%B', date_day)    AS month_name
FROM days
