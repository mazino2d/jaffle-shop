-- Staging: customers
-- Selects the latest snapshot version of each customer (dbt_valid_to IS NULL).
-- Downstream models should use this view to get current customer state.
SELECT
    id AS customer_id,
    name,
    email,
    country,
    status,
    created_at::TIMESTAMP AS created_at,
    updated_at::TIMESTAMP AS updated_at,
    dbt_valid_from AS valid_from,
    dbt_valid_to AS valid_to
FROM {{ ref("customers_snapshot") }}
WHERE dbt_valid_to IS NULL
