#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$(cd "${SCRIPT_DIR}/../../" && pwd)"

echo "==> Applying Namespace..."
kubectl apply -f "${SCRIPT_DIR}/namespace.yaml"

echo "==> Installing wg-easy-verify..."
helm upgrade --install wg-easy-verify "${CHART_DIR}" \
  --namespace wg-easy-verify \
  --values "${SCRIPT_DIR}/values.yaml"

echo ""
echo "Install complete. Run verify.sh to check logs and health."
