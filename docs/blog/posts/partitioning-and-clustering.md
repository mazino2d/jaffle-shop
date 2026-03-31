---
slug: partitioning-and-clustering
date: 2026-03-28
description: Partitioning and clustering are query optimization tools, not just storage strategies — learn how to design partition schemes that eliminate data reads for common query patterns.
authors:
  - khoi
categories:
  - Storage
tags:
  - storage
  - performance
  - query optimization
---

# Partitioning and Clustering: Designing for Query Patterns

Partitioning is often described as "splitting a table into smaller pieces." That description is accurate but misses the point. The purpose of partitioning is not to create smaller files — it's to allow the query engine to skip large portions of data based on filter conditions. Designed correctly, partitioning eliminates reads. Designed incorrectly, it creates new problems.

<!-- more -->

## What Partitioning Does

When a table is partitioned on a column, data is physically separated by the values in that column. A query with a filter on the partition column can skip all partitions whose values don't match.

Example: a table partitioned by `date`:

```
data/
├── date=2026-01-01/
│   └── part-0.parquet
├── date=2026-01-02/
│   └── part-0.parquet
└── date=2026-01-03/
    └── part-0.parquet
```

A query `WHERE date = '2026-01-02'` reads only the `date=2026-01-02` directory. The query engine never touches the other partitions. This is **partition pruning**.

Without partitioning, the same query scans the entire table. For a 3-year event log with daily queries, partitioning can reduce read volume by 99%.

## Choosing a Partition Key

The partition key should match the dominant filter pattern in your queries.

**Good partition keys:**

- **Date/timestamp (truncated to day or hour):** the most common choice for time-series data. Most analytical queries filter by time range. `WHERE event_date >= '2026-01-01' AND event_date < '2026-02-01'` becomes a directory listing, not a full scan.
- **Region or country:** for global datasets where queries are typically scoped to one region.
- **Status (carefully):** for tables where queries typically filter on status, and the status has a small, stable set of values.

**Problematic partition keys:**

- **High-cardinality unique IDs:** partitioning by `customer_id` for a table with 10M customers creates 10M partitions. Directory listing alone becomes expensive.
- **Unbounded string columns:** user-submitted strings, URLs, or free-text fields make unpredictable partition counts.
- **Columns not used in filters:** if your queries never filter on `product_category`, partitioning by it provides no benefit.

## The Small Files Problem

Each partition directory contains at least one file. If partitions are small, you end up with many tiny files.

This is the **small files problem**: query engines are optimized to read large files sequentially. Reading 10,000 files of 1MB each is much slower than reading 10 files of 1GB each, even if the total data volume is identical. The overhead comes from file metadata, S3 LIST operations, and connection establishment per file.

Signs of the small files problem:
- Queries are slow despite small data volume
- The `LIST` operations in query logs take longer than the actual reads
- Partitions have files in the KB range

Common causes:
- Over-partitioning (too many distinct partition values)
- Frequent small appends without compaction
- Micro-batch ingestion writing one file per batch per partition

The fix: **compaction** — periodically merging small files into larger ones, or choosing a coarser partition granularity (daily instead of hourly).

## Clustering (Sorting Within Partitions)

Clustering sorts rows within each partition by one or more columns. Unlike partitioning, clustering doesn't create separate directories — it just changes the physical order of rows.

A query that filters on the clustering column within a partition can skip blocks of rows based on min/max statistics. This is **block skipping**, analogous to how Parquet row groups work.

Example: events partitioned by `date`, clustered by `customer_id`. A query `WHERE date = '2026-01-01' AND customer_id = 42` reads only the blocks in the January 1st partition where `customer_id` ranges include 42.

**When clustering helps:**
- You frequently filter on a column within partitions
- The clustered column has high cardinality (many distinct values)
- Queries benefit from range scans on the clustered column

**When clustering doesn't help:**
- The column is never used as a filter
- Cardinality is too low (sorting by a boolean provides no benefit)

Partitioning and clustering are complementary: partition on the coarse filter (date, region), cluster on the fine filter (customer_id, product_id).

## A Practical Design Process

1. **Identify your most frequent and expensive queries.** What do they filter on?

2. **Choose partition keys** that match those filters and have bounded, moderate cardinality (days, regions, a handful of status values).

3. **Choose clustering keys** that are used as secondary filters within partitions and have high cardinality.

4. **Monitor file sizes.** If partitions produce files under 100MB regularly, consider coarsening the partition granularity or adding compaction.

5. **Validate with EXPLAIN.** Check that the query engine is actually applying partition pruning, not scanning everything.

## The Takeaway

Partitioning is not about organization — it's about eliminating reads. Design partition keys around your actual query filters, not around intuitive groupings. Keep partition granularity coarse enough to avoid the small files problem. Use clustering as a secondary layer to speed up high-cardinality filters within partitions. And always validate that partition pruning is actually being applied by the query engine.
