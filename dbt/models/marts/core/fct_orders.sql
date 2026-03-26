-- Mart: fct_orders
-- One row per order, enriched with payment summary and customer snapshot at order time.
SELECT
    o.order_id,
    o.customer_id,
    o.status AS order_status,
    o.amount AS order_amount,
    o.placed_at,
    o.updated_at,

    -- Payment summary
    COALESCE(p.payment_attempts, 0) AS payment_attempts,
    COALESCE(p.paid_amount, 0) AS paid_amount,
    COALESCE(p.is_paid, FALSE) AS is_paid,
    COALESCE(p.failed_payments, 0) AS failed_payments,
    COALESCE(p.refunded_payments, 0) AS refunded_payments,

    -- Computed flags
    o.status = 'returned' AS is_returned,
    o.amount - COALESCE(p.paid_amount, 0) AS unpaid_amount
FROM {{ ref("stg_orders") }} AS o
LEFT JOIN {{ ref("int_order_payments") }} AS p
    ON o.order_id = p.order_id
