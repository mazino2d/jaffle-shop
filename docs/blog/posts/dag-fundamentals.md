---
slug: dag-fundamentals
date: 2026-03-28
description: Learn how Directed Acyclic Graphs (DAGs) model pipeline dependencies, why cycles cause deadlocks, and how orchestrators use DAGs to manage execution order.
authors:
  - khoi
categories:
  - Orchestration
tags:
  - orchestration
  - DAG
  - architecture
---

# DAGs: The Right Mental Model for Pipeline Dependencies

Modern data pipelines are not sequences of steps — they're dependency graphs. Step C can't run until both A and B have completed. Steps D and E can run in parallel once C finishes. If F fails, G and H should not start. A Directed Acyclic Graph (DAG) is the data structure that represents these relationships precisely.

<!-- more -->

## What Makes It a DAG

**Directed:** dependencies flow in one direction. If step B depends on step A, data flows from A to B, never from B back to A.

**Acyclic:** there are no cycles. Step A cannot directly or indirectly depend on itself. A cycle would mean "step A can't start until step B finishes, and step B can't start until step A finishes" — a deadlock with no resolution.

**Graph:** a collection of nodes (pipeline steps) connected by edges (dependency relationships), not a linear sequence.

These three properties together give pipeline orchestration its mathematical foundation. Because the graph is acyclic, there's always at least one topological ordering — an execution sequence where every step runs after all its dependencies.

## Task Dependency vs. Data Dependency

A common source of confusion: two kinds of dependencies exist in data pipelines, and conflating them leads to fragile designs.

**Task dependency** is an explicit declaration: "step B must run after step A completes successfully." This is what most orchestrators model. You declare the dependency; the orchestrator enforces the execution order.

**Data dependency** is implicit: "step B reads data that step A produces." If step A runs but produces no new data (or produces stale data), step B runs anyway — with whatever data happens to be in the table.

Task dependencies guarantee execution order. They do not guarantee data freshness. A pipeline where step A fails silently (the job completes but no rows are inserted) and step B runs successfully on stale data is task-dependency-correct but data-dependency-broken.

This is why freshness checks and volume monitoring matter — they verify data dependencies that task dependencies alone cannot guarantee.

## Failure Propagation

When a node in the DAG fails, downstream nodes that depend on it should not run. Most orchestrators implement this as the default: a downstream task is skipped or marked as failed if any upstream dependency failed.

This is the right behavior for most analytical pipelines: if `stg_orders` fails to build, don't run `int_customer_orders`, `dim_customers`, or `fct_orders`. Running them with stale staging data would produce misleading results that look correct but aren't.

However, not all failures should propagate equally:

- A source freshness failure should probably block everything downstream from that source
- A model failure in one mart should block the dependent downstream models but not prevent other independent branches from running
- A non-critical alerting step failing should not block the entire pipeline

Design your DAG with the failure propagation behavior you want, not just the happy-path execution order.

## Parallelism

One of the main benefits of DAG-based orchestration over sequential scripting is parallelism: nodes with no dependency relationship between them can run simultaneously.

If your pipeline has 10 staging models that all read directly from raw sources, they can all run at the same time. If `dim_customers` and `dim_products` don't depend on each other, they can build in parallel.

This reduces total pipeline runtime significantly. A pipeline that would take 60 minutes if run sequentially might complete in 15 minutes if independent branches run in parallel.

The orchestrator handles this automatically given the correct dependency declarations. The developer's job is to declare only the dependencies that actually exist — not to over-constrain the graph by adding unnecessary sequential ordering.

## What Goes in a Node

A node in a pipeline DAG can represent:
- A single SQL model or dbt model
- A Python function or script
- An entire dbt project build (`dbt build --select tag:staging`)
- A data ingestion job
- An external API call

The granularity of nodes is a design decision. Too fine-grained (one node per SQL statement) creates an orchestration overhead larger than the actual work. Too coarse-grained (one node for the entire pipeline) loses the parallelism and isolation benefits.

A practical heuristic: group steps that always succeed or fail together, and separate steps that could independently fail or that should run in parallel.

## The Takeaway

A DAG is not just a visualization of your pipeline — it's the mathematical structure that enables parallelism, controlled failure propagation, and correct execution ordering. Declare only the dependencies that actually exist. Distinguish between task dependencies (execution ordering) and data dependencies (freshness guarantees). Design failure propagation intentionally, not by accident.
