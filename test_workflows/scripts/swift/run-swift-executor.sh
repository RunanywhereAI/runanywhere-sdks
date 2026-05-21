#!/usr/bin/env bash
# Swift iOS lane executor — drives TC-02..TC-21 via the shared mobile harness.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=../_tc_helper.sh
source "${SCRIPT_DIR}/../_tc_helper.sh"
# shellcheck source=_swift_log_lib.sh
source "${SCRIPT_DIR}/_swift_log_lib.sh"

: "${RAC_RUN_ID:?RAC_RUN_ID required}"
export RAC_LANE_SLUG="02_swift_ios"
export RAC_IOS_SIM_UDID="${RAC_IOS_SIM_UDID:-booted}"
RAC_SESSION_ROOT="${REPO}/test_workflows/logs/runs/${RAC_RUN_ID}/lanes/${RAC_LANE_SLUG}"
export RAC_SESSION_ROOT
BUNDLE_ID="${BUNDLE_ID:-com.runanywhere.RunAnywhere}"

export RAC_TAB_CHAT="Chat"
export RAC_TAB_TRANSCRIBE="Transcribe"
export RAC_TAB_SPEAK="Speak"
export RAC_TAB_VISION="Vision"
export RAC_TAB_VOICE="Voice"
export RAC_TAB_DOCS="Docs"
export RAC_TAB_STORAGE="Storage"
export RAC_TAB_SETTINGS="Settings"

export RAC_MCP_SHOT_CMD='_swift_shot'
export RAC_MCP_TAP_CMD='_swift_tap'
export RAC_MCP_TYPE_CMD='_swift_type'
export RAC_MCP_GREP_CMD='_swift_grep'

_swift_shot() {
  local out="$1"
  xcrun simctl io "${RAC_IOS_SIM_UDID}" screenshot "${out}" >/dev/null 2>&1 || true
}

# Tap by accessibility label using xcrun simctl ui (Xcode 15+) — fallback to
# a Mobile-MCP HTTP call if RAC_MCP_TAP_HTTP is set by the operator.
_swift_tap() {
  local label="$1"
  if [[ -n "${RAC_MCP_TAP_HTTP:-}" ]]; then
    curl -fsS -X POST "${RAC_MCP_TAP_HTTP}" --data-urlencode "label=${label}" >/dev/null 2>&1 || true
    return 0
  fi
  xcrun simctl ui "${RAC_IOS_SIM_UDID}" tap --label "${label}" >/dev/null 2>&1 || true
}

_swift_type() {
  local text="$1"
  xcrun simctl io "${RAC_IOS_SIM_UDID}" send-text "${text}" >/dev/null 2>&1 || true
}

_swift_regrade_tc07() {
  local evidence status notes
  if ! evidence="$(_swift_tc07_evidence)"; then
    return 0
  fi
  _swift_tc07_status_from_evidence "${evidence}" | {
    IFS=$'\t' read -r status notes
    rac_tc_done tc07 "${status}" "${notes}" "screenshots/013_transcribe.png"
  }
}

rac_tc_init_lane
sleep 5
rac_mcp_shot "${RAC_SESSION_ROOT}/screenshots/000_after_launch.png"
if _swift_tc01_ready; then
  rac_tc_done tc01 PASS "SDK init or app-ready marker in sim logs" "screenshots/000_after_launch.png"
else
  rac_tc_done tc01 BLOCKED "no SDK init / app-ready marker in captured logs" "screenshots/000_after_launch.png"
fi

rac_tc_drive_catalog
_swift_regrade_tc07
echo "Swift iOS executor: catalog drive complete"
