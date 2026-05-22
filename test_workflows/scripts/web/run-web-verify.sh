#!/usr/bin/env bash
# Wraps the web E2E lane: init session, start Vite, run web-lane-e2e.mjs,
# finalize, analyze. Mirrors how Kotlin/Swift lanes drive their verify runs
# so the loop orchestrator has a single command per lane.
#
# Usage:
#   test_workflows/scripts/web/run-web-verify.sh <run-id> [notes]
#
# Env vars:
#   RA_BROWSER_CHANNEL    Default: chrome (use 'msedge', 'firefox', or empty for bundled chromium)
#   RA_HEADLESS           0|1 — default 0 (headed)
#   RAC_ALLOW_DIRTY       1 to skip git clean check
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/_session_lib.sh
source "${SCRIPT_DIR}/../lib/_session_lib.sh"

run_id="${1:?run-id required}"
notes="${2:-Web E2E iter5 (headed Chrome)}"

export RAC_RUN_ID="${run_id}"
export RA_BROWSER_CHANNEL="${RA_BROWSER_CHANNEL:-chrome}"
export RA_HEADLESS="${RA_HEADLESS:-0}"

repo="$(rac_repo_root)"
example="${repo}/examples/web/RunAnywhereAI"
lane_root="$(rac_session_root web "${run_id}")"

rac_session_init web "${run_id}" "" "${notes}"
mkdir -p "${lane_root}/logs"

vite_log="${lane_root}/logs/vite.log"
vite_pid="${lane_root}/logs/vite.pid"

cleanup() {
  if [[ -f "${vite_pid}" ]]; then
    kill "$(cat "${vite_pid}")" 2>/dev/null || true
    rm -f "${vite_pid}"
  fi
}
trap cleanup EXIT

(cd "${example}" && npm run dev -- --host 127.0.0.1 > "${vite_log}" 2>&1 &
  echo $! > "${vite_pid}")
echo "[web-verify] vite pid=$(cat "${vite_pid}") log=${vite_log}"

deadline=$(($(date +%s) + 120))
until curl -fsS "http://127.0.0.1:5173/" > /dev/null 2>&1; do
  if [[ $(date +%s) -gt "${deadline}" ]]; then
    echo "[web-verify] vite did not start within 120s — tail:" >&2
    tail -n 60 "${vite_log}" >&2
    exit 1
  fi
  sleep 2
done
echo "[web-verify] vite is up"

export WEB_LANE_ROOT="${lane_root}"
export RA_REPO_ROOT="${repo}"

executor_log="${lane_root}/executor.log"
echo "[web-verify] running web-lane-e2e.mjs (channel=${RA_BROWSER_CHANNEL} headless=${RA_HEADLESS})"
set +e
(cd "${repo}/sdk/runanywhere-web" && node scripts/web-lane-e2e.mjs) > "${executor_log}" 2>&1
rc=$?
set -e
echo "EXIT=${rc}" >> "${executor_log}"
echo "[web-verify] executor exit=${rc}"

set +e
(cd "${repo}/sdk/runanywhere-web" && WEB_LANE_ROOT="${lane_root}" node scripts/web-lane-finalize.mjs) >> "${executor_log}" 2>&1
set -e

"${SCRIPT_DIR}/../lane-finalize.sh" web "" 2>&1 | tail -3 || true
"${SCRIPT_DIR}/../run-lane-analyzer.sh" web --run-id "${run_id}" 2>&1 | tail -5 || true

exit "${rc}"
