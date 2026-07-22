with source as (

    select * from {{ source('shop_backend', 'raw_orders') }}

),

renamed as (

    select
        id as order_id,
        customer_id,
        lower(status) as status,
        ordered_at,

        -- passthrough on purpose: fct_orders (incremental) and the snapshots
        -- use updated_at to detect changed rows
        updated_at,
        _synced_at as synced_at

    from source

)

select * from renamed
