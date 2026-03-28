---
slug: ingestion-patterns
date: 2026-03-28
authors:
  - khoi
categories:
  - Ingestion
tags:
  - ingestion
  - CDC
  - incremental
---

# Three Ingestion Patterns: Full Refresh, Incremental, and CDC

Choosing how to ingest data is one of the first decisions in a pipeline — and one where the wrong choice creates problems that compound over time. There are three fundamental patterns, each with different tradeoffs in simplicity, latency, and correctness.

<!-- more -->

## Pattern 1: Full Refresh

Full refresh means truncating the destination and reloading all source data on every run.

```sql
TRUNCATE destination_table;
INSERT INTO destination_table SELECT * FROM source;
```

**When it works well:**

- The source table is small enough to reload completely within your scheduling window
- The source doesn't expose change tracking (no `updated_at`, no CDC logs)
- You need guaranteed consistency — no partial states, no missed deletes

**The appeal:** simplicity and correctness. There's no logic for detecting what changed. The destination always reflects the exact current state of the source. Rerunning the job produces the same result (it's inherently idempotent).

**The problem at scale:** if the source table has 100M rows, you're moving 100M rows every run. This becomes expensive in compute, in network transfer, and in time.

Full refresh is the right default for small-to-medium mutable tables where tracking changes is more complex than the reload cost. When the reload cost becomes unacceptable, you move to incremental.

## Pattern 2: Incremental Loading

Incremental loading processes only the rows that have changed since the last run, typically identified by a watermark column.

```sql
INSERT INTO destination_table
SELECT * FROM source
WHERE updated_at > (SELECT MAX(updated_at) FROM destination_table);
```

**When it works well:**

- The source has a reliable `updated_at` or `created_at` column
- The table is too large to reload fully
- Deletes are rare or unimportant

**The problems:**

**Watermark reliability.** If `updated_at` is not maintained consistently by the source system (rows updated without touching the column, or with clock skew), you silently miss changes. This is the most common failure mode.

**Deletes are invisible.** If a row is deleted from the source, it remains in the destination indefinitely. Full refresh handles deletes automatically; incremental does not.

**Late-arriving data.** Events that arrive with a timestamp before the watermark will be missed. A common fix is a lookback window — always reprocess the last N hours/days — at the cost of some redundant processing.

Incremental loading requires trusting the watermark column. Before adopting it, verify that the source actually maintains it correctly.

## Pattern 3: Change Data Capture (CDC)

CDC captures changes at the database level, reading from the transaction log (binlog in MySQL, WAL in PostgreSQL) rather than querying the table directly.

Every INSERT, UPDATE, and DELETE is captured as an event and streamed to the destination.

**When it works well:**

- You need low-latency data (minutes, not hours)
- You need to capture deletes
- The source database can expose its transaction log
- You have the infrastructure to run a CDC connector

**The advantages over incremental:**

- No watermark column required — changes are captured at the database level
- Deletes are captured as explicit events
- Near real-time latency with continuous streaming

**The cost:**

- Requires infrastructure: a CDC connector (Debezium, Airbyte CDC, Fivetran) and typically a message broker (Kafka)
- Source database must have binlog/WAL enabled and the connector must have appropriate permissions
- Operational complexity: monitoring replication lag, handling connector failures, managing schema changes in the log

CDC is justified when you genuinely need near-real-time data or must capture deletes. It's overkill for most analytical pipelines.

## Choosing by Data Nature

The right pattern follows from the nature of the data, not the capabilities of your tools:

| Data characteristic | Right pattern |
|---|---|
| Small table, any size | Full refresh |
| Large table, reliable `updated_at`, deletes unimportant | Incremental |
| Large table, deletes matter, low latency required | CDC |
| Append-only events | Incremental (append) — no watermark needed |

A common mistake: choosing incremental because it sounds more efficient, without verifying that the watermark is reliable. Full refresh with a reliable result is better than incremental with silent data loss.

## A Note on Append-Only Tables

Event tables (payments, clicks, log entries) are a special case: they only accumulate new rows, never update or delete. For these, incremental loading with `id > MAX(id)` or `created_at > last_run` is straightforward and reliable — there's no risk of missing updates because updates don't happen.

This is why it makes sense to treat entity data and event data differently at the ingestion layer: the right write strategy differs for each.

## The Takeaway

Start with full refresh for small tables. Move to incremental when the reload cost becomes a real constraint, but verify the watermark. Add CDC only when near-real-time or delete capture is a genuine requirement. Don't adopt complexity preemptively — the simpler pattern is often the more reliable one.
