#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$(cd "${SCRIPT_DIR}/../../" && pwd)"

echo "==> Applying Secret..."
kubectl apply -f "${SCRIPT_DIR}/secrets.yaml"

echo "==> Applying ConfigMap..."
kubectl apply -f "${SCRIPT_DIR}/cm.yaml"

echo "==> Installing wordpress-verify..."
helm upgrade --install wordpress-verify "${CHART_DIR}" \
  --values "${SCRIPT_DIR}/values.yaml"

echo ""
echo "Install complete. Run verify.sh to check logs and health."
