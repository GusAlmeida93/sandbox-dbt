-- Staging model: 1:1 with the source table. Rename, cast, lightly clean --
-- and NOTHING else (no joins, no aggregation). Every downstream model reads
-- staging instead of raw, so cleaning happens exactly once. See docs/04.

with source as (

    select * from {{ source('shop_backend', 'raw_customers') }}

),

renamed as (

    select
        id as customer_id,

        -- the source system stores names in whatever case the cashier typed
        initcap(first_name) as first_name,
        initcap(last_name)  as last_name,
        lower(email)        as email,

        address,
        city,
        upper(country_code) as country_code,

        created_at,
        updated_at,
        _synced_at as synced_at

    from source

)

select * from renamed
