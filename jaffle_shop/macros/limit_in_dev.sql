{% macro limit_in_dev(row_limit=1000) -%}
{#- Target-aware Jinja: emit a LIMIT clause only in the dev target, and only
    when explicitly asked for via a var. Real projects use this pattern (often
    with a date filter instead of LIMIT) to keep dev runs fast and cheap:

        dbt run -s stg_events --vars '{limit_dev_rows: true}'

    `target` (which profile output is active) and `var()` are both available
    in every model and macro. -#}
    {%- if target.name == 'dev' and var('limit_dev_rows', false) %}
    limit {{ row_limit }}
    {%- endif -%}
{%- endmacro %}
