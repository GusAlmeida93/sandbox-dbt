with source as (

    select * from {{ source('shop_backend', 'raw_payments') }}

),

renamed as (

    select
        id as payment_id,
        order_id,

        -- the payment gateway occasionally SHOUTS ('CREDIT_CARD');
        -- normalize so accepted_values / relationships tests hold
        lower(payment_method) as payment_method,

        {{ cents_to_dollars('amount_cents') }} as amount,
        paid_at

    from source

)

select * from renamed
