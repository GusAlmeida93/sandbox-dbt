# 08 · Documentation & exposures

dbt documentation is not a wiki that drifts — it's generated from the same
YAML that configures your project, plus the live warehouse, every time you
run `dbt docs generate`. Descriptions live in version control, next to the
code they describe, reviewed in the same PRs.

## Descriptions

Every resource and column takes a `description:`; they render in the docs
site and can be pushed into the warehouse itself:

```yaml
models:
  - name: dim_customers
    description: '{{ doc("dim_customers") }}'   # long-form, see below
    config:
      persist_docs:            # also COMMENT ON in Postgres
        relation: true
        columns: true
    columns:
      - name: lifetime_value
        description: '{{ doc("lifetime_value") }}'
```

`persist_docs` means even someone poking at the DB with psql sees the docs:

```sql
select obj_description('dev_marts.dim_customers'::regclass);
```

## Doc blocks: long-form, reusable prose

Markdown files with named blocks
([_marts__docs.md](../jaffle_shop/models/marts/_marts__docs.md)):

```
{% docs lifetime_value %}
Total payments across the customer's non-cancelled, non-returned orders...
{% enddocs %}
```

Referenced with `{{ doc("lifetime_value") }}` from any description. Write
the definition once; every model exposing the column links the same prose.
The special block `__overview__` replaces the docs site's landing page —
this repo uses it.

## The docs site

```bash
make docs          # generate + serve on http://localhost:8081
make docs-static   # single self-contained HTML file you can email
```

`dbt docs generate` writes two artifacts: `manifest.json` (project as
parsed) and `catalog.json` (schemas/types/stats queried from the live
warehouse). The site merges them: model pages show description, columns,
tests, compiled SQL, and — the killer feature — the **lineage graph**, where
you can trace any column-bearing relation from raw source to exposure and
filter with the same `--select` syntax you use on the CLI.

(Inside Docker, serving needs `--host 0.0.0.0`; `make docs` handles it.)

## Exposures: documenting the *consumers*

The DAG usually ends at your marts — but reality doesn't. Dashboards,
notebooks, ML jobs and reverse-ETL syncs consume those marts. An
**exposure** ([_marts__exposures.yml](../jaffle_shop/models/marts/_marts__exposures.yml))
declares one:

```yaml
exposures:
  - name: revenue_notebook
    type: notebook            # dashboard | notebook | analysis | ml | application
    url: http://localhost:8888/lab/tree/notebooks/08_artifacts_and_dag.ipynb
    depends_on:
      - ref('fct_orders')
      - ref('agg_daily_revenue')
    owner: {name: Gustavo Almeida, email: gusalmeida93@gmail.com}
```

What that buys, concretely:

```bash
# build exactly what this notebook needs:
dbt build --select +exposure:revenue_notebook
# impact analysis -- what consumers does fct_orders feed?
dbt ls --select fct_orders+ --resource-type exposure
```

...and the exposure appears in the lineage graph with an owner to call when
you're about to break it. Low ceremony, high payoff: most teams
under-declare exposures and then can't answer "who reads this table?"

## Working habits that keep docs alive

- Write the description **when you write the model** — a `codegen`-generated
  YAML skeleton ([docs/12](12_packages.md)) makes this nearly free.
- Doc blocks for anything longer than a sentence or reused anywhere.
- Descriptions state *grain* first ("one row per ...") — it's the single
  highest-value fact about any table.
- CI can enforce coverage: `dbt ls --select "resource_type:model"` + a
  check that descriptions exist (or packages like dbt_meta_testing).

---
Next: [09 · Jinja & macros](09_jinja_and_macros.md) — the templating layer
everything else is built on.
