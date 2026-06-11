#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Uninstalling wg-easy-verify..."
helm uninstall wg-easy-verify --namespace wg-easy-verify || true

echo "==> Deleting PVC (not removed by Helm due to resourcePolicy: keep)..."
kubectl -n wg-easy-verify delete pvc wg-easy-verify --ignore-not-found

echo "==> Deleting Namespace..."
kubectl delete -f "${SCRIPT_DIR}/namespace.yaml" --ignore-not-found

echo ""
echo "Uninstall complete."
