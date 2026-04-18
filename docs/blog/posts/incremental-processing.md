---
slug: incremental-processing
date: 2026-03-28
description: Incremental processing reduces pipeline cost by processing only new data, but introduces correctness challenges around late-arriving data that must be addressed explicitly.
authors:
  - Mazino2D
categories:
  - Transformation
tags:
  - incremental
  - late data
  - reliability
---

# Incremental Processing and Late-Arriving Data

Processing only new data seems like an obvious optimization: why rebuild everything when you only need to process what changed? The reality is more complex. Incremental processing introduces correctness challenges — particularly around late-arriving data — that don't exist with full rebuild approaches.

<!-- more -->

## Why Incremental?

Full rebuild — reprocessing all historical data on every run — is simple and correct. For small datasets, it's the right default. But as data volume grows, full rebuild becomes prohibitively slow or expensive.

Incremental processing processes only the rows added or changed since the last run. A model that processes 10 million events per day processes 10 million rows on the first build and ~28,000 rows (one day's worth) on every subsequent run.

The cost: correctness is no longer automatic. You have to explicitly handle the cases where incremental logic breaks down.

## The Simple Case: Append-Only Tables

The easiest incremental case is append-only event tables. Events have a `created_at` timestamp and never change after creation.

```sql
SELECT *
FROM raw_events
WHERE created_at > (SELECT MAX(created_at) FROM this)
```

This works reliably because:
- Events don't change after creation (no updates to miss)
- The `created_at` timestamp is set by the producer at event time (reliable watermark)
- There's a natural deduplication key (event_id) to handle duplicate ingestion

For append-only tables, incremental is safe and straightforward.

## The Problem: Late-Arriving Data

Late-arriving data is an event that reaches your pipeline after its event timestamp has already been processed.

Example: a payment event with `created_at = 2026-01-10 14:00:00` arrives in your raw table at 2026-01-12 09:00:00 — two days after it occurred. If your pipeline ran on January 11th and filtered `WHERE created_at > '2026-01-11'`, this event is permanently missed.

Late arrival happens for real reasons:
- Mobile apps that buffer events offline and sync when reconnecting
- Backend services that retry failed event writes with original timestamps
- Third-party systems with delayed delivery guarantees
- Manual data corrections with historical timestamps

For many systems, a meaningful percentage of events arrive hours or days late. Ignoring late data means systematically undercounting recent periods.

## The Lookback Window

The standard mitigation is a **lookback window**: always reprocess the last N days, even if those days have been processed before.

```sql
SELECT *
FROM raw_events
WHERE created_at >= DATEADD(day, -3, (SELECT MAX(created_at) FROM this))
```

This reprocesses the last 3 days on every run. Events that arrived late within that window are captured. Events that arrive after the window closes are permanently missed — an accepted tradeoff.

The lookback window size is a correctness-vs-cost tradeoff:
- Larger window: more late data captured, more rows reprocessed each run
- Smaller window: cheaper runs, but some late data missed

Choose based on the empirical latency distribution of your data: if 99% of events arrive within 24 hours, a 3-day lookback provides ample safety.

## Deduplication Within the Lookback

When reprocessing historical data, you'll encounter rows that were already processed. Without deduplication, you get duplicates in the output.

The fix: use a unique key to deduplicate within the incremental run.

```sql
SELECT *
FROM raw_events
WHERE created_at >= DATEADD(day, -3, (SELECT MAX(created_at) FROM this))
QUALIFY ROW_NUMBER() OVER (PARTITION BY event_id ORDER BY loaded_at DESC) = 1
```

This selects only one row per `event_id`, taking the most recent version if the same event appears multiple times.

## When Incremental Logic Is Wrong: Full Reprocessing

Incremental models encode their logic in SQL. When that logic needs to change — a bug is fixed, a business rule is updated, a new column is added — the historical data was processed with the old logic and the new runs use the new logic. The model is inconsistent across time.

The correct fix: trigger a full reprocessing of the incremental model from scratch. In dbt terms, this is `dbt run --full-refresh`. The entire model is rebuilt, with all historical data processed through the current logic.

Full reprocessing should be planned for:
- Bug fixes that affected historical calculations
- Business rule changes that apply retroactively
- New columns added to the model that need historical values populated

The ability to trigger a full rebuild safely depends on the model being idempotent — another reason idempotency is non-negotiable.

## Reprocessing vs. Correction

Two strategies for handling wrong historical data:

**Reprocessing:** re-run the model from scratch, processing all historical source data through the corrected logic. Correct and complete, but expensive. Required when the transformation logic was wrong.

**Correction:** insert or update specific rows to fix known bad values. Faster, but requires knowing exactly which rows are wrong and what the correct values should be. Appropriate for isolated data errors, not for logic bugs.

Reprocessing is always the safer approach. Corrections are appropriate only when the scope of the problem is small and precisely known.

## The Takeaway

Incremental processing is an optimization, not a correctness guarantee. It works reliably for append-only tables with stable logic. It requires explicit handling — lookback windows and deduplication — to correctly capture late-arriving data. And it requires full reprocessing whenever the transformation logic changes. The tradeoff: faster runs, at the cost of more careful design and explicit correctness management.
