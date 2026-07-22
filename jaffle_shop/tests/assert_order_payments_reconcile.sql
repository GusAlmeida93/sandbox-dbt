-- A SINGULAR test: a one-off .sql file in tests/ asserting something specific
-- across models. Same contract as all dbt tests: return the bad rows, zero
-- rows = pass. Use these when the assertion is too bespoke for a generic test.

select
    orders.order_id,
    orders.order_revenue,
    payments.total_amount as amount_paid

from {{ ref('fct_orders') }} as orders
inner join {{ ref('int_order_payments') }} as payments
    on orders.order_id = payments.order_id

-- every order should be fully paid (this shop charges at checkout)
where abs(orders.order_revenue - payments.total_amount) > 0.01
