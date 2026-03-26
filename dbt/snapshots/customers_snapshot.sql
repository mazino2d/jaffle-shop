{% snapshot customers_snapshot %}

{{
    config(
        unique_key="id",
        strategy="timestamp",
        updated_at="updated_at",
    )
}}

-- Capture SCD Type 2 history for customers.
-- The backend updates records in-place; snapshots preserve each version.
SELECT
    id,
    name,
    email,
    country,
    status,
    created_at::TIMESTAMP AS created_at,
    updated_at::TIMESTAMP AS updated_at
FROM {{ source("raw", "customers") }}

{% endsnapshot %}
