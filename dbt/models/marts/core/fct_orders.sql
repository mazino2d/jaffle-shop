-- Mart: fct_orders
-- One row per order (current version) with payment summary and surrogate keys.
--
-- order_sk / order_master_sk:       Identify the order version and entity.
-- customer_sk / customer_master_sk: Point-in-time customer version active when the
--                                   order was placed, and the stable entity key.
--
-- Join strategy:
--   Primary: point-in-time — finds the customer version whose validity window
--            contains placed_at (captures customer state at order time).
--   Fallback: if placed_at precedes all snapshot versions (bootstrap gap), use
--             the current customer version to ensure no NULLs.
SELECT
    o.sk AS order_sk,
    o.master_sk AS order_master_sk,
    o.order_id,
    o.customer_id,
    o.status AS order_status,
    o.amount AS order_amount,
    o.placed_at,
    o.updated_at,
    COALESCE(c_pit.sk, c_cur.sk) AS customer_sk,
    COALESCE(c_pit.master_sk, c_cur.master_sk) AS customer_master_sk,

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
-- Primary: point-in-time customer version at order placement
LEFT JOIN {{ ref("stg_customers") }} AS c_pit
    ON
        o.customer_id = c_pit.customer_id
        AND o.placed_at >= c_pit.valid_from
        AND (c_pit.valid_to IS NULL OR o.placed_at < c_pit.valid_to)
-- Fallback: for orders placed before the first snapshot (bootstrap gap)
LEFT JOIN {{ ref("stg_customers") }} AS c_cur
    ON
        c_pit.sk IS NULL
        AND o.customer_id = c_cur.customer_id
        AND c_cur.is_current = TRUE
WHERE o.is_current = TRUE
