# 07 · Testing

dbt has two testing philosophies that answer different questions:

- **Data tests** — "is the data in the warehouse healthy *right now*?" Run
  after building. The workhorse.
- **Unit tests** (dbt 1.8+) — "is my SQL *logic* correct, independent of
  data?" Run with mocked inputs, before the model builds.

Notebook [04](../notebooks/04_testing.ipynb) exercises everything below,
including breaking things on purpose.

## Data tests: a test is a SELECT that returns bad rows

Zero rows = pass. That's the whole contract, for all four flavors:

### 1. Built-in generic tests

Declared in YAML next to the column they guard
([_staging__models.yml](../jaffle_shop/models/staging/_staging__models.yml)):

```yaml
columns:
  - name: order_id
    data_tests:          # NOT `tests:` -- that spelling is deprecated (1.8+)
      - unique
      - not_null
  - name: status
    data_tests:
      - accepted_values:
          arguments:     # test kwargs go under `arguments:` since 1.10
            values: ['placed', 'shipped', 'completed', 'returned', 'cancelled']
  - name: customer_id
    data_tests:
      - relationships:
          arguments:
            to: ref('stg_customers')
            field: customer_id
```

The big four cover most real needs: **unique** and **not_null** on every
primary key (grain protection), **accepted_values** on enums,
**relationships** for referential integrity (works against any ref()-able
thing — this repo checks `country_code` against a *seed*).

### 2. Custom generic tests

A parameterized test you write once and attach anywhere —
[tests/generic/positive_value.sql](../jaffle_shop/tests/generic/positive_value.sql):

```sql
{% test positive_value(model, column_name) %}
select * from {{ model }}
where {{ column_name }} is not null and {{ column_name }} <= 0
{% endtest %}
```

Attach with `- positive_value` like any built-in. This repo guards
`price`, `quantity`, and `amount` with it.

### 3. Package tests

`dbt_utils` and `dbt_expectations` ship dozens more
([docs/12](12_packages.md)); used here:

```yaml
- dbt_utils.accepted_range:
    arguments: {min_value: 0, inclusive: true}
- dbt_expectations.expect_column_values_to_be_between:
    arguments: {min_value: 0, max_value: 10000}
```

### 4. Singular tests

One-off assertions as plain SQL files in `tests/` —
[assert_order_payments_reconcile.sql](../jaffle_shop/tests/assert_order_payments_reconcile.sql)
cross-checks `fct_orders` revenue against payments. If you write the same
singular test twice, refactor it into a custom generic.

## Test configuration worth knowing

```yaml
- accepted_values:
    arguments: {values: [...]}
    config:
      severity: warn          # nag, don't block (stg_events here)
      store_failures: true    # materialize bad rows for inspection
      where: "ordered_at > current_date - 30"   # test a slice
      limit: 100
```

- **severity: warn** — the build continues. Use for "worth knowing, not
  worth waking up for" (a new enum value upstream).
- **store_failures** — failing rows land in a `<schema>_dbt_test__audit`
  table so you can look at *which* rows broke instead of re-deriving them.
  Postgres truncates long generated table names — discover, don't hardcode
  (notebook 04 shows how).
- **`dbt build` gates on tests**: a failing test SKIPs everything
  downstream. This is the feature that makes tests worth writing — bad data
  stops *propagating*. (`dbt test` alone just reports.)

## Unit tests (dbt 1.8+)

[_intermediate__models.yml](../jaffle_shop/models/intermediate/_intermediate__models.yml)
defines one for the payment pivot:

```yaml
unit_tests:
  - name: unit_int_order_payments_pivot
    model: int_order_payments
    given:
      - input: ref('stg_payments')
        rows:
          - {order_id: 1, payment_method: credit_card, amount: 30.00}
          - {order_id: 1, payment_method: pix, amount: 20.00}
    overrides:
      macros:
        dbt_utils.get_column_values: ['bank_transfer', 'credit_card', ...]
    expect:
      rows:
        - {order_id: 1, total_amount: "50.00", credit_card_amount: "30.00", ...}
```

Mocked inputs go in as inline CTEs; the model's compiled SQL runs against
them; output must match `expect`. In `dbt build`, unit tests run **before**
the model and gate it. Use them for logic worth protecting: pivots, window
functions, regex parsing, edge-case CASE ladders.

Two real-world quirks (this repo hit both; the YAML comments tell the story):

1. **Introspective macros can't see mocks** — `get_column_values` queries
   the warehouse, and a mocked input is just a CTE. `overrides.macros` pins
   the macro's return value (also making the test hermetic).
2. **Expected values compare textually** — YAML parses `50.00` into `50.0`,
   which then mismatches a `numeric(16,2)`'s `"50.00"`. Quote decimal
   expectations as strings.

## What to test, pragmatically

Baseline that scales: `unique` + `not_null` on every model's grain;
`accepted_values` on enums; `relationships` on the joins your marts depend
on; a singular test per business invariant that would embarrass you in a
dashboard; a unit test per genuinely tricky transformation. 100% coverage of
trivial columns is noise — test what would *hurt*.

---
Next: [08 · Documentation & exposures](08_documentation_and_exposures.md).
