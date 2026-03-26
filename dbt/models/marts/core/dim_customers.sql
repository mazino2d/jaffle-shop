-- Mart: dim_customers
-- One row per customer with current profile and lifetime order summary.
SELECT
    c.customer_id,
    c.name,
    c.email,
    c.country,
    c.status,
    c.created_at,
    c.updated_at,

    -- Order history aggregates
    COALESCE(co.total_orders, 0) AS total_orders,
    COALESCE(co.total_spent, 0) AS total_spent,
    COALESCE(co.completed_orders, 0) AS completed_orders,
    COALESCE(co.returned_orders, 0) AS returned_orders,
    co.first_order_at,
    co.last_order_at
FROM {{ ref("stg_customers") }} AS c
LEFT JOIN {{ ref("int_customer_orders") }} AS co
    ON c.customer_id = co.customer_id
