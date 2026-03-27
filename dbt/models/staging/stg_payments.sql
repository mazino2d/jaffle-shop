{{
    config(
        materialized="incremental",
        unique_key="payment_id",
        incremental_strategy="delete+insert",
    )
}}

-- Staging: payments (incremental)
-- Payments are an append-only log. On incremental runs, only rows newer than
-- the latest created_at already in this table are processed. QUALIFY deduplicates
-- within the batch in case dlt loaded the same id more than once.
WITH source AS (
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
)
SELECT *
FROM source
QUALIFY ROW_NUMBER() OVER (PARTITION BY payment_id ORDER BY created_at DESC) = 1
