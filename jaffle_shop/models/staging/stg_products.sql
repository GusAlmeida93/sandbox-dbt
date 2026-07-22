with source as (

    select * from {{ source('shop_backend', 'raw_products') }}

),

renamed as (

    select
        id as product_id,
        name as product_name,
        category,

        -- money lives in integer cents upstream; convert exactly once, here,
        -- with a project macro so every model agrees on the conversion
        {{ cents_to_dollars('price_cents') }} as price,

        created_at

    from source

)

select * from renamed
