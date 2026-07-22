{#-
    Project hooks (configured in dbt_project.yml):
      on-run-start -> create_audit_log()
      on-run-end   -> log_run_results(results)

    Together they maintain audit.dbt_run_log: one row per dbt invocation with
    node counts and outcomes. Query it after any run:

        select * from audit.dbt_run_log order by finished_at desc;

    The macros RETURN SQL text -- dbt executes whatever the hook renders to.
-#}

{% macro create_audit_log() %}
    {# on-run-start hooks fire BEFORE dbt creates any schemas, so this must
       create its own -- a classic gotcha #}
    create schema if not exists audit;
    create table if not exists audit.dbt_run_log (
        invocation_id text,
        target_name   text,
        command       text,
        started_at    timestamptz,
        finished_at   timestamptz,
        node_count    integer,
        ok_count      integer,
        error_count   integer
    );
{% endmacro %}


{% macro log_run_results(results) %}
    {# `results` only exists in the on-run-end context: one entry per executed
       node, each with .status ('success'/'pass'/'error'/'fail'/'warn'/'skipped') #}
    {%- if execute and results | length > 0 -%}
        {%- set ok = results
                | selectattr('status', 'in', ['success', 'pass', 'warn'])
                | list | length -%}
        {%- set errors = results
                | selectattr('status', 'in', ['error', 'fail'])
                | list | length -%}
        insert into audit.dbt_run_log values (
            '{{ invocation_id }}',
            '{{ target.name }}',
            '{{ flags.WHICH }}',
            '{{ run_started_at }}'::timestamptz,
            now(),
            {{ results | length }},
            {{ ok }},
            {{ errors }}
        )
    {%- endif -%}
{% endmacro %}
