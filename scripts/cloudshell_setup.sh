#!/usr/bin/env bash
# Prepara AWS CloudShell para desplegar el proyecto E2_EQ01.
# Uso (desde la carpeta E2_EQ01):  bash scripts/cloudshell_setup.sh
set -euo pipefail

TF_VERSION="1.9.8"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="${HOME}/bin"

echo "== Permisos de ejecución para los scripts"
chmod +x "${REPO_ROOT}"/scripts/*.sh

echo "== Terraform"
if command -v terraform >/dev/null 2>&1; then
  echo "Ya instalado: $(terraform version | head -1)"
else
  case "$(uname -m)" in
    x86_64) TF_ARCH="amd64" ;;
    aarch64 | arm64) TF_ARCH="arm64" ;;
    *) echo "Arquitectura no soportada: $(uname -m)" >&2; exit 1 ;;
  esac
  mkdir -p "${BIN_DIR}"
  TMP_DIR="$(mktemp -d)"
  curl -fsSL -o "${TMP_DIR}/tf.zip" \
    "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_${TF_ARCH}.zip"
  unzip -o -q "${TMP_DIR}/tf.zip" -d "${BIN_DIR}"
  rm -rf "${TMP_DIR}"
  # ~/bin persiste entre sesiones de CloudShell; se agrega al PATH si falta.
  if ! grep -q 'HOME/bin' "${HOME}/.bashrc" 2>/dev/null; then
    echo 'export PATH="$HOME/bin:$PATH"' >> "${HOME}/.bashrc"
  fi
  export PATH="${BIN_DIR}:${PATH}"
  echo "Instalado: $(terraform version | head -1)"
fi

echo "== Dependencias Python locales (boto3, pytest)"
python3 -m pip install --user -q -r "${REPO_ROOT}/requirements-dev.txt"

echo "== Identidad AWS"
aws sts get-caller-identity --output table

echo
echo "Listo. Si 'terraform' no se encuentra en esta terminal, ejecuta:  source ~/.bashrc"
echo "Siguiente paso:"
echo "  ./scripts/deploy.sh   (pide la API key sin mostrarla)"
