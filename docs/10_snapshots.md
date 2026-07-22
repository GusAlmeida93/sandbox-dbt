# 10 · Snapshots (Slowly Changing Dimensions, Type 2)

## The problem

Operational systems overwrite. When a customer moves, `raw_customers.address`
is UPDATEd; the old address is gone. Yesterday's revenue-by-region report can
no longer be reproduced — the data that produced it no longer exists.

**SCD Type 2** keeps every version of every row, with validity intervals.
dbt snapshots implement it for you.

## What a snapshot looks like

Run `make dbt-snapshot` twice around a data mutation (notebook
[07](../notebooks/07_snapshots.ipynb) choreographs it) and
`dev_snapshots.snap_customers` grows rows like:

| id | city | dbt_valid_from | dbt_valid_to |
|---|---|---|---|
| 42 | Lisbon | 2026-07-01 09:14 | 2026-07-03 16:02 |
| 42 | Porto  | 2026-07-03 16:02 | *null* |

plus `dbt_scd_id` (surrogate key per version), `dbt_updated_at`, and — for
each `dbt snapshot` run — dbt compares source vs snapshot, **closes** changed
rows (fills `dbt_valid_to`) and **inserts** the new version.

## Definition: YAML since dbt 1.9

[snapshots/snapshots.yml](../jaffle_shop/snapshots/snapshots.yml):

```yaml
snapshots:
  - name: snap_customers
    relation: source('shop_backend', 'raw_customers')
    config:
      unique_key: id
      strategy: timestamp
      updated_at: updated_at

  - name: snap_order_status
    relation: source('shop_backend', 'raw_orders')
    config:
      unique_key: id
      strategy: check
      check_cols: [status]
```

(The legacy form — `{% snapshot %}` blocks in `.sql` files — still works;
YAML is the modern default.)

## The two strategies

**timestamp** (prefer when possible): a row changed iff its `updated_at`
moved forward. Cheap — one column compare — but requires an updated_at you
actually trust. `dbt_valid_from` of the new version = the source's
`updated_at` (business time!).

**check**: a row changed iff any of `check_cols` differ (or `check_cols:
all`). No timestamp needed; costs a column-by-column comparison;
`dbt_valid_from` = snapshot run time (wall clock — you only know the change
happened *since the last run*).

That difference in `dbt_valid_from` semantics matters: check-strategy
history is only as precise as your snapshot *frequency*. Which motivates the
operational rule: **snapshot early, snapshot often** — running against an
unchanged source is a free no-op.

## Querying SCD-2

The two canonical patterns:

```sql
-- current state
select * from dev_snapshots.snap_customers
where dbt_valid_to is null;

-- as of a moment in time
select * from dev_snapshots.snap_customers
where dbt_valid_from <= '2026-07-02 12:00'
  and (dbt_valid_to > '2026-07-02 12:00' or dbt_valid_to is null);
```

Point-in-time joins (fact rows against the dimension *as it was*) join on
the key **and** the validity window: `on f.customer_id = s.id and
f.ordered_at >= s.dbt_valid_from and (f.ordered_at < s.dbt_valid_to or
s.dbt_valid_to is null)`.

## Operational truths (learn these before production)

1. **Snapshot sources, not marts.** History you don't capture at the edge is
   gone; downstream logic changes shouldn't rewrite "what we saw". Both
   snapshots here read `source()` directly.
2. **Snapshots are state, not derivations.** `--full-refresh` deliberately
   does not rebuild them; dropping one deletes history you cannot recover.
   Treat the snapshots schema as production data — even in dev.
3. **Schedule them independently if needed** — classically `dbt snapshot` on
   its own cadence; `dbt build` also runs them in DAG position.
4. **1.9+ niceties** (commented in this repo's YAML):
   `dbt_valid_to_current: "to_date('9999-12-31')"` (sentinel instead of NULL
   simplifies BETWEEN), `hard_deletes: ignore | invalidate | new_record`
   (what to do when a row vanishes upstream).
5. Downstream models can `ref('snap_customers')` like any model — a common
   pattern builds `dim_customers` *from the snapshot* (current rows only) so
   the dimension and its history share one source of truth. This repo keeps
   dims on staging for DAG clarity and leaves the snapshot-driven variant as
   an exercise.

## Why this beats hand-rolled history

The naive alternatives all lose: full-table daily copies (storage explodes,
still miss intra-day changes), audit columns in place (schema surgery on a
source you don't own), CDC pipelines (right answer at scale, heavy to
operate). Snapshots are ~15 lines of YAML on infrastructure you already run.

---
Next: [11 · Incremental models](11_incremental_deep_dive.md) — the other
kind of statefulness.
