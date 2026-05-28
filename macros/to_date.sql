{# Raw dates land as ISO strings like '2022-07-25T00:00:00.000'. Take the first
   10 chars and cast to DATE (SAFE_CAST returns NULL on anything unparseable). #}
{% macro to_date(col) %}
    SAFE_CAST(SUBSTR({{ col }}, 1, 10) AS DATE)
{% endmacro %}
