#!/usr/bin/env bash
# Full verification run: install → wait → check logs → check WireGuard interface → report.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE="wg-easy-verify"
NAMESPACE="wg-easy-verify"
TIMEOUT="${VERIFY_TIMEOUT:-300s}"
ERRORS=0

red()   { echo -e "\033[0;31m$*\033[0m"; }
green() { echo -e "\033[0;32m$*\033[0m"; }
yellow() { echo -e "\033[0;33m$*\033[0m"; }
bold()  { echo -e "\033[1m$*\033[0m"; }

check_logs() {
  local label="$1"; local pod="$2"; local container_flag="${3:-}"
  echo ""
  bold "--- Logs: ${label} ---"
  # shellcheck disable=SC2086
  kubectl -n "${NAMESPACE}" logs "${pod}" ${container_flag} --tail=100 2>&1 | tee /tmp/verify_logs_tmp.txt
  if grep -qiE "(error|fatal|panic|exception|failed|crash)" /tmp/verify_logs_tmp.txt 2>/dev/null; then
    red "  [WARN] Suspicious keywords found in ${label} logs (see above)"
    ERRORS=$((ERRORS + 1))
  else
    green "  [OK] No errors detected in ${label} logs"
  fi
}

# ── 1. Install ────────────────────────────────────────────────────────────────
bold "==> Step 1: Install"
bash "${SCRIPT_DIR}/install.sh"

# ── 2. Wait for pod ready ─────────────────────────────────────────────────────
bold ""
bold "==> Step 2: Wait for all pods to be Ready (timeout: ${TIMEOUT})"
kubectl -n "${NAMESPACE}" wait pod \
  -l "app.kubernetes.io/instance=${RELEASE}" \
  --for=condition=Ready \
  --timeout="${TIMEOUT}" || {
    red "Pods did not become Ready within ${TIMEOUT} — collecting debug info..."
    kubectl -n "${NAMESPACE}" get pods -l "app.kubernetes.io/instance=${RELEASE}" -o wide
    ERRORS=$((ERRORS + 1))
  }

# ── 3. Pod overview ────────────────────────────────────────────────────────────
bold ""
bold "==> Step 3: Pod overview"
kubectl -n "${NAMESPACE}" get pods -l "app.kubernetes.io/instance=${RELEASE}" -o wide

WG_POD=$(kubectl -n "${NAMESPACE}" get pod \
  -l "app.kubernetes.io/instance=${RELEASE},app.kubernetes.io/name=wg-easy" \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

# ── 4. Container logs ─────────────────────────────────────────────────────────
bold ""
bold "==> Step 4: wg-easy container logs"
if [[ -n "${WG_POD}" ]]; then
  check_logs "wg-easy" "${WG_POD}"
else
  red "Could not find wg-easy pod — skipping log and interface checks"
  ERRORS=$((ERRORS + 1))
fi

# ── 5. wg0 interface up ───────────────────────────────────────────────────────
bold ""
bold "==> Step 5: wg0 interface state"
if [[ -n "${WG_POD}" ]]; then
  if kubectl -n "${NAMESPACE}" exec "${WG_POD}" -- sh -c "ip link show dev wg0 | grep -s up" >/dev/null 2>&1; then
    green "  [OK] wg0 interface is up"
  else
    red "  [FAIL] wg0 interface is not up"
    ERRORS=$((ERRORS + 1))
  fi
fi

# ── 6. Web UI smoke test ──────────────────────────────────────────────────────
bold ""
bold "==> Step 6: Web UI smoke test (NodePort 30921)"
UI_URL="http://192.168.178.21:30921"
HTTP_CODE="000"
for i in $(seq 1 10); do
  HTTP_CODE=$(curl -o /dev/null -s -w "%{http_code}" --max-time 10 "${UI_URL}" || true)
  [[ "${HTTP_CODE}" =~ ^(200|301|302)$ ]] && break
  echo "  Attempt ${i}/10: HTTP ${HTTP_CODE} — retrying in 5s..."
  sleep 5
done
if [[ "${HTTP_CODE}" =~ ^(200|301|302)$ ]]; then
  green "  [OK] ${UI_URL} returned HTTP ${HTTP_CODE}"
else
  red "  [FAIL] ${UI_URL} returned HTTP ${HTTP_CODE} (expected 200/301/302)"
  ERRORS=$((ERRORS + 1))
fi

# ── 7. Service smoke test ─────────────────────────────────────────────────────
bold ""
bold "==> Step 7: Service smoke test"
UI_SVC_PORTS=$(kubectl -n "${NAMESPACE}" get svc "${RELEASE}-ui" -o jsonpath='{.spec.ports[0].port}:{.spec.ports[0].nodePort}/{.spec.ports[0].protocol}' 2>/dev/null || true)
if [[ "${UI_SVC_PORTS}" == "51821:30921/TCP" ]]; then
  green "  [OK] Service '${RELEASE}-ui' exposes ${UI_SVC_PORTS}"
else
  red "  [FAIL] Service '${RELEASE}-ui' exposes '${UI_SVC_PORTS}' (expected 51821:30921/TCP)"
  ERRORS=$((ERRORS + 1))
fi

WG_SVC_PORTS=$(kubectl -n "${NAMESPACE}" get svc "${RELEASE}-wireguard" -o jsonpath='{.spec.ports[0].port}:{.spec.ports[0].nodePort}/{.spec.ports[0].protocol}' 2>/dev/null || true)
if [[ "${WG_SVC_PORTS}" == "51820:30920/UDP" ]]; then
  green "  [OK] Service '${RELEASE}-wireguard' exposes ${WG_SVC_PORTS}"
else
  red "  [FAIL] Service '${RELEASE}-wireguard' exposes '${WG_SVC_PORTS}' (expected 51820:30920/UDP)"
  ERRORS=$((ERRORS + 1))
fi

# ── 8. ServiceMonitor smoke test ──────────────────────────────────────────────
bold ""
bold "==> Step 8: ServiceMonitor smoke test"
SM_SELECTOR=$(kubectl -n "${NAMESPACE}" get servicemonitor "${RELEASE}" \
  -o jsonpath='{.spec.selector}' 2>/dev/null || true)
if [[ -n "${SM_SELECTOR}" ]]; then
  green "  [OK] ServiceMonitor '${RELEASE}' exists (selector: ${SM_SELECTOR})"
else
  yellow "  [SKIP] ServiceMonitor not enabled in this values set — nothing to verify"
fi

# ── 9. NetworkPolicy smoke test ───────────────────────────────────────────────
bold ""
bold "==> Step 9: NetworkPolicy smoke test"
NP_SELECTOR=$(kubectl -n "${NAMESPACE}" get networkpolicy "${RELEASE}" \
  -o jsonpath='{.spec.podSelector.matchLabels}' 2>/dev/null || true)
if [[ -n "${NP_SELECTOR}" ]]; then
  green "  [OK] NetworkPolicy '${RELEASE}' exists (podSelector: ${NP_SELECTOR})"
else
  yellow "  [SKIP] NetworkPolicy not enabled in this values set — nothing to verify"
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
