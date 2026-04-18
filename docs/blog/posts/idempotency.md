---
slug: idempotency
date: 2026-03-28
description: Idempotent pipelines produce the same result whether run once or ten times — the essential property for safe retries and reliable operational recovery.
authors:
  - Mazino2D
categories:
  - Ingestion
tags:
  - reliability
  - best practices
---

# Idempotency: Pipelines That Are Safe to Run Twice

A well-designed pipeline should produce the same result whether it runs once or ten times. This property — idempotency — is not a nice-to-have. It's the foundation of operational reliability.

<!-- more -->

## Why Retries Are Inevitable

Pipelines fail. The causes are mundane and unavoidable:

- Network timeouts between the pipeline and the source API
- The warehouse runs out of memory mid-transformation
- A scheduled job overlaps with a previous run that hadn't finished
- A deployment restarts the orchestrator mid-job
- A developer manually triggers a backfill

In every case, the right response is to retry the job. But retrying a non-idempotent pipeline creates a new problem: duplicate data, double-counted aggregates, corrupted state.

If you can't safely retry, you can't safely operate.

## What Idempotency Means

A mathematical function `f` is idempotent if `f(f(x)) = f(x)`. Apply it twice and the result is the same as applying it once.

For a data pipeline: running the job again for the same time window produces the same data in the destination. No duplicates, no gaps, no drift.

## Non-Idempotent Patterns (and Why They Break)

**Plain INSERT without deduplication:**

```sql
INSERT INTO payments SELECT * FROM raw.payments WHERE created_at > :last_run;
```

If this runs twice — because of a retry, a manual rerun, or a scheduling overlap — every row from the source is inserted twice. Downstream aggregations like `SUM(amount)` are now double-counted.

**Running totals computed at load time:**

```sql
INSERT INTO daily_totals SELECT date, SUM(amount) FROM payments GROUP BY date;
```

Running this twice for the same date appends a duplicate summary row. Your total for that day is now 2x.

**Sequence-based IDs assigned at load time:**

```sql
INSERT INTO fact_orders (surrogate_id, ...) VALUES (NEXTVAL('orders_seq'), ...);
```

Each run generates new surrogate IDs for the same source rows. Joins on those IDs break.

## Idempotent Patterns

**TRUNCATE + INSERT (for full refresh):**

```sql
TRUNCATE destination_table;
INSERT INTO destination_table SELECT * FROM source;
```

Truncating before inserting means running twice produces the same result. This is the simplest idempotent pattern.

**MERGE / UPSERT (for incremental):**

```sql
MERGE INTO destination USING source ON destination.id = source.id
WHEN MATCHED THEN UPDATE SET ...
WHEN NOT MATCHED THEN INSERT ...;
```

Running twice with the same source data updates existing rows (no-op if data is unchanged) and inserts new ones. No duplicates.

**Deduplication with a unique key (for append-only events):**

Append-only event tables (payments, clicks) can accumulate duplicates if the source sends the same event twice or if the pipeline retries. The standard fix: deduplicate in the staging layer using the event's natural unique key.

```sql
-- In the incremental staging model:
SELECT *
FROM source
QUALIFY ROW_NUMBER() OVER (PARTITION BY payment_id ORDER BY loaded_at DESC) = 1
```

This ensures that regardless of how many times the source sends the same payment record, only one row per `payment_id` appears in staging.

## Idempotency Is a Design Property

Idempotency cannot be added as an afterthought. It must be designed in from the start, at every layer:

- **Ingestion:** full refresh (truncate + insert) or upsert, never plain append for mutable data
- **Staging:** deduplication logic for event tables, unique keys as the foundation
- **Transformation:** models that read from already-deduplicated staging produce idempotent results naturally
- **Orchestration:** ensure jobs for the same time window replace (not append to) previous results

## The Practical Test

For any pipeline step, ask: if I run this step again right now with the same inputs, is the output identical to what it was before?

If the answer is no, the step is not idempotent. Find the INSERT that doesn't check for existing rows. Find the aggregation that appends instead of replaces. Fix it before a 3am retry creates corrupted data that takes days to untangle.

## The Takeaway

Retries are not exceptional events — they're the normal operating condition of any production pipeline. Idempotency is what makes retries safe. Design for it from the start: prefer TRUNCATE + INSERT over plain INSERT, use MERGE for incremental loads, and deduplicate event data at the staging boundary with a unique key.
