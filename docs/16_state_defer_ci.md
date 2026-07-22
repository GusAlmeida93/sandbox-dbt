# 16 · State, defer & CI

The jump from "I run dbt" to "dbt runs itself, safely, on every change".
Three ideas compound: **state** (compare project versions), **defer**
(borrow another environment's tables), **slim CI** (build only what a
change touched).

## State: manifests as memory

`target/manifest.json` fully describes a parsed project. Save one, and dbt
can diff the *current* project against it:

```bash
cp -r target target_base            # save state (in CI: download prod's manifest)
# ...edit a model...
dbt ls --select state:modified+ --state target_base
```

Selector methods unlocked: `state:modified` (changed nodes — content,
config, or macro fallout), `state:new`, and `result:error` /
`result:success` from `run_results.json` — which enables the beautiful
retry idiom:

```bash
dbt build --select result:error+ --state target   # rerun only what failed
```

Notebook [08](../notebooks/08_artifacts_and_dag.ipynb) runs the whole
state:modified demo live.

## Defer: half a warehouse is enough

Problem: your PR changes `dim_customers`; building it needs `stg_customers`,
which you haven't built in your CI schema. Building *everything* defeats
the point.

```bash
dbt build --select state:modified+ --defer --state prod_artifacts/
```

With `--defer`, refs to nodes **not selected and not built in your schema**
resolve to the *state* environment's relations (prod's `staging` schema)
instead. Modified nodes build in your schema; everything upstream is
borrowed. Cheap PR builds on real data.

## Slim CI: the pattern assembled

```
PR opened
  └▶ fetch prod manifest        (artifact store / S3 / previous CI run)
  └▶ dbt build --select state:modified+ --defer --state ./prod-manifest
  └▶ tests gate the merge; PR schema torn down after
```

Plus the other CI-only tricks worth knowing: schema-per-PR via
`schema: "ci_pr_{{ env_var('PR_NUMBER') }}"`-style profiles;
`dbt build --empty` (dbt 1.8+) as a compile-and-execute-with-LIMIT-0 dry
run; `dbt parse` as the cheapest "is it valid" gate.

## This repo's CI (deliberately one notch simpler)

[.github/workflows/ci.yml](../.github/workflows/ci.yml) runs the honest
beginner version — full build against a throwaway Postgres **service
container**, no stored state:

```
push/PR ─▶ postgres:17 service ─▶ uv sync --frozen ─▶ generate 2 days of data
        ─▶ dbt deps ─▶ dbt build (full project, real tests)
```

Why not slim CI here? True slim CI needs a persistent artifact store for
the production manifest — real infrastructure with real staleness questions,
and this sandbox has no prod. The workflow file is heavily commented as
teaching material, and the `state:modified` mechanics it *would* add are
exactly what notebook 08 demonstrates locally. When you do graduate: store
`target/manifest.json` from every main-branch build, fetch it in PR builds,
add `--select state:modified+ --defer --state`.

The workflow also shows the env-var pattern from
[docs/02](02_environment_setup.md) doing real work: the same
`profiles.yml`, pointed at the service container via `DBT_HOST=localhost`.

## Environments, minimally

Everything composes from two primitives you already have:

- **targets** pick where you write ([docs/15](15_advanced_config.md)) —
  dev = your namespaced schemas, prod = clean schemas, CI = throwaway;
- **state+defer** picks what you borrow.

A sane maturity ladder: (1) scheduled `dbt build` on main + freshness
checks; (2) CI full build on PRs — *this repo's level*; (3) slim CI with
defer; (4) blue/green or WAP deploys where prod swaps atomically. Climb
when the pain arrives, not before.

---
Next: [17 · Debugging & performance](17_debugging_and_performance.md).
