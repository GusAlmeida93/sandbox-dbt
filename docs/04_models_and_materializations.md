# 04 · Models & materializations

## A model is a SELECT

One `.sql` file under `models/` = one model = one `SELECT` statement. You
never write DDL or DML — dbt wraps your SELECT in whatever statements the
chosen **materialization** requires, per adapter. That inversion is dbt's
core trick: *declare the result, let dbt manage the lifecycle*.

```sql
-- models/staging/stg_orders.sql  →  becomes relation dev_staging.stg_orders
select
    id as order_id,
    lower(status) as status,
    ...
from {{ source('shop_backend', 'raw_orders') }}
```

The model's **name** (filename) becomes the relation name; its schema comes
from configuration ([docs/15](15_advanced_config.md)); references to it are
always `{{ ref('stg_orders') }}`, never a hardcoded name.

## The five materializations (all live in this repo)

| materialization | dbt emits (Postgres) | when to use | example here |
|---|---|---|---|
| `view` | `create view as select ...` | default for cheap/light transforms; always fresh | all of `staging/` |
| `table` | `create table as select ...` (staged + atomic swap) | queried often, computed once per run | `dim_customers` |
| `ephemeral` | nothing — inlined as a CTE into consumers | shared logic too small for a relation | `int_order_items_enriched` |
| `incremental` | first run: table; then insert/merge/delete+insert of new rows | big tables where full rebuilds hurt | `fct_orders`, `fct_events` |
| `materialized view` | `create materialized view` / `refresh` | precomputed + warehouse-managed refresh | `agg_daily_revenue` |

Run notebook [02](../notebooks/02_models_materializations.ipynb) to see each
one land in `pg_class` with a different `relkind` — and to see the ephemeral
model *not* land anywhere.

### view vs table: the default decision

Views cost nothing to build and are always up to date, but every consumer
re-executes the logic. Tables pay the compute once per `dbt run` and read
fast. The standard shape (this repo follows it): **staging = views, marts =
tables**, promote to incremental only with evidence
([docs/11](11_incremental_deep_dive.md)).

### Ephemeral: powerful, use sparingly

`int_order_items_enriched` is `materialized='ephemeral'` — every model that
`ref()`s it gets its SQL pasted in as `__dbt__cte__int_order_items_enriched`.
Look at `target/compiled/jaffle_shop/models/marts/fct_orders.sql` after a
compile: the CTE is right there. Costs to know about:

- recomputed in *every* consumer (both `fct_orders` and `fct_order_items` here)
- can't be queried, can't be a `relationships` target, hard to debug
- introspective macros (e.g. `dbt_utils.get_column_values`) refuse to run on it

### Materialized view: the warehouse-native cousin

`agg_daily_revenue` shows the `materialized_view` materialization: dbt
creates it once, then issues `REFRESH MATERIALIZED VIEW` on subsequent runs.
`on_configuration_change: apply|continue|fail` governs definition changes.
Compared to a dbt `table`, refresh happens *without* re-sending the SQL — and
on warehouses with real auto-refresh (Snowflake dynamic tables, BigQuery MVs)
this family shifts scheduling into the warehouse itself.

## Where the SQL you wrote actually goes

After any run/compile, `target/` holds the receipts:

- `target/compiled/.../<model>.sql` — your SELECT after Jinja rendering
- `target/run/.../<model>.sql` — wrapped in materialization DDL

When a model misbehaves, read those files first — they are exactly what the
warehouse executed. (`make dbt-compile` regenerates them without running.)

## Configuring materializations

Three levels, most specific wins ([docs/03](03_project_structure.md)):

```yaml
# 1. dbt_project.yml — folder defaults
models:
  jaffle_shop:
    staging:
      +materialized: view
```

```yaml
# 2. properties yml — per model
models:
  - name: dim_products
    config:
      materialized: table
```

```sql
-- 3. in the model file — wins
{{ config(materialized='incremental', unique_key='order_id') }}
```

House style: folder-level defaults for the common case; `config()` blocks
only where a model genuinely differs (this repo: the two incrementals and
the MV).

## Model naming conventions (they carry meaning)

- `stg_<source>__<entity>` or `stg_<entity>` — staging, 1:1 with a source
- `int_<what>` — intermediate building blocks
- `dim_<entity>` / `fct_<event>` — marts: dimensions describe, facts record
- `agg_<grain>` — pre-aggregated rollups

More in [docs/18](18_best_practices_and_cheatsheet.md).

---
Next: [05 · Sources, seeds & freshness](05_sources_seeds_freshness.md) —
where models get their inputs.
