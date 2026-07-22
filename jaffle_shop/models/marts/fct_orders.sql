-- INCREMENTAL model, delete+insert strategy. On the first run (or with
-- --full-refresh) this builds like a normal table. Afterwards, only rows
-- that changed since the last run are processed: the is_incremental() branch
-- filters staging to new/updated rows, and the delete+insert strategy
-- replaces matching order_ids in the target. That is how STATUS CHANGES on
-- old orders get picked up, not just brand-new orders. See docs/11.
{{ config(
    materialized='incremental',
    incremental_strategy='delete+insert',
    unique_key='order_id',
    on_schema_change='append_new_columns'
) }}

with orders as (

    select * from {{ ref('stg_orders') }}

    {% if is_incremental() %}
    -- {{ this }} = the already-built version of THIS model in the warehouse.
    -- Only rows the source touched since our high-water mark.
    where updated_at > (select coalesce(max(updated_at), '1900-01-01'::timestamp) from {{ this }})
    {% endif %}

),

order_totals as (

    -- int_order_items_enriched is ephemeral: look at this model in
    -- target/compiled/ and you will find it inlined right here as a CTE
    select
        order_id,
        sum(item_revenue) as order_revenue,
        sum(quantity) as item_count
    from {{ ref('int_order_items_enriched') }}
    group by 1

),

payments as (

    select * from {{ ref('int_order_payments') }}

)

select
    orders.order_id,
    orders.customer_id,
    orders.status,
    orders.ordered_at,
    orders.updated_at,
    coalesce(order_totals.order_revenue, 0) as order_revenue,
    coalesce(order_totals.item_count, 0) as item_count,
    coalesce(payments.total_amount, 0) as amount_paid

from orders
left join order_totals
    on orders.order_id = order_totals.order_id
left join payments
    on orders.order_id = payments.order_id
