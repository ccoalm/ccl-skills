# Batch And Pipeline Architecture

Use this for imports, exports, backfills, repair scripts, data processing, and pipeline-like Python work.

## Boundaries

- Keep one-off scripts from becoming hidden production systems. If a script is repeated, add config, logs, dry run, resume, and tests.
- For large jobs, define chunk size, checkpoint, restart behavior, max concurrency, rate limits, and output artifacts.
- Use durable task state for multi-step jobs that affect product data.
- Separate extraction, transformation, validation, persistence, and reporting.
- For Airflow, Dagster, Spark, dbt, or true data-engineering orchestration, consider a future dedicated `python-data-pipeline` skill instead of overloading this skill.
