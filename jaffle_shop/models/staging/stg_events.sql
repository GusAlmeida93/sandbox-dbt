-- event_time tells dbt which column represents "when this row happened".
-- It is REQUIRED here because the downstream microbatch model (fct_events)
-- filters its upstreams by batch window -- without it, every batch would
-- silently re-scan the whole table. See docs/11.
{{ config(event_time='event_ts') }}

with source as (

    select * from {{ source('web_analytics', 'raw_events') }}

),

renamed as (

    select
        id as event_id,

        -- null for logged-out visitors: this is WHY there is no not_null
        -- test on this column
        customer_id,

        event_type,
        page,
        event_ts

    from source

    -- a target-aware Jinja macro: expands to a LIMIT only when
    -- --vars '{limit_dev_rows: true}' is passed in the dev target (docs/09)
    {{ limit_in_dev(50000) }}

)

select * from renamed
