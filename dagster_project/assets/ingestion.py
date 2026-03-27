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

    motherduck_token = os.getenv("MOTHERDUCK_TOKEN")
    context.log.info(f"MOTHERDUCK_TOKEN set: {bool(motherduck_token)}")

    if motherduck_token:
        destination = dlt.destinations.motherduck("md:jaffle_shop")
        context.log.info("Writing to: md:jaffle_shop (MotherDuck)")
    else:
        duckdb_path = os.getenv("DUCKDB_DEV_PATH", "./jaffle_shop_dev.duckdb")
        destination = dlt.destinations.duckdb(duckdb_path)
        context.log.info(f"Writing to: {duckdb_path}")

    pipeline = dlt.pipeline(
        pipeline_name="jaffle_shop",
        destination=destination,
        dataset_name="raw",
    )

    load_info = pipeline.run(jaffle_shop())
    context.log.info(str(load_info))
