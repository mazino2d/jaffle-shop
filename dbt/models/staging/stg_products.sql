-- Staging: products
-- Selects the latest snapshot version of each product (dbt_valid_to IS NULL).
SELECT
    id AS product_id,
    name AS product_name,
    category,
    price,
    is_active,
    created_at::TIMESTAMP AS created_at,
    updated_at::TIMESTAMP AS updated_at,
    dbt_valid_from AS valid_from,
    dbt_valid_to AS valid_to
FROM {{ ref("products_snapshot") }}
WHERE dbt_valid_to IS NULL
