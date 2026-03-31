---
slug: storage-formats
date: 2026-03-28
description: Parquet is not just compressed CSV — column-oriented storage enables analytical engines to skip irrelevant data entirely, delivering order-of-magnitude query speedups.
authors:
  - khoi
categories:
  - Storage
tags:
  - storage
  - parquet
  - performance
---

# Storage Formats: Why Parquet Is Not Just "Smaller CSV"

When people first encounter Parquet, the framing is often "it's like CSV but compressed." This undersells both what Parquet does and why the format matters for query performance. The difference between row-oriented and column-oriented storage is not about compression — it's about fundamentally different access patterns.

<!-- more -->

## Row-Oriented Storage

In a row-oriented format (CSV, JSON, most OLTP databases), all columns for a single row are stored together:

```
Row 1: customer_id=1, name="Alice", country="US", ltv=450.00
Row 2: customer_id=2, name="Bob",   country="DE", ltv=320.00
Row 3: customer_id=3, name="Carol", country="US", ltv=890.00
```

To read a row, you seek to its position and read contiguously — fast for row-level access.

To compute `AVG(ltv)` across all customers, you must read every row in its entirety, even though you only need one column. Every byte of `name` and `country` that gets read is wasted I/O.

Row-oriented formats are optimal for OLTP workloads: insert a new customer, update a customer's address, fetch a customer's complete record. One row, all columns.

## Column-Oriented Storage

In a column-oriented format (Parquet, ORC), all values for a single column are stored together:

```
customer_id: [1, 2, 3, ...]
name:        ["Alice", "Bob", "Carol", ...]
country:     ["US", "DE", "US", ...]
ltv:         [450.00, 320.00, 890.00, ...]
```

To compute `AVG(ltv)`, the query engine reads only the `ltv` column — skipping `name`, `country`, and everything else. For a table with 50 columns where a query touches 3, this means reading 6% of the data instead of 100%.

For analytical workloads — aggregations, filters, GROUP BY across large datasets — column-oriented storage is dramatically more efficient.

## What Parquet Actually Does

Parquet is a columnar file format designed for analytical workloads. Beyond column-oriented storage, it provides:

**Row groups:** the file is divided into row groups (typically 64MB–1GB). Within each row group, data is stored column by column. This allows the query engine to skip entire row groups based on metadata.

**Column statistics:** each column in each row group stores min/max values (and optionally bloom filters). A query `WHERE country = 'DE'` can skip all row groups where `country_min = 'US' AND country_max = 'US'`.

**Encoding:** columns store repeated values efficiently. A `country` column with 95% "US" values doesn't store "US" 95 times — it uses run-length encoding or dictionary encoding to compress dramatically.

**Compression:** Parquet applies compression (GZIP, Snappy, LZ4, ZSTD) on top of encoding. Because similar values are stored together, compression ratios are much higher than compressing row-oriented files.

## Comparing the Common Formats

| Format | Orientation | Schema | Best for |
|---|---|---|---|
| CSV | Row | None | Human-readable interchange, small files |
| JSON / JSONL | Row | None | Semi-structured data, API responses |
| Avro | Row | Required (Avro schema) | Kafka/streaming, schema evolution with registry |
| Parquet | Column | Optional | OLAP queries, data lakes, dbt output |
| ORC | Column | Required | Hive ecosystem, heavy Spark workloads |

**Avro** deserves a note: it's row-oriented but ships with a schema definition, making it the standard for streaming systems (Kafka, Kinesis). The schema is embedded or registered separately, enabling schema evolution across producers and consumers. Not the right choice for analytical storage.

**ORC** is functionally similar to Parquet but more tightly coupled to the Hive/Spark ecosystem. For most modern use cases, Parquet is the neutral default.

## Compression Codec Tradeoffs

Parquet supports multiple compression algorithms. The choice is a tradeoff between file size and read/write speed:

| Codec | Size | Speed | Use case |
|---|---|---|---|
| GZIP | Smallest | Slowest | Cold storage, archival |
| Snappy | Medium | Fast | Default for most analytical workloads |
| LZ4 | Larger | Fastest | High-throughput streaming to lake |
| ZSTD | Small | Fast | Modern default, best balance |

Snappy is a safe default. ZSTD is increasingly the recommended choice for new systems — it achieves near-GZIP compression at near-Snappy speeds.

## When CSV and JSON Are Justified

Despite their inefficiency, unstructured formats still have legitimate uses:

- **Interoperability:** CSV can be opened by any tool, from Python to Excel to Notepad. When the consumer is unknown, CSV is the safe choice.
- **Small files:** for a table with 1,000 rows, the overhead of Parquet (schema metadata, row group structure) is not worth it.
- **Debugging:** reading raw data to inspect it is easier in CSV/JSON than in Parquet, which requires a reader library.
- **External APIs:** most APIs return JSON. You don't choose the format at the source.

The rule: use Parquet (or ORC) for anything that will be queried analytically at scale. Use CSV/JSON for interchange, small files, and human inspection.

## The Takeaway

Column-oriented formats are faster for analytical queries because they minimize I/O — you read only the columns a query needs. Parquet adds row group skipping and column statistics on top of that, enabling the query engine to skip large portions of data based on filter conditions. The compression is a side effect of storing similar values together, not the primary design goal.

Choose your format based on your access pattern: row-oriented for OLTP and streaming, column-oriented for analytics.
