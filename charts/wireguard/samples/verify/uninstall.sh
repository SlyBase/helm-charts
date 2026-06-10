#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Uninstalling wireguard-verify..."
helm uninstall wireguard-verify --namespace wireguard-verify || true

echo "==> Deleting PVC (not removed by Helm due to resourcePolicy: keep)..."
kubectl -n wireguard-verify delete pvc wireguard-verify --ignore-not-found

echo "==> Deleting Namespace..."
kubectl delete -f "${SCRIPT_DIR}/namespace.yaml" --ignore-not-found

echo ""
echo "Uninstall complete."
