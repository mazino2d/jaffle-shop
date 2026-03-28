---
slug: feature-engineering
date: 2026-03-28
authors:
  - khoi
categories:
  - Serving
tags:
  - ML
  - feature engineering
  - point-in-time
---

# Feature Engineering: Bridging Analytics and Machine Learning

The gap between an analytical mart and a machine learning feature table is larger than it first appears. An analyst's `dim_customers` table answers "what is this customer's current profile?" A machine learning feature table must answer "what was this customer's profile at the moment of the event we're predicting?" These are fundamentally different questions, and conflating them is one of the most common sources of training data bugs in ML systems.

<!-- more -->

## Why ML Features Are a Distinct Layer

Analytical marts are designed for human consumption: they tell you the current state of business entities. Machine learning features are designed for model consumption: they describe the state of the world at a specific historical point in time.

The distinction matters because ML models are trained on historical data and deployed to make predictions on current data. If you train a churn model using each customer's *current* lifetime value rather than their lifetime value *at the moment of churn*, you've leaked future information into the training data. The model learns patterns that wouldn't be available at prediction time — a form of data leakage that makes training metrics look good while production performance is poor.

**The rule:** every feature in a training dataset must be a quantity that was knowable at the time of the prediction event.

## Point-in-Time Correctness

Point-in-time correctness means each row in a training dataset reflects the state of the world as it was at the timestamp of the event being predicted.

For a churn prediction model trained on orders:

```sql
-- Wrong: uses current customer state, not state at order time
SELECT
    o.order_id,
    o.created_at AS order_date,
    c.lifetime_value,          -- current LTV, includes future orders
    c.return_rate,             -- current return rate, includes future returns
    o.was_returned             -- label: did this order get returned?
FROM fct_orders o
JOIN dim_customers c ON o.customer_id = c.customer_id
```

The `lifetime_value` and `return_rate` here include data from after the order was placed. A customer who placed order #5 and later returned order #8 would show a high return rate in order #5's training row — information that didn't exist when order #5 was placed.

```sql
-- Correct: uses customer state as of order date
SELECT
    o.order_id,
    o.created_at AS order_date,
    c_at_order.lifetime_value,  -- LTV from orders before this one
    c_at_order.return_rate,     -- return rate from orders before this one
    o.was_returned
FROM fct_orders o
JOIN customer_features_at_order_time c_at_order
    ON o.customer_id = c_at_order.customer_id
    AND o.created_at BETWEEN c_at_order.valid_from AND c_at_order.valid_to
```

This requires either a historical feature table (recalculated for each point in time) or point-in-time join logic. It's more complex, but it's the only way to produce training data that reflects what the model would actually see at prediction time.

## RFM: A Practical Starting Framework

RFM (Recency, Frequency, Monetary) is a foundational framework for customer behavior features. Originally developed for direct mail marketing, it remains one of the most useful feature sets for customer-facing ML models.

**Recency:** how recently has the customer engaged? Measured as days since last order, last login, last meaningful action. Recent customers are more likely to respond to outreach and less likely to have churned.

**Frequency:** how often does the customer engage? Order count, session count, purchase frequency. High-frequency customers have demonstrated consistent engagement; sudden drops in frequency are a churn signal.

**Monetary:** how much has the customer spent? Total lifetime value, average order value, total items purchased. High-value customers warrant different interventions than low-value ones.

These three dimensions, combined, provide a surprisingly strong signal for churn prediction, return risk, and next-purchase probability. They're also straightforward to compute from standard transactional data:

```sql
SELECT
    customer_id,
    DATEDIFF(day, MAX(order_date), CURRENT_DATE) AS recency_days,
    COUNT(DISTINCT order_id) AS frequency,
    SUM(order_amount) AS monetary_value
FROM fct_orders
WHERE order_status = 'completed'
GROUP BY customer_id
```

Beyond the base RFM features, derived metrics add signal:
- `avg_order_value = monetary_value / frequency`
- `return_rate = returned_order_count / total_order_count`
- `avg_days_between_orders` (requires window functions over order history)
- `payment_failure_rate = failed_payment_count / total_payment_attempts`

## Feature Stores: When You Actually Need One

A feature store is a centralized system for storing, versioning, and serving features for both training and inference.

**What it provides:**
- Feature reuse: define `customer_lifetime_value` once, use in multiple models
- Training/serving consistency: the same feature computation logic runs offline (for training) and online (for inference)
- Point-in-time retrieval: historical feature values for any entity at any timestamp
- Versioning: track which feature definitions were used to train which model versions

**When you actually need one:**
- Multiple ML models reusing the same features (otherwise you're duplicating computation)
- Online inference requirements (predictions must be served in milliseconds, requiring pre-computed features in low-latency storage)
- Point-in-time training data at scale (features for millions of events, each with different historical lookback)

**When you don't need one:**
- A single model, retrained periodically, with no online serving requirement
- Features that are simple to compute at training time
- A small team where feature sharing is achieved through code, not infrastructure

Most early-stage ML systems don't need a feature store. The right time to adopt one is when the pain of not having it — duplicated computation, training/serving skew, point-in-time retrieval complexity — becomes concrete and measurable.

## The Practical Approach

For most data teams building initial ML capabilities:

1. **Build an `fct_orders` or `fct_events` table** — one row per training event, with its label (did the customer churn? was the order returned?)

2. **Build a `customer_features` table** — aggregations of customer behavior up to the current date

3. **Join them with point-in-time awareness** — for historical training data, ensure you're joining customer state as-of the event date, not current state

4. **Separate the feature table from the mart** — don't add ML-specific columns to `dim_customers`; create a dedicated `customer_features` table with ML-oriented naming and computation

5. **Document what each feature means and how it's computed** — ML engineers need to reproduce the same logic at inference time

## The Takeaway

Feature engineering is not just data transformation for ML — it's a distinct discipline with specific correctness requirements. Point-in-time correctness is the most critical: features must reflect the state of the world at prediction time, not current state. RFM provides a strong baseline. Feature stores are valuable at scale but often unnecessary early on. Build a dedicated feature layer, separate from your analytical marts, and treat point-in-time correctness as a non-negotiable requirement from the start.
