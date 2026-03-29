-- Staging: orders — all historical versions with surrogate keys.
--
-- sk:        Unique per version (= dbt_scd_id from snapshot).
-- master_sk: Stable per order entity — useful when tracking an order across
--            status changes (placed → shipped → completed → returned).
--
-- Incremental strategy:
--   Full refresh  → master_sk via FIRST_VALUE window function (bootstrap only).
--   Daily runs    → master_sk via O(1) hash join against dim_order_sk_map.
{{ config(materialized='incremental', unique_key='sk', on_schema_change='fail') }}

WITH
{{ scd_surrogate_keys(
    ref('orders_snapshot'),
    'id',
    sk_map_ref=ref('dim_order_sk_map')
) }}

SELECT
    sk,
    master_sk,
    source_id AS order_id,
    canonical_id,
    customer_id,
    status,
    amount,
    placed_at::TIMESTAMP AS placed_at,
    updated_at::TIMESTAMP AS updated_at,
    valid_from,
    valid_to,
    is_current
FROM _sk_final
