"""Dagster asset wrapping the dlt ingestion pipeline."""

import os
from pathlib import Path

from dagster import AssetExecutionContext, asset

_DLT_SOURCES_DIR = str(Path(__file__).parent.parent.parent / "dlt")


@asset(
    group_name="raw_ingestion",
    description="Load all Jaffle Shop raw tables via dlt into DuckDB.",
)
def raw_jaffle_data(context: AssetExecutionContext) -> None:
    import sys

    # Must be inside the function so the path is present in the execution
    # context where the deferred import runs.
    if _DLT_SOURCES_DIR not in sys.path:
        sys.path.insert(0, _DLT_SOURCES_DIR)

    import dlt
    from sources.jaffle_shop import jaffle_shop

    target = os.getenv("DBT_TARGET", "dev")
    if target == "cloud":
        cloud_path = os.getenv("DUCKDB_CLOUD_PATH")
        destination = dlt.destinations.motherduck(cloud_path)
        context.log.info(f"Writing to: {cloud_path} (MotherDuck)")
    elif target == "prod":
        duckdb_path = os.getenv("DUCKDB_PROD_PATH")
        destination = dlt.destinations.duckdb(duckdb_path)
        context.log.info(f"Writing to: {duckdb_path}")
    else:
        duckdb_path = os.getenv("DUCKDB_DEV_PATH")
        destination = dlt.destinations.duckdb(duckdb_path)
        context.log.info(f"Writing to: {duckdb_path}")

    pipeline = dlt.pipeline(
        pipeline_name="jaffle_shop",
        destination=destination,
        dataset_name="raw",
    )

    load_info = pipeline.run(jaffle_shop())
    context.log.info(str(load_info))
