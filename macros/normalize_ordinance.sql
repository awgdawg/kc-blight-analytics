{# Unify the violation-type key across eras. Historical ordinances look like
   '48-30 C.O.'; the current (EnerGov) feed uses '48-30'. Strip the 'C.O.'
   suffix and trim so both map to the same code (e.g. '48-30'). #}
{% macro normalize_ordinance(col) %}
    NULLIF(TRIM(REPLACE(REPLACE({{ col }}, 'C.O.', ''), 'c.o.', '')), '')
{% endmacro %}
