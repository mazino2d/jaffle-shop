---
slug: serving-layer
date: 2026-03-28
description: The serving layer is not one-size-fits-all — designing tables for BI dashboards, ML models, and operational APIs requires different materializations and update patterns.
authors:
  - Mazino2D
categories:
  - Serving
tags:
  - architecture
  - BI
  - ML
  - materialization
---

# Designing the Serving Layer for Different Consumers

A fact table that perfectly serves an executive dashboard is often a poor fit for a machine learning model. A feature table optimized for model training is unnecessarily complex for a business analyst. The serving layer is not one thing — it's a set of tables designed for specific consumers, each with different requirements.

<!-- more -->

## Who Are Your Consumers?

Before designing any serving table, identify who will query it and what they need.

**BI and dashboard consumers:**
- Write SQL or use a drag-and-drop interface
- Need data that is pre-aggregated or aggregable with simple GROUP BY
- Expect human-readable column names and values
- Need stable schemas (dashboard queries break when columns are renamed)
- Query the same set of metrics repeatedly — performance matters

**Analytical/ad-hoc query consumers:**
- Write complex SQL
- Need access to granular, un-pre-aggregated data
- Can tolerate more complex schemas
- Value completeness over simplicity
- Often explore the data to answer one-time questions

**Machine learning consumers:**
- Need feature-complete rows — one row per training example
- Often need historical joins (point-in-time correctness)
- Don't need human-readable labels (model doesn't care if a column is named `f1` or `avg_order_value`)
- Need consistent formats: numeric features as numbers, categorical features encoded, no NULLs in inputs
- May need large volumes without aggregation

**Operational/API consumers:**
- Need low-latency reads on specific keys
- Query by identifier (`WHERE customer_id = 42`), not aggregation patterns
- Need results within milliseconds, not seconds
- Often require a different storage layer entirely (Redis, DynamoDB) rather than a warehouse

## Materialization Strategy

How a table is materialized — view, table, or materialized view — determines the tradeoff between compute cost and query speed.

**Views:** defined as SQL, executed at query time. Zero storage cost. Query always runs the underlying SQL, including all joins and aggregations. Appropriate for simple transformations where query speed is not critical, or for staging models that no consumer queries directly.

**Tables:** data is computed and stored at model build time. Queries are fast because the result is pre-computed. Appropriate for mart models that are queried frequently. The cost: storage and the compute to rebuild on each pipeline run.

**Materialized views:** hybrid — like a view, but the result is cached and automatically refreshed on a schedule or on change. Available in some warehouses (BigQuery, Snowflake, Redshift). Reduces query time without manual pipeline scheduling. The complexity: refresh logic and staleness windows vary by warehouse.

For analytical marts that are queried by BI tools: use tables. The query frequency justifies the rebuild cost, and the pre-computation speed is necessary for interactive dashboards.

For feature tables that are rebuilt once per day and queried by ML training jobs: use tables. Training jobs may read millions of rows; pre-computation is essential.

For staging models and intermediate models: use views or ephemeral. They're not queried directly by consumers, so storage is wasted.

## SLA Flows Upstream

The freshness requirement of the consumer determines the schedule of the pipeline that produces it.

An executive dashboard that stakeholders view during their 8am standup needs data that is fresh by 7:30am. That means the mart model must complete by 7:30am. That means the intermediate models must complete earlier. That means the staging models must complete earlier. That means ingestion must complete earlier.

The SLA flows upstream: the consumer's requirement sets a deadline, and every upstream step must be scheduled to meet it.

This is why designing the serving layer is not purely a data question — it's also a scheduling and SLA management question. Understanding what your consumers need, when they need it, and what happens if data is late, shapes the entire pipeline schedule.

## Stability vs. Flexibility

BI consumers need stable schemas: when a dashboard query runs, it expects the column `total_revenue` to exist and have the same semantics as last week. Renaming it to `gross_revenue` breaks the dashboard immediately.

ML consumers are more tolerant of schema changes because the model is retrained periodically. A renamed feature column requires updating the feature extraction code, but doesn't break production immediately.

This creates a design tension: BI consumers want stability, analytical consumers want the most accurate representation, ML consumers want completeness.

The resolution: separate tables for fundamentally different consumer types. `dim_customers` for BI (stable, denormalized, human-readable). `customer_features` for ML (complete, point-in-time, possibly different naming conventions). Both read from the same intermediate models; they differ in their serving design.

## What Goes in a Mart

Core marts for BI should include:

- All the attributes a consumer would want to filter or group by, without requiring joins
- Pre-computed aggregates for common metrics (order count, lifetime value) rather than requiring consumers to aggregate themselves
- Human-readable values (status = "completed", not status = 3)
- Surrogate keys for joining to related tables when needed
- A clear grain documented in the model description

What does not belong in a BI mart:

- Raw technical fields (internal IDs, debug timestamps) unless consumers need them
- Intermediate aggregation steps that should stay in the intermediate layer
- Data from domains unrelated to the mart's primary subject

## The Takeaway

The serving layer is not a single table architecture decision — it's a set of tables designed for specific consumers. Understand what each consumer needs, when they need it, and how they'll query it. Choose materialization based on query frequency and latency requirements. Let consumer SLAs set pipeline schedules. Separate tables for fundamentally different consumer types rather than building one table that compromises for everyone.
