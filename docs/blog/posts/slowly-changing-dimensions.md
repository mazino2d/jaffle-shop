---
slug: slowly-changing-dimensions
date: 2026-03-28
authors:
  - khoi
categories:
  - Data Modeling
tags:
  - data modeling
  - SCD
  - history
---

# Slowly Changing Dimensions: When History Matters More Than Current State

A dimension describes an entity — a customer, a product, a salesperson. Dimensions change over time: customers move to different cities, change their subscription tier, or update their email. Products get recategorized. Salespeople change regions.

The question every data model must answer: when a dimension changes, what do you do with history?

<!-- more -->

## The Business Question Determines the Answer

Before choosing an SCD type, identify what your business needs to know:

- "What is the customer's current tier?" → you only need current state, history doesn't matter
- "What was the customer's tier when they made this purchase?" → you need historical state at a point in time
- "How many customers were in the Premium tier at the end of last quarter?" → you need historical state for an entire population at a point in time

The type of question your downstream consumers ask determines which SCD approach is correct. The data model serves the queries, not the other way around.

## Type 1: Overwrite

Type 1 is the simplest approach: when a dimension value changes, overwrite the old value. No history is kept.

```
Before: customer_id=1, tier="Standard"
After:  customer_id=1, tier="Premium"
```

The old "Standard" value is gone. Any historical query that asks "what was this customer's tier at purchase time?" will see "Premium," even for purchases made before the upgrade.

**When to use Type 1:**
- The attribute doesn't affect historical analysis (e.g., a formatting fix to a name)
- The business explicitly doesn't need historical context for that attribute
- Storing history would create compliance issues (e.g., correcting PII should overwrite)

**When Type 1 is wrong:**
- Revenue attribution depends on the attribute at transaction time
- Auditing or compliance requires knowing what state data was in at a past date
- Trend analysis requires knowing the historical distribution

## Type 2: Add a New Row

Type 2 preserves history by creating a new row for each version of the dimension, tracking validity with date ranges.

```
customer_id=1, tier="Standard", valid_from=2025-01-01, valid_to=2026-01-15
customer_id=1, tier="Premium",  valid_from=2026-01-15, valid_to=NULL
```

The NULL `valid_to` indicates the current version. Historical versions have a non-NULL `valid_to`.

To get the customer's tier at the time of a purchase:

```sql
SELECT c.tier
FROM fct_orders o
JOIN dim_customers c ON o.customer_id = c.customer_id
WHERE o.order_date BETWEEN c.valid_from AND COALESCE(c.valid_to, CURRENT_DATE)
```

This query returns the tier that was active when the order was placed — even if the customer has since changed tiers.

**When to use Type 2:**
- Historical attribute values affect analysis (revenue attribution, cohort analysis)
- Auditing or compliance requires point-in-time accuracy
- The question "what was the state on date X?" must be answerable

**The tradeoffs:**
- The dimension table grows as history accumulates
- Queries are more complex (the date range join)
- You must track which row is "current" — conventionally `WHERE valid_to IS NULL`

## Type 6: Hybrid

Type 6 is a hybrid: it stores history (like Type 2, with multiple rows) but also adds a current value column to every row.

```
customer_id=1, tier="Standard", current_tier="Premium", valid_from=2025-01-01, valid_to=2026-01-15
customer_id=1, tier="Premium",  current_tier="Premium", valid_from=2026-01-15, valid_to=NULL
```

This allows two types of queries on the same model:
- "What was the tier at purchase time?" → join on date range, use `tier`
- "What is the customer's current tier?" → filter on `valid_to IS NULL`, use `current_tier`

**When to use Type 6:** when you frequently need both historical and current state in the same query, and you want to avoid a self-join or subquery to fetch the current value.

**The cost:** the `current_tier` column must be updated on every row for that entity when the current value changes. This is a write-heavy operation for slowly changing dimensions with large history.

## Implementing Type 2 in Practice

The standard implementation pattern:

1. **Ingestion:** load the full source table on each run (full refresh, since we need to detect changes)
2. **Snapshot:** compare new source records against the previous snapshot; if `updated_at` changed, close the old row and insert a new one
3. **Staging:** filter the snapshot table with `WHERE valid_to IS NULL` to produce a current-state view
4. **Downstream:** join on `customer_id` for current-state queries, or on `customer_id + date range` for historical queries

The snapshot step is where the history logic lives. The staging layer abstracts it: most downstream models want current state and can simply query staging without knowing the snapshot mechanism exists.

## The Decision Framework

| Question type | SCD type |
|---|---|
| "What is it now?" | Type 1 |
| "What was it then?" | Type 2 |
| "Both, in the same model" | Type 6 |
| "Is it sensitive data that must be corrected?" | Type 1 |

When in doubt: implement Type 2. You can always derive Type 1 behavior from Type 2 by filtering to the current row. You cannot reconstruct history from Type 1 once it's been overwritten.

## The Takeaway

The right SCD type follows from the questions your business needs to answer. Type 1 is appropriate when history doesn't matter. Type 2 is the standard for dimensions where historical state is needed for accurate analysis. Implement it early — reconstructing history after the fact requires re-ingesting and re-snapshotting, which is expensive and sometimes impossible.
