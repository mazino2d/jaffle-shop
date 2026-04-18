---
slug: batch-vs-streaming
date: 2026-03-28
description: Understand the tradeoffs between batch, streaming, and micro-batch processing models, and how to choose the right approach for your actual business needs.
authors:
  - Mazino2D
categories:
  - Foundations
tags:
  - architecture
  - streaming
---

# Batch vs. Streaming vs. Micro-batch: Choosing the Right Processing Model

"We need real-time data" is one of the most common requirements in data engineering — and one of the most frequently misunderstood. Real-time is a spectrum, not a binary, and the right point on that spectrum depends on the actual business need, not the ambition.

<!-- more -->

## Batch Processing

Batch processing collects data over a period — an hour, a day, a week — and processes all of it at once at a scheduled time.

A nightly job that loads yesterday's transactions into a warehouse is batch processing. A dbt run that rebuilds all models every morning is batch processing.

**Strengths:**
- Simple to reason about — you always know what data window you're processing
- Easy to backfill — re-run the job for a past time window
- Efficient — large operations amortize the overhead of startup, connection, and serialization
- Debuggable — the entire input set is fixed and inspectable

**Weaknesses:**
- Latency — data is stale by definition (hours to days)
- All-or-nothing — a late-running job delays everything downstream

Batch is the right default for analytics. A dashboard that refreshes once per hour is batch. A weekly cohort report is batch. Most analytical use cases do not require data that is minutes old.

## Streaming

Streaming processes each event as it arrives, continuously, with no fixed batch window.

A fraud detection system that evaluates every transaction within milliseconds is streaming. A real-time leaderboard that updates as events occur is streaming.

**Strengths:**
- Low latency — data is available within seconds of arriving
- Continuous — no waiting for a batch window to close

**Weaknesses:**
- Complexity — windowing, watermarking, late data, exactly-once semantics are all hard problems
- Operational burden — stream processing systems require dedicated infrastructure and expertise
- Difficult to backfill — replaying historical data through a streaming system is non-trivial
- Harder to debug — the input is a moving target, not a fixed set

Streaming is justified when **the business action that depends on the data is itself time-sensitive at the sub-minute level**. Fraud detection, alerting, live bidding systems. The bar should be high.

## Lambda Architecture: A Cautionary Example

Lambda architecture was a popular attempt to get the best of both worlds: a streaming layer for low-latency results, and a batch layer to periodically correct them.

The idea: streaming gives you approximate real-time results, batch gives you accurate eventual results, a "serving layer" merges them.

The reality: you now maintain two codebases that must produce equivalent results, and any logic change must be implemented twice. Teams consistently underestimate this maintenance burden. Lambda architectures tend to drift — the batch and streaming paths produce different answers — and debugging across two systems is painful.

The lesson: don't add streaming complexity to solve a problem that batch can solve.

## Micro-batch: The Practical Middle Ground

Micro-batch is batch processing at high frequency: every minute, every five minutes, every thirty seconds. The processing model is identical to batch — a fixed window is processed on a schedule — but the windows are small.

**Why micro-batch often wins:**
- Latency is good enough for most "near real-time" requirements (< 5 minutes is "real-time" to most business users)
- The code is identical to batch — no streaming semantics to learn
- Backfill works exactly like regular batch
- Infrastructure is simpler — scheduled jobs, not stream processing clusters

The key question is: does the business actually need sub-second data, or do they need data that's less than 10 minutes old? In most cases, it's the latter, and micro-batch delivers that with a fraction of the complexity.

## Choosing the Right Model

| Requirement | Right model |
|---|---|
| Daily/hourly reports | Batch |
| Dashboards with hourly refresh | Batch |
| Dashboards with < 5 min refresh | Micro-batch |
| Alerting within minutes | Micro-batch |
| Fraud detection within seconds | Streaming |
| Real-time user-facing features | Streaming |

Start with batch. If latency is genuinely a problem for a specific use case, move to micro-batch. Introduce streaming only when micro-batch cannot meet the actual business requirement.

## The Takeaway

The push toward real-time data is often driven by perception rather than need. Batch is simpler, cheaper, and sufficient for the vast majority of analytical workloads. Micro-batch covers most "near real-time" cases without streaming complexity. Reserve true streaming for use cases where the business action itself happens within seconds.

Choose the least complex model that meets the actual requirement — not the most impressive one.
