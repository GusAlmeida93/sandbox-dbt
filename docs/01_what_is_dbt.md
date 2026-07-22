# 01 · What is dbt?

dbt (data build tool) is a framework for **transforming data that is already in
your warehouse** using SQL, with the practices of software engineering wrapped
around it: version control, testing, documentation, modularity, environments,
and CI.

## ELT, and the job dbt does

The modern data stack splits data movement into:

```
 Extract+Load                Transform                    Consume
┌─────────────┐        ┌─────────────────────┐        ┌──────────────┐
│ Fivetran,   │        │        dbt          │        │ BI tools,    │
│ Airbyte,    │  ───▶  │  raw ──▶ staging    │  ───▶  │ notebooks,   │
│ custom code │        │      ──▶ marts      │        │ ML, apps     │
└─────────────┘        └─────────────────────┘        └──────────────┘
   land raw data          SQL SELECTs, run             read the marts
   in the warehouse       IN the warehouse
```

Older ETL transformed data *before* loading it, on separate infrastructure.
ELT loads raw data first and transforms **inside** the warehouse, because
modern warehouses are cheap, elastic compute. dbt is the "T": it compiles your
SQL and orchestrates it *in* the warehouse. dbt itself never stores or
processes rows — in this sandbox, dbt sends SQL to Postgres and Postgres does
all the work.

In this repo, `scripts/generate_data.py` plays the EL role (landing the `raw`
schema), and everything under [jaffle_shop/](../jaffle_shop/) is the T.

## The core mental model

Four ideas carry most of dbt:

1. **A model is one `SELECT` statement in a `.sql` file.** No DDL, no
   `INSERT` — you declare *what* the table should contain, and dbt wraps it in
   the right `CREATE TABLE AS` / `CREATE VIEW` / `MERGE` (the
   *materialization*). See [docs/04](04_models_and_materializations.md).

2. **`ref()` builds a DAG.** Models reference each other with
   `{{ ref('stg_orders') }}` instead of hardcoded table names. From those
   references dbt derives a dependency graph, runs nodes in the right order,
   parallelizes independent branches, and knows exactly what is downstream of
   any change. See [docs/06](06_refs_dag_selection.md).

3. **Everything is text, so everything is Jinja.** Models are templates:
   loops, conditionals, macros, and environment-aware logic generate SQL at
   compile time. See [docs/09](09_jinja_and_macros.md).

4. **Quality is declared next to the code.** Tests and documentation live in
   YAML beside the models; `dbt build` refuses to build downstream of a failed
   test. See [docs/07](07_testing.md).

## What dbt is not

- **Not an orchestrator.** dbt runs when something invokes it (cron, Airflow,
  Dagster, dbt Cloud, your terminal). It orders its own nodes, but does not
  schedule itself.
- **Not an EL tool.** It will not fetch data from APIs or databases into the
  warehouse (the small exception: [seeds](05_sources_seeds_freshness.md), for
  tiny static lookup files).
- **Not a BI tool.** It prepares tables for consumption; something else reads
  them (declare those consumers as [exposures](08_documentation_and_exposures.md)).

## Analytics engineering

The role dbt created a name for: applying software-engineering discipline to
analytics. The shift it replaces is real and painful — a world of unversioned
2,000-line stored procedures, `final_v3_REALLY_FINAL.sql`, and dashboards
nobody trusts. With dbt, transformations are:

- **modular** — small named models building on each other, not one giant query
- **reviewed** — plain text files, so pull requests work
- **tested** — assertions run on every build
- **documented** — descriptions compile into a browsable site with lineage
- **reproducible** — anyone can rebuild the warehouse from source + raw data

## The dbt product landscape (as of mid-2026)

| thing | what it is | this repo |
|---|---|---|
| **dbt-core** | open-source Python engine + CLI | ✅ pinned `>=1.10,<1.11` |
| **adapters** | per-warehouse plugins (`dbt-postgres`, `dbt-snowflake`, ...) — versioned independently of core since 2024 | ✅ `dbt-postgres` |
| **dbt Cloud / dbt platform** | SaaS: scheduler, IDE, hosted docs, semantic layer serving, Fusion hosting | not used |
| **Fusion engine** | dbt Labs' next-gen Rust engine (faster parsing, live SQL comprehension). Strategic direction, but a separate CLI with its own adapter coverage | not used — dbt-core is the stable, fully-open choice for learning |

Everything you learn against dbt-core transfers: projects, models, tests,
Jinja, and YAML are the same language across all of them.

## Try it

```bash
make init        # one-shot: build, start, load data, dbt build
make notebook    # then open notebook 01
```

---
Next: [02 · Environment setup](02_environment_setup.md) — what `make init`
actually assembled.
