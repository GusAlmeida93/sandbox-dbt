# 11 · Incremental models, deep dive

A `table` model reprocesses everything on every run. Fine at 500k rows,
ruinous at 5B. **Incremental** models process only what's new or changed —
trading simplicity for speed, because now your model has *state*.

This repo ships both major patterns, verified daily by the notebooks:

- `fct_orders` — classic `is_incremental()` + high-water mark, `delete+insert`
- `fct_events` — microbatch (dbt 1.9+)

## The classic pattern, annotated

[fct_orders.sql](../jaffle_shop/models/marts/fct_orders.sql):

```sql
{{ config(
    materialized='incremental',
    incremental_strategy='delete+insert',
    unique_key='order_id',
    on_schema_change='append_new_columns'
) }}

select ... from {{ ref('stg_orders') }}
{% if is_incremental() %}
where updated_at > (select coalesce(max(updated_at), '1900-01-01'::timestamp)
                    from {{ this }})
{% endif %}
```

Execution logic:

- **first run / `--full-refresh`**: `is_incremental()` is false → plain
  `create table as`.
- **subsequent runs**: the WHERE filters staging to rows past the target's
  high-water mark (`{{ this }}` = the already-built table); the strategy
  merges that delta in.

Two deliberate choices to study:

1. **Filter on `updated_at`, not `created_at`/id.** The source *mutates*
   (order statuses advance). An insert-only filter would freeze every order
   at `placed` forever. Filtering on updated_at catches new AND changed rows
   — run notebook [06](../notebooks/06_incremental_models.ipynb) and watch
   `rows_affected` exceed the net-new count.
2. **`delete+insert` + `unique_key`.** Changed rows *replace* their old
   versions instead of duplicating them (delete matching keys, insert the
   delta).

## Choosing a strategy (dbt-postgres)

| strategy | behavior | fits |
|---|---|---|
| `append` | just INSERT | true append-only streams, dupes impossible/acceptable |
| `delete+insert` | delete keys present in delta, insert delta | mutable rows, moderate deltas (this repo's choice) |
| `merge` | one MERGE statement (PG15+) | mutable rows; fewer statements, row-level upsert |
| `microbatch` | one operation per time window | event data — below |

`on_schema_change` governs drift between the built table and today's SELECT:
`ignore` (default) / `append_new_columns` / `sync_all_columns` / `fail`.
It only handles add/remove — **type changes still require `--full-refresh`**.

## Microbatch: incremental by time window

[fct_events.sql](../jaffle_shop/models/marts/fct_events.sql):

```sql
{{ config(
    materialized='incremental',
    incremental_strategy='microbatch',
    event_time='event_ts',
    batch_size='day',
    begin=var('training_start_date'),
    lookback=1,
    unique_key='event_id'
) }}
select ... from {{ ref('stg_events') }}
```

No `is_incremental()`, no high-water mark — you declare *time semantics* and
dbt derives the plumbing:

- work splits into one **batch per day** from `begin` → now; each batch
  processes independently (separately retryable — one bad day doesn't
  poison the run; each shows in the log: `Batch 3 of 21...`);
- upstream models that declare `event_time` (see
  [stg_events.sql](../jaffle_shop/models/staging/stg_events.sql)) are
  **auto-filtered to the batch window** — without that config every batch
  would silently scan the full table;
- steady-state runs process only `lookback` + current batches.

Postgres requires `unique_key` for microbatch (batch replacement is
delete+insert under the hood). And keep `begin` sane — every day between
`begin` and now becomes a batch, even empty ones (this sandbox sets it via
`var('training_start_date')`).

### Late-arriving data: the lesson this sandbox forces

Load a new business day (`make data-day DAY=4`) and run `fct_events`: **no
rows arrive.** The new events carry business dates outside the lookback
window — from microbatch's perspective they're *late data*. The remedy is a
targeted backfill of exactly the affected window:

```bash
dbt run -s fct_events --event-time-start "2026-07-04" --event-time-end "2026-07-05"
```

That replaces one day's batch, leaving everything else untouched. This
surgical replayability is the whole argument for microbatch: with the
classic pattern the equivalent is a hand-written wretched WHERE clause or a
full refresh.

## Full refresh: your safety net, keep it safe

```bash
dbt build --full-refresh                # rebuild incrementals from scratch
dbt run -s fct_orders --full-refresh    # just one
```

Iron rule: **an incremental model must produce identical results under
`--full-refresh`**. If not, your incremental logic is quietly wrong.
Notebook 06 asserts this equivalence. Corollaries: treat incremental state
as a cache; expect to full-refresh after logic changes, type changes, or
backfill surgery gone wrong. (Also: after deleting *raw* history — stale
incremental state referencing vanished upstream rows is how this repo's
`make reset-all` earned its existence.)

## When to go incremental at all

Only when a full rebuild measurably hurts (minutes, not seconds — check
`run_results.json` timings first, [docs/17](17_debugging_and_performance.md)).
The complexity tax is real: state, late data, schema drift, full-refresh
discipline. `agg_daily_revenue` in this repo makes the counterpoint — it
reads the incremental `fct_orders` but is itself a cheap materialized view.

---
Next: [12 · Packages](12_packages.md).
