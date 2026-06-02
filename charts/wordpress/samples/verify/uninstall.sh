#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Uninstalling wordpress-verify..."
helm uninstall wordpress-verify || true

echo "==> Deleting StatefulSet PVCs (not tracked by Helm)..."
kubectl delete pvc \
  wordpress-verify-wordpress-verify-0 \
  wordpress-verify-wordpress-verify-1 \
  data-wordpress-verify-mariadb-0 \
  data-wordpress-verify-valkey-0 \
  --ignore-not-found

echo "==> Deleting ConfigMap..."
kubectl delete -f "${SCRIPT_DIR}/cm.yaml" --ignore-not-found

echo "==> Deleting Secret..."
kubectl delete -f "${SCRIPT_DIR}/secrets.yaml" --ignore-not-found

echo ""
echo "Uninstall complete."
