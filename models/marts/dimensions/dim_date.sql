{{ config(materialized='table') }}

-- date_spine yields a DATETIME on BigQuery; cast to DATE so date_sk hashes the
-- same 'YYYY-MM-DD' string the fact does (fact date_found is a DATE).

WITH days AS (
    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('2005-01-01' as date)",
        end_date="date_add(current_date(), interval 1 day)"
    ) }}
),
typed AS (
    SELECT CAST(date_day AS DATE) AS date_day FROM days
)

SELECT
    {{ dbt_utils.generate_surrogate_key(['date_day']) }} AS date_sk,
    date_day,
    EXTRACT(YEAR    FROM date_day) AS year,
    EXTRACT(QUARTER FROM date_day) AS quarter,
    EXTRACT(MONTH   FROM date_day) AS month,
    FORMAT_DATE('%B', date_day)    AS month_name
FROM typed
