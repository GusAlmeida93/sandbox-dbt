-- Jinja generating SQL: the pivot columns below are not written by hand --
-- they are produced by looping over the rows of the payment_methods SEED at
-- compile time (dbt_utils.get_column_values runs a real query against the
-- warehouse). Look at this model in target/compiled/ to see the generated
-- SQL. New payment method in the seed => new column here, for free. docs/09.
--
-- Whitespace-control warning: adding minus signs inside the set block's
-- delimiters (Jinja's whitespace-stripping syntax) would eat the surrounding
-- newlines and glue `select` onto this comment line, commenting it out.
-- Painful to debug; see docs/09. (And no, this comment cannot SHOW you the
-- syntax: SQL comments are still rendered by Jinja.)

{% set payment_methods = dbt_utils.get_column_values(
    table=ref('payment_methods'),
    column='payment_method',
    order_by='payment_method',
    default=['bank_transfer', 'credit_card', 'debit_card', 'gift_card', 'pix']
) %}

select
    order_id,
    sum(amount) as total_amount,
    {%- for method in payment_methods %}
    sum(case when payment_method = '{{ method }}' then amount else 0 end)
        as {{ method }}_amount{{ "," if not loop.last }}
    {%- endfor %}

from {{ ref('stg_payments') }}
group by order_id
