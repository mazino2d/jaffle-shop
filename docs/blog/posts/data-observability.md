---
slug: data-observability
date: 2026-03-28
description: Data observability goes beyond job monitoring to continuously track data freshness, schema health, and row-level correctness — because a successful job does not mean correct data.
authors:
  - khoi
categories:
  - Quality & Reliability
tags:
  - observability
  - monitoring
  - lineage
---

# Data Observability: Beyond "Did the Job Succeed?"

A pipeline job that completes successfully is not the same as data that is correct. Jobs can succeed while loading stale data, incorrect aggregations, missing rows, or schema-shifted values. "The job ran" answers the operational question. It says nothing about whether the data is trustworthy.

Data observability is the practice of continuously understanding the state of the data — not just the state of the pipeline.

<!-- more -->

## Monitoring vs. Observability

**Monitoring** is about the pipeline infrastructure: did the job run, did it fail, how long did it take, how much compute did it use? These are operational metrics about the system that moves data.

**Observability** is about the data itself: is it fresh, is the volume expected, does the schema match, do the distributions look normal? These are data quality signals about the state of the data the pipeline produces.

Both are necessary. A job that fails is an operational problem. A job that succeeds but produces wrong data is an observability problem — and often the harder one to detect.

## Four Pillars of Data Observability

### Freshness

Is the data current? The most recent record in a table should be within a defined window of the current time.

```
Last updated: 26 hours ago. Expected: ≤24 hours.
```

Freshness failures indicate that upstream data hasn't arrived, that a pipeline job silently failed, or that an ingestion process stopped producing output without raising an error.

Freshness is the first signal to check because it's the simplest to define and the most common failure mode.

### Volume

Is the row count within expected bounds? A table that normally receives 50,000 rows per day receiving 500 rows on a given day is a signal worth investigating — even if the job succeeded.

Volume anomalies can indicate:
- Upstream data loss or truncation
- A filter that was incorrectly applied
- A source system that stopped generating events
- A legitimate spike or drop that should be understood

Volume checks work best with a baseline: the average and variance of row counts over the past N days. Deviations beyond a threshold trigger an alert.

### Schema

Has the schema changed? New columns, removed columns, type changes — all of these can indicate a source system change that the pipeline wasn't updated to handle.

Schema drift detection compares the current table schema against the expected schema on each run. Non-breaking changes (new columns) generate a notification. Breaking changes (removed required columns, type incompatibilities) trigger an alert.

### Distribution

Do the values in key columns look normal? A `country` column that was 60% "US" yesterday and is 60% "NULL" today is a problem that freshness, volume, and schema checks all miss.

Distribution checks monitor:
- NULL rates per column (a spike in NULLs indicates upstream data problems)
- Value distributions for categorical columns (unexpected new values, missing expected values)
- Numeric ranges (revenue shouldn't be negative, ages shouldn't be 500)

Distribution monitoring is the most powerful and most complex of the four pillars. Start with NULL rates — they catch a large proportion of real problems with minimal implementation overhead.

## Lineage: Understanding Impact

Data lineage maps the dependencies between models: A depends on B, B depends on C.

Lineage answers two critical questions:

**Root cause:** when something looks wrong in a dashboard, which upstream models and sources does it depend on? Where did the problem enter?

**Impact assessment:** if source table X changes or fails, which downstream models are affected? Which dashboards will show wrong numbers?

Without lineage, troubleshooting requires manual tracing through a codebase. With lineage, the dependency graph is explicit and queryable.

Beyond technical dependencies, lineage should include **exposures** — the downstream consumers that ultimately depend on the data: dashboards, ML models, external reports, APIs. Knowing that `fct_orders` feeds both the executive dashboard and the churn prediction model determines the urgency of fixing a problem in that table.

## Alerting That Doesn't Cry Wolf

Observability tools produce value only if their alerts are actionable. An alert that fires too often is ignored. An alert with no clear owner is also ignored.

Effective alerting:
- **Specific:** "NULL rate for `payment_status` in `fct_orders` increased from 0.1% to 14.7%"
- **Actionable:** routes to a team with the context to investigate and the authority to fix it
- **Tiered:** distinguish warnings (investigate when convenient) from errors (investigate now)
- **Suppressible:** allow known anomalies (planned maintenance, expected seasonal spikes) to be muted without disabling the alert permanently

## Starting Simply

Full observability tooling is not required to get started. Minimum viable observability:

1. **Freshness checks in the pipeline itself.** Define max expected staleness for each source and alert when violated. (Most transformation tools support this natively.)

2. **Row count logging.** Log the row count of each table after each build. Plot it. Set an alert for deviations beyond 20% from the 7-day average.

3. **NULL rate monitoring for critical columns.** For the five most important columns in your core fact tables, compute NULL rates daily and alert on spikes.

4. **Lineage in documentation.** Document which models depend on which sources. Even a text description is better than nothing.

This is achievable with standard SQL and a simple alerting mechanism. It catches the majority of real-world data quality failures.

## The Takeaway

Pipeline success is a necessary but not sufficient condition for data correctness. Data observability extends operational monitoring into the data layer: freshness tells you if data arrived on time, volume tells you if the expected amount arrived, schema tells you if its structure is intact, and distribution tells you if its values look right. Lineage connects failures to their upstream causes and downstream impacts. Build observability as part of the pipeline, not as an afterthought.
