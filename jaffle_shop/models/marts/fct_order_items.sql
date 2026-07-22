-- Finest-grain fact: one row per product per order. The surrogate key is a
-- hash of the natural compound key -- stable across rebuilds, unlike a
-- sequence, and it gives tests/joins a single-column handle on the grain.

select
    {{ dbt_utils.generate_surrogate_key(['order_id', 'product_id']) }}
        as order_item_key,
    order_item_id,
    order_id,
    customer_id,
    ordered_at,
    product_id,
    product_name,
    category,
    quantity,
    unit_price,
    item_revenue

from {{ ref('int_order_items_enriched') }}
