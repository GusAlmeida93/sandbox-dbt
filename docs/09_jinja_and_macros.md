# 09 · Jinja & macros

Every `.sql` file in a dbt project is a **Jinja template that renders to
SQL**. `ref()` is a macro. Materializations are macros. Understanding the
two-phase model — *render first, execute second* — unlocks everything
advanced in dbt.

```
your .sql (Jinja+SQL) ──render (Jinja)──▶ pure SQL ──execute──▶ warehouse
                                          │
                                          └── written to target/compiled/
```

## Jinja in 90 seconds

```
{{ expression }}     prints a value into the SQL
{% statement %}      control flow: set / if / for -- prints nothing
{# comment #}        rendered away entirely
```

```sql
{% set methods = ['credit_card', 'pix'] %}
select
  order_id
  {% for m in methods %}
  , sum(case when payment_method = '{{ m }}' then amount end) as {{ m }}_amount
  {% endfor %}
from {{ ref('stg_payments') }}
group by 1
```

The rendered SQL contains no Jinja — the warehouse never knows it existed.

## The playground: `dbt compile`

```bash
dbt compile --inline "select {{ cents_to_dollars('1234') }} as x"   # any snippet
dbt compile -s int_order_payments                                    # then read target/compiled/
```

Notebook [05](../notebooks/05_jinja_and_macros.ipynb) drives both
programmatically. Make "compile, then read the SQL" your reflex for
debugging anything Jinja.

## Macros: functions that return SQL

[macros/cents_to_dollars.sql](../jaffle_shop/macros/cents_to_dollars.sql):

```sql
{% macro cents_to_dollars(column_name, precision=2) -%}
    ({{ column_name }} / 100.0)::numeric(16, {{ precision }})
{%- endmacro %}
```

Business rules ("money is integer cents") live in exactly one place. The
other macros in this repo show the spectrum:

| macro | demonstrates |
|---|---|
| `cents_to_dollars` | plain reusable snippet with defaults |
| `limit_in_dev` | branching on `target.name` + `var()` |
| `generate_schema_name` | overriding dbt built-in behavior ([docs/15](15_advanced_config.md)) |
| `drop_old_relations` | `run_query()`, the `graph` object, run-operation ([docs/14](14_hooks_operations_grants.md)) |
| audit hooks | macros as hook payloads |

## The context: what you can use inside the braces

Always available, most-used first: `ref()`, `source()`, `config()`, `var()`,
`env_var()`, `target` (`.name/.schema/...`), `this` (the current model's
relation — see `fct_orders`' incremental filter), `is_incremental()`,
`adapter` (`.dispatch`, `.get_columns_in_relation`...), `run_query()`,
`log()`, `graph`, `invocation_id`, `flags`, `modules.datetime` /
`modules.re`.

### Two-phase execution and `execute`

Parsing renders every file *before* anything runs, with `execute = false`
and `run_query` unavailable; at execution time templates render again with
`execute = true`. Hence the guard you'll see in every introspective macro:

```sql
{% if execute %}
    {% set results = run_query(query) %}   -- returns an Agate table
    {% for row in results.rows %} ... {% endfor %}
{% endif %}
```

`int_order_payments` leans on this via `dbt_utils.get_column_values`: it
queries the seed *at compile time* and writes the pivot columns into the
SQL. Dynamic SQL from data — the signature dbt move.

## War stories from building this repo (all still in the code)

1. **SQL comments are still Jinja.** A header comment in `dim_customers.sql`
   that *mentioned* `config()` with braces executed it and failed the parse
   with "Invalid inline model config". Comments are rendered. Escape hatch:
   `{% raw %} ... {% endraw %}`.
2. **Whitespace control can eat your SQL.** A set block written with
   minus-delimiters directly after a `--` comment line glued `select` onto
   the comment, commenting it out — "syntax error at or near order_id",
   nowhere near the actual bug. Default to plain `{% ... %}`; blank lines in
   compiled SQL are free, missing newlines are not.
3. **Macro namespaces**: package macros are called qualified
   (`dbt_utils.get_column_values`), your own are global. A project macro
   named like a built-in *overrides it project-wide* — that's a feature
   (`generate_schema_name`) and a footgun (accidentally shadowing `ref`).

## Taste: when NOT to use Jinja

SQL first, Jinja when it pays for itself. A `for` loop that saves 4 lines
costs more in readability than it saves in typing; a `for` loop that
maintains 15 pivot columns from a seed is pure win. If logic can live in SQL
(CASE, joins), keep it in SQL — Jinja is for what SQL *can't* express:
repetition across columns/models, environment awareness, compile-time
introspection.

---
Next: [10 · Snapshots](10_snapshots.md) — history for data that forgets.
