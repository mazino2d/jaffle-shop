-- Intermediate: customer order history
-- Aggregates order-level metrics per customer, used by core and feature models.
-- Filters to is_current = TRUE to count each order once (its final state).
SELECT
    o.customer_id,
    COUNT(o.order_id) AS total_orders,
    SUM(o.amount) AS total_spent,
    MIN(o.placed_at) AS first_order_at,
    MAX(o.placed_at) AS last_order_at,
    COUNT(CASE WHEN o.status = 'returned' THEN 1 END) AS returned_orders,
    COUNT(CASE WHEN o.status = 'completed' THEN 1 END) AS completed_orders
FROM {{ ref("stg_orders") }} AS o
WHERE o.is_current = TRUE
GROUP BY o.customer_id
