-- Analyses live in analyses/ and are COMPILED but never RUN: full Jinja +
-- ref() support, no relation created. Good for exploratory queries you want
-- version-controlled next to the project. Find the runnable SQL in
-- target/compiled/jaffle_shop/analyses/ after `dbt compile`. See docs/13.

select
    customer_id,
    first_name,
    last_name,
    country_name,
    number_of_orders,
    lifetime_value,
    ltv_quartile

from {{ ref('dim_customers') }}
order by lifetime_value desc
limit 10
