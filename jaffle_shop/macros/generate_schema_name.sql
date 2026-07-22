{% macro generate_schema_name(custom_schema_name, node) -%}
{#-
    THE most-overridden macro in real dbt projects.

    dbt calls this for every model to decide which schema it lands in. The
    built-in default is `<target.schema>_<custom_schema>` for EVERY target,
    which surprises everyone the first time: on prod you wanted the mart in
    `marts`, not `analytics_marts`.

    This override implements the pattern most teams actually want:

      target  +schema config   resulting schema
      ------  --------------   ----------------
      dev     (none)           dev
      dev     marts            dev_marts        <- namespaced per developer
      prod    (none)           analytics
      prod    marts            marts            <- clean names in production

    Try it:  dbt ls --target prod --output keys --output-keys "name schema"
-#}
    {%- set default_schema = target.schema -%}
    {%- if custom_schema_name is none -%}

        {{ default_schema }}

    {%- elif target.name == 'prod' -%}

        {{ custom_schema_name | trim }}

    {%- else -%}

        {{ default_schema }}_{{ custom_schema_name | trim }}

    {%- endif -%}
{%- endmacro %}
