# 12 · Packages

A dbt package is just a dbt project you install into yours — its macros,
models and tests become available as if you wrote them (namespaced by
package name). The ecosystem lives at [hub.getdbt.com](https://hub.getdbt.com).

## Installing

[packages.yml](../jaffle_shop/packages.yml):

```yaml
packages:
  - package: dbt-labs/dbt_utils          # from the hub
    version: [">=1.3.0", "<2.0.0"]       # RANGE, not exact pin

  # other source types you'll meet:
  # - git: "https://github.com/org/private-package.git"
  #   revision: v1.2.0                   # tag / branch / commit
  # - local: ../shared_macros            # monorepo pattern
```

```bash
dbt deps        # installs into dbt_packages/ (gitignored)
```

**Version ranges + `package-lock.yml`** is the modern workflow (mirrors
uv/npm): ranges express compatibility, the lock file (committed — this repo
does) records exactly what resolved, so CI and teammates get identical
packages. `dbt deps --upgrade` re-resolves inside the ranges.

Also good to know: `dbt deps` needs network (bootstrap step, not image
build); packages declare their own `require-dbt-version`; and a project
macro with the same name as a package macro overrides it project-wide.

## The three packages installed here

### dbt_utils — the standard library

Used in this repo, and roughly in order of real-world frequency:

```sql
-- surrogate keys from compound grains (fct_order_items)
{{ dbt_utils.generate_surrogate_key(['order_id', 'product_id']) }}

-- compile-time introspection: pivot columns from seed rows (int_order_payments)
{% set methods = dbt_utils.get_column_values(table=ref('payment_methods'),
                                             column='payment_method') %}
```

```yaml
# generic tests beyond the built-in four (fct_orders)
- dbt_utils.accepted_range:
    arguments: {min_value: 0, inclusive: true}
```

Worth knowing even though this repo doesn't use them: `date_spine` (calendar
tables), `union_relations` (align+union differing schemas), `star` (SELECT
column lists minus exclusions), `expression_is_true`, `equal_rowcount`.

### dbt_expectations — assertion-style tests

Great Expectations ported to dbt-native tests; hundreds of prebuilt
assertions with self-describing names:

```yaml
- dbt_expectations.expect_column_values_to_be_between:
    arguments: {min_value: 0, max_value: 10000}
```

(Note the namespace: originally `calogica/`, maintained by Metaplane since
2023 — hub package `metaplane/dbt_expectations`. It transitively installs
`dbt_date`; you'll see it in `dbt deps` output.)

### codegen — write your boilerplate for you

Operations that print starter YAML/SQL:

```bash
dbt run-operation generate_model_yaml --args '{model_names: [dim_products]}'
dbt run-operation generate_source --args '{schema_name: raw, generate_columns: true}'
dbt run-operation generate_base_model --args '{source_name: shop_backend, table_name: raw_orders}'
```

Paste, then edit. The cheapest path from "no docs" to "docs".

## Judgment calls

- **Reach for dbt_utils before writing a macro** — if the itch feels
  generic, it's probably already there, tested across adapters.
- **Don't install what you won't read.** Packages ship real macros into
  your compile path (`dbt deps` here brings ~900 macros along). Two or
  three well-chosen packages beat ten.
- Audit-style helper packages exist for migrations (`audit_helper`),
  project health (`dbt_project_evaluator`), and metadata testing — worth
  knowing they exist when the need appears.

---
Next: [13 · Analyses & the semantic layer](13_semantic_layer_and_analyses.md).
