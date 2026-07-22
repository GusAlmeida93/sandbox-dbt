-- Customer dimension. Note there is no config() block here: the
-- materialization (table) and schema (marts) come from dbt_project.yml, and
-- the enforced CONTRACT comes from _marts__models.yml -- config can live in
-- three places, with the model file winning on conflicts. See docs/04, /15.
-- (Fun fact: SQL comments are still rendered by Jinja, so you cannot even
-- MENTION the config function with double braces in a comment -- docs/09.)

with customers as (

    select * from {{ ref('stg_customers') }}

),

countries as (

    select * from {{ ref('country_codes') }}

),

orders as (

    select * from {{ ref('stg_orders') }}

),

payments as (

    select * from {{ ref('int_order_payments') }}

),

customer_orders as (

    select
        customer_id,
        min(ordered_at) as first_order_at,
        max(ordered_at) as most_recent_order_at,
        count(*) as number_of_orders
    from orders
    where status != 'cancelled'
    group by 1

),

customer_revenue as (

    select
        orders.customer_id,
        sum(payments.total_amount) as lifetime_value
    from orders
    inner join payments
        on orders.order_id = payments.order_id
    where orders.status not in ('cancelled', 'returned')
    group by 1

),

final as (

    select
        customers.customer_id,
        customers.first_name,
        customers.last_name,
        customers.email,
        customers.city,
        customers.country_code,
        countries.country_name,
        countries.region,
        customers.created_at as customer_since,
        customer_orders.first_order_at,
        customer_orders.most_recent_order_at,
        coalesce(customer_orders.number_of_orders, 0) as number_of_orders,
        coalesce(customer_revenue.lifetime_value, 0) as lifetime_value,

        -- window function over the whole dimension: quartile 1 = top spenders
        ntile(4) over (order by coalesce(customer_revenue.lifetime_value, 0) desc)
            as ltv_quartile

    from customers
    left join countries
        on customers.country_code = countries.country_code
    left join customer_orders
        on customers.customer_id = customer_orders.customer_id
    left join customer_revenue
        on customers.customer_id = customer_revenue.customer_id

)

select * from final
