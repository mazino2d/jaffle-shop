{{
    config(
        materialized="incremental",
        unique_key="order_item_id",
        incremental_strategy="delete+insert",
    )
}}

-- Staging: order_items (incremental)
-- Order items are an append-only log. On incremental runs, only rows newer than
-- the latest _dlt_load_time already in this table are processed.
SELECT
    id AS order_item_id,
    order_id,
    product_id,
    quantity,
    unit_price,
    created_at::TIMESTAMP AS created_at,
    (quantity * unit_price) AS line_total
FROM {{ source("raw", "order_items") }}

{% if is_incremental() %}
    WHERE created_at::TIMESTAMP > (SELECT MAX(created_at) FROM {{ this }})
{% endif %}
