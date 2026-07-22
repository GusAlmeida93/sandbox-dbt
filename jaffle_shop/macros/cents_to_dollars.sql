{% macro cents_to_dollars(column_name, precision=2) -%}
{#- The simplest kind of macro: a reusable SQL snippet with arguments.
    Business rules like "money is stored in cents" should live in exactly
    one place -- change the conversion here and every model using it follows. -#}
    ({{ column_name }} / 100.0)::numeric(16, {{ precision }})
{%- endmacro %}
