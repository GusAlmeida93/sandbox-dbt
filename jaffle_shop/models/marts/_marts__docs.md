{% docs dim_customers %}
One row per customer, enriched with order history and lifetime value.

This model carries an **enforced contract**: its column names and types are
declared in `_marts__models.yml` and dbt refuses to build the model if the
SQL drifts from the declaration. Try renaming a column in `dim_customers.sql`
and running `dbt run -s dim_customers` to see it fail *before* touching the
warehouse.
{% enddocs %}

{% docs lifetime_value %}
Total payments across the customer's non-cancelled, non-returned orders, in
dollars. **Definition choices worth knowing:**

- returned orders are excluded entirely (the shop refunds them)
- there is no time-window: this is all-time value
{% enddocs %}

{% docs fct_orders %}
One row per order with revenue, item counts, and amounts paid.

Built **incrementally** (delete+insert): each run only processes orders whose
`updated_at` moved past the previous high-water mark, so both brand-new orders
and status changes on old orders are picked up. `dbt build --full-refresh`
rebuilds it from scratch.
{% enddocs %}

{% docs __overview__ %}
# jaffle_shop -- a dbt learning project

This is the documentation site for the `sandbox-dbt` learning repository.
The project transforms raw e-commerce data (loaded by a synthetic EL
simulator) into a small dimensional warehouse:

```
raw (sources) -> staging (views) -> intermediate -> marts (facts + dims)
```

Use the graph button (bottom right) to explore the DAG, and click through any
model to see its description, columns, tests, and compiled SQL. The learning
docs live in the repo under `docs/`, and the interactive notebooks under
`notebooks/`.
{% enddocs %}
