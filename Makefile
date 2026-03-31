.PHONY: ingest snapshot build pipeline docs blog dagster lint fix sync install

ingest:
	dagster asset materialize -m dag.definitions --select raw_jaffle_data

snapshot:
	dagster asset materialize -m dag.definitions --select jaffle_snapshot_assets

build:
	dagster asset materialize -m dag.definitions --select jaffle_dbt_assets

pipeline:
	dagster asset materialize -m dag.definitions --select "*"

docs:
	cd dbt && dbt docs generate --profiles-dir . && dbt docs serve --profiles-dir .

blog:
	mkdocs serve

dagster:
	dagster dev -f dag/definitions.py --log-level warning

lint:
	sqlfluff lint dbt/models

fix:
	sqlfluff fix dbt/models

sync:
	pip-compile pyproject.toml -o requirements.txt

install:
	pip install -e ".[dev]"
