#!/usr/bin/env python3
"""Execute the three required Athena queries and record exact scan metrics."""

from __future__ import annotations

import argparse
import csv
import json
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import boto3

TERMINAL_STATES = {"SUCCEEDED", "FAILED", "CANCELLED"}
MIN_BILLED_BYTES = 10_000_000
ATHENA_USD_PER_TB = 5.0


def parse_args() -> argparse.Namespace:
    repo_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser()
    parser.add_argument("--terraform-dir", type=Path, default=repo_root / "infrastructure" / "terraform")
    parser.add_argument("--query-dir", type=Path, default=repo_root / "athena" / "queries")
    parser.add_argument("--evidence-dir", type=Path, default=repo_root / "evidencias")
    parser.add_argument("--region")
    parser.add_argument("--database")
    parser.add_argument("--workgroup")
    parser.add_argument("--league-id", type=int)
    parser.add_argument("--season", type=int)
    parser.add_argument("--poll-seconds", type=float, default=2.0)
    return parser.parse_args()


def terraform_outputs(terraform_dir: Path) -> dict[str, Any]:
    command = ["terraform", f"-chdir={terraform_dir}", "output", "-json"]
    try:
        raw = subprocess.check_output(command, text=True)
    except FileNotFoundError as exc:
        raise RuntimeError("Terraform no está instalado y faltan argumentos explícitos.") from exc
    except subprocess.CalledProcessError as exc:
        raise RuntimeError("No se pudieron leer los outputs de Terraform.") from exc
    values = json.loads(raw)
    return {name: item["value"] for name, item in values.items()}


def render_sql(path: Path, database: str, league_id: int, season: int) -> str:
    sql = path.read_text(encoding="utf-8")
    return (
        sql.replace("{{DATABASE}}", database)
        .replace("{{LEAGUE_ID}}", str(league_id))
        .replace("{{NEXT_SEASON}}", str(season + 1))
        .replace("{{SEASON}}", str(season))
    )


def wait_for_query(client: Any, execution_id: str, poll_seconds: float) -> dict[str, Any]:
    while True:
        response = client.get_query_execution(QueryExecutionId=execution_id)
        execution = response["QueryExecution"]
        state = execution["Status"]["State"]
        if state in TERMINAL_STATES:
            return execution
        time.sleep(poll_seconds)


def save_results(client: Any, execution_id: str, output_path: Path) -> int:
    paginator = client.get_paginator("get_query_results")
    row_count = 0
    wrote_header = False
    with output_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        for page in paginator.paginate(QueryExecutionId=execution_id):
            result_set = page["ResultSet"]
            columns = [item["Label"] for item in result_set["ResultSetMetadata"]["ColumnInfo"]]
            if not wrote_header:
                writer.writerow(columns)
                wrote_header = True
            for row in result_set.get("Rows", []):
                values = [cell.get("VarCharValue", "") for cell in row.get("Data", [])]
                values += [""] * (len(columns) - len(values))
                if values == columns:
                    continue
                writer.writerow(values)
                row_count += 1
    return row_count


def estimated_cost_usd(scanned_bytes: int) -> float:
    billed_bytes = max(scanned_bytes, MIN_BILLED_BYTES)
    return billed_bytes / 1_000_000_000_000 * ATHENA_USD_PER_TB


def main() -> int:
    args = parse_args()
    values: dict[str, Any] = {}
    required = [args.region, args.database, args.workgroup, args.league_id, args.season]
    if any(value is None for value in required):
        values = terraform_outputs(args.terraform_dir)

    region = args.region or values["aws_region"]
    database = args.database or values["glue_database_name"]
    workgroup = args.workgroup or values["athena_workgroup_name"]
    league_id = args.league_id or int(values["league_id"])
    season = args.season or int(values["season"])

    args.evidence_dir.mkdir(parents=True, exist_ok=True)
    query_paths = sorted(args.query_dir.glob("*.sql"))
    if len(query_paths) < 3:
        raise RuntimeError(f"Se esperaban al menos tres consultas en {args.query_dir}.")

    client = boto3.client("athena", region_name=region)
    records: list[dict[str, Any]] = []

    for query_path in query_paths:
        sql = render_sql(query_path, database, league_id, season)
        started = client.start_query_execution(
            QueryString=sql,
            QueryExecutionContext={"Database": database},
            WorkGroup=workgroup,
            ClientRequestToken=f"{query_path.stem}-{time.time_ns()}",
        )
        execution_id = started["QueryExecutionId"]
        execution = wait_for_query(client, execution_id, args.poll_seconds)
        status = execution["Status"]["State"]
        statistics = execution.get("Statistics", {})
        scanned_bytes = int(statistics.get("DataScannedInBytes", 0))
        reason = execution["Status"].get("StateChangeReason", "")
        result_rows = 0
        result_file = args.evidence_dir / f"{query_path.stem}-results.csv"
        if status == "SUCCEEDED":
            result_rows = save_results(client, execution_id, result_file)

        record = {
            "query": query_path.name,
            "execution_id": execution_id,
            "status": status,
            "data_scanned_bytes": scanned_bytes,
            "data_scanned_mib": scanned_bytes / (1024 * 1024),
            "engine_ms": int(statistics.get("EngineExecutionTimeInMillis", 0)),
            "total_ms": int(statistics.get("TotalExecutionTimeInMillis", 0)),
            "estimated_cost_usd": estimated_cost_usd(scanned_bytes),
            "result_rows": result_rows,
            "reason": reason,
        }
        records.append(record)
        print(json.dumps(record, ensure_ascii=False))

    timestamp = datetime.now(timezone.utc).isoformat()
    csv_path = args.evidence_dir / "athena-query-metrics.csv"
    with csv_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(records[0].keys()))
        writer.writeheader()
        writer.writerows(records)

    md_path = args.evidence_dir / "athena-query-metrics.md"
    with md_path.open("w", encoding="utf-8") as handle:
        handle.write("# Evidencia de consultas Athena\n\n")
        handle.write(f"Generado: `{timestamp}`  \n")
        handle.write(f"Región: `{region}` · Base: `{database}` · Workgroup: `{workgroup}`  \n")
        handle.write(f"Liga: `{league_id}` · Temporada: `{season}`\n\n")
        handle.write("| Consulta | Estado | Bytes escaneados | MiB | Tiempo total (ms) | Costo estimado USD* | Execution ID |\n")
        handle.write("|---|---:|---:|---:|---:|---:|---|\n")
        for record in records:
            handle.write(
                f"| {record['query']} | {record['status']} | {record['data_scanned_bytes']:,} | "
                f"{record['data_scanned_mib']:.3f} | {record['total_ms']:,} | "
                f"{record['estimated_cost_usd']:.6f} | `{record['execution_id']}` |\n"
            )
        handle.write("\n*Estimación a USD 5/TB y mínimo facturable de 10 MB por consulta. El criterio de entrega usa el valor exacto `DataScannedInBytes` mostrado en la tabla.*\n")

    failed = [record for record in records if record["status"] != "SUCCEEDED"]
    if failed:
        print(f"{len(failed)} consulta(s) no terminaron correctamente. Revisa {md_path}.", file=sys.stderr)
        return 1

    print(f"Evidencia guardada en {md_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
