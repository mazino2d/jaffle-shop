"""
Config-driven DAG factory.

Reads YAML files from dag/dags/ and creates Dagster jobs and
schedules. Each YAML file maps to one job. Cron-triggered DAGs get a schedule;
asset_sensor-triggered DAGs rely on Dagster's asset lineage to chain execution.
"""

from pathlib import Path

import yaml
from dagster import AssetSelection, ScheduleDefinition, define_asset_job
from dagster_dbt import build_dbt_asset_selection

DAG_CONFIG_DIR = Path(__file__).parent / "dags"


def _load_configs() -> list[dict]:
    return [
        yaml.safe_load(f.read_text())
        for f in sorted(DAG_CONFIG_DIR.glob("*.yml"))
    ]


def build_jobs_and_schedules(snapshot_assets, model_assets) -> tuple[list, list]:
    """Return (jobs, schedules) built from YAML dag configs.

    snapshot_assets: @dbt_assets built with select='resource_type:snapshot'
    model_assets:    @dbt_assets built with exclude='resource_type:snapshot'

    build_dbt_asset_selection requires exactly one AssetsDefinition, so we
    route each dag config to the correct one based on its dbt_selector.
    """
    jobs: list = []
    schedules: list = []

    for cfg in _load_configs():
        name = cfg["name"]

        # Resolve asset selection — route to the right @dbt_assets object
        if "dbt_selector" in cfg:
            selector = cfg["dbt_selector"]
            target_assets = (
                snapshot_assets
                if "resource_type:snapshot" in selector
                else model_assets
            )
            selection = build_dbt_asset_selection(
                [target_assets], dbt_select=selector
            )
        else:
            selection = AssetSelection.groups(name)

        job = define_asset_job(
            name=f"{name}_job",
            selection=selection,
            description=cfg.get("description", ""),
        )
        jobs.append(job)

        trigger = cfg.get("trigger", {})
        if trigger.get("type") == "cron":
            schedules.append(
                ScheduleDefinition(
                    job=job,
                    cron_schedule=trigger["cron_schedule"],
                    name=f"{name}_schedule",
                )
            )
        # asset_sensor: downstream jobs are chained via Dagster's asset lineage graph

    return jobs, schedules
