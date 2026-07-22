-- MATERIALIZED VIEW: Postgres stores the query result like a table, but
-- remembers the defining query. dbt run refreshes it (REFRESH MATERIALIZED
-- VIEW) instead of rebuilding, and on_configuration_change controls what
-- happens when the definition itself changes. See docs/04.
{{ config(
    materialized='materialized_view',
    on_configuration_change='apply'
) }}

select
    ordered_at::date as order_date,
    count(*) as orders_count,
    sum(order_revenue) as revenue,
    sum(amount_paid) as amount_paid,
    sum(item_count) as items_sold

from {{ ref('fct_orders') }}
where status != 'cancelled'
group by 1
