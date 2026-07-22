# sandbox-dbt

A hands-on environment for learning **dbt** from zero to advanced — a real,
runnable analytics project you can break and rebuild, plus a written
curriculum and interactive notebooks that walk every concept.

```
 scripts/generate_data.py      jaffle_shop/ (dbt)              consumers
┌───────────────────────┐   ┌──────────────────────────┐   ┌──────────────────┐
│ synthetic EL tool:    │   │ staging ─▶ intermediate  │   │ JupyterLab :8888 │
│ customers, orders,    ├──▶│    ─▶ marts + snapshots  ├──▶│ dbt docs  :8081  │
│ payments, events ...  │   │    + tests + docs        │   │ Adminer   :8080  │
└───────────────────────┘   └──────────────────────────┘   └──────────────────┘
        raw schema                PostgreSQL 17  (Docker)
```

Everything runs locally in Docker (bound to `127.0.0.1`), with Python
managed by [uv](https://docs.astral.sh/uv/). dbt-core is pinned to the
mature **1.10.x** line with `dbt-postgres`.

## Quickstart

Prereqs: Docker Desktop, [uv](https://docs.astral.sh/uv/getting-started/installation/), make.

```bash
make init
```

That's it — it copies `.env`, builds the image, starts Postgres + JupyterLab
+ Adminer, installs dbt packages, loads two days of synthetic data, and runs
the first `dbt build`. Then:

| open | at |
|---|---|
| **JupyterLab** (start with notebook 01) | http://localhost:8888/?token=dbt |
| **Adminer** (browse the warehouse) | http://localhost:8080 — server `postgres`, user/pass/db `dbt`/`dbt`/`jaffle_shop` |
| **dbt docs** (after `make docs`) | http://localhost:8081 |

Daily commands: `make help` lists everything (`make dbt-build`, `make
data-day DAY=4`, `make db-shell`, `make verify`, ...). Every dbt/data target
also runs on the host instead of Docker with `LOCAL=1` (hybrid mode — see
[docs/02](docs/02_environment_setup.md)).

## The curriculum

**Docs** (read in order, or dip in — each stands alone):

| # | doc | # | doc |
|---|---|---|---|
| 01 | [What is dbt?](docs/01_what_is_dbt.md) | 10 | [Snapshots (SCD-2)](docs/10_snapshots.md) |
| 02 | [Environment setup](docs/02_environment_setup.md) | 11 | [Incremental deep dive](docs/11_incremental_deep_dive.md) |
| 03 | [Project structure & profiles](docs/03_project_structure.md) | 12 | [Packages](docs/12_packages.md) |
| 04 | [Models & materializations](docs/04_models_and_materializations.md) | 13 | [Semantic layer & analyses](docs/13_semantic_layer_and_analyses.md) |
| 05 | [Sources, seeds & freshness](docs/05_sources_seeds_freshness.md) | 14 | [Hooks, operations & grants](docs/14_hooks_operations_grants.md) |
| 06 | [ref(), DAG & selection](docs/06_refs_dag_selection.md) | 15 | [Advanced configuration](docs/15_advanced_config.md) |
| 07 | [Testing](docs/07_testing.md) | 16 | [State, defer & CI](docs/16_state_defer_ci.md) |
| 08 | [Documentation & exposures](docs/08_documentation_and_exposures.md) | 17 | [Debugging & performance](docs/17_debugging_and_performance.md) |
| 09 | [Jinja & macros](docs/09_jinja_and_macros.md) | 18 | [Best practices & cheatsheet](docs/18_best_practices_and_cheatsheet.md) |

**Notebooks** (each pairs with a doc; they run dbt live, break things on
purpose, and clean up after themselves):

1. [First dbt run](notebooks/01_first_dbt_run.ipynb) — the whole stack, `!dbt` vs `dbtRunner`
2. [Materializations](notebooks/02_models_materializations.ipynb) — view/table/ephemeral/MV in `pg_class`
3. [Sources & freshness](notebooks/03_sources_seeds_freshness.ipynb) — break and repair `dbt source freshness`
4. [Testing](notebooks/04_testing.ipynb) — inject bad rows, inspect `store_failures`, unit tests
5. [Jinja & macros](notebooks/05_jinja_and_macros.ipynb) — `compile --inline`, pivots, the audit log
6. [Incremental models](notebooks/06_incremental_models.ipynb) — high-water marks, microbatch backfills
7. [Snapshots](notebooks/07_snapshots.ipynb) — SCD-2 versions appearing live
8. [Artifacts & DAG](notebooks/08_artifacts_and_dag.ipynb) — draw the DAG from `manifest.json`, `state:modified`

## What the dbt project demonstrates

The [jaffle_shop/](jaffle_shop/) project is small (14 models) but exercises
essentially every dbt feature: all the materializations (view, table,
ephemeral, incremental `delete+insert`, incremental **microbatch**,
materialized view), sources with freshness rules, seeds, YAML-defined
snapshots (timestamp + check strategies), an enforced **model contract**,
generic/singular/custom/package **tests** plus a **unit test**, doc blocks
and an exposure, macros from trivial to `generate_schema_name`, audit hooks,
`run-operation`, YAML selectors, and dev/prod targets. Every file is
commented as teaching material — including the real bugs hit while building
it (Jinja-in-comments, whitespace control, YAML float gotchas), left in as
warnings to future travelers.

The synthetic data is **deterministic** (any day N is byte-identical on
every machine) yet **mutable** (order statuses advance, customers move) —
so incremental models and snapshots have something real to do. `make
data-day DAY=4` advances business time by a day.

## Repo layout

```
docker-compose.yml, Dockerfile    the environment (Postgres 17 + workbench + Adminer)
pyproject.toml, uv.lock           Python deps, uv-managed (Python 3.12)
Makefile                          all the buttons (make help)
scripts/generate_data.py          deterministic synthetic EL loader
jaffle_shop/                      the dbt project
docs/                             the 18-part curriculum
notebooks/                        the 8 interactive tutorials
.github/workflows/ci.yml          teaching example: dbt build in GitHub Actions
```

## Verifying everything works

```bash
make verify
```

Clean-slate end-to-end: resets the warehouse, reloads data, full `dbt
build`, advances a day, rebuilds (incremental + snapshots), then executes
all 8 notebooks headlessly. Green means every example in this repo runs.

Notebooks are committed with outputs stripped (`make nb-clean` before
committing changes).
