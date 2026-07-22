# 18 · Best practices, governance & command cheatsheet

The distilled version of how experienced teams structure dbt projects —
this repo practices what it preaches — plus the reference card.

## Project structure (the dbt Labs shape, and why)

```
staging      1:1 with source tables. Rename, cast, lightly clean. Views.
             THE ONLY LAYER THAT TOUCHES source(). stg_<entity>.
intermediate Reusable building blocks between staging and marts. int_<what>.
marts        What analysts consume: dim_ / fct_ / agg_. Tables (or better).
```

The load-bearing rules:

- **Sources are quarantined in staging.** Every raw column name/type quirk
  is handled exactly once; everything downstream speaks the clean
  vocabulary. Grep this repo: `source(` appears only under
  `models/staging/` (and in snapshots, which capture raw history —
  [docs/10](10_snapshots.md)).
- **Dependencies flow one way**: staging → intermediate → marts. No mart
  refs raw; no staging refs a mart; cycles are design smells before they're
  compile errors.
- **Grain is sacred**: every model's docs state it ("one row per ...");
  `unique`+`not_null` on the grain column(s) enforce it
  ([docs/07](07_testing.md)).

## Style, condensed

SQL: lowercase keywords; CTEs over subqueries (import CTEs first — see any
staging model here); one idea per CTE; explicit column lists in marts
(`select *` is fine mid-pipeline, never at the boundary). Naming:
`stg_/int_/dim_/fct_/agg_` prefixes; `_id` for keys, `_at` for timestamps
(`ordered_at`), `is_/has_` for booleans; plural table names. YAML: one
properties file per directory (`_staging__models.yml` pattern), tests+docs
live with the layer they describe. (Linters exist — sqlfluff with the dbt
templater is the standard — left out of this sandbox to keep the toolchain
lean; adopt it the moment two humans share a repo.)

## Governance: contracts, versions, groups

The 1.5+ toolkit for "this model is an API someone depends on":

- **Contracts** — `contract: {enforced: true}` + full column/type spec;
  dbt refuses to build if the SQL drifts from the declaration.
  **Live in this repo**: `dim_customers`
  ([_marts__models.yml](../jaffle_shop/models/marts/_marts__models.yml)) —
  rename a column in the SQL and watch the build fail *before* touching the
  warehouse. Constraints (`not_null`) even land in the DDL.
- **Model versions** — `versions:` lets `dim_customers_v2` coexist with v1
  while consumers migrate; `ref('dim_customers', v=1)` pins.
- **Groups & access** — `group:` + `access: private|protected|public`
  restricts who may ref() a model; public models are your stable API.

Adopt in that order, and only for models with real downstream consumers —
governance on a personal sandbox is ceremony.

## Operating habits that age well

Daily: `dbt build` (not bare `run` — tests gate), work off `--select
state:modified+` locally too. Per PR: docs updated with the model, CI green
([docs/16](16_state_defer_ci.md)). Scheduled: source freshness separate
from builds; snapshots early and often. Quarterly: dependency bumps
(`dbt deps --upgrade`, behavior flags — [docs/15](15_advanced_config.md)),
prune dead models (`drop_old_relations` dry run tells you what's orphaned).

## Command cheatsheet

### Core lifecycle
```bash
dbt debug                        # config + connection check
dbt deps                         # install packages
dbt seed                         # load CSVs
dbt run                          # build models
dbt test                         # run tests
dbt build                        # seed+run+test+snapshot, DAG order  ← default
dbt snapshot                     # capture SCD-2 history
dbt compile                      # render Jinja only
dbt docs generate && dbt docs serve
dbt clean                        # rm target/ dbt_packages/ logs/
```

### Selection (compose freely — [docs/06](06_refs_dag_selection.md))
```bash
-s stg_orders            -s stg_orders+          -s +dim_customers
-s @stg_orders           -s staging              -s tag:nightly
-s source:shop_backend+  -s test_type:unit       -s config.materialized:incremental
-s state:modified+ --state PATH                  -s result:error+ --state target
--exclude fct_events     --selector daily_marts
```

### Incremental & state
```bash
dbt build --full-refresh                       # rebuild incrementals
dbt run -s fct_events --event-time-start "2026-07-04" --event-time-end "2026-07-05"
dbt build -s state:modified+ --defer --state ./prod-manifest
```

### Debugging
```bash
dbt --debug run -s my_model      # verbose console
dbt compile --inline "..."       # Jinja REPL
dbt show -s my_model --limit 5   # peek at results
dbt run-operation my_macro --args '{k: v}'
tail -f logs/dbt.log
```

### Flags everyone eventually needs
```bash
--target prod        --vars '{k: v}'      --threads 8
--fail-fast          --warn-error         --no-partial-parse
--profiles-dir DIR   --project-dir DIR    --log-format json
```

### This repo's wrappers
```bash
make init | up | down | nuke          make data | data-day DAY=n | reset-all
make dbt-build | dbt-<anything>       make docs | db-shell | notebook
make verify                           # the full end-to-end proof
LOCAL=1 make dbt-build                # hybrid mode (dbt on host)
```

## Where to go from here

Ideas this sandbox is deliberately one step short of — each is a natural
next exercise: rebuild `dim_customers` from the snapshot (point-in-time
dimension); add sqlfluff + a lint CI job; store the manifest from main and
make CI slim ([docs/16](16_state_defer_ci.md)); write a semantic model YAML
for revenue and query it with the MetricFlow CLI
([docs/13](13_semantic_layer_and_analyses.md)); swap Postgres for DuckDB in
a second profile target and feel how portable the project is.

---
*End of the curriculum. The [README](../README.md) has the map.*
