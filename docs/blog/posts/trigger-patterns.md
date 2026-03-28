---
slug: trigger-patterns
date: 2026-03-28
authors:
  - khoi
categories:
  - Orchestration
tags:
  - orchestration
  - scheduling
  - event-driven
---

# Trigger Patterns: Cron, Sensors, and Event-Driven Pipelines

Every pipeline step needs to know when to run. The simplest answer — "run on a schedule" — works well in isolation but breaks down when pipelines have dependencies on upstream data that doesn't arrive on a perfectly predictable cadence.

There are three fundamental trigger patterns, each with different tradeoffs in simplicity, correctness, and coupling.

<!-- more -->

## Cron: Schedule-Based Triggering

The most common pattern: run the pipeline at a fixed time or interval.

```
0 6 * * *  # Run at 6am every day
*/15 * * * *  # Run every 15 minutes
```

**Why it's the default:** cron is simple to reason about. You know exactly when a job will run. You don't need to know anything about upstream systems. Debugging is straightforward — if a job should have run at 6am and didn't, you know what to look for.

**The fundamental problem:** cron assumes upstream data will be ready by the scheduled time. If the source ingestion job is delayed — due to a slow API, a large dataset, or a transient failure — your downstream transformation still runs, on stale data, at 6am.

This is the "assume the data is ready" problem. Cron doesn't verify that the data it depends on actually arrived — it only verifies that the clock reached the scheduled time.

**When cron is appropriate:**
- The pipeline's source data has a strict, reliable SLA (it's always ready by 5:45am)
- Some staleness is acceptable (the pipeline can safely use yesterday's data if today's hasn't arrived)
- Simplicity is a higher priority than perfect data dependency management

## Sensors: Poll Until Ready

A sensor waits for a condition to be true before triggering. Common conditions:

- A file exists in a cloud storage location
- A table's max timestamp is more recent than the previous run
- A row count exceeds a threshold
- A status column in a control table is set to "ready"

```python
# Run the transformation job when new data arrives in the landing zone
sensor = S3KeySensor(bucket="raw-landing", prefix="orders/{{ds}}/")
transform_job.set_upstream(sensor)
```

The sensor polls at a defined interval (every minute, every five minutes) until the condition is met, then triggers the downstream job.

**Why sensors are better for data readiness:** the pipeline doesn't run until the data is actually there. If the source data arrives 2 hours late, the downstream transformation automatically waits and then runs with complete data.

**The tradeoffs:**
- Sensors consume orchestrator resources while polling
- A sensor that never resolves (because the condition is never met) requires a timeout and alerting
- Sensors create coupling between your pipeline and the source system's delivery mechanism

## Asset-Based Triggering

A more sophisticated form of event-driven triggering: instead of sensing for a file or row count, you declare that a downstream asset (a table or model) should be refreshed when an upstream asset changes.

```
[raw_orders updated] → [stg_orders rebuilt] → [fct_orders rebuilt] → [dashboard refreshed]
```

Each step is triggered by the completion of its upstream dependency, not by a clock.

This is the purest form of data dependency expression: the pipeline reflects what should happen when data changes, not what should happen when a clock reaches a specific time.

**The appeal:** when source data arrives early, the entire downstream chain runs immediately. When it arrives late, everything waits automatically. The pipeline is data-driven, not time-driven.

**The tradeoffs:**
- More complex to implement and reason about than cron
- Harder to predict when a given step will run (it depends on upstream timing)
- Can create tight coupling: if one asset is rebuilt frequently, it triggers cascading rebuilds of everything downstream

## Combining Patterns

In practice, most pipelines use a combination:

**Cron at the entry point, assets downstream:**
- Ingestion runs on a cron schedule (because it depends on external sources, not internal assets)
- Transformation steps trigger as assets when ingestion completes
- This combines the predictability of cron at the boundary with the data-awareness of asset triggering internally

**Cron with freshness guards:**
- Run on a schedule but check freshness before proceeding
- If the source data isn't fresh enough, skip the run (or alert)
- Simpler than full sensor/asset patterns, with some data-readiness protection

**Sensors for external dependencies:**
- Use sensors only for the boundary between external systems and your pipeline
- Once data enters your controlled pipeline, use asset-based triggering internally

## The Coupling Question

Every trigger pattern makes a tradeoff between independence and coupling:

**Cron** is maximally independent: your pipeline doesn't know anything about what upstream systems are doing. The cost: it doesn't know if the data is ready.

**Sensors** create coupling to the delivery mechanism of the source: your pipeline knows how the upstream data arrives (a file, a table update) and waits for it. The benefit: it runs when the data is ready. The cost: if the source changes how it delivers data, the sensor breaks.

**Asset triggers** create coupling to the orchestration graph: every step knows what its upstreams are and waits for them. This is usually the right tradeoff for internal pipeline dependencies, where you control both sides.

The general rule: use sensors at the boundary with external systems (where you don't control the source), use asset-based triggers for internal pipeline dependencies (where you control both sides), and use cron where a strict schedule is a genuine requirement.

## The Takeaway

Cron is simple but assumes data arrives on schedule. Sensors wait for data readiness but create coupling to the source's delivery mechanism. Asset-based triggering expresses data dependencies directly but requires more sophisticated orchestration. Choose the pattern based on who controls the upstream: cron or sensors for external sources, asset triggers for internal dependencies.
