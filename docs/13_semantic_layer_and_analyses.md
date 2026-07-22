# 13 · Analyses, and an honest look at the semantic layer

Two loosely-related topics that answer the same question — "where does
*consumption* logic live?" — at very different levels of ceremony.

## Analyses: version-controlled scratch SQL

Files in `analyses/` get full Jinja + `ref()` treatment and are **compiled
but never run** — no relation is created:

```bash
dbt compile
cat target/compiled/jaffle_shop/analyses/top_customers.sql   # runnable SQL
```

[analyses/top_customers.sql](../jaffle_shop/analyses/top_customers.sql) is
the demo: an exploratory ranking query that deserves version control and
lineage-aware refs, but not a table in the warehouse. Use analyses for
audit queries, one-off investigations worth keeping, and SQL you're
incubating before it becomes a model. (For queries a *tool* runs on a
schedule, prefer a real model + [exposure](08_documentation_and_exposures.md).)

## The metric-consistency problem

"Revenue" gets defined in four dashboards, three notebooks, and two
spreadsheets — slightly differently in each. Marts help (shared tables) but
don't fully solve it: every consumer still writes its own `sum(...) where
status not in (...)` on top.

The classic mitigations, cheapest first:

1. **Push definitions down into marts** — this repo's approach.
   `lifetime_value` is computed *once*, in `dim_customers`, and documented
   with a doc block stating its definition choices. Consumers select the
   column; they don't re-derive it.
2. **Pre-aggregate the blessed rollups** — `agg_daily_revenue` fixes the
   grain AND the filter (`status != 'cancelled'`) for daily revenue.
3. **A semantic layer** — define metrics *declaratively* and let a query
   engine generate correct SQL for any dimensional cut.

## The dbt Semantic Layer / MetricFlow, honestly

dbt's answer to level 3 is **MetricFlow**: you declare semantic models and
metrics in YAML alongside your project —

```yaml
# illustrative only -- not wired up in this repo
semantic_models:
  - name: orders
    model: ref('fct_orders')
    entities: [{name: order, type: primary, expr: order_id}]
    dimensions: [{name: ordered_at, type: time, type_params: {time_granularity: day}}]
    measures: [{name: revenue, agg: sum, expr: order_revenue}]
metrics:
  - name: revenue
    type: simple
    type_params: {measure: revenue}
```

— and a query layer answers `revenue by region by week` with generated SQL,
identically for every consumer.

**The honest part**: the *serving* infrastructure (the APIs your BI tool
queries) is a **dbt Cloud / dbt platform** feature. With pure dbt-core you
can write the YAML and use the open-source MetricFlow CLI to develop and
test metric queries locally, but there is no self-hosted production API.
The predecessor `metrics:` spec (pre-1.6) is dead; ignore old tutorials
that mention `dbt_metrics`.

So the pragmatic guidance for a dbt-core learner:

- master levels 1-2 — they carry most of the value and all of this repo;
- learn to *read* semantic-model YAML so the concepts are familiar;
- adopt the semantic layer when (a) you're on the dbt platform and (b)
  metric drift across consumers is a real, observed pain — it's a tax worth
  paying at BI-fleet scale, not at notebook scale.

---
Next: [14 · Hooks, operations & grants](14_hooks_operations_grants.md).
