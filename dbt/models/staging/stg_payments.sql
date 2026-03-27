SELECT
    id AS payment_id,
    order_id,
    method AS payment_method,
    status AS payment_status,
    amount,
    created_at::TIMESTAMP AS created_at
FROM {{ source("raw", "payments") }}
