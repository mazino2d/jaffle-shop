---
slug: staging-intermediate-marts
date: 2026-03-28
description: Layered dbt transformation architecture — staging, intermediate, and marts — gives each transformation a single responsibility, making models easier to test and maintain.
authors:
  - khoi
categories:
  - Transformation
tags:
  - dbt
  - architecture
  - transformation
---

# Staging → Intermediate → Marts: The Case for Layered Transforms

Every transformation layer should have one clear responsibility. When you mix cleaning, joining, and business logic in the same model, you get a model that's hard to test, hard to debug, and hard to change. Layered transformation architecture solves this by giving each responsibility its own layer with clear rules.

<!-- more -->

## The Three Layers

### Staging: Clean, Don't Transform

Staging models sit directly on top of source tables. Their one job: make raw data usable without applying any business logic.

What staging does:
- Rename columns to consistent, readable names (`cust_id` → `customer_id`)
- Cast columns to correct types (`'2026-01-01'` string → `DATE`)
- Apply basic filters (deduplicate on unique key for append-only tables)
- Coalesce NULLs where semantically appropriate

What staging does not do:
- Join to other tables
- Apply business rules or conditions
- Compute derived fields beyond simple type casting
- Aggregate rows

The canonical rule: **one staging model per source table, 1:1 with the source schema (modulo cleaning).**

Staging models are materialized as views — they're cheap to create, and there's no value in caching data that's already in the source layer.

```sql
-- stg_orders.sql
SELECT
    id AS order_id,
    customer_id,
    status,
    CAST(total_amount AS DECIMAL(10, 2)) AS total_amount,
    CAST(created_at AS TIMESTAMP) AS created_at
FROM {{ source('raw', 'orders') }}
WHERE dbt_valid_to IS NULL  -- current snapshot version only
```

This model is transparent: anyone looking at `stg_orders` knows exactly what it maps to in the source.

### Intermediate: Business Logic, Hidden From Consumers

Intermediate models apply business logic: joining staging tables, computing derived fields, rolling up to a different grain.

What intermediate does:
- Join multiple staging models to produce a unified view
- Compute business-defined aggregations (`total_spend_per_customer`)
- Derive business fields (`is_returning_customer`, `days_since_signup`)
- Prepare data for the final mart model

What intermediate does not do:
- Expose data directly to BI tools or downstream consumers
- Join to staging models from different business domains without good reason
- Duplicate business logic that already exists in another model

The canonical rule: **intermediate models are implementation details, not part of the public interface.**

Intermediate models are often materialized as views or ephemeral (compiled inline) — they exist to simplify mart logic, not to store intermediate results for independent use.

```sql
-- int_customer_orders.sql
SELECT
    o.customer_id,
    COUNT(DISTINCT o.order_id) AS order_count,
    SUM(o.total_amount) AS lifetime_value,
    MIN(o.created_at) AS first_order_at,
    MAX(o.created_at) AS last_order_at
FROM {{ ref('stg_orders') }} o
GROUP BY 1
```

### Marts: The Public Interface

Marts are the only layer that downstream consumers — BI tools, ML pipelines, analysts writing ad-hoc queries — should query directly.

What marts do:
- Combine intermediate models into a single, coherent, queryable table
- Denormalize to make queries simple (join dimension attributes into the fact)
- Apply final business rules and definitions
- Materialize as tables (persistent, queryable without re-computation)

What marts do not do:
- Read directly from raw sources (must go through staging)
- Mix data from multiple unrelated domains in one model

```sql
-- dim_customers.sql
SELECT
    c.customer_id,
    c.name,
    c.email,
    c.country,
    c.tier,
    COALESCE(co.order_count, 0) AS order_count,
    COALESCE(co.lifetime_value, 0) AS lifetime_value,
    co.first_order_at,
    co.last_order_at
FROM {{ ref('stg_customers') }} c
LEFT JOIN {{ ref('int_customer_orders') }} co USING (customer_id)
```

This model is what analysts query. The complexity of the join and the aggregation logic is hidden in the intermediate layer.

## Why These Boundaries Matter

**Debugging.** When a mart produces wrong numbers, you can inspect the intermediate model to see if the aggregation logic is wrong. You can inspect the staging model to see if the raw data was misread. You know exactly where to look.

**Testing.** Staging models test source data quality (not_null, unique). Intermediate models test business logic correctness. Mart models test final output. Each layer has a clear scope for its tests.

**Change isolation.** If the source system renames a column, you update the staging model. Nothing downstream changes — they still reference `stg_orders.order_id`. If business logic for customer segmentation changes, you update the intermediate model without touching staging or the final mart join.

**Reuse.** The `int_customer_orders` model can be referenced by `dim_customers`, `order_features`, and any future model that needs customer-level aggregates. The logic is defined once.

## The Dependency Rule

Models must follow the dependency direction:

```
raw sources → staging → intermediate → marts
```

No model should reference a source at a different layer level. Marts should not read directly from raw sources. Intermediate models should not reference marts. Staging models should not reference other staging models (except through a source reference).

Violating these rules breaks the modularity that makes the architecture work.

## The Takeaway

Staging cleans. Intermediate joins and computes. Marts serve. When each layer does exactly one thing, the model is testable, debuggable, and changeable in isolation. The discipline of maintaining these boundaries pays off at scale — when the codebase has 50 models, clear layer boundaries are the difference between a navigable architecture and an unmaintainable tangle.
