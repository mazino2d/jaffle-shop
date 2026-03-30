# Jaffle Shop — Data Pipeline Demo

A learning project demonstrating a modern data stack for building end-to-end data pipelines. Uses a fictional e-commerce store (Jaffle Shop) as the data domain.

## Stack

| Layer | Tool | Role |
|---|---|---|
| Ingestion | [dlt](https://dlthub.com) | Load raw data from backend into DuckDB |
| Warehouse | [DuckDB](https://duckdb.org) | Local, file-based analytical database |
| Transformation | [dbt](https://www.getdbt.com) | Build and test data models in layers |
| Orchestration | [Dagster](https://dagster.io) | Schedule, run, and observe the pipeline |

---

## Architecture

```
Backend (simulated by Faker)
    │
    ▼  dlt — daily sync
DuckDB  raw schema
    │   ├── customers     (replace — SCD source)
    │   ├── orders        (replace — SCD source)
    │   ├── products      (replace — SCD source)
    │   ├── payments      (append — event log)
    │   └── order_items   (append — event log)
    │
    ▼  dbt snapshot — SCD Type 2
DuckDB  snapshots schema
    │   ├── customers_snapshot  (tracks customer status/profile changes)
    │   ├── orders_snapshot     (tracks order status transitions)
    │   └── products_snapshot   (tracks price/catalog changes)
    │
    ▼  dbt build
DuckDB  staging      → clean 1:1 views from raw + snapshots + seeds
        intermediate → business logic joins + surrogate key maps (ephemeral)
        marts/core   → dim_customers, fct_orders
        marts/features → customer_features (RFM), order_features (AOV, return risk)
```

### Why two types of source tables?

| Type | Tables | Backend behavior | dbt approach |
|---|---|---|---|
| **SCD** (slowly changing) | customers, orders, products | Record updated in-place | `dbt snapshot` → captures history |
| **Log** (append-only) | payments, order_items | New row per event | `incremental` model → process new rows only |

---

## Data Flow in Detail

### 1. Ingestion — `dlt/`

`dlt/sources/jaffle_shop.py` defines five resources using Faker to simulate a backend database. Running the pipeline loads all tables into DuckDB under the `raw` schema.

```bash
make ingest
```

### 2. Snapshots — `dbt/snapshots/`

SCD tables change in-place on the backend (e.g. an order's status moves from `placed` → `shipped` → `completed`). dbt snapshots use the `timestamp` strategy on `updated_at` to capture each version with `dbt_valid_from` / `dbt_valid_to` columns.

```bash
make snapshot
```

### 3. Transformations — `dbt/models/`

Models are organized in three layers:

```
staging/          Clean and rename raw columns. Incremental for log tables.
                  Includes stg_customer_id_mapping from seed data.
intermediate/     Business logic joins + surrogate key maps for SCD entities.
marts/
  core/           Reporting tables: dim_customers, fct_orders
  features/       ML feature tables: customer_features, order_features
```

Each layer is tagged in `dbt_project.yml` (`staging`, `intermediate`, `core`, `features`). Dagster uses these tags to build per-layer jobs.

#### Surrogate key enrichment

`dbt/macros/` provides macros that precompute foreign key surrogate key (FK→SK) mappings from snapshots, and an enrichment macro to join them onto fact tables. This powers dimension lookups in `intermediate/` via `dim_customer_sk_map`, `dim_order_sk_map`, and `dim_product_sk_map`.

```bash
make build        # full build + tests
make build-prod   # build against prod target
make freshness    # check source SLA (warn >12h, error >24h)
make docs         # generate + serve lineage graph
```

### 4. Orchestration — `dag/`

Each pipeline layer maps to a Dagster job defined by a YAML config in `dag/dags/`:

```
dag/dags/
├── raw_ingestion.yml   → cron: 0 6 * * *  (daily at 6am)
├── snapshots.yml       → sensor: triggers after raw_ingestion
├── staging.yml         → sensor: triggers after snapshots
├── intermediate.yml    → sensor: triggers after staging
├── core.yml            → sensor: triggers after intermediate
└── features.yml        → sensor: triggers after core
```

Each YAML config controls:
- `trigger.type`: `cron` or `asset_sensor` (depend on upstream job)
- `trigger.depends_on`: upstream dag name
- `catchup.enabled`: whether to support partition backfill
- `retry`: max retries and delay

`dag/loader.py` reads these YAML files at startup and creates Dagster jobs + schedules automatically — no Python changes needed to add or reconfigure a job.

```bash
make dagster      # open http://localhost:3000
```

---

## ML Features

`marts/features/` produces wide feature tables ready for ML training:

**`customer_features`** — one row per customer (RFM model):
- `days_since_last_order` — recency
- `order_frequency` — frequency (completed orders)
- `lifetime_value` — monetary
- `return_rate`, `avg_order_value`, `avg_days_between_orders`

**`order_features`** — one row per order:
- `payment_failure_rate`, `item_count`, `unique_products`
- `customer_ltv_at_order`, `customer_return_rate` — customer context at order time

Downstream consumers are documented in `dbt/models/marts/features/_exposures.yml`:
- `customer_churn_model` — 30-day churn prediction
- `return_risk_model` — order return prediction
- `executive_dashboard` — KPI reporting

---

## Project Structure

```
jaffle-shop/
├── Makefile                        # all commands
├── pyproject.toml                  # Python dependencies
├── mkdocs.yml                      # documentation site config
├── dagster_cloud.yaml              # Dagster Cloud deployment config
├── .env                            # local config (gitignored)
├── .env.example                    # template for new developers
│
├── dlt/
│   ├── sources/
│   │   └── jaffle_shop.py          # Faker-based source (5 tables)
│   └── pipeline.py                 # standalone runner
│
├── dbt/
│   ├── dbt_project.yml             # layer tags + materializations
│   ├── profiles.yml                # DuckDB connection (dev/prod)
│   ├── packages.yml                # dbt-utils
│   ├── seeds/
│   │   └── customer_id_mapping.csv # static customer ID reference data
│   ├── macros/                     # surrogate key enrichment macros
│   │   ├── scd_surrogate_keys.sql
│   │   ├── scd_sk_map.sql
│   │   ├── fk_sk_enrich.sql
│   │   └── snapshot_incremental_filter.sql
│   ├── snapshots/                  # SCD Type 2 for customers, orders, products
│   └── models/
│       ├── staging/                # _sources.yml (freshness SLA), stg_*.sql
│       ├── intermediate/           # int_customer_orders, int_order_payments,
│       │                           # dim_*_sk_map (surrogate key lookups)
│       └── marts/
│           ├── core/               # dim_customers, fct_orders
│           └── features/           # customer_features, order_features, exposures
│
└── dag/
    ├── dags/                       # one YAML config per job
    ├── assets/
    │   └── ingestion.py            # raw_jaffle_data asset (wraps dlt)
    ├── loader.py                   # YAML → Dagster jobs/schedules factory
    └── definitions.py              # Dagster entry point
```

---

## Quickstart

### Prerequisites

- Python 3.11+
- A Python virtual environment

### Setup

```bash
# 1. Install dependencies
make install

# 2. Copy and configure environment
cp .env.example .env
# Edit .env: set DUCKDB_DEV_PATH to the absolute path of this repo
# e.g. DUCKDB_DEV_PATH=/home/user/jaffle-shop/jaffle_shop_dev.duckdb

# 3. Install dbt packages
cd dbt && dbt deps --profiles-dir . && cd ..

# 4. Install git hooks (runs lint on commit)
pre-commit install
```

### Run the full pipeline (CLI)

```bash
make pipeline     # ingest → snapshot → build (in sequence)
make freshness    # verify source data SLA
make docs         # open dbt lineage in browser
```

### Run with Dagster UI

```bash
# Compile dbt manifest first (required by Dagster on first run)
cd dbt && dbt compile --profiles-dir . && cd ..

make dagster      # open http://localhost:3000
```

In the UI:
1. Go to **Assets** → select all → **Materialize**
2. Or trigger individual jobs: `raw_ingestion_job` → cascades downstream automatically
3. Go to **Runs** to see logs and execution timeline
4. Go to **Asset catalog** to explore lineage from raw → features

### Simulate a second day (incremental load)

```bash
make ingest       # loads new data (append-only tables get new rows)
make snapshot     # captures any SCD changes
make build        # incremental models process only new rows
```

---

## Code Quality

```bash
make lint         # SQLFluff: lint all SQL models
make fix          # SQLFluff: auto-fix style issues
```

SQLFluff config: `.sqlfluff` (dialect: DuckDB, templater: dbt).

---

## Documentation

```bash
make blog         # serve MkDocs documentation site locally
```
