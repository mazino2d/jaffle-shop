SELECT
    id AS order_item_id,
    order_id,
    product_id,
    quantity,
    unit_price,
    created_at::TIMESTAMP AS created_at,
    (quantity * unit_price) AS line_total
FROM {{ source("raw", "order_items") }}
