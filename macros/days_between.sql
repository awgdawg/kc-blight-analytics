{% macro days_between(start_date, end_date) %}
    CASE
        WHEN {{ start_date }} IS NULL OR {{ end_date }} IS NULL THEN NULL
        ELSE DATE_DIFF({{ end_date }}, {{ start_date }}, DAY)
    END
{% endmacro %}
