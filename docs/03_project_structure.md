# 03 · Project structure, dbt_project.yml & profiles

Two YAML files define a dbt project's identity: **dbt_project.yml** (WHAT the
project is) and **profiles.yml** (WHERE it runs). Keep that split in your
head and the rest of the configuration story falls into place.

## The project tree

```
jaffle_shop/
├── dbt_project.yml        # project identity + defaults (required)
├── profiles.yml           # connection config (usually lives in ~/.dbt/!)
├── packages.yml           # dependencies        → docs/12
├── package-lock.yml       # resolved dep pins (committed)
├── selectors.yml          # named node selections → docs/06
├── models/
│   ├── staging/           # 1:1 with sources; rename/cast/clean
│   ├── intermediate/      # reusable building blocks
│   └── marts/             # facts & dimensions analysts consume
├── seeds/                 # small static CSVs    → docs/05
├── snapshots/             # SCD-2 history        → docs/10
├── macros/                # reusable Jinja       → docs/09
├── tests/                 # singular + custom generic tests → docs/07
├── analyses/              # compiled-not-run scratch SQL → docs/13
├── dbt_packages/          # installed packages (gitignored)
├── logs/                  # dbt.log (gitignored)
└── target/                # compiled SQL + artifacts (gitignored)
```

## dbt_project.yml, key by key

[The real file](../jaffle_shop/dbt_project.yml) is commented line-by-line;
the highlights:

```yaml
name: 'jaffle_shop'              # namespace for configs, docs, packages
require-dbt-version: ">=1.10.0,<2.0.0"   # refuse to run on the wrong dbt
profile: 'jaffle_shop'           # which entry in profiles.yml to use

model-paths: ["models"]          # where dbt looks for each resource type
seed-paths: ["seeds"]            # (these are the defaults, spelled out)

vars:                            # project-wide variables: {{ var('...') }}
  training_start_date: "2026-07-01"

flags:                           # global behavior flags (1.8+ lives here)
  send_anonymous_usage_stats: false

on-run-start: ...                # hooks → docs/14

models:                          # config applied by FOLDER hierarchy
  jaffle_shop:                   #   (must match `name`)
    staging:
      +materialized: view        # everything in models/staging/ = view
      +schema: staging           # custom schema → docs/15
    marts:
      +materialized: table
      +schema: marts
```

The `+` prefix marks a **config** (as opposed to a subfolder name). Folder
level config is how you say "staging is views, marts are tables" once,
instead of per-file.

### Config precedence (memorize this)

```
dbt_project.yml   <   properties .yml (config:)   <   config() in the model
   (folder-wide)         (per model)                    (wins)
```

`dim_customers` in this repo demonstrates it: materialization comes from
dbt_project.yml, its contract from `_marts__models.yml`, and nothing from the
model file — while `fct_orders` overrides everything locally with `config()`.

## profiles.yml: targets, threads, and why it's env-var driven

A **profile** holds one or more **targets** (named connection configs); you
pick one with `--target` (default: the `target:` key).

```yaml
jaffle_shop:
  target: dev              # default
  outputs:
    dev:
      type: postgres
      host: "{{ env_var('DBT_HOST', 'localhost') }}"
      port: "{{ env_var('DBT_PORT', '5432') | as_number }}"
      schema: dev          # base schema for this developer
      threads: 4
    prod:
      schema: analytics
      threads: 8
```

Worth internalizing:

- **profiles.yml normally lives in `~/.dbt/` and is never committed** — it
  holds credentials. This repo commits it *because* every value is an
  `env_var()` with toy defaults (see the file's header comment). That pattern
  — env-var-driven profiles — is also exactly what you want in CI.
- **Resolution order** for finding profiles.yml: `--profiles-dir` flag →
  `DBT_PROFILES_DIR` env var → the current working directory → `~/.dbt/`.
  The workbench container sets `DBT_PROFILES_DIR=/workspace/jaffle_shop`.
- **`env_var('X', 'default')`** reads an environment variable at parse time;
  it returns strings, hence `| as_number` for the port (a profiles-only
  filter).
- **threads** = how many DAG nodes dbt runs concurrently. More threads ≠
  faster warehouse; it just keeps more queries in flight. 4-8 is typical.
- **targets are the environment switch**: `dbt build --target prod` changes
  schema, thread count, and anything keyed off `target.name` in Jinja (this
  repo's `generate_schema_name` and `limit_in_dev` both do). Try:

```bash
make dbt-ls LOCAL=1                       # dev: dev_staging / dev_marts
cd jaffle_shop && uv run dbt ls --target prod --select stg_orders \
  --output json --output-keys "name schema"   # prod: staging
```

## Where state lives

| path | contents | committed? |
|---|---|---|
| `target/` | compiled SQL, run artifacts (manifest.json, ...) | no |
| `logs/dbt.log` | debug-level log of every invocation | no |
| `dbt_packages/` | installed packages | no |
| `package-lock.yml` | resolved package versions | **yes** |
| `.user.yml` | anonymous stat cookie dbt drops next to a local profiles.yml | no |

---
Next: [04 · Models & materializations](04_models_and_materializations.md) —
what dbt actually does with your SELECT.
