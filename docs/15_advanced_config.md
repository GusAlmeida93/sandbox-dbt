# 15 · Advanced configuration

The configuration mechanics that separate "runs on my machine" from "runs
for a team": custom schemas, aliases, variables, environment switches, and
behavior flags.

## Custom schemas & generate_schema_name

Configs like `+schema: marts` don't name a schema directly — they feed a
macro. dbt's **built-in** rule:

```
<target.schema>_<custom_schema>     -- in EVERY target
```

So dev gives `dev_marts` (great — developers get namespaced sandboxes), but
prod gives `analytics_marts` (almost never what anyone wants). Hence the
most-copied override in the dbt world, included here as
[macros/generate_schema_name.sql](../jaffle_shop/macros/generate_schema_name.sql):

| target | `+schema:` | built-in default | this repo's override |
|---|---|---|---|
| dev | — | `dev` | `dev` |
| dev | `marts` | `dev_marts` | `dev_marts` |
| prod | — | `analytics` | `analytics` |
| prod | `marts` | `analytics_marts` | **`marts`** |

Verified live in this sandbox:

```bash
dbt ls --select dim_customers --output json --output-keys "name schema"                 # dev_marts
dbt ls --select dim_customers --target prod --output json --output-keys "name schema"  # marts
```

Sibling macros exist for `generate_database_name` and `generate_alias_name`
— same override pattern.

## Aliases: file name ≠ table name

Model files need unique names project-wide; the warehouse relation can
differ:

```yaml
models:
  - name: stg_orders_v2       # file / ref() name
    config:
      alias: stg_orders       # relation name in the warehouse
```

Use sparingly (renames-in-flight, reserved words, versioned migrations) —
every alias is a mapping someone must hold in their head.

## Variables: parameterize the project

```yaml
# dbt_project.yml
vars:
  training_start_date: "2026-07-01"
```

```sql
begin=var('training_start_date')                  -- fct_events config
{% if var('limit_dev_rows', false) %} ...         -- limit_in_dev macro
```

```bash
dbt run --vars '{limit_dev_rows: true}'           # CLI wins over project
```

Rules that keep vars sane: always give a default (`var('x', default)`) or
define it in the project file — a missing var is a compile error; keep the
count low (each is a hidden input); business constants (start dates,
thresholds) yes, environment identity no — that's what `target` is for.

### var() vs env_var()

| | `var()` | `env_var()` |
|---|---|---|
| source | project yml / `--vars` | process environment |
| use for | business parameters | secrets, deploy-time config |
| secrets? | no — YAML is committed | yes (values prefixed `DBT_ENV_SECRET_` are masked in logs) |

This repo's [profiles.yml](../jaffle_shop/profiles.yml) is the env_var
showcase — every connection field, with defaults, powering the
dual-mode (host/container) setup ([docs/02](02_environment_setup.md)).

## Targets as the environment axis

One profile, many targets (`dev`/`prod` here). Anything can key off
`target.name` in Jinja — schema naming, row limits, warehouse sizing.
Convention: **dev is the default; prod is explicit** (`--target prod`), so
mistakes default to the harmless side. Keep Jinja branches on target rare
and centralized in macros; a project peppered with
`{% if target.name == 'prod' %}` is a project whose dev and prod behavior
have quietly diverged.

## Behavior flags & `flags:`

Global settings live under `flags:` in dbt_project.yml (this repo:
`send_anonymous_usage_stats: false`). The same block hosts **behavior
change flags** — dbt's migration mechanism: new safer behavior ships off by
default, you opt in (`require_explicit_package_overrides_for_builtin_materializations`
and friends), and a later major flips the default. Skim the flags page in
the dbt docs on every minor upgrade; adopting flags early = smaller major
migrations. Related config in the same spirit: `require-dbt-version` (this
repo pins `>=1.10.0,<2.0.0`) makes version drift a loud error instead of a
subtle one.

## The full precedence ladder (final answer)

```
dbt_project.yml   <   properties .yml (config:)   <   {{ config() }} in the file
```

plus: CLI `--vars` beat project vars; env vars beat profile defaults
(they're read *by* them); and the schema/database/alias trio resolves
through their generate_* macros last. When in doubt, ask dbt, not the YAML:

```bash
dbt ls --select my_model --output json | jq .config
```

---
Next: [16 · State, defer & CI](16_state_defer_ci.md) — configuration meets
automation.
