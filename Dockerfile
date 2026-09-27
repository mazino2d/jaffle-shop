# Code location image for self-hosted Dagster OSS.
# Serves the `dag` package over gRPC; webserver/daemon run from the official Dagster images.
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONPATH=/opt/jaffle-shop

WORKDIR /opt/jaffle-shop

# Install runtime dependencies first so code changes do not bust this layer
COPY pyproject.toml ./
RUN python -c "import tomllib; print('\n'.join(tomllib.load(open('pyproject.toml', 'rb'))['project']['dependencies']))" \
        > /tmp/requirements.txt \
    && pip install -r /tmp/requirements.txt \
    && rm /tmp/requirements.txt

COPY dbt ./dbt
COPY dlt ./dlt
COPY dag ./dag

# Bake the dbt manifest into the image. Parsing does not connect to the warehouse,
# so the dev target is used and no MotherDuck token is needed at build time.
RUN cd dbt \
    && dbt deps --profiles-dir . \
    && dbt parse --profiles-dir . --target dev \
    && rm -rf logs

# dbt writes target/ and logs/ at runtime, dlt writes pipeline state under $HOME
RUN useradd --create-home --uid 1000 dagster \
    && chown -R dagster:dagster /opt/jaffle-shop
USER dagster

ENV DBT_TARGET=cloud

EXPOSE 3030
CMD ["dagster", "api", "grpc", "-m", "dag", "-h", "0.0.0.0", "-p", "3030"]
