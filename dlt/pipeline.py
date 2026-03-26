"""
Entry point for running the dlt ingestion pipeline.

Usage:
    python dlt/pipeline.py

Loads all Jaffle Shop tables into DuckDB under the 'raw' dataset.
Run this script to simulate a daily backend sync.
"""

import os
import sys
from pathlib import Path

# Add dlt/ directory to path so 'sources' can be imported without
# conflicting with the installed dlt package's own dlt.sources module.
sys.path.insert(0, str(Path(__file__).parent))

import dlt
from dotenv import load_dotenv

from sources.jaffle_shop import jaffle_shop

load_dotenv()

DUCKDB_PATH = os.getenv("DUCKDB_DEV_PATH", "./jaffle_shop_dev.duckdb")


def run():
    pipeline = dlt.pipeline(
        pipeline_name="jaffle_shop",
        destination=dlt.destinations.duckdb(DUCKDB_PATH),
        dataset_name="raw",
    )

    load_info = pipeline.run(jaffle_shop())
    print(load_info)


if __name__ == "__main__":
    run()
