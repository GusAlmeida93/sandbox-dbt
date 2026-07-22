# 14 · Hooks, run-operation & grants

Sometimes you need SQL that *isn't* a model: audit bookkeeping, permissions,
maintenance. dbt gives you three escape hatches, in increasing order of
"you drive":

## 1. Hooks: SQL attached to lifecycle events

| hook | fires | configured in |
|---|---|---|
| `on-run-start` | once, before any node | dbt_project.yml |
| `on-run-end` | once, after all nodes | dbt_project.yml |
| `pre-hook` | before **each** model/seed/snapshot | model config |
| `post-hook` | after **each** | model config |

This repo runs a real audit log with project hooks
([dbt_project.yml](../jaffle_shop/dbt_project.yml) →
[macros/audit_hooks.sql](../jaffle_shop/macros/audit_hooks.sql)):

```yaml
on-run-start:
  - "{{ create_audit_log() }}"          # create schema + table if needed
on-run-end:
  - "{{ log_run_results(results) }}"    # one row per invocation
```

Every dbt command you've run in this sandbox is in the table:

```sql
select * from audit.dbt_run_log order by finished_at desc;
```

Mechanics worth understanding:

- A hook is a **string that renders to SQL** — macros make them readable.
- The `on-run-end` context has extras: `results` (per-node statuses — the
  audit macro counts successes/errors from it) and `schemas`.
- **Gotcha encoded in this repo**: `on-run-start` fires *before* dbt creates
  any schemas — the audit macro must `create schema if not exists` itself.
- Model-level hooks take config like everything else:

```sql
{{ config(post_hook="analyze {{ this }}") }}   -- e.g. stats after build
```

Restraint clause: hooks are invisible side effects — every hook is
something a reader of the model can't see. Grants and stats are good hooks;
business logic never is.

## 2. run-operation: macros as CLI commands

```bash
dbt run-operation drop_old_relations                          # dry run
dbt run-operation drop_old_relations --args '{dry_run: false}'
```

[macros/drop_old_relations.sql](../jaffle_shop/macros/drop_old_relations.sql)
is a genuinely useful admin tool: dbt never drops relations it stops
managing (rename a model and the old table lingers forever), so this macro
diffs `information_schema` against the manifest's `graph` and drops the
orphans. It demonstrates the whole operations toolkit: `execute` guard,
`run_query()` → Agate rows, `graph.nodes.values()`, `log(..., info=true)`,
and `--args` as YAML.

Other classic operations: vacuum/optimize sweeps, warehouse resize,
masking-policy application, `codegen` generators ([docs/12](12_packages.md)).

## 3. Grants: declarative, not hook-based (since 1.2)

Permissions used to be everyone's first post-hook; now they're config:

```yaml
# dbt_project.yml -- everything in marts readable by the BI role
models:
  jaffle_shop:
    marts:
      +grants:
        select: ['reporting_role']
```

dbt applies the right GRANT/REVOKE after each build and knows each
adapter's copy-grants semantics. Standard-config precedence applies; use
`+grants:` to *replace*. (Not demonstrated live here — the sandbox has a
single superuser — but this is the pattern to reach for the moment a second
role exists.)

## Choosing between them

| need | tool |
|---|---|
| bookkeeping around every run | project hooks |
| per-model side effect (stats, index) | post-hook |
| permissions | `grants` config |
| ad-hoc/scheduled admin task | run-operation |
| transformation logic | **a model** — always a model |

---
Next: [15 · Advanced configuration](15_advanced_config.md).
