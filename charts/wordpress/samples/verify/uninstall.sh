#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Uninstalling wordpress-verify..."
helm uninstall wordpress-verify || true

echo "==> Waiting for PVC deletion..."
kubectl wait --for=delete pvc/wordpress-verify --timeout=60s 2>/dev/null || true

echo "==> Deleting ConfigMap..."
kubectl delete -f "${SCRIPT_DIR}/cm.yaml" --ignore-not-found

echo "==> Deleting Secret..."
kubectl delete -f "${SCRIPT_DIR}/secrets.yaml" --ignore-not-found

echo ""
echo "Uninstall complete."
