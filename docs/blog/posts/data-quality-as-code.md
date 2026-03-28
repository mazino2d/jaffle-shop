---
slug: data-quality-as-code
date: 2026-03-28
authors:
  - khoi
categories:
  - Quality & Reliability
tags:
  - data quality
  - testing
  - reliability
---

# Data Quality as Code: Tests That Ship With the Pipeline

Data quality checks are often treated as operational afterthoughts: a dashboard someone checks weekly, an alert someone set up once and forgot about, a manual audit done before a quarterly report. By the time a problem is discovered, bad data has propagated through the entire stack.

The alternative: define quality checks in code, run them as part of every pipeline execution, and fail fast when expectations are violated.

<!-- more -->

## The Problem With Downstream Quality Checks

When quality checks live downstream from the pipeline — in the BI layer, in a spreadsheet, in an analyst's ad-hoc query — they discover problems after bad data has already been loaded, transformed, and in some cases served to stakeholders.

The propagation path of a bad record:

```
Source → raw → staging → intermediate → marts → dashboard → stakeholder decision
```

If the check happens at the dashboard layer, the bad data has already passed through six layers. It may have been joined with other tables, aggregated, and used to compute metrics. Correcting it requires reprocessing every downstream model.

Quality checks belong as close to the source as possible. A bad record caught at staging never reaches intermediate. A bad record caught at intermediate never reaches a mart.

## Three Types of Quality Checks

### Schema Tests

Schema tests verify structural invariants that should always hold:

- **Not null:** a required column should never be NULL
- **Unique:** a primary key or business identifier should have no duplicates
- **Accepted values:** a categorical column should only contain defined values
- **Referential integrity:** a foreign key should always exist in the referenced table

These tests run against the data, not against logic. They catch data quality problems introduced by the source — missing values, unexpected categories, broken relationships.

In practice, every primary key in every model should have both `not_null` and `unique` tests. These are not optional.

### Business Logic Tests

Business logic tests verify domain-specific rules:

- Order totals should not be negative
- A completed order must have at least one payment
- Payment amounts should sum to the order total within a tolerance
- A customer's first order date should not be in the future

These tests encode business knowledge as assertions. They catch problems that schema tests miss: data that is structurally valid but semantically wrong.

```sql
-- Test: payment amounts should not exceed order amount by more than 1%
SELECT order_id
FROM fct_orders
WHERE total_paid > order_amount * 1.01
```

If any rows are returned, the test fails.

### Freshness SLAs

Freshness tests verify that data arrived on time. Rather than testing the data itself, they test the metadata — specifically, when the most recent record was loaded.

A source table that normally updates every hour should raise a warning if no new data has arrived in 12 hours, and an error if no new data in 24 hours.

Freshness tests catch a class of problems that schema and logic tests miss: everything is structurally correct, the data is semantically valid, but it's stale because an upstream process silently failed.

## Fail Fast, at the Lowest Layer

The principle: run tests at the layer where the assumption is first relevant.

**Source freshness tests:** run before any downstream processing begins. If source data is stale, don't start transformations.

**Schema tests on staging:** run after staging models build, before intermediate models reference them. A staging model with NULL primary keys should stop the run immediately.

**Business logic tests on marts:** run after the final model builds, as a final verification before the data is considered ready for consumption.

This layered approach means failures are caught as close to their source as possible, minimizing the blast radius of any single failure.

## Making Tests Actionable

A test failure is only useful if:

1. The failure is visible — someone sees it
2. The failure is actionable — someone knows what to do
3. The failure is specific — someone knows which model and which rows

Test names should describe the violation, not just the test type. Not "test_payment_id_not_null" but a description that tells an on-call engineer what broke and in which context.

Test failures should block downstream jobs from running with bad data. If staging tests fail, intermediate models should not build. Allowing downstream models to run with known bad staging data extends the contamination.

## Documentation as Quality

Listing expected values, documenting what each column means, and specifying the grain of each model is not just documentation — it's a form of quality specification.

A column description that says "status: one of [placed, shipped, completed, returned]" is the specification for the `accepted_values` test. Documenting that `fct_orders` has grain "one row per order" is the specification for the `unique` test on `order_id`.

Writing documentation and writing tests are the same activity, approached from different angles. Do both.

## The Takeaway

Data quality checks are not an operational add-on — they're part of the pipeline. Define them in code, run them on every execution, and fail fast when expectations are violated. Schema tests at staging, business logic tests at marts, freshness tests at the source boundary. The earlier a problem is caught, the smaller its blast radius.
