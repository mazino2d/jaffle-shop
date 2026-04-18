---
slug: fact-table-patterns
date: 2026-03-28
description: Compare the three fact table patterns — transactional, periodic snapshot, and accumulating snapshot — and learn which design fits each type of business measurement.
authors:
  - Mazino2D
categories:
  - Data Modeling
tags:
  - data modeling
  - fact tables
  - dimensional modeling
---

# Fact Table Patterns: Transactional, Periodic Snapshot, Accumulating Snapshot

Not all measurements are the same. Some record an event that happens at a point in time. Some capture a state that changes continuously. Some track a process that passes through multiple stages. Each pattern calls for a different fact table design.

<!-- more -->

## Transactional Fact Tables

A transactional fact table records individual business events — one row per event, at the moment it occurs.

Examples:
- A payment was processed: one row for that payment
- A user clicked an ad: one row for that click
- A product was shipped: one row for that shipment

The key characteristics:

**Grain: one row per event.** Each row captures a single, atomic business occurrence.

**Sparse measures:** not every event has every measure. An order might have a `discount_amount` of NULL if no discount was applied. This is expected.

**Additive measures:** revenue, quantity, duration — all additive across dimensions. You can sum across any combination of time, customer, product, geography.

**Never updated:** once a transaction is recorded, it's immutable. Corrections are new rows, not updates.

Transactional fact tables are the most common type and the right default for event-driven data. For e-commerce: `fct_orders` (one row per order), `fct_payments` (one row per payment attempt), `fct_page_views` (one row per view).

## Periodic Snapshot Fact Tables

A periodic snapshot captures the state of something at fixed, regular intervals — regardless of whether anything changed.

Examples:
- Account balance at end of each day
- Inventory level at end of each week
- Active user count at end of each month

The key characteristics:

**Grain: one row per entity per time period.** Every account has a row for every day, even if the balance didn't change.

**Semi-additive measures:** account balance summed across accounts is meaningful ("total deposits"). Account balance summed across time periods is not ("total balance last 30 days" double-counts).

**Regular cadence:** rows are inserted on a schedule, not triggered by events. If no transaction occurred, a row is still inserted with the current state.

Periodic snapshots answer questions like "what was the inventory level on November 15th?" or "how have active users trended over the last 12 months?" — questions that transactional tables can technically answer but require expensive window functions and careful handling of time gaps.

**Implementation:** typically a scheduled dbt model that takes a snapshot of the current state of a dimension or aggregate:

```sql
SELECT
    CURRENT_DATE AS snapshot_date,
    customer_id,
    account_balance,
    subscription_tier
FROM dim_customers
```

Run daily, this produces a complete daily history of customer account state.

## Accumulating Snapshot Fact Tables

An accumulating snapshot tracks a business process through multiple stages, with one row per process instance that is updated as the process progresses.

Examples:
- An order moving through stages: placed → picked → shipped → delivered
- A loan application progressing: submitted → reviewed → approved → funded
- A support ticket: opened → assigned → in-progress → resolved → closed

The key characteristics:

**Grain: one row per process instance.** One row per order, one row per loan application, one row per ticket.

**Multiple date columns:** one date column per milestone. `placed_at`, `picked_at`, `shipped_at`, `delivered_at`.

**Updated as milestones complete:** when an order ships, the `shipped_at` column in its row is updated. This is the only fact table type where existing rows are updated.

**Lag measures:** the interval between milestones is often the key measurement. `shipped_at - placed_at` is the fulfillment time. `delivered_at - shipped_at` is the transit time.

Accumulating snapshots answer questions like "what is the average time from order placement to delivery?" or "at what stage are most tickets stalled?" — questions about process efficiency and flow.

**When to use:** when the business process has a defined lifecycle with well-known stages, and the analysis focuses on the movement through those stages rather than the individual events at each stage.

## Choosing the Right Pattern

| Question | Fact table type |
|---|---|
| "How many orders were placed today?" | Transactional |
| "What was the account balance on a specific date?" | Periodic snapshot |
| "How long does fulfillment take, end to end?" | Accumulating snapshot |
| "How has revenue trended over 12 months?" | Transactional |
| "What inventory levels did we carry last quarter?" | Periodic snapshot |
| "At what stage do applications most often stall?" | Accumulating snapshot |

In practice, most data models are dominated by transactional fact tables, with periodic snapshots added for semi-additive measures like balances and inventory. Accumulating snapshots are less common but invaluable when the business process warrants them.

## The Takeaway

The type of fact table follows from the type of question. Transactional for event-level analysis, periodic snapshot for state-over-time analysis, accumulating snapshot for process-lifecycle analysis. Getting the grain right — what exactly does one row represent — is the most important modeling decision for each table.
