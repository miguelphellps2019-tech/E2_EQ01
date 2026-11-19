#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${REPO_ROOT}/infrastructure/terraform"
OUT_DIR="${REPO_ROOT}/evidencias/generated"
mkdir -p "${OUT_DIR}"

for command_name in aws terraform; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Error: falta el comando ${command_name}." >&2
    exit 1
  fi
done

REGION="$(terraform -chdir="${TF_DIR}" output -raw aws_region)"
BUCKET="$(terraform -chdir="${TF_DIR}" output -raw bucket_name)"
GLUE_JOB="$(terraform -chdir="${TF_DIR}" output -raw glue_job_name)"
DDB_TABLE="$(terraform -chdir="${TF_DIR}" output -raw dynamodb_table_name)"
WORKGROUP="$(terraform -chdir="${TF_DIR}" output -raw athena_workgroup_name)"
SCHEDULE="$(terraform -chdir="${TF_DIR}" output -raw scheduler_name)"
LAMBDA_FUNCTION="$(terraform -chdir="${TF_DIR}" output -raw lambda_function_name)"
GLUE_ERROR_LOG_GROUP="$(terraform -chdir="${TF_DIR}" output -raw glue_error_log_group_name)"
GLUE_OUTPUT_LOG_GROUP="$(terraform -chdir="${TF_DIR}" output -raw glue_output_log_group_name)"

terraform -chdir="${TF_DIR}" output -json > "${OUT_DIR}/terraform-outputs.json"
aws s3 ls "s3://${BUCKET}/raw/" --recursive --human-readable --summarize > "${OUT_DIR}/s3-raw.txt"
aws s3 ls "s3://${BUCKET}/curated/" --recursive --human-readable --summarize > "${OUT_DIR}/s3-curated.txt"
aws s3api get-bucket-lifecycle-configuration --region "${REGION}" --bucket "${BUCKET}" --no-cli-pager > "${OUT_DIR}/s3-lifecycle.json"
aws s3api get-public-access-block --region "${REGION}" --bucket "${BUCKET}" --no-cli-pager > "${OUT_DIR}/s3-public-access-block.json"
aws s3api get-bucket-encryption --region "${REGION}" --bucket "${BUCKET}" --no-cli-pager > "${OUT_DIR}/s3-encryption.json"
aws s3api get-bucket-versioning --region "${REGION}" --bucket "${BUCKET}" --no-cli-pager > "${OUT_DIR}/s3-versioning.json"
aws glue get-job --region "${REGION}" --job-name "${GLUE_JOB}" --no-cli-pager > "${OUT_DIR}/glue-job.json"
aws glue get-job-runs --region "${REGION}" --job-name "${GLUE_JOB}" --max-results 5 --no-cli-pager > "${OUT_DIR}/glue-job-runs.json"
aws dynamodb describe-table --region "${REGION}" --table-name "${DDB_TABLE}" --no-cli-pager > "${OUT_DIR}/dynamodb-table.json"
aws dynamodb describe-time-to-live --region "${REGION}" --table-name "${DDB_TABLE}" --no-cli-pager > "${OUT_DIR}/dynamodb-ttl.json"
aws dynamodb scan --region "${REGION}" --table-name "${DDB_TABLE}" --max-items 10 --no-cli-pager > "${OUT_DIR}/dynamodb-sample.json"
aws athena get-work-group --region "${REGION}" --work-group "${WORKGROUP}" --no-cli-pager > "${OUT_DIR}/athena-workgroup.json"
aws glue get-tables --region "${REGION}" --database-name "$(terraform -chdir="${TF_DIR}" output -raw glue_database_name)" --no-cli-pager > "${OUT_DIR}/glue-catalog-tables.json"
aws scheduler get-schedule --region "${REGION}" --name "${SCHEDULE}" --no-cli-pager > "${OUT_DIR}/scheduler.json"
terraform -chdir="${TF_DIR}" output -json role_arns > "${OUT_DIR}/iam-role-arns.json"
aws logs describe-log-groups --region "${REGION}" --log-group-name-prefix "/aws/lambda/${LAMBDA_FUNCTION}" --no-cli-pager > "${OUT_DIR}/lambda-log-group.json"
aws logs describe-log-groups --region "${REGION}" --log-group-name-prefix "${GLUE_ERROR_LOG_GROUP}" --no-cli-pager > "${OUT_DIR}/glue-error-log-group.json"
aws logs describe-log-groups --region "${REGION}" --log-group-name-prefix "${GLUE_OUTPUT_LOG_GROUP}" --no-cli-pager > "${OUT_DIR}/glue-output-log-group.json"
aws logs tail "/aws/lambda/${LAMBDA_FUNCTION}" --region "${REGION}" --since 1d --format short > "${OUT_DIR}/lambda-last-day.log" || true

cat > "${OUT_DIR}/README.txt" <<EOF
Evidencia automática generada en $(date -u +%Y-%m-%dT%H:%M:%SZ)
Cuenta: $(aws sts get-caller-identity --query Account --output text)
Región: ${REGION}
Bucket: ${BUCKET}

Complemente estos archivos con capturas de consola según evidencias/README.md.
EOF

echo "Evidencia técnica guardada en ${OUT_DIR}"
