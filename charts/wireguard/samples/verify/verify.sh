#!/usr/bin/env bash
# Full verification run: install → wait → check logs → check WireGuard interface → report.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE="wireguard-verify"
NAMESPACE="wireguard-verify"
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
  -l "app.kubernetes.io/instance=${RELEASE},app.kubernetes.io/name=wireguard" \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

# ── 4. Container logs ─────────────────────────────────────────────────────────
bold ""
bold "==> Step 4: WireGuard container logs"
if [[ -n "${WG_POD}" ]]; then
  check_logs "wireguard" "${WG_POD}"
else
  red "Could not find wireguard pod — skipping log and interface checks"
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

# ── 6. wg show: listening port and peers ──────────────────────────────────────
bold ""
bold "==> Step 6: wg show (listening port and peers)"
EXPECTED_PORT="51820"
EXPECTED_PEERS=2
if [[ -n "${WG_POD}" ]]; then
  WG_SHOW=$(kubectl -n "${NAMESPACE}" exec "${WG_POD}" -- sh -c "wg show" 2>/dev/null || true)
  echo "${WG_SHOW}"
  ACTUAL_PORT=$(echo "${WG_SHOW}" | awk -F': ' '/listening port/ {print $2}')
  ACTUAL_PEERS=$(echo "${WG_SHOW}" | grep -c "^peer:" || true)
  if [[ "${ACTUAL_PORT}" == "${EXPECTED_PORT}" ]]; then
    green "  [OK] wg0 listening port is ${ACTUAL_PORT} (expected ${EXPECTED_PORT})"
  else
    red "  [FAIL] wg0 listening port is '${ACTUAL_PORT}' (expected ${EXPECTED_PORT})"
    ERRORS=$((ERRORS + 1))
  fi
  if [[ "${ACTUAL_PEERS}" -eq "${EXPECTED_PEERS}" ]]; then
    green "  [OK] ${ACTUAL_PEERS} peer(s) configured (expected ${EXPECTED_PEERS})"
  else
    red "  [FAIL] ${ACTUAL_PEERS} peer(s) configured (expected ${EXPECTED_PEERS})"
    ERRORS=$((ERRORS + 1))
  fi
fi

# ── 7. Service / NodePort smoke test ──────────────────────────────────────────
bold ""
bold "==> Step 7: Service smoke test"
SVC_PORTS=$(kubectl -n "${NAMESPACE}" get svc "${RELEASE}" -o jsonpath='{.spec.ports[0].port}:{.spec.ports[0].nodePort}/{.spec.ports[0].protocol}' 2>/dev/null || true)
if [[ "${SVC_PORTS}" == "51820:31920/UDP" ]]; then
  green "  [OK] Service '${RELEASE}' exposes ${SVC_PORTS}"
else
  red "  [FAIL] Service '${RELEASE}' exposes '${SVC_PORTS}' (expected 51820:31920/UDP)"
  ERRORS=$((ERRORS + 1))
fi

if [[ -n "${WG_POD}" ]]; then
  if kubectl -n "${NAMESPACE}" exec "${WG_POD}" -- sh -c "ss -lnup 2>/dev/null | grep -q ':51820 '"; then
    green "  [OK] wg0 is listening on UDP/51820 inside the pod"
  else
    red "  [FAIL] No UDP listener on port 51820 inside the pod"
    ERRORS=$((ERRORS + 1))
  fi
fi

# ── 8. NetworkPolicy smoke test ───────────────────────────────────────────────
bold ""
bold "==> Step 8: NetworkPolicy smoke test"
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
