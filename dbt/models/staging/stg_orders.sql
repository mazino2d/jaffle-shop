-- Staging: orders
-- Selects the latest snapshot version of each order (dbt_valid_to IS NULL).
SELECT
    id AS order_id,
    customer_id,
    status,
    amount,
    placed_at::TIMESTAMP AS placed_at,
    updated_at::TIMESTAMP AS updated_at,
    dbt_valid_from AS valid_from,
    dbt_valid_to AS valid_to
FROM {{ ref("orders_snapshot") }}
WHERE dbt_valid_to IS NULL
