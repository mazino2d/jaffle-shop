---
slug: backfilling-and-catchup
date: 2026-03-28
description: Learn how to safely reprocess historical data in data pipelines — the difference between backfilling and catchup, and how to design pipelines that support both.
authors:
  - Mazino2D
categories:
  - Orchestration
tags:
  - orchestration
  - backfilling
  - reliability
---

# Backfilling and Catchup: Reprocessing Historical Data

Every data pipeline will eventually need to reprocess historical data. A bug is discovered that corrupted two months of records. A business rule changes retroactively. A new model is added that needs to be populated from the beginning. The pipeline was down for three days and missed scheduled runs.

How you handle these situations — and whether your pipeline was designed to support them safely — determines whether reprocessing is a controlled operation or an emergency.

<!-- more -->

## Backfill vs. Catchup: Two Different Problems

These terms are sometimes used interchangeably, but they describe distinct scenarios.

**Catchup** is reprocessing missed scheduled runs. The pipeline was supposed to run daily at 6am, and it didn't run for three days. Catchup means running three consecutive daily jobs for those three missing days, in order.

The question: should the orchestrator automatically catch up on missed runs when the pipeline is restarted? In most cases, no — automatic catchup can create unexpected data load and resource contention. It's usually safer to configure catchup as off by default and enable it deliberately when needed.

**Backfill** is reprocessing historical data because something was wrong or has changed. The transformation logic had a bug that produced incorrect values. A business rule was updated that should apply retroactively. A new column is being added and needs historical values populated.

Backfill is typically more complex than catchup because:
- It often requires changing the transformation logic before reprocessing
- The scope may be weeks or months of data, not a few missed days
- It requires careful ordering: dependencies must be backfilled in topological order

## Prerequisites for Safe Backfilling

Backfilling is only safe if your pipeline is **idempotent**: running the same job for the same time window twice produces the same result as running it once.

A non-idempotent pipeline cannot be safely backfilled:
- A plain INSERT that doesn't deduplicate will double rows on the second run
- A running total computed incrementally at load time will be wrong after backfill
- A surrogate key assigned by auto-increment will create new IDs for existing records on reprocessing

If your pipeline uses TRUNCATE + INSERT for full refresh, MERGE for incremental loads, and unique-key deduplication at staging boundaries, it's safe to backfill.

Idempotency is not just good practice for reliability — it's the prerequisite for backfilling to work at all.

## Partitioned Backfill: Limiting Blast Radius

For large historical backfills (months of data), processing everything at once is risky:
- A failure partway through leaves the data in a mixed state (some partitions backfilled, some not)
- Resource contention from processing months of data simultaneously may impact production jobs
- If the backfill produces wrong results, you've corrupted everything at once

The safer approach: **partitioned backfill** — process one day (or one week) at a time.

```bash
# Run backfill one day at a time from start to end
for date in $(seq 2025-01-01 2026-01-01); do
    dbt run --select my_model --vars "{run_date: $date}" --full-refresh
done
```

Benefits:
- Each day's run is independently verifiable before proceeding
- A failure stops the backfill at a known partition boundary
- Resource usage is spread over time rather than concentrated
- Results can be spot-checked partition by partition

## Backfill Ordering in Dependency Chains

When backfilling a chain of dependent models, order matters:

```
stg_orders → int_customer_orders → dim_customers → fct_orders
```

Backfill `stg_orders` first. Then `int_customer_orders`. Then `dim_customers`. Then `fct_orders`. Backfilling `fct_orders` before `stg_orders` means it reads unprocessed staging data and re-produces the same wrong results you were trying to fix.

The dependency graph determines the backfill order. The topological sort of the DAG is the correct backfill sequence.

## Validating a Backfill Before Promoting

For large or high-stakes backfills, validate before promoting to production:

1. **Backfill to a staging schema** rather than overwriting production data directly
2. **Run quality checks** on the backfilled data: row counts, NULL rates, key metrics
3. **Compare samples** between the backfilled data and the previous data to verify the change is as expected
4. **Promote to production** only after validation passes

For smaller backfills where the risk is lower, direct production backfill with a verified idempotent pipeline is acceptable.

## Documenting Backfills

Backfills that touch historical data should be documented:

- What triggered the backfill (bug fix, logic change, new model)
- What date range was reprocessed
- What changed in the output data
- Who approved and ran the backfill

This documentation is valuable for:
- Future debugging ("when did this metric start looking different?")
- Audit trails for compliance-relevant data
- Understanding anomalies in historical trends that result from the backfill

## The Takeaway

Design your pipeline for backfilling from the start: idempotent operations, partitioned processing, topological ordering. Backfilling is not an exceptional scenario — it's a normal part of operating a data pipeline. When you need to reprocess historical data, the question should be "how do I safely backfill this?" not "is it even possible?"
