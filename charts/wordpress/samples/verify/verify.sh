#!/usr/bin/env bash
# Full verification run: install → wait → check logs → report.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE="wordpress-verify"
TIMEOUT="${VERIFY_TIMEOUT:-300s}"
ERRORS=0

red()   { echo -e "\033[0;31m$*\033[0m"; }
green() { echo -e "\033[0;32m$*\033[0m"; }
bold()  { echo -e "\033[1m$*\033[0m"; }

check_logs() {
  local label="$1"; local pod="$2"; local container_flag="${3:-}"
  echo ""
  bold "--- Logs: ${label} ---"
  # shellcheck disable=SC2086
  kubectl logs "${pod}" ${container_flag} --tail=100 2>&1 | tee /tmp/verify_logs_tmp.txt
  # Filter known-harmless patterns before checking for real errors:
  #   - MariaDB io_uring EPERM + fallback: expected on Talos/hardened kernels, falls back to libaio safely
  if grep -viE "(io_uring_queue_init\(\) failed with EPERM|create_uring failed: falling back)" /tmp/verify_logs_tmp.txt \
      | grep -qiE "(error|fatal|panic|exception|failed|crash)" 2>/dev/null; then
    red "  [WARN] Suspicious keywords found in ${label} logs (see above)"
    ERRORS=$((ERRORS + 1))
  else
    green "  [OK] No errors detected in ${label} logs"
  fi
}

# ── 1. Install ────────────────────────────────────────────────────────────────
bold "==> Step 1: Install"
bash "${SCRIPT_DIR}/install.sh"

# ── 2. Wait for init job to finish ───────────────────────────────────────────
bold ""
bold "==> Step 2: Wait for init container to complete (timeout: ${TIMEOUT})"
echo "Waiting for wordpress-verify pod to appear..."
kubectl wait pod \
  -l "app.kubernetes.io/instance=${RELEASE},app.kubernetes.io/name=wordpress" \
  --for=condition=Initialized \
  --timeout="${TIMEOUT}" 2>/dev/null || true

# ── 3. Wait for all pods ready ────────────────────────────────────────────────
bold ""
bold "==> Step 3: Wait for all pods to be Ready"
kubectl wait pod \
  -l "app.kubernetes.io/instance=${RELEASE}" \
  --for=condition=Ready \
  --timeout="${TIMEOUT}" || {
    red "Pods did not become Ready within ${TIMEOUT} — collecting debug info..."
    kubectl get pods -l "app.kubernetes.io/instance=${RELEASE}" -o wide
    ERRORS=$((ERRORS + 1))
  }

# ── 4. Pod overview ───────────────────────────────────────────────────────────
bold ""
bold "==> Step 4: Pod overview"
kubectl get pods -l "app.kubernetes.io/instance=${RELEASE}" -o wide

# ── 5. Init container logs ────────────────────────────────────────────────────
bold ""
bold "==> Step 5: Init container logs"
WP_POD=$(kubectl get pod -l "app.kubernetes.io/instance=${RELEASE},app.kubernetes.io/name=wordpress" \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

if [[ -n "${WP_POD}" ]]; then
  # Enumerate init containers
  INIT_CONTAINERS=$(kubectl get pod "${WP_POD}" \
    -o jsonpath='{.spec.initContainers[*].name}' 2>/dev/null || true)
  for c in ${INIT_CONTAINERS}; do
    check_logs "init:${c}" "${WP_POD}" "-c ${c}"
  done

  # ── 6. Main container logs ──────────────────────────────────────────────────
  bold ""
  bold "==> Step 6: Main WordPress container logs"
  check_logs "wordpress" "${WP_POD}" "-c wordpress"

  # Apache metrics sidecar (if present)
  if kubectl get pod "${WP_POD}" -o jsonpath='{.spec.containers[*].name}' 2>/dev/null \
      | grep -q "apache-exporter"; then
    check_logs "apache-exporter" "${WP_POD}" "-c apache-exporter"
  fi
else
  red "Could not find wordpress pod — skipping log checks"
  ERRORS=$((ERRORS + 1))
fi

# ── 7. MariaDB logs ───────────────────────────────────────────────────────────
bold ""
bold "==> Step 7: MariaDB logs"
MARIADB_POD=$(kubectl get pod -l "app.kubernetes.io/instance=${RELEASE},app.kubernetes.io/name=mariadb" \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -n "${MARIADB_POD}" ]]; then
  check_logs "mariadb" "${MARIADB_POD}"
else
  echo "  No MariaDB pod found (external DB or not yet running)"
fi

# ── 8. Valkey logs ────────────────────────────────────────────────────────────
bold ""
bold "==> Step 8: Valkey logs"
VALKEY_POD=$(kubectl get pod -l "app.kubernetes.io/instance=${RELEASE},app.kubernetes.io/name=valkey" \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -n "${VALKEY_POD}" ]]; then
  check_logs "valkey" "${VALKEY_POD}"
else
  echo "  No Valkey pod found"
fi

# ── 9. HTTP smoke test ────────────────────────────────────────────────────────
bold ""
bold "==> Step 9: HTTP smoke test (NodePort 30911)"
WP_URL="http://192.168.178.21:30911"
# Retry up to 10 times to allow NodePort routing to stabilise after pod Ready
HTTP_CODE="000"
for i in $(seq 1 10); do
  HTTP_CODE=$(curl -o /dev/null -s -w "%{http_code}" --max-time 10 "${WP_URL}" || true)
  [[ "${HTTP_CODE}" =~ ^(200|301|302)$ ]] && break
  echo "  Attempt ${i}/10: HTTP ${HTTP_CODE} — retrying in 5s..."
  sleep 5
done
if [[ "${HTTP_CODE}" =~ ^(200|301|302)$ ]]; then
  green "  [OK] ${WP_URL} returned HTTP ${HTTP_CODE}"
else
  red "  [FAIL] ${WP_URL} returned HTTP ${HTTP_CODE} (expected 200/301/302)"
  ERRORS=$((ERRORS + 1))
fi

# ── 10. NetworkPolicy smoke test ──────────────────────────────────────────────
bold ""
bold "==> Step 10: NetworkPolicy smoke test"
NP_NAME="${RELEASE}"
NP_SELECTOR=$(kubectl get networkpolicy "${NP_NAME}" -n default \
  -o jsonpath='{.spec.podSelector.matchLabels}' 2>/dev/null || true)
if [[ -n "${NP_SELECTOR}" ]]; then
  green "  [OK] NetworkPolicy '${NP_NAME}' exists (podSelector: ${NP_SELECTOR})"
else
  red "  [FAIL] NetworkPolicy '${NP_NAME}' not found in default namespace"
  ERRORS=$((ERRORS + 1))
fi

# ── 11. Secondary Ingress smoke test ──────────────────────────────────────────
bold ""
bold "==> Step 11: Secondary Ingress smoke test"
INGRESS_COUNT=$(kubectl get ingress -n default \
  -l "app.kubernetes.io/instance=${RELEASE}" \
  --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ "${INGRESS_COUNT}" -ge 1 ]]; then
  green "  [OK] Found ${INGRESS_COUNT} Ingress object(s) for release '${RELEASE}'"
  kubectl get ingress -n default -l "app.kubernetes.io/instance=${RELEASE}" \
    --no-headers 2>/dev/null | awk '{print "    -", $1}'
else
  echo "  [SKIP] No Ingress controller in this environment — object-existence check only"
  # Check the secondary ingress object exists as a K8s resource
  SEC_INGRESS=$(kubectl get ingress "${RELEASE}-verify-secondary" -n default \
    --no-headers 2>/dev/null | wc -l | tr -d ' ')
  if [[ "${SEC_INGRESS}" -ge 1 ]]; then
    green "  [OK] Secondary Ingress object '${RELEASE}-verify-secondary' exists"
  else
    red "  [FAIL] Secondary Ingress object '${RELEASE}-verify-secondary' not found"
    ERRORS=$((ERRORS + 1))
  fi
fi

# ── 12. WordPress metrics endpoint ────────────────────────────────────────────
bold ""
bold "==> Step 12: WordPress metrics endpoint"
# Uses /slymetrics/metrics (Apache rewrite path served by the slymetrics plugin)
METRICS_CODE=$(curl -o /dev/null -s -w "%{http_code}" --max-time 10 \
  -H "Authorization: Bearer f5634d6a966856848e2f3f4a139e534b844805f7561d86642adb19060719e95d" \
  "${WP_URL}/slymetrics/metrics" || true)
if [[ "${METRICS_CODE}" =~ ^(200|401)$ ]]; then
  green "  [OK] Metrics endpoint reachable (HTTP ${METRICS_CODE})"
else
  red "  [WARN] Metrics endpoint returned HTTP ${METRICS_CODE}"
  ERRORS=$((ERRORS + 1))
fi

# ── 13. Backup CronJob smoke test ─────────────────────────────────────────────
bold ""
bold "==> Step 13: Backup CronJob smoke test"
CRONJOB_NAME="${RELEASE}-backup"
if kubectl get cronjob "${CRONJOB_NAME}" -n default --no-headers 2>/dev/null | grep -q "${CRONJOB_NAME}"; then
  green "  [OK] CronJob '${CRONJOB_NAME}' exists"
  # Check backup PVC
  PVC_NAME="${RELEASE}-backup"
  if kubectl get pvc "${PVC_NAME}" -n default --no-headers 2>/dev/null | grep -q "${PVC_NAME}"; then
    green "  [OK] Backup PVC '${PVC_NAME}' exists"
  else
    red "  [FAIL] Backup PVC '${PVC_NAME}' not found"
    ERRORS=$((ERRORS + 1))
  fi
else
  red "  [FAIL] CronJob '${CRONJOB_NAME}' not found"
  ERRORS=$((ERRORS + 1))
fi

# ── Result ────────────────────────────────────────────────────────────────────
echo ""
bold "============================================"
if [[ "${ERRORS}" -eq 0 ]]; then
  green "  ALL CHECKS PASSED"
else
  red "  ${ERRORS} CHECK(S) FAILED — review output above"
fi
bold "============================================"
exit "${ERRORS}"
