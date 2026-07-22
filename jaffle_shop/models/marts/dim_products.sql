with products as (

    select * from {{ ref('stg_products') }}

),

final as (

    select
        product_id,
        product_name,
        category,
        price,
        case
            when price >= 50 then 'premium'
            when price >= 15 then 'standard'
            else 'budget'
        end as price_tier,
        created_at
    from products

)

select * from final
