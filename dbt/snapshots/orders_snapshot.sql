{% snapshot orders_snapshot %}

{{
    config(
        unique_key="id",
        strategy="timestamp",
        updated_at="updated_at",
    )
}}

-- Capture SCD Type 2 history for orders.
-- Order status transitions (placed → shipped → completed) are tracked here.
SELECT
    id,
    customer_id,
    status,
    amount,
    placed_at::TIMESTAMP AS placed_at,
    updated_at::TIMESTAMP AS updated_at
FROM {{ source("raw", "orders") }}

{% endsnapshot %}
