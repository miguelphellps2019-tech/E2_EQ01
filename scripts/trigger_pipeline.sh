#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${REPO_ROOT}/infrastructure/terraform"
RESPONSE_FILE="${REPO_ROOT}/evidencias/lambda-manual-response.json"
INVOKE_META_FILE="${REPO_ROOT}/evidencias/lambda-invoke-metadata.json"

for command_name in aws terraform python3; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Error: falta el comando ${command_name}." >&2
    exit 1
  fi
done

REGION="$(terraform -chdir="${TF_DIR}" output -raw aws_region)"
FUNCTION_NAME="$(terraform -chdir="${TF_DIR}" output -raw lambda_function_name)"

mkdir -p "${REPO_ROOT}/evidencias"

aws lambda invoke \
  --region "${REGION}" \
  --function-name "${FUNCTION_NAME}" \
  --cli-binary-format raw-in-base64-out \
  --payload '{}' \
  --no-cli-pager \
  "${RESPONSE_FILE}" > "${INVOKE_META_FILE}"

cat "${RESPONSE_FILE}"
echo

python3 - "${INVOKE_META_FILE}" "${RESPONSE_FILE}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    metadata = json.load(handle)
with open(sys.argv[2], encoding="utf-8") as handle:
    payload = json.load(handle)

if metadata.get("FunctionError") or "errorMessage" in payload:
    raise SystemExit(
        "La invocación Lambda falló. Revisa evidencias/lambda-manual-response.json "
        "y CloudWatch Logs."
    )
for required_key in ("glue_job_name", "glue_job_run_id"):
    if required_key not in payload:
        raise SystemExit(f"La respuesta Lambda no contiene {required_key!r}.")
PY

JOB_NAME="$(python3 - "${RESPONSE_FILE}" <<'PY'
import json, sys
with open(sys.argv[1], encoding='utf-8') as handle:
    payload = json.load(handle)
print(payload['glue_job_name'])
PY
)"
JOB_RUN_ID="$(python3 - "${RESPONSE_FILE}" <<'PY'
import json, sys
with open(sys.argv[1], encoding='utf-8') as handle:
    payload = json.load(handle)
print(payload['glue_job_run_id'])
PY
)"

echo "Esperando Glue job ${JOB_NAME}/${JOB_RUN_ID}..."
while true; do
  STATE="$(aws glue get-job-run \
    --region "${REGION}" \
    --job-name "${JOB_NAME}" \
    --run-id "${JOB_RUN_ID}" \
    --query 'JobRun.JobRunState' \
    --output text \
    --no-cli-pager)"
  echo "Glue state: ${STATE}"
  case "${STATE}" in
    SUCCEEDED)
      break
      ;;
    FAILED|STOPPED|TIMEOUT|ERROR|EXPIRED)
      echo "El job de Glue terminó con error: ${STATE}" >&2
      exit 1
      ;;
  esac
  sleep 20
done

echo "Pipeline terminado. Ya puedes ejecutar scripts/run_athena_queries.py."
