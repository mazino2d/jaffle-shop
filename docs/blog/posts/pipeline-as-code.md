---
slug: pipeline-as-code
date: 2026-03-28
description: Configuration-driven orchestration separates pipeline behavior from pipeline logic, enabling new jobs to be added without code changes by defining them in YAML.
authors:
  - Mazino2D
categories:
  - Orchestration
tags:
  - orchestration
  - architecture
  - best practices
---

# Pipeline as Code: Configuration Over Imperative DAG Definitions

The second pipeline you build will look a lot like the first. The third even more so. Without a principled approach to pipeline definition, you end up with duplicated code, inconsistent patterns, and orchestration logic that's harder to change than the transformation logic it was meant to manage.

Pipeline-as-code is the practice of defining pipeline behavior in code rather than through UI configuration — and configuration-driven orchestration takes this further by separating pipeline behavior from pipeline logic.

<!-- more -->

## The Imperative DAG Problem

In the simplest orchestration setup, each pipeline is defined as a Python function or class that explicitly declares its tasks, dependencies, and configuration:

```python
# pipeline_orders.py
with DAG("orders_pipeline", schedule_interval="0 6 * * *") as dag:
    ingest = PythonOperator(task_id="ingest", python_callable=run_ingestion)
    transform = PythonOperator(task_id="transform", python_callable=run_dbt)
    ingest >> transform
```

This works fine for one pipeline. By the fifth pipeline, you're copying and modifying the same structure repeatedly. The scheduling configuration is buried in Python. Retry logic is duplicated across files. Adding a new pipeline requires understanding the Python DAG API, not just the pipeline configuration.

The problem gets worse when pipelines need to be modified: changing retry behavior across all pipelines means editing every DAG file individually. A mistake in one file means a broken pipeline with no compile-time error.

## Config-Driven Orchestration

The alternative: separate pipeline behavior (configuration) from pipeline structure (code).

**Configuration:** what a specific pipeline does — which assets it processes, when it runs, how many retries, whether catchup is enabled.

**Code:** the generic engine that reads configuration and creates pipeline objects.

```yaml
# dags/orders_transformation.yml
name: orders_transformation
trigger:
  type: cron
  cron_schedule: "0 6 * * *"
assets:
  - type: dbt
    selector: "tag:orders"
retry:
  max_retries: 3
  delay_minutes: 5
catchup:
  enabled: false
```

```python
# loader.py (the engine — written once)
def build_pipeline_from_config(config: dict) -> Pipeline:
    trigger = build_trigger(config["trigger"])
    assets = build_assets(config["assets"])
    return Pipeline(name=config["name"], trigger=trigger, assets=assets, ...)

for config_file in glob("dags/*.yml"):
    pipeline = build_pipeline_from_config(load_yaml(config_file))
    register(pipeline)
```

Adding a new pipeline: write a YAML file. No new Python code. No copy-paste. No need to understand the orchestration framework API.

## What Configuration Should Define

Good candidates for configuration:

- **Trigger type and schedule:** when does the pipeline run?
- **Asset selection:** which models or jobs does it execute? (Often expressed as tags or selectors)
- **Retry policy:** how many retries, with what delay?
- **Catchup behavior:** should missed runs be automatically caught up?
- **Dependencies:** which other pipelines must complete before this one starts?
- **Notification settings:** who gets alerted on failure?

Poor candidates for configuration:

- **Complex conditional logic:** if you need if-else branches in the configuration, use code
- **Dynamic runtime behavior:** values that can only be determined during execution
- **One-off customization:** if a pipeline is sufficiently unique that it doesn't fit the schema, it should be written in code directly

The configuration schema should cover the common case well. Unusual pipelines that don't fit are written in code and are clearly exceptional.

## The Tradeoffs

**Expressiveness vs. discoverability.** Imperative code can express anything. Configuration can express what the schema allows. Configuration is easier to read and reason about but harder to extend.

**Validation.** YAML configuration can be validated against a schema before deployment. A misconfigured retry policy is caught at CI time, not at runtime. Imperative code validation requires running the code.

**Uniformity.** Config-driven pipelines all follow the same patterns. Imperative pipelines diverge over time as each developer adds their own patterns. Uniformity makes the codebase navigable; divergence makes it a maze.

**Debugging.** A generic loader that reads YAML and produces pipeline objects adds an indirection layer. When a pipeline behaves unexpectedly, you need to understand both the configuration and the loader. Direct code doesn't have this indirection.

## When to Use Each

**Use config-driven for:** pipelines that follow a standard pattern (dbt model runs, ingestion jobs, reporting refreshes). This covers 80%+ of pipelines in most organizations.

**Use imperative code for:** pipelines with genuinely unique logic that doesn't fit a standard pattern. Complex fan-out, conditional branching, dynamic task generation. These should be clearly marked as special cases, not the standard.

**Hybrid:** write config-driven orchestration for the common case, expose an escape hatch for pipelines that need custom logic. The escape hatch should be rarely used and well-documented.

## Infrastructure as Code, Applied to Pipelines

The same principles that drove infrastructure-as-code apply to pipelines:

- Pipeline definition should be version-controlled
- Changes should go through code review
- Pipeline state should be reproducible from code, not dependent on UI state
- Drift between declared configuration and actual pipeline behavior should be detectable

A pipeline defined only in an orchestration UI is fragile: it's not versioned, can't be reviewed, and can be accidentally modified by anyone with UI access.

## The Takeaway

Define pipelines in code, not in UI configuration. For pipelines that follow standard patterns — most of them — use configuration-driven orchestration to separate what a pipeline does from how it's built. The overhead of writing a YAML file is lower than copy-pasting Python. The uniformity is maintainable; the divergence of imperative duplication is not.
