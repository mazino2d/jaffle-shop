"""
Dagster Definitions entry point.

Combines:
- raw_jaffle_data: dlt ingestion asset
- jaffle_snapshot_assets: dbt snapshots (dbt snapshot command)
- jaffle_dbt_assets: all dbt models, excluding snapshots (dbt build command)
- Jobs and schedules loaded from dags/*.yml
"""

import os
from pathlib import Path

from dagster import Definitions
from dagster_dbt import DbtCliResource, dbt_assets

from dagster_project.assets.ingestion import raw_jaffle_data
from dagster_project.loader import build_jobs_and_schedules

REPO_ROOT = Path(__file__).parent.parent
DBT_PROJECT_DIR = REPO_ROOT / "dbt"
DBT_MANIFEST = DBT_PROJECT_DIR / "target" / "manifest.json"
os.environ.setdefault("DUCKDB_DEV_PATH", str(REPO_ROOT / "jaffle_shop_dev.duckdb"))
os.environ.setdefault("DUCKDB_PROD_PATH", str(REPO_ROOT / "jaffle_shop_prod.duckdb"))


@dbt_assets(
    manifest=DBT_MANIFEST,
    select="resource_type:snapshot",
    name="jaffle_snapshot_assets",
)
def jaffle_snapshot_assets(context, dbt: DbtCliResource):
    # Snapshots require 'dbt snapshot', not 'dbt build'
    yield from dbt.cli(["snapshot"], context=context).stream()


@dbt_assets(
    manifest=DBT_MANIFEST,
    exclude="resource_type:snapshot",
    name="jaffle_dbt_assets",
)
def jaffle_dbt_assets(context, dbt: DbtCliResource):
    yield from dbt.cli(["build"], context=context).stream()


jobs, schedules = build_jobs_and_schedules(jaffle_snapshot_assets, jaffle_dbt_assets)

defs = Definitions(
    assets=[raw_jaffle_data, jaffle_snapshot_assets, jaffle_dbt_assets],
    resources={
        "dbt": DbtCliResource(
            project_dir=str(DBT_PROJECT_DIR),
            profiles_dir=str(DBT_PROJECT_DIR),  # use dbt/profiles.yml, not ~/.dbt/
            target=os.getenv("DBT_TARGET", "dev"),
        )
    },
    jobs=jobs,
    schedules=schedules,
)
