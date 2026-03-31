---
slug: data-contracts
date: 2026-03-28
description: Data contracts formalize the agreement between data producers and consumers, preventing silent pipeline failures when source schemas change unexpectedly.
authors:
  - khoi
categories:
  - Quality & Reliability
tags:
  - data contracts
  - governance
  - reliability
---

# Data Contracts: The Agreement Between Producers and Consumers

Most data pipeline failures don't originate in the pipeline itself. They originate upstream: a backend engineer adds a column, renames a field, or changes the semantics of a value — unaware that a downstream data pipeline depends on the exact current schema. The pipeline breaks, or worse, silently produces wrong results.

Data contracts are the formalization of the agreement between the producer of data and the consumer of that data.

<!-- more -->

## The Implicit Contract Problem

Every data pipeline encodes an implicit contract with its sources: "I expect these columns, in these types, with these values."

When that contract is implicit — encoded only in SQL column references and `WHERE` clauses — it's invisible. The source team doesn't know the contract exists. The data team doesn't know when the contract has been violated until the pipeline fails.

Implicit contracts always break eventually. The source changes for legitimate reasons. No one was warned because no one knew there was a contract to warn about.

## What a Data Contract Contains

A data contract formalizes the expectations between producer and consumer:

**Schema:** which fields exist, their types, and their constraints.

```yaml
contract:
  fields:
    - name: customer_id
      type: string
      nullable: false
    - name: status
      type: string
      accepted_values: [active, churned, at_risk]
    - name: updated_at
      type: timestamp
      nullable: false
```

**Semantics:** what the fields mean, not just their types.

```yaml
    - name: status
      description: >
        Current customer engagement status.
        'active': last order within 90 days.
        'at_risk': no order in 90-180 days.
        'churned': no order in >180 days.
```

**SLA:** how frequently the data is updated and what the maximum acceptable latency is.

```yaml
  freshness:
    update_frequency: daily
    warn_after_hours: 25
    error_after_hours: 48
```

**Deprecation policy:** how much notice the producer gives before making breaking changes.

```yaml
  breaking_change_notice_days: 14
```

## Explicit vs. Implicit Contracts

The difference between implicit and explicit contracts is not the content of the agreement — it's the visibility.

An implicit contract exists in every pipeline. The question is whether it's documented somewhere both parties can see.

An explicit contract:
- Is written down in a shared location (a YAML file in the repository, a schema registry, a documentation system)
- Is versioned alongside the data schema
- Creates a review process for changes
- Triggers notifications when the source schema diverges

## Schema Drift Detection as Enforcement

A contract without enforcement is just documentation. Schema drift detection is the mechanism that turns a contract into an active guardrail.

On each ingestion run, compare the schema of the incoming data against the defined contract:

- New columns: non-breaking, but log and notify
- Missing required columns: breaking, fail the ingestion
- Type changes: potentially breaking, fail and notify
- Unexpected values in categorical fields: log and notify

This gives the team visibility into violations before they propagate downstream.

## Downstream Consumer Documentation

A contract isn't just about what the source provides — it's also about what the consumer depends on. Documenting dependencies explicitly:

- **Which models depend on which sources.** If `stg_orders` breaks, what else breaks?
- **Which downstream consumers depend on which mart models.** If `fct_orders` changes, which dashboard and which ML model are affected?
- **What SLA the downstream consumer requires.** The executive dashboard needs data by 6am. What does the pipeline need to deliver?

This bidirectional documentation enables impact assessment: before making a change, you can see who would be affected.

## The Organizational Challenge

Technical contracts are the easier problem. The harder problem is organizational: getting source teams to respect the contract and notify before making breaking changes.

This requires:

**Making the contract visible.** If the contract is buried in a YAML file that only the data team sees, source engineers won't know to check it before making changes.

**Creating a change process.** A lightweight review: "before renaming this column, check if any data consumers depend on it."

**Building relationships.** Data teams that are known and accessible are more likely to be consulted before breaking changes happen. Data teams that are invisible are the last to know.

The contract is a coordination mechanism, not just a technical specification. Its value is proportional to how many people know it exists and respect it.

## Starting Simply

A full contract system is not required on day one. The minimum viable contract:

1. Write down the expected schema of each source in a YAML file
2. Run schema comparison on each ingestion run and log differences
3. Alert when differences are detected
4. Share the contract file with the source team

This is achievable in a few hours and provides most of the value. Formal enforcement, schema registries, and automated change reviews can be added incrementally as the need grows.

## The Takeaway

Every pipeline depends on implicit contracts with its sources. Making those contracts explicit — writing them down, versioning them, detecting when they're violated — is the difference between a pipeline that breaks mysteriously and one that breaks predictably and with actionable information. Start with a YAML file. Grow from there.
