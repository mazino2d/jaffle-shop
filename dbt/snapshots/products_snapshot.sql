{% snapshot products_snapshot %}

{{
    config(
        unique_key="id",
        strategy="timestamp",
        updated_at="updated_at",
    )
}}

-- Capture SCD Type 2 history for products.
-- Price and name changes are preserved so historical orders reflect
-- correct values.
    SELECT
        id,
        name,
        category,
        price,
        is_active,
        created_at::TIMESTAMP AS created_at,
        updated_at::TIMESTAMP AS updated_at
    FROM {{ source("raw", "products") }}

{% endsnapshot %}
