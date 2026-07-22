# 05 · Sources, seeds & freshness

Models transform data; this doc is about where the *inputs* come from and
how dbt keeps you honest about them.

## Sources: declaring what you don't own

The `raw` schema in this sandbox is loaded by
[scripts/generate_data.py](../scripts/generate_data.py) — dbt did not put it
there and cannot rebuild it. A **source** declaration
([models/staging/_staging__sources.yml](../jaffle_shop/models/staging/_staging__sources.yml))
tells dbt about such tables:

```yaml
sources:
  - name: shop_backend          # logical source system
    schema: raw                 # physical location
    loaded_at_field: _synced_at
    freshness:
      warn_after: {count: 24, period: hour}
    tables:
      - name: raw_orders
        freshness:
          error_after: {count: 72, period: hour}
      - name: raw_products
        freshness: null         # static table: opt out
```

Models then use `{{ source('shop_backend', 'raw_orders') }}` instead of
`raw.raw_orders`. What that buys:

1. **Lineage** — sources appear in the DAG and docs site; you can answer
   "what breaks if this feed dies?" with `dbt ls -s source:shop_backend+`.
2. **One place to relocate** — if the EL tool changes schemas, edit one YAML.
3. **Freshness checking** — below.
4. **Tests and docs on raw data** — same YAML machinery as models.

This repo declares two sources on purpose (`shop_backend`,
`web_analytics`): group tables by the *system* they come from, not by the
schema they happen to land in.

## Source freshness: the pipeline smoke alarm

```bash
make dbt-source-freshness     # or: dbt source freshness
```

For each table with rules, dbt runs
`select max(_synced_at) ...` and classifies the result: `pass`, `warn`
(older than `warn_after`), or `error` (older than `error_after`). Results
land in `target/sources.json`.

The point: **detect upstream failure before stakeholders do.** A scheduled
freshness check that errors = the EL pipeline is down = your models are
faithfully transforming stale data. Notebook
[03](../notebooks/03_sources_seeds_freshness.ipynb) breaks and repairs
freshness live.

Design notes visible in this repo's YAML:

- defaults at source level, override or `freshness: null` per table —
  static tables (product catalog) should not page anyone
- `loaded_at_field` should be EL-tool metadata (`_synced_at`), not a business
  timestamp — you are measuring the *pipeline*, not the business

## Seeds: CSVs that dbt loads

The one exception to "dbt doesn't load data":

```
seeds/payment_methods.csv   →  dbt seed  →  dev_seeds.payment_methods
seeds/country_codes.csv                     dev_seeds.country_codes
```

Seeds are for **small, static, analyst-owned mappings** — the kind of
knowledge that otherwise lives in someone's head or a lost spreadsheet.
They are code: version-controlled, reviewed, testable, `ref()`-able:

```sql
left join {{ ref('country_codes') }} using (country_code)
```

Config lives in [seeds/_seeds.yml](../jaffle_shop/seeds/_seeds.yml) — note
`column_types` forcing `fee_percent` to `numeric(5,2)` (CSV columns
otherwise arrive as whatever dbt infers) — and this repo tests seeds
(`unique`, `not_null`) and pivots off one at compile time
([docs/09](09_jinja_and_macros.md)).

### When a seed is the wrong tool

| situation | use instead |
|---|---|
| actual source data (orders, users, events) | EL tool |
| more than ~1k rows / changes weekly | EL tool or a model |
| secrets, PII | never — seeds are in git |
| generated series (dates...) | `dbt_utils.date_spine` |

`dbt seed` truncates+reloads by default; `--full-refresh` drops and
recreates (needed after column changes).

## The full input picture

```
EL tool (generate_data.py)──▶ raw.* ──source()──▶ staging models ──ref()──▶ ...
analyst-owned CSVs ──dbt seed──▶ seeds ──ref()──────────────────────▶ ...
```

Every edge above is visible in `dbt docs` lineage because nothing bypasses
`source()`/`ref()`. Keep it that way: a hardcoded `from raw.raw_orders` in a
model would compile fine and silently punch a hole in the DAG.

---
Next: [06 · ref(), the DAG & selection](06_refs_dag_selection.md).
