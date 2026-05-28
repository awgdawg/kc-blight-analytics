"""Extract KCMO Socrata datasets and load them into BigQuery (kc_blight_raw).

Auth: uses GCP_SA_KEY (JSON string env var) if set, else the service-account
keyfile at ~/.dbt/cms-analytics-sa.json. Socrata app token via SOCRATA_APP_TOKEN
(optional but recommended — anonymous requests are throttled).

Each table is fetched page-by-page (with retry/backoff for throttling), streamed
to a temporary newline-delimited JSON file, then loaded to BigQuery in a single
autodetect job. The single-file load avoids per-page schema-drift that a
page-by-page WRITE_APPEND can hit when a later page introduces a field/type the
first page's autodetected schema didn't cover.

Usage:
    python ingest/extract_load.py                 # live datasets only
    python ingest/extract_load.py --include-frozen  # one-time historical load too
"""
import argparse
import json
import os
import re
import sys
import tempfile
import time
from pathlib import Path

import yaml
from google.cloud import bigquery
from google.oauth2 import service_account
from sodapy import Socrata

DOMAIN = "data.kcmo.org"
RAW_DATASET = "kc_blight_raw"
PAGE_SIZE = 50000
MAX_RETRIES = 6


def sanitize_key(key: str) -> str:
    """Make a Socrata field name safe as a BigQuery column name.

    ':@computed_region_9t2m_phkm' -> 'computed_region_9t2m_phkm'
    """
    k = re.sub(r"[^0-9a-zA-Z_]", "_", key).strip("_").lower()
    if k and k[0].isdigit():
        k = "_" + k
    return k


def clean_record(record: dict) -> dict:
    """Sanitize keys and coerce every value to a string (or None).

    The raw layer is intentionally all-STRING. KCMO datasets have dirty,
    mixed-type columns (e.g. `inspection_area` is usually numeric but is
    sometimes a street name), which makes BigQuery autodetect guess a numeric
    type and then fail on the first text value. Coercing everything to STRING
    lets autodetect pick STRING for every column; dbt staging casts to proper
    types downstream. Nested values (Socrata point/location structs) are
    JSON-encoded so staging can JSON_EXTRACT lat/lng from them.
    """
    cleaned = {}
    for key, value in record.items():
        k = sanitize_key(key)
        if value is None:
            cleaned[k] = None
        elif isinstance(value, (dict, list)):
            cleaned[k] = json.dumps(value)
        else:
            cleaned[k] = str(value)
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


def fetch_page(socrata: Socrata, dataset_id: str, offset: int) -> list:
    """Fetch one page with retry/backoff (anonymous Socrata is throttled)."""
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            return socrata.get(dataset_id, limit=PAGE_SIZE, offset=offset)
        except Exception as e:  # 429 throttle, read timeout, transient network
            wait = min(60, 2 ** attempt)
            print(f"    fetch retry {attempt}/{MAX_RETRIES} at offset {offset} "
                  f"after error: {str(e)[:120]} (waiting {wait}s)", flush=True)
            time.sleep(wait)
    raise RuntimeError(
        f"Failed to fetch {dataset_id} at offset {offset} after {MAX_RETRIES} retries"
    )


def load_dataset(socrata: Socrata, bq: bigquery.Client, project: str, cfg: dict) -> int:
    table_id = f"{project}.{RAW_DATASET}.{cfg['table']}"
    offset = 0
    total = 0
    tmp = tempfile.NamedTemporaryFile(
        mode="w", suffix=".ndjson", delete=False, encoding="utf-8"
    )
    tmp_path = tmp.name
    try:
        with tmp:
            while True:
                rows = fetch_page(socrata, cfg["id"], offset)
                if not rows:
                    break
                for r in rows:
                    tmp.write(json.dumps(clean_record(r)) + "\n")
                total += len(rows)
                offset += PAGE_SIZE
                print(f"  {cfg['table']}: fetched {total} rows...", flush=True)
                if len(rows) < PAGE_SIZE:
                    break
        if total == 0:
            print(f"ERROR: {cfg['table']} fetched 0 rows", file=sys.stderr, flush=True)
            sys.exit(1)
        print(f"  {cfg['table']}: loading {total} rows to BigQuery...", flush=True)
        job_config = bigquery.LoadJobConfig(
            autodetect=True,
            write_disposition="WRITE_TRUNCATE",
            source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
        )
        with open(tmp_path, "rb") as fh:
            bq.load_table_from_file(fh, table_id, job_config=job_config).result()
    finally:
        os.unlink(tmp_path)
    print(f"DONE {cfg['table']}: {total} rows", flush=True)
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
            print(f"SKIP frozen {cfg['table']} (use --include-frozen to load)", flush=True)
            continue
        print(f"Loading {cfg['table']} from {cfg['id']}...", flush=True)
        load_dataset(socrata, bq, args.project, cfg)


if __name__ == "__main__":
    main()
