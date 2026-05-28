"""Extract KCMO Socrata datasets and load them into BigQuery (kc_blight_raw).

Auth: uses GCP_SA_KEY (JSON string env var) if set, else the service-account
keyfile at ~/.dbt/cms-analytics-sa.json. Socrata app token via SOCRATA_APP_TOKEN
(optional, raises rate limits).

Usage:
    python ingest/extract_load.py                 # live datasets only
    python ingest/extract_load.py --include-frozen  # one-time historical load too
"""
import argparse
import json
import os
import re
import sys
from pathlib import Path

import yaml
from google.cloud import bigquery
from google.oauth2 import service_account
from sodapy import Socrata

DOMAIN = "data.kcmo.org"
RAW_DATASET = "kc_blight_raw"
PAGE_SIZE = 50000


def sanitize_key(key: str) -> str:
    """Make a Socrata field name safe as a BigQuery column name.

    ':@computed_region_9t2m_phkm' -> 'computed_region_9t2m_phkm'
    """
    k = re.sub(r"[^0-9a-zA-Z_]", "_", key).strip("_").lower()
    if k and k[0].isdigit():
        k = "_" + k
    return k


def clean_record(record: dict) -> dict:
    """Sanitize keys and JSON-encode nested values (Socrata point/location)."""
    cleaned = {}
    for key, value in record.items():
        k = sanitize_key(key)
        cleaned[k] = json.dumps(value) if isinstance(value, (dict, list)) else value
    return cleaned


def get_bq_client(project: str) -> bigquery.Client:
    key_json = os.environ.get("GCP_SA_KEY")
    if key_json:
        info = json.loads(key_json)
        creds = service_account.Credentials.from_service_account_info(info)
    else:
        key_path = Path.home() / ".dbt" / "cms-analytics-sa.json"
        creds = service_account.Credentials.from_service_account_file(str(key_path))
    return bigquery.Client(project=project, credentials=creds)


def load_dataset(socrata: Socrata, bq: bigquery.Client, project: str, cfg: dict) -> int:
    table_id = f"{project}.{RAW_DATASET}.{cfg['table']}"
    offset = 0
    total = 0
    schema = None  # established from the first page, reused for appends
    while True:
        rows = socrata.get(cfg["id"], limit=PAGE_SIZE, offset=offset)
        if not rows:
            break
        cleaned = [clean_record(r) for r in rows]
        if schema is None:
            job_config = bigquery.LoadJobConfig(
                autodetect=True,
                write_disposition="WRITE_TRUNCATE",
                source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
            )
            bq.load_table_from_json(cleaned, table_id, job_config=job_config).result()
            schema = bq.get_table(table_id).schema
        else:
            job_config = bigquery.LoadJobConfig(
                schema=schema,
                write_disposition="WRITE_APPEND",
                source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
            )
            bq.load_table_from_json(cleaned, table_id, job_config=job_config).result()
        total += len(cleaned)
        offset += PAGE_SIZE
        print(f"  {cfg['table']}: {total} rows loaded...")
        if len(rows) < PAGE_SIZE:
            break
    if total == 0:
        print(f"ERROR: {cfg['table']} loaded 0 rows", file=sys.stderr)
        sys.exit(1)
    print(f"DONE {cfg['table']}: {total} rows")
    return total


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--include-frozen", action="store_true",
                        help="also (re)load datasets marked frozen")
    parser.add_argument("--project", default="cms-medicare-analytics")
    args = parser.parse_args()

    cfg_path = Path(__file__).parent / "datasets.yml"
    datasets = yaml.safe_load(cfg_path.read_text())["datasets"]

    socrata = Socrata(DOMAIN, os.environ.get("SOCRATA_APP_TOKEN"), timeout=120)
    bq = get_bq_client(args.project)
    bq.create_dataset(f"{args.project}.{RAW_DATASET}", exists_ok=True)

    for cfg in datasets:
        if cfg.get("mode") == "frozen" and not args.include_frozen:
            print(f"SKIP frozen {cfg['table']} (use --include-frozen to load)")
            continue
        print(f"Loading {cfg['table']} from {cfg['id']}...")
        load_dataset(socrata, bq, args.project, cfg)


if __name__ == "__main__":
    main()
