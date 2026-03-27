{{
    config(
        materialized="incremental",
        unique_key="payment_id",
        incremental_strategy="delete+insert",
    )
}}

-- Staging: payments (incremental)
-- Payments are an append-only log. On incremental runs, only rows newer than
-- the latest _dlt_load_time already in this table are processed.
SELECT
    id AS payment_id,
    order_id,
    method AS payment_method,
    status AS payment_status,
    amount,
    created_at::TIMESTAMP AS created_at
FROM {{ source("raw", "payments") }}

{% if is_incremental() %}
    WHERE created_at::TIMESTAMP > (SELECT MAX(created_at) FROM {{ this }})
{% endif %}
