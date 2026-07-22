# 06 · ref(), the DAG & node selection

## ref(): one function, three superpowers

```sql
select * from {{ ref('stg_orders') }}
```

compiles to `"jaffle_shop"."dev_staging"."stg_orders"` — and while doing so:

1. **resolves the environment** — same code compiles to `dev_staging` for
   you, `staging` for prod, because ref respects target + schema config;
2. **declares a dependency edge** — dbt now knows `stg_orders` must build
   first, and parallelizes what's independent (up to `threads`);
3. **feeds every downstream feature** — lineage docs, `state:modified+`,
   `--defer`, exposures, impact analysis.

Hardcoding a table name instead of `ref()`/`source()` still runs — and
silently breaks all three. Treat it as a bug in review.

## The DAG mindset

A dbt project is a **directed acyclic graph**; a run is a topological
traversal of it. This repo's DAG (draw it live in notebook
[08](../notebooks/08_artifacts_and_dag.ipynb), or `make docs` → lineage tab):

```
sources ─▶ staging ─▶ intermediate ─▶ marts ─▶ exposure
seeds ───▶─┘              (ephemeral inlined)
snapshots (from sources)
```

Cycles are compile errors. If model A needs B and B needs A, the shared
piece wants to be a third model upstream of both.

## Node selection: talking about pieces of the DAG

Every command takes `--select` / `--exclude`. The syntax compounds:

| syntax | selects |
|---|---|
| `dbt build -s stg_orders` | one node |
| `-s stg_orders+` | it and all descendants |
| `-s +dim_customers` | it and all ancestors |
| `-s +fct_orders+` | its whole lineage both ways |
| `-s stg_orders+2` | descendants at most 2 edges away |
| `-s @stg_orders` | descendants **plus their other ancestors** (build a subtree correctly) |
| `-s staging` | folder (path) selection |
| `-s tag:nightly` | by `+tags` config |
| `-s config.materialized:incremental` | by config value |
| `-s source:shop_backend+` | everything downstream of a source |
| `-s resource_type:seed` / `test_type:unit` | by kind |
| `-s state:modified+` | changed vs a saved manifest → [docs/16](16_state_defer_ci.md) |
| `-s result:error+ --state target/` | retry what failed last time |

Set logic: space = union, comma = intersection.

```bash
dbt ls -s "staging,config.materialized:view"   # staging AND views
dbt build -s stg_orders fct_orders             # union
```

`dbt ls` is the dry-run: it prints what a selector matches without running
anything. Use it before any surgical build.

### Try these against this repo

```bash
make dbt-ls                                        # everything
docker compose exec -w /workspace/jaffle_shop workbench \
  dbt ls -s +exposure:revenue_notebook --resource-type model
docker compose exec -w /workspace/jaffle_shop workbench \
  dbt build -s @fct_orders
```

## YAML selectors: named, reviewed, reusable

Complex selections belong in
[selectors.yml](../jaffle_shop/selectors.yml), not in a wiki page of shell
one-liners:

```yaml
selectors:
  - name: daily_marts
    description: Marts plus everything upstream.
    definition:
      method: path
      value: models/marts
      parents: true
```

```bash
dbt build --selector daily_marts
```

Selectors compose union/intersection/difference trees in YAML and show up in
`dbt ls --selector`. Production schedulers should invoke selectors, so the
definition of "the nightly run" is version-controlled.

## How dbt "knows" the graph: parsing

At startup dbt parses every file into `target/manifest.json` (the DAG,
configs, docs — everything; [docs/17](17_debugging_and_performance.md)).
Jinja makes parsing nontrivial, so dbt caches partial parse state in
`target/partial_parse.msgpack`; changes to files reparse only what's
affected. If weirdness strikes after upgrades or env-var changes:
`dbt parse --no-partial-parse`.

---
Next: [07 · Testing](07_testing.md).
