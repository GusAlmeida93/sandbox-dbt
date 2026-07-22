{% macro drop_old_relations(dry_run=true) %}
{#-
    An OPERATION: a macro you invoke directly with `dbt run-operation`, not
    from a model. This one finds relations in your target schemas that the
    project no longer produces (renamed/deleted models leave orphans behind,
    because dbt never drops what it stops managing).

        dbt run-operation drop_old_relations                          # dry run
        dbt run-operation drop_old_relations --args '{dry_run: false}'  # actually drop

    Teaching points inside: `execute` guard, run_query() returning an Agate
    table, the `graph` context variable, and log(). See docs/09 and /14.
-#}
    {% if execute %}

        {# every relation the CURRENT project knows how to build #}
        {% set managed = [] %}
        {% for node in graph.nodes.values() %}
            {% if node.resource_type in ['model', 'seed', 'snapshot', 'test'] %}
                {% do managed.append((node.schema ~ '.' ~ (node.alias or node.name)) | lower) %}
            {% endif %}
        {% endfor %}

        {% set find_relations %}
            select
                table_schema,
                table_name,
                case table_type when 'VIEW' then 'view' else 'table' end as rel_type
            from information_schema.tables
            where table_schema like '{{ target.schema }}%'
        {% endset %}

        {% set results = run_query(find_relations) %}

        {% for row in results.rows %}
            {% set fqn = (row['table_schema'] ~ '.' ~ row['table_name']) | lower %}
            {% if fqn not in managed %}
                {% if dry_run %}
                    {{ log('would drop: ' ~ fqn ~ ' (' ~ row['rel_type'] ~ ')', info=true) }}
                {% else %}
                    {% do run_query('drop ' ~ row['rel_type'] ~ ' if exists ' ~ fqn ~ ' cascade') %}
                    {{ log('dropped: ' ~ fqn, info=true) }}
                {% endif %}
            {% endif %}
        {% endfor %}

    {% endif %}
{% endmacro %}
