-- EPHEMERAL: this model never exists in the database. Anything that ref()s it
-- gets its SQL inlined as a CTE at compile time. Compare the compiled SQL of
-- fct_orders / fct_order_items in target/compiled/ to see it happen.
-- Good for shared logic too small to justify a real relation; bad for
-- anything you want to query, test heavily, or debug. See docs/04.
{{ config(materialized='ephemeral') }}

select
    items.order_item_id,
    items.order_id,
    orders.customer_id,
    orders.ordered_at,
    items.product_id,
    products.product_name,
    products.category,
    items.quantity,
    items.unit_price,
    items.quantity * items.unit_price as item_revenue

from {{ ref('stg_order_items') }} as items
inner join {{ ref('stg_orders') }} as orders
    on items.order_id = orders.order_id
inner join {{ ref('stg_products') }} as products
    on items.product_id = products.product_id
