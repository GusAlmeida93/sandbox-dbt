# 17 · Debugging, logging & performance

A field guide for when dbt misbehaves — and for making it faster once it
behaves.

## The debugging ladder

**1. Read the error class first.** dbt fails in phases, and the phase tells
you where to look: *Parsing/Compilation Error* (YAML or Jinja — no SQL ran)
→ *Database Error* (your SQL, warehouse's opinion) → *test failure* (SQL
fine, data wrong).

**2. `dbt debug`** — config/connection sanity: which profiles.yml, which
target, can it connect. First move for "works here, not there".

**3. Read the compiled SQL.** For Database Errors, open
`target/run/.../<model>.sql` — the *exact* text the warehouse rejected —
and run it directly (psql/Adminer here). Debugging templated SQL through
dbt's error messages alone is self-inflicted pain.

**4. `--debug` / the log file.** Console shows INFO; `logs/dbt.log` always
has DEBUG — full SQL, timings, connection chatter. `dbt --debug run ...`
streams it live. For machine-reading: `dbt --log-format json build`.

**5. Interactive probes:**

```bash
dbt compile --inline "select {{ var('training_start_date') }}"   # Jinja REPL
dbt show --select dim_customers --limit 5                        # peek at output
dbt build --empty --select my_model                              # dry-run w/ LIMIT 0
```

### War stories from this repo (real, reproducible)

The classics you'll hit, all documented where they happened: Jinja executing
inside SQL *comments* (docs/09, twice); whitespace control eating the
`select` keyword ("syntax error at or near order_id" — nowhere near the
bug); pandas/psycopg2 treating a literal `%` in SQL as a placeholder
(notebook 04's discovery cell); stale incremental state after a raw-data
reset (born: `make reset-all`); microbatch "missing" late data by design
(docs/11).

## The artifacts: dbt's flight recorder

Every command writes `target/` JSON; notebook
[08](../notebooks/08_artifacts_and_dag.ipynb) parses all of these live:

| file | from | use it for |
|---|---|---|
| `manifest.json` | every command | the DAG, configs, docs — powers state:modified, docs site, lineage tools |
| `run_results.json` | run/build/test/seed | per-node status, timing, `rows_affected`, `result:*` retries |
| `catalog.json` | docs generate | actual warehouse schemas/stats |
| `sources.json` | source freshness | freshness statuses |

The ecosystem (dbt Cloud, Datafold, Elementary, dbt_artifacts, ...) is
substantially "products built on these files". If you need run telemetry in
the warehouse itself, this repo's audit hooks
([docs/14](14_hooks_operations_grants.md)) are the 20-line version.

## Performance

**Measure first** — `run_results.json` timings (notebook 08 charts them),
or eyeball the per-node times in console output.

Levers, in the order to pull them:

1. **threads** (profiles.yml; 4 dev / 8 prod here) — parallelism across
   *independent* DAG nodes. Helps wide DAGs; does nothing for one slow
   model; bounded by warehouse concurrency.
2. **Materialization strategy** — the big hammer. Rebuild-everything
   `table` → `incremental` when size justifies the complexity tax
   ([docs/11](11_incremental_deep_dive.md)).
3. **Build less** — `--select` surgically, `--exclude` the heavy tail,
   state:modified in CI ([docs/16](16_state_defer_ci.md)), `--defer` to
   borrow instead of build.
4. **Warehouse-side** — on Postgres: indexes via post-hooks on
   frequently-joined marts, `analyze` after big builds; on cloud
   warehouses: clustering/partitioning configs per adapter.
5. **Parse time** — partial parsing is on by default
   (`target/partial_parse.msgpack`); it invalidates on env-var/flag
   changes, which is why CI (fresh checkout, no cache) always full-parses.
   Big projects care; this one parses in ~1s.

Non-levers to un-learn: threads beyond warehouse capacity (queues, not
speed); ephemeral models as a "performance" trick (they *duplicate*
compute); premature incrementalization (state bugs cost more than compute).

## Health-check commands, collected

```bash
dbt debug                      # config + connection
dbt parse                      # is the project valid at all
dbt ls --select ...            # what would this selection touch
dbt compile --inline "..."     # Jinja playground
dbt show --select m --limit 5  # what does this model return
tail -f logs/dbt.log           # everything, always
```

---
Next: [18 · Best practices & cheatsheet](18_best_practices_and_cheatsheet.md).
