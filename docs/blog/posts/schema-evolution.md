---
slug: schema-evolution
date: 2026-03-28
description: Schema evolution is the most underestimated operational challenge in data pipelines — how to detect, handle, and recover from upstream source changes gracefully.
authors:
  - khoi
categories:
  - Ingestion
tags:
  - schema
  - reliability
---

# Schema Evolution: When Your Source Changes Without Warning

Source systems change. A backend engineer adds a column. A product team renames a field. A third-party API deprecates an attribute and replaces it with two new ones. Your pipeline was working yesterday and now it isn't — or worse, it's still running but silently producing wrong results.

Schema evolution is the most underestimated operational challenge in data engineering.

<!-- more -->

## Why It Catches Teams Off Guard

When a pipeline is first built, the source schema is known and stable. Contracts between the data team and the source team are often informal — a Slack message, a shared doc, an assumption. The pipeline encodes the schema implicitly, in column references scattered across SQL files.

Then the source changes. The pipeline either breaks loudly (a column reference fails) or breaks silently (a missing column defaults to NULL, downstream metrics quietly drop).

The silent failure is worse. A dashboard showing wrong numbers for three weeks before someone notices is a much bigger problem than a pipeline that fails immediately.

## Types of Schema Changes

Not all schema changes are equally disruptive:

**Non-breaking changes** — the pipeline continues to function correctly without modification:
- Adding a new column (if the pipeline doesn't need it, it's ignored)
- Adding a new value to an enum (if not in `accepted_values` tests, it passes through)
- Loosening a type constraint (e.g., INT → BIGINT)

**Breaking changes** — the pipeline fails or produces wrong results:
- Renaming a column (all references to the old name break)
- Removing a column (same)
- Changing a column type in an incompatible way (e.g., STRING → INT fails to cast)
- Changing the meaning of a column without renaming it (the most dangerous: the pipeline runs, but results are wrong)

The last category — semantic changes without syntactic change — is undetectable by any automated schema check. It requires communication, documentation, and data contracts.

## Strategies for Handling Schema Evolution

### 1. Fail loudly at ingestion

The simplest defensive strategy: enforce schema at the ingestion boundary. If the source sends a column that wasn't expected, or is missing a column that was required, the ingestion job fails.

This is the "schema-on-write" approach: problems are caught immediately, before bad data enters the warehouse.

The tradeoff: non-breaking changes (new columns) also cause failures, requiring manual intervention even when the downstream pipeline is unaffected.

### 2. Forward-compatible schema tolerance

Allow additive changes (new columns) automatically while alerting on structural changes (removed or renamed columns). The ingestion layer stores whatever columns the source sends; downstream models explicitly reference only the columns they need.

This reduces friction for the common case (source adds a column you don't need yet) while still alerting on breaking changes.

### 3. Schema drift detection

Automatically compare the source schema on each run against the previously known schema. Alert when differences are detected — don't necessarily fail, but notify.

This gives the team visibility into changes before they cause downstream failures, without blocking ingestion entirely.

### 4. Explicit data contracts

A data contract is a formal agreement between the producer (source system team) and the consumer (data pipeline) on what the schema will look like and what guarantees are provided.

Contracts can be:
- A schema definition file committed to version control
- A JSON Schema or Avro schema registered in a schema registry
- A documented YAML that both teams agree to and version together

The key property: changes to the source schema require updating the contract, which creates a change review opportunity before the pipeline breaks.

## The Operational Reality

Most teams don't have formal contracts. The practical minimum:

1. **Make schema changes visible.** Log the source schema on each ingestion run and alert when it differs from the previous run.

2. **Fail fast on missing required columns.** Explicitly declare which source columns your pipeline depends on and fail if they're absent.

3. **Avoid SELECT \*.** Explicit column selection makes schema dependencies visible and prevents new source columns from silently flowing into downstream models.

4. **Document semantic expectations.** For columns where the name doesn't fully capture the meaning, document what you expect. "status: one of [placed, shipped, completed, returned]" — not just the type, but the values and their meaning.

## The Takeaway

Source schemas will change. The question is whether those changes break your pipeline loudly and immediately, or silently corrupt data over time. Loud, immediate failures are almost always preferable.

Build schema evolution handling into the ingestion layer from the start: make the schema explicit, detect drift, and communicate with source teams through contracts rather than assumptions.
