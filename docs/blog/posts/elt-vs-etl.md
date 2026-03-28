---
slug: elt-vs-etl
date: 2026-03-28
authors:
  - khoi
categories:
  - Foundations
tags:
  - architecture
  - ingestion
---

# ELT vs. ETL: A Paradigm Shift, Not Just a Letter Swap

ETL and ELT differ by more than the order of two letters. They represent fundamentally different assumptions about where computation should happen — and those assumptions have very different consequences for how you build, debug, and evolve data pipelines.

<!-- more -->

## What ETL Was Built For

ETL — Extract, Transform, Load — was the standard for decades. The pattern is simple: pull data from a source, transform it into the target shape, then load the result into a destination.

The underlying assumption: **compute is expensive, storage is expensive, load the minimum necessary.**

In the era of on-premise data warehouses with per-CPU licensing, this made sense. You couldn't afford to store raw data or run exploratory transformations after the fact. You did the work before loading, and you loaded only what you needed.

The consequence: every business question that wasn't anticipated at design time required a new ETL job. The transformation logic lived outside the warehouse, often in Java or Python, owned by a platform team, difficult to iterate on quickly.

## Why ELT Won

ELT inverts the pattern: Extract data from a source, Load it raw into the warehouse, then Transform it inside the warehouse using SQL.

The underlying assumption: **storage is cheap, warehouse compute is powerful, preserve everything.**

Three things changed to make ELT the default:

**Cloud storage economics.** Object storage costs pennies per GB. Storing raw data indefinitely is no longer a meaningful cost concern for most organizations.

**Columnar SQL engines.** Modern warehouses (BigQuery, Snowflake, DuckDB, Redshift) execute analytical SQL at speeds that would have been unimaginable on legacy systems. Complex transformations that previously required map-reduce jobs now run in seconds as SQL.

**Replayability.** Because raw data is preserved, you can always re-transform. If your business logic was wrong, you fix the transformation and re-run — you don't need to re-extract from the source. This is the most underrated advantage of ELT.

## The Practical Difference

With ETL, the transformation logic is in your pipeline code. Debugging means running the pipeline again with logging. Iteration means deploying new pipeline code. The raw data is gone after transformation.

With ELT, the transformation logic is in SQL inside the warehouse. Debugging means querying the raw tables directly. Iteration means rewriting a SQL model. The raw data is always there to inspect.

This is why ELT pairs naturally with tools like dbt: the transformation layer is just SQL on top of already-loaded raw data. A data analyst can write and modify transformations without touching the ingestion pipeline at all.

## When ETL Still Makes Sense

ELT is the right default, but there are legitimate reasons to transform before loading:

**PII and sensitive data.** If personally identifiable information should never enter the warehouse — even temporarily — you need to mask or drop it before loading. This is a compliance requirement, not a performance one.

**Extreme volume pre-aggregation.** If you're ingesting billions of events where even storing the raw data is cost-prohibitive, pre-aggregating before load may be justified. This is rare and should be validated against actual cost projections, not assumed.

**Source system constraints.** Some sources only expose aggregated data or have strict rate limits that make repeated raw extraction impractical.

Outside these cases, defaulting to ETL adds complexity without benefit: you lose raw data, you couple transformation logic to the ingestion pipeline, and you make iteration harder.

## The Takeaway

ELT won because the economics changed. Load raw data into the warehouse, then transform it with SQL. Preserve history, iterate freely, debug by querying. The raw layer is your safety net — the transformation layer is where business logic lives, and it can always be rewritten.

ETL still has a narrow role: compliance-driven pre-processing where raw data must not enter the warehouse. Outside that, it's the wrong default.
