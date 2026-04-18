---
slug: dimensional-modeling
date: 2026-03-28
description: An introduction to dimensional modeling — fact tables, dimension tables, and star schema design — built for how analysts actually query data, not how applications write it.
authors:
  - Mazino2D
categories:
  - Data Modeling
tags:
  - data modeling
  - star schema
  - dimensional modeling
---

# Dimensional Modeling: Facts, Dimensions, and Star Schema

Normalized schemas are correct for transactional systems. They eliminate redundancy, enforce referential integrity, and make writes fast. They are also painful for analytics: answering "total revenue by product category for customers who signed up in Q1" requires joining six tables and knowing the exact relationship between each.

Dimensional modeling solves this. It's a schema design approach built for how analysts actually query data, not how applications write it.

<!-- more -->

## The Problem With Normalized Schemas in Analytics

In a normalized (3NF) OLTP schema, data is split into many small tables to avoid redundancy. A typical e-commerce schema might have: `orders`, `order_items`, `products`, `product_categories`, `customers`, `customer_addresses`, `payments`.

To answer "revenue by product category, by customer region, last 90 days" requires joining all of these tables. Analysts must understand foreign keys, join conditions, and the cardinality of each relationship. The query is complex, easy to write incorrectly, and often slow because normalization is optimized for writes, not reads.

Dimensional modeling inverts this: it's optimized for the questions analysts ask, at the cost of some redundancy.

## Facts and Dimensions

Dimensional modeling uses two types of tables:

**Fact tables** store measurements of business events. Each row represents something that happened: an order was placed, a payment was processed, a user clicked a button.

Fact tables are:
- **Narrow:** mostly numeric measurements (revenue, quantity, duration)
- **Large:** one row per event, potentially billions of rows
- **Additive:** most measures can be summed across any dimension

**Dimension tables** store the context for those events. Each row describes an entity: a customer, a product, a store, a date.

Dimension tables are:
- **Wide:** many descriptive attributes (name, category, region, tier)
- **Small:** one row per entity, typically thousands to millions of rows
- **Slowly changing:** the same entity exists over time, possibly with different attributes

## The Star Schema

A star schema connects one central fact table to multiple dimension tables through foreign keys:

```
            dim_customers
                  |
dim_dates — fct_orders — dim_products
                  |
            dim_payments
```

The fact table sits at the center. Each dimension table connects to it on a single key. To answer the revenue-by-category query:

```sql
SELECT
    p.category,
    c.region,
    SUM(o.revenue)
FROM fct_orders o
JOIN dim_products p ON o.product_id = p.product_id
JOIN dim_customers c ON o.customer_id = c.customer_id
WHERE o.order_date >= CURRENT_DATE - 90
GROUP BY 1, 2
```

Simple. No chained joins, no subqueries, no needing to know the relationship between `product_categories` and `products`.

## Snowflake Schema: A Tradeoff

A snowflake schema normalizes dimension tables, splitting them into further sub-dimensions:

```
dim_products → dim_product_categories → dim_product_subcategories
```

**Why do it:** reduces storage by eliminating redundancy in dimension tables. A product's category name isn't repeated in every product row — it's stored once in `dim_product_categories`.

**Why it hurts analytics:** now queries require an additional join to get category. The analytical simplicity of the star schema is partially lost. For dimension tables, which are small, the storage savings are rarely worth the query complexity.

**The practical guidance:** use star schema by default. Use snowflake only when dimension tables are large enough that redundancy creates a real storage concern, or when you have a genuine normalization requirement.

## Denormalization Is Not a Mistake in Analytics

In OLTP design, denormalization is a code smell — it means the same data lives in multiple places, risking inconsistency. In analytics, it's the correct design choice.

In a dimensional model, `dim_customers` might contain the customer's current country, even though that country was originally in a separate `addresses` table. That's intentional: it makes the join simple and the query fast.

The fact table might contain pre-computed fields like `order_total` even though it could be derived from `order_items`. That's also intentional: aggregating line items inside every revenue query is expensive and error-prone.

Denormalization in dimensional models trades storage for query simplicity and performance — an excellent tradeoff for analytical workloads.

## Building the Right Facts

Not all measures belong in a fact table. Good measures are:

**Additive:** can be summed across all dimensions. Revenue is additive — you can sum it by date, by product, by customer, or all three. Use it freely in fact tables.

**Semi-additive:** can be summed across some dimensions but not others. Account balance is semi-additive — summing across customers makes sense, but summing across time periods doesn't (you'd be double-counting).

**Non-additive:** cannot be summed meaningfully. Ratios, percentages, averages. Don't store these in fact tables — derive them at query time from the underlying additive measures.

## The Takeaway

Dimensional modeling is a query-first design philosophy. Design your tables around the questions analysts will ask, not around the structure of source systems. Fact tables capture events with numeric measurements. Dimension tables capture entity attributes. Star schema minimizes join complexity. Denormalize aggressively — storage is cheap, query complexity is expensive.
