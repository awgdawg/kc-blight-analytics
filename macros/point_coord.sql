{# Extract a coordinate from a Socrata point/location column stored as a JSON
   string: {"type":"Point","coordinates":[lng, lat]}. index 0 = lng, 1 = lat. #}
{% macro point_coord(point_col, index) %}
    SAFE_CAST(JSON_EXTRACT_SCALAR({{ point_col }}, '$.coordinates[{{ index }}]') AS FLOAT64)
{% endmacro %}
