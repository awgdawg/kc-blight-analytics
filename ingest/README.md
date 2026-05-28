# Ingestion (EL)

Pulls KCMO Socrata datasets into BigQuery `kc_blight_raw`.

## One-time full load (includes the frozen historical table)
```
python ingest/extract_load.py --include-frozen
```

## Routine refresh (live datasets only; what the scheduled Action runs)
```
python ingest/extract_load.py
```

Auth: set `GCP_SA_KEY` (service-account JSON string) or rely on
`~/.dbt/cms-analytics-sa.json`. Optional `SOCRATA_APP_TOKEN` raises rate limits.
