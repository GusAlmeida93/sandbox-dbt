with source as (

    select * from {{ source('shop_backend', 'raw_order_items') }}

),

renamed as (

    select
        id as order_item_id,
        order_id,
        product_id,
        quantity,
        {{ cents_to_dollars('unit_price_cents') }} as unit_price

    from source

)

select * from renamed
