"""Scheduled ingestion from API-Football into an AWS data lake.

The function performs three API calls (fixtures, teams, standings), stores the
unaltered API payload plus ingestion metadata in S3 raw/, updates a small
operational DynamoDB table, and starts the AWS Glue transformation job.

No third-party Python packages are required in the Lambda deployment package;
boto3 is supplied by the Lambda runtime and HTTP calls use urllib.
"""

from __future__ import annotations

import json
import logging
import os
import random
import re
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any, Mapping

import boto3

LOGGER = logging.getLogger()
LOGGER.setLevel(os.getenv("LOG_LEVEL", "INFO"))

API_BASE_URL = os.getenv("API_BASE_URL", "https://v3.football.api-sports.io").rstrip("/")
API_KEY_PARAMETER_NAME = os.getenv("API_KEY_PARAMETER_NAME", "")
BUCKET_NAME = os.environ["BUCKET_NAME"]
RAW_PREFIX = os.getenv("RAW_PREFIX", "raw").strip("/")
DDB_TABLE_NAME = os.environ["DDB_TABLE_NAME"]
GLUE_JOB_NAME = os.environ["GLUE_JOB_NAME"]
LEAGUE_ID = int(os.getenv("LEAGUE_ID", "39"))
SEASON = int(os.getenv("SEASON", "2024"))
ENDPOINTS = tuple(
    endpoint.strip()
    for endpoint in os.getenv("ENDPOINTS", "fixtures,teams,standings").split(",")
    if endpoint.strip()
)
FIXTURE_TTL_DAYS = int(os.getenv("FIXTURE_TTL_DAYS", "400"))
RUN_TTL_DAYS = int(os.getenv("RUN_TTL_DAYS", "30"))
HTTP_TIMEOUT_SECONDS = int(os.getenv("HTTP_TIMEOUT_SECONDS", "25"))
HTTP_MAX_ATTEMPTS = int(os.getenv("HTTP_MAX_ATTEMPTS", "3"))

ssm = boto3.client("ssm")
s3 = boto3.client("s3")
glue = boto3.client("glue")
dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(DDB_TABLE_NAME)


class ApiSportsError(RuntimeError):
    """Raised when API-Sports returns an HTTP or logical API error."""


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _compact_mapping(values: Mapping[str, Any]) -> dict[str, Any]:
    """Remove values DynamoDB should not store while preserving False and 0."""

    compact: dict[str, Any] = {}
    for key, value in values.items():
        if value is None or value == "":
            continue
        if isinstance(value, dict):
            nested = _compact_mapping(value)
            if nested:
                compact[key] = nested
        else:
            compact[key] = value
    return compact


def _api_key() -> str:
    # Opción 1: variable de entorno de Lambda (cifrada en reposo con KMS). Se usa
    # cuando una SCP de la organización bloquea ssm:PutParameter.
    env_value = os.getenv("API_KEY", "").strip()
    if env_value:
        return env_value

    # Opción 2: SSM Parameter Store SecureString.
    if not API_KEY_PARAMETER_NAME:
        raise RuntimeError("No hay API key: defina API_KEY o API_KEY_PARAMETER_NAME.")
    response = ssm.get_parameter(Name=API_KEY_PARAMETER_NAME, WithDecryption=True)
    value = response["Parameter"]["Value"].strip()
    if not value or value == "REPLACE_ME":
        raise RuntimeError(
            f"El parámetro SSM {API_KEY_PARAMETER_NAME!r} no contiene una API key válida."
        )
    return value


def _request_parameters(endpoint: str) -> dict[str, str]:
    parameters = {"league": str(LEAGUE_ID), "season": str(SEASON)}
    if endpoint == "fixtures":
        parameters["timezone"] = "UTC"
    return parameters


def _logical_api_errors(payload: Mapping[str, Any]) -> list[str]:
    errors = payload.get("errors")
    if not errors:
        return []
    if isinstance(errors, dict):
        return [f"{key}: {value}" for key, value in errors.items()]
    if isinstance(errors, list):
        return [str(value) for value in errors]
    return [str(errors)]


def _validate_api_payload(endpoint: str, payload: Any) -> dict[str, Any]:
    if not isinstance(payload, dict):
        raise ApiSportsError(
            f"{endpoint} devolvió un JSON de tipo {type(payload).__name__}, no un objeto."
        )

    logical_errors = _logical_api_errors(payload)
    if logical_errors:
        raise ApiSportsError("; ".join(logical_errors))

    response_items = payload.get("response")
    if not isinstance(response_items, list):
        raise ApiSportsError(f"{endpoint} no devolvió el arreglo 'response'.")
    if not response_items:
        raise ApiSportsError(
            f"{endpoint} devolvió cero registros; se conserva la última corrida completa."
        )
    return payload


def _validated_run_id(value: Any) -> str:
    run_id = str(value)
    if not re.fullmatch(r"[A-Za-z0-9._-]{1,128}", run_id):
        raise ValueError(
            "run_id solo puede contener letras, números, punto, guion y guion bajo "
            "(máximo 128 caracteres)."
        )
    return run_id


def _get_json(endpoint: str, api_key: str) -> tuple[dict[str, Any], dict[str, str], str]:
    query = urllib.parse.urlencode(_request_parameters(endpoint))
    url = f"{API_BASE_URL}/{endpoint}?{query}"
    request = urllib.request.Request(
        url,
        method="GET",
        headers={
            "x-apisports-key": api_key,
            "Accept": "application/json",
            "User-Agent": "E2-EQ01-AWS-Data-Lake/1.0",
        },
    )

    last_error: Exception | None = None
    for attempt in range(1, HTTP_MAX_ATTEMPTS + 1):
        try:
            with urllib.request.urlopen(request, timeout=HTTP_TIMEOUT_SECONDS) as response:
                raw_body = response.read()
                payload = _validate_api_payload(
                    endpoint, json.loads(raw_body.decode("utf-8"))
                )

                response_headers = {
                    name.lower(): value
                    for name, value in response.headers.items()
                    if name.lower().startswith("x-ratelimit")
                }
                return payload, response_headers, url
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")[:1000]
            last_error = ApiSportsError(
                f"HTTP {exc.code} al consultar {endpoint}: {body or exc.reason}"
            )
            retryable = exc.code == 429 or 500 <= exc.code < 600
            if not retryable or attempt == HTTP_MAX_ATTEMPTS:
                raise last_error from exc
            retry_after = exc.headers.get("Retry-After")
            delay = float(retry_after) if retry_after and retry_after.isdigit() else 2 ** (attempt - 1)
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, ApiSportsError) as exc:
            last_error = exc
            if isinstance(exc, ApiSportsError) or attempt == HTTP_MAX_ATTEMPTS:
                raise ApiSportsError(f"Fallo al consultar {endpoint}: {exc}") from exc
            delay = 2 ** (attempt - 1)

        delay += random.uniform(0, 0.5)
        LOGGER.warning(
            "Reintentando endpoint=%s intento=%s/%s en %.2fs",
            endpoint,
            attempt + 1,
            HTTP_MAX_ATTEMPTS,
            delay,
        )
        time.sleep(delay)

    raise ApiSportsError(f"No fue posible consultar {endpoint}: {last_error}")


def _raw_key(entity: str, run_id: str, now: datetime) -> str:
    return (
        f"{RAW_PREFIX}/source=api_sports/entity={entity}/"
        f"ingestion_date={now:%Y-%m-%d}/run_id={run_id}.json"
    )


def _write_raw(
    entity: str,
    payload: Mapping[str, Any],
    headers: Mapping[str, str],
    request_url: str,
    run_id: str,
    now: datetime,
) -> tuple[str, int]:
    wrapper = {
        "metadata": {
            "run_id": run_id,
            "ingested_at": now.isoformat(),
            "source": "api_sports",
            "sport": "football",
            "entity": entity,
            "league_id": LEAGUE_ID,
            "season": SEASON,
            "request_url": request_url,
            "rate_limit": dict(headers),
        },
        "payload": payload,
    }
    body = json.dumps(wrapper, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    key = _raw_key(entity, run_id, now)
    s3.put_object(
        Bucket=BUCKET_NAME,
        Key=key,
        Body=body,
        ContentType="application/json",
        Metadata={
            "source": "api-sports",
            "entity": entity,
            "run-id": run_id,
            "league-id": str(LEAGUE_ID),
            "season": str(SEASON),
        },
    )
    return key, len(body)


def _fixture_items(payload: Mapping[str, Any], run_id: str, now: datetime) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    expires_at = int((now + timedelta(days=FIXTURE_TTL_DAYS)).timestamp())
    for record in payload.get("response", []):
        fixture = record.get("fixture") or {}
        league = record.get("league") or {}
        teams = record.get("teams") or {}
        goals = record.get("goals") or {}
        status = fixture.get("status") or {}
        home = teams.get("home") or {}
        away = teams.get("away") or {}
        fixture_id = fixture.get("id")
        if fixture_id is None:
            continue

        item = _compact_mapping(
            {
                "pk": f"FIXTURE#{fixture_id}",
                "sk": "LATEST",
                "gsi1pk": f"LEAGUE#{league.get('id', LEAGUE_ID)}#SEASON#{league.get('season', SEASON)}",
                "gsi1sk": fixture.get("date") or "9999-12-31T00:00:00+00:00",
                "entity_type": "fixture",
                "fixture_id": int(fixture_id),
                "league_id": int(league.get("id", LEAGUE_ID)),
                "season": int(league.get("season", SEASON)),
                "round": league.get("round"),
                "fixture_date": fixture.get("date"),
                "status_short": status.get("short"),
                "status_long": status.get("long"),
                "home_team_id": home.get("id"),
                "home_team_name": home.get("name"),
                "away_team_id": away.get("id"),
                "away_team_name": away.get("name"),
                "home_goals": goals.get("home"),
                "away_goals": goals.get("away"),
                "source_run_id": run_id,
                "updated_at": now.isoformat(),
                "expires_at": expires_at,
            }
        )
        items.append(item)
    return items


def _write_operational_view(
    fixture_payload: Mapping[str, Any],
    run_id: str,
    now: datetime,
    counts: Mapping[str, int],
    raw_objects: Mapping[str, str],
) -> int:
    fixture_items = _fixture_items(fixture_payload, run_id, now)
    with table.batch_writer(overwrite_by_pkeys=["pk", "sk"]) as batch:
        for item in fixture_items:
            batch.put_item(Item=item)

    table.put_item(
        Item={
            "pk": f"RUN#{run_id}",
            "sk": "METADATA",
            "gsi1pk": "INGESTION_RUNS",
            "gsi1sk": now.isoformat(),
            "entity_type": "ingestion_run",
            "status": "RAW_READY",
            "league_id": LEAGUE_ID,
            "season": SEASON,
            "counts": dict(counts),
            "raw_objects": dict(raw_objects),
            "created_at": now.isoformat(),
            "expires_at": int((now + timedelta(days=RUN_TTL_DAYS)).timestamp()),
        }
    )
    return len(fixture_items)


def _start_glue(run_id: str, ingestion_date: str) -> str:
    response = glue.start_job_run(
        JobName=GLUE_JOB_NAME,
        Arguments={
            "--INGESTION_RUN_ID": run_id,
            "--INGESTION_DATE": ingestion_date,
        },
    )
    job_run_id = response["JobRunId"]
    table.update_item(
        Key={"pk": f"RUN#{run_id}", "sk": "METADATA"},
        UpdateExpression="SET #s = :status, glue_job_run_id = :job_run_id",
        ExpressionAttributeNames={"#s": "status"},
        ExpressionAttributeValues={
            ":status": "GLUE_STARTED",
            ":job_run_id": job_run_id,
        },
    )
    return job_run_id


def lambda_handler(event: Mapping[str, Any] | None, context: Any) -> dict[str, Any]:
    """Entrypoint used by EventBridge Scheduler and manual test invocations."""

    event = event or {}
    now = _utc_now()
    # One deterministic raw snapshot per UTC day. Scheduler retries overwrite the
    # same objects instead of creating duplicate small files.
    run_id = _validated_run_id(
        event.get("run_id")
        or f"{now:%Y%m%d}-league-{LEAGUE_ID}-season-{SEASON}"
    )
    invocation_id = getattr(context, "aws_request_id", str(uuid.uuid4()))
    LOGGER.info(
        "Inicio de ingesta run_id=%s invocation_id=%s league=%s season=%s endpoints=%s",
        run_id,
        invocation_id,
        LEAGUE_ID,
        SEASON,
        ENDPOINTS,
    )

    api_key = _api_key()
    fetched: dict[str, tuple[dict[str, Any], dict[str, str], str]] = {}
    # Fetch every endpoint before writing, so a source failure does not leave a
    # partially completed daily snapshot.
    for endpoint in ENDPOINTS:
        fetched[endpoint] = _get_json(endpoint, api_key)

    raw_objects: dict[str, str] = {}
    raw_bytes: dict[str, int] = {}
    counts: dict[str, int] = {}
    for endpoint, (payload, headers, request_url) in fetched.items():
        key, size = _write_raw(endpoint, payload, headers, request_url, run_id, now)
        raw_objects[endpoint] = f"s3://{BUCKET_NAME}/{key}"
        raw_bytes[endpoint] = size
        counts[endpoint] = int(payload.get("results", len(payload.get("response", []))))

    if "fixtures" not in fetched:
        raise RuntimeError("ENDPOINTS debe incluir 'fixtures' para poblar DynamoDB.")

    ddb_fixture_count = _write_operational_view(
        fetched["fixtures"][0], run_id, now, counts, raw_objects
    )
    glue_job_run_id = _start_glue(run_id, now.strftime("%Y-%m-%d"))

    response = {
        "run_id": run_id,
        "invocation_id": invocation_id,
        "league_id": LEAGUE_ID,
        "season": SEASON,
        "counts": counts,
        "raw_bytes": raw_bytes,
        "raw_objects": raw_objects,
        "dynamodb_fixture_items": ddb_fixture_count,
        "glue_job_name": GLUE_JOB_NAME,
        "glue_job_run_id": glue_job_run_id,
    }
    LOGGER.info("Ingesta iniciada correctamente: %s", json.dumps(response, default=str))
    return response
