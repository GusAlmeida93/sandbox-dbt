{% test positive_value(model, column_name) %}
{#-
    A CUSTOM GENERIC test: works like the built-in `unique`/`not_null` -- put
    `- positive_value` under any column in a properties file. dbt passes in
    the model and column automatically.

    A test is just a SELECT that returns the BAD rows: zero rows = pass.
-#}

select *
from {{ model }}
where {{ column_name }} is not null
  and {{ column_name }} <= 0

{% endtest %}
