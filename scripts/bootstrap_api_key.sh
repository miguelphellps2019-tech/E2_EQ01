#!/usr/bin/env bash
set -euo pipefail

REGION="${1:-us-east-1}"
PARAMETER_NAME="${2:-/e2/eq01/api-sports/key}"

if ! command -v aws >/dev/null 2>&1; then
  echo "Error: AWS CLI no está instalado." >&2
  exit 1
fi

if [[ -z "${API_SPORTS_KEY:-}" ]]; then
  read -r -s -p "API-Sports key: " API_SPORTS_KEY
  echo
fi

if [[ -z "${API_SPORTS_KEY}" ]]; then
  echo "Error: la API key no puede estar vacía." >&2
  exit 1
fi

aws ssm put-parameter \
  --region "${REGION}" \
  --name "${PARAMETER_NAME}" \
  --description "API-Sports key for E2 Route 1" \
  --type SecureString \
  --value "${API_SPORTS_KEY}" \
  --overwrite \
  --no-cli-pager >/dev/null

echo "Parámetro seguro creado/actualizado: ${PARAMETER_NAME} (${REGION})"
