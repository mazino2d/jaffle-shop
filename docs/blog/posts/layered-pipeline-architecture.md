---
slug: layered-pipeline-architecture
date: 2026-03-28
authors:
  - khoi
categories:
  - Foundations
tags:
  - architecture
  - best practices
---

# Layered Pipeline Architecture: Why Not One Script?

The most natural instinct when building a data pipeline is to write one script that does everything: connects to the source, applies transformations, and writes results to the destination. It works on day one. By month six, it's the most feared file in the codebase.

<!-- more -->

## The Monolith Problem

A monolith ETL script looks innocent at first:

```python
# pipeline.py
data = fetch_from_api()
data = clean_and_join(data)
data = apply_business_rules(data)
write_to_warehouse(data)
```

The problems compound as the pipeline grows:

**Everything fails together.** If the business logic step crashes, you have to re-run the entire pipeline including the expensive API fetch. There's no intermediate state to resume from.

**Nothing is independently testable.** To test the business logic, you need the API to be available. To test the API fetch, you need to run the entire transformation.

**Logic is invisible.** The rules buried in `apply_business_rules()` are not queryable. You can't inspect the intermediate state without adding debug logging or temporary outputs.

**Changes have unknown blast radius.** Touching one function could break anything downstream. There are no boundaries.

## The Layered Alternative

Layered architecture separates the pipeline into distinct stages, each with a single responsibility, writing intermediate results to durable storage.

The typical layers for an analytical pipeline:

```
Source → [Ingestion] → Raw → [Snapshot] → History → [Staging] → [Intermediate] → [Marts]
```

Each layer:

- **Reads from the previous layer** — not directly from the source
- **Writes to durable storage** — so it can be inspected and resumed
- **Has one job** — and does nothing outside that job

### What each layer does

**Ingestion** pulls data from external sources and writes it to a raw zone with minimal processing. Its only job is to get data in. No business logic, no joins, no renaming.

**Raw** is the immutable record of what arrived from the source. It should never be modified after writing.

**Snapshot** (for mutable entity data) captures historical versions. It reads raw and writes a versioned history. Its only job is change detection and history tracking.

**Staging** cleans and standardizes raw or snapshotted data — renaming columns, casting types, enforcing data types. It does not join tables or apply business rules. One staging model per source table.

**Intermediate** applies business logic: joining, aggregating, computing derived fields. It is never exposed directly to downstream consumers — it exists to simplify the next layer.

**Marts** are the serve layer: one model per business concept, ready for BI tools and downstream consumers to query.

## The Cost-Benefit of Each Layer

Adding layers adds complexity. Each intermediate write costs storage. Each boundary requires a contract. This is a real tradeoff.

The benefits:

**Independent resumability.** If staging fails, you don't re-ingest. If a mart fails, you don't re-snapshot. Each layer can be re-run independently.

**Isolated testability.** You can test staging logic by querying staging tables directly, without running ingestion. You can test mart logic by querying intermediate tables.

**Visible intermediate state.** Every layer is queryable. When something looks wrong in a mart, you can inspect staging and intermediate to find exactly where the corruption entered.

**Controlled blast radius.** Changing business logic in intermediate does not touch staging or ingestion. You know exactly what's affected.

## The Redundancy Test

A useful heuristic: if removing a layer wouldn't change the final output for any query, the layer is redundant.

Intermediate models exist because they simplify mart logic. If a mart can read directly from staging with no loss of clarity or correctness, the intermediate layer is unnecessary overhead for that model.

This doesn't mean fewer layers are always better — it means each layer should earn its existence by doing something the next layer would otherwise have to do inline.

## The Takeaway

The monolith pipeline is tempting because it's simple on day one. It becomes unmaintainable because complexity accumulates in a single place with no boundaries.

Layered architecture distributes that complexity across well-defined boundaries, each with one job. The cost is more files and more structure. The benefit is a pipeline you can debug, test, and modify without fear.
