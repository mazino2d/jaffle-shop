---
slug: mutable-vs-immutable
date: 2026-03-28
description: The most fundamental split in data engineering — mutable entities that change in place versus immutable events that accumulate — and why mixing them corrupts history.
authors:
  - Mazino2D
categories:
  - Foundations
tags:
  - data modeling
  - ingestion
---

# Two Mental Models for Data: Mutable Entities vs. Immutable Events

Before choosing a tool, a write strategy, or a pipeline pattern — you need to answer one question: **does this data change, or does it accumulate?**

This is the most fundamental split in data engineering, and getting it wrong causes double-counting, silent data loss, and corrupted history downstream.

<!-- more -->

## The Two Types

Every piece of data in a system falls into one of two categories:

**Mutable entities** are records that represent the current state of something. A customer record. A product listing. An order status. These change in place — a customer updates their email, an order moves from `placed` to `shipped`. At any point in time, there is one authoritative version.

**Immutable events** are records that represent something that happened. A payment attempt. A page view. A log entry. These never change — once written, they are facts. The only valid operation is appending new ones.

## Why It Matters

The mistake is treating entity data like event data, or vice versa.

**Appending entity data** gives you growing duplicates. Every sync creates a new row for the same customer, and you lose the concept of "current state" without complex deduplication logic.

**Overwriting event data** destroys history. If a payment attempt is retried and you overwrite the first record, you've lost the information that a failure occurred.

### The downstream consequences

| Mistake | Symptom | Root cause |
|---|---|---|
| Appending entities | Inflated row counts, wrong aggregations | No "current state" concept |
| Overwriting events | Missing transactions, incorrect totals | History destroyed on rewrite |
| Not tracking entity history | Can't answer "what was the status on day X?" | No SCD implementation |

## Applying the Mental Model

Once you've classified your data, the write strategy follows naturally:

- **Mutable entities** → full replace on each load (or CDC if volume is large), then snapshot for history
- **Immutable events** → append-only, with deduplication at the staging boundary

This isn't a tool decision — it's a data design decision. The tools follow.

## A Concrete Example

In a typical e-commerce system:

- `customers`, `orders`, `products` — **mutable entities**. A customer's status changes. An order's status transitions. These are replaced on each sync. If you need to know what an order's status was last Tuesday, you snapshot them.

- `payments`, `order_items` — **immutable events**. A payment attempt happened. A line item was part of an order. These are appended. Nothing overwrites them.

The staging layer unifies both: entities come through as snapshots filtered to current state (`WHERE valid_to IS NULL`), events come through as deduplicated incremental loads. Downstream models don't need to know the difference.

## The Takeaway

Before you write any pipeline code, ask: is this data describing **what something is right now**, or **what happened at a point in time**?

The answer determines your write strategy, your deduplication logic, your snapshot design, and your incremental model patterns — everything else flows from it.
