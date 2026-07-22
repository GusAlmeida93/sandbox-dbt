-- MICROBATCH incremental (dbt 1.9+): dbt splits processing into one batch
-- per day between `begin` and "now", and each batch only reads the matching
-- slice of the upstream (stg_events declares event_time, so dbt injects the
-- date filter automatically -- check target/run/ after a run). Batches are
-- independently retryable and replaceable:
--   dbt run -s fct_events --event-time-start "2026-07-02" --event-time-end "2026-07-03"
-- reprocesses exactly one day. No is_incremental() plumbing needed. docs/11.
{{ config(
    materialized='incremental',
    incremental_strategy='microbatch',
    event_time='event_ts',
    batch_size='day',
    begin=var('training_start_date'),
    lookback=1,
    unique_key='event_id'
) }}

select
    event_id,
    customer_id,
    event_type,
    page,
    event_ts,
    event_ts::date as event_date

from {{ ref('stg_events') }}
