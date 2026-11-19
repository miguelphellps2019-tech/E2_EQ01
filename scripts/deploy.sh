#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${REPO_ROOT}/infrastructure/terraform"

for command_name in aws terraform; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Error: falta el comando ${command_name}." >&2
    exit 1
  fi
done

if [[ ! -f "${TF_DIR}/terraform.tfvars" ]]; then
  echo "Falta infrastructure/terraform/terraform.tfvars." >&2
  echo "Cópialo desde terraform.tfvars.example y reemplaza EQ01." >&2
  exit 1
fi

if [[ -z "${TF_VAR_api_key:-}" ]]; then
  echo "API key de API-Sports (no se mostrará)."
  echo "Déjela vacía y presione Enter solo si la guardó en SSM con bootstrap_api_key.sh."
  read -r -s -p "API key: " TF_VAR_api_key
  echo
  export TF_VAR_api_key
fi

terraform -chdir="${TF_DIR}" fmt -recursive
terraform -chdir="${TF_DIR}" init
terraform -chdir="${TF_DIR}" validate
terraform -chdir="${TF_DIR}" apply

echo
echo "Despliegue terminado. Ejecuta scripts/trigger_pipeline.sh para generar datos y evidencias."
