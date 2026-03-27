{{
    config(
        materialized="incremental",
        unique_key="order_item_id",
        incremental_strategy="delete+insert",
    )
}}

-- Staging: order_items (incremental)
-- Order items are an append-only log. On incremental runs, only rows newer than
-- the latest created_at already in this table are processed. QUALIFY deduplicates
-- within the batch in case dlt loaded the same id more than once.
WITH source AS (
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
)
SELECT *
FROM source
QUALIFY ROW_NUMBER() OVER (PARTITION BY order_item_id ORDER BY created_at DESC) = 1
