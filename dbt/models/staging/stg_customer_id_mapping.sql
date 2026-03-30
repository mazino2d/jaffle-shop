-- Staging: customer_id_mapping
-- Maps old_id → new_id when the backend reassigns a customer's source ID.
-- Add rows here to preserve master_sk stability across ID migrations.
SELECT
    old_id::INTEGER AS old_id,
    new_id::INTEGER AS new_id
FROM {{ ref("customer_id_mapping") }}
