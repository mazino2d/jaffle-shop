.PHONY: ingest snapshot build build-prod freshness docs dagster lint fix pipeline install

ingest:
	python dlt/pipeline.py

snapshot:
	cd dbt && dbt snapshot --profiles-dir .

build:
	cd dbt && dbt build --profiles-dir .

build-prod:
	cd dbt && dbt build --profiles-dir . --target prod

freshness:
	cd dbt && dbt source freshness --profiles-dir .

docs:
	cd dbt && dbt docs generate --profiles-dir . && dbt docs serve --profiles-dir .

dagster:
	dagster dev -f dagster_project/definitions.py --log-level warning

lint:
	sqlfluff lint dbt/models

fix:
	sqlfluff fix dbt/models

pipeline:
	$(MAKE) ingest && $(MAKE) snapshot && $(MAKE) build

install:
	pip install -e ".[dev]"
