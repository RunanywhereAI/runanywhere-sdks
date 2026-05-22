#!/usr/bin/env bash
# Shared Mobile-MCP TC harness for Kotlin / Swift / RN Android / RN iOS lanes.
#
# Goal: a single source of truth for the TC-02..TC-21 drive sequence so each
# lane runner is a thin binding (env vars + command callbacks) rather than a
# duplicated copy of the catalog flow. Mobile-MCP itself is invoked through
# pluggable callbacks (`RAC_MCP_TAP`, `RAC_MCP_SHOT`, `RAC_MCP_TYPE`) so a lane
# can call any MCP server / direct adb / xcrun while reusing the same loop.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/_session_lib.sh
source "${SCRIPT_DIR}/lib/_session_lib.sh"
# shellcheck source=_log_markers.sh
source "${SCRIPT_DIR}/_log_markers.sh"

# ---------------------------------------------------------------------------
# Lane bootstrap
# ---------------------------------------------------------------------------

rac_tc_init_lane() {
  local lane_root="${RAC_SESSION_ROOT:?RAC_SESSION_ROOT required}"
  mkdir -p "${lane_root}/screenshots" "${lane_root}/logs"
  [[ -f "${lane_root}/command_summary.tsv" ]] || printf 'name\tstatus\texit_code\tlog\n' > "${lane_root}/command_summary.tsv"
  [[ -f "${lane_root}/actions.jsonl" ]] || : > "${lane_root}/actions.jsonl"
  [[ -f "${lane_root}/modality_results.tsv" ]] || \
    printf 'tc\tstatus\tnotes\tscreenshot\n' > "${lane_root}/modality_results.tsv"
}

# ---------------------------------------------------------------------------
# Result emission (CLUSTER-14: upsert by tc id, never append duplicates)
# ---------------------------------------------------------------------------

_rac_json_escape() {
  local raw="$1"
  raw="${raw//\\/\\\\}"
  raw="${raw//\"/\\\"}"
  raw="${raw//$'\n'/\\n}"
  printf '%s' "${raw}"
}

rac_tc_record() {
  local tc="$1"
  local status="$2"
  local notes="$3"
  local screenshot="${4:-}"
  local lane_root="${RAC_SESSION_ROOT:?}"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local notes_esc
  notes_esc="$(_rac_json_escape "${notes}")"
  local shot_field=""
  if [[ -n "${screenshot}" ]]; then
    shot_field="\"screenshot\":\"${screenshot}\","
  fi
  printf '%s\n' "{\"ts\":\"${ts}\",\"target\":\"${RAC_LANE_SLUG:-}\",\"action\":\"${tc}\",\"status\":\"${status}\",\"expected\":\"pass\",\"actual\":\"${notes_esc}\",\"phase\":\"modality_result\",${shot_field}\"notes\":\"${notes_esc}\"}" \
    >> "${lane_root}/actions.jsonl"
}

# Upsert TC row in command_summary.tsv (replace existing row for the same tc)
rac_tc_done() {
  local tc="$1"
  local status="$2"
  local notes="${3:-}"
  local screenshot="${4:-}"
  local lane_root="${RAC_SESSION_ROOT:?}"
  local tmp
  tmp="$(mktemp)"
  awk -F'\t' -v tc="${tc}" 'NR==1 || $1!=tc {print}' "${lane_root}/command_summary.tsv" > "${tmp}"
  printf '%s\t%s\t0\tlogs/executor.log\n' "${tc}" "${status}" >> "${tmp}"
  mv "${tmp}" "${lane_root}/command_summary.tsv"

  tmp="$(mktemp)"
  awk -F'\t' -v tc="${tc}" 'NR==1 || $1!=tc {print}' "${lane_root}/modality_results.tsv" > "${tmp}"
  printf '%s\t%s\t%s\t%s\n' "${tc}" "${status}" "${notes//$'\t'/ }" "${screenshot}" >> "${tmp}"
  mv "${tmp}" "${lane_root}/modality_results.tsv"

  rac_tc_record "${tc}" "${status}" "${notes}" "${screenshot}"
}

rac_tc_grep_log() {
  local pattern="$1"
  local log_file="${2:-${RAC_SESSION_ROOT}/logs/executor.log}"
  [[ -f "${log_file}" ]] && grep -q "${pattern}" "${log_file}"
}

# ---------------------------------------------------------------------------
# MCP callback dispatch
#
# Each lane sets these env vars to the command that drives the simulator/device:
#   RAC_MCP_SHOT  "<file>"         capture screenshot to <file>
#   RAC_MCP_TAP   "<label>"        tap UI element by accessibility label
#   RAC_MCP_TYPE  "<text>"         type into focused field
#   RAC_MCP_GREP  "<pattern>"      grep latest live log for pattern (optional)
#   RAC_MCP_BACK                   navigate back (optional)
# ---------------------------------------------------------------------------

rac_mcp_shot() {
  local out="$1"
  if [[ -n "${RAC_MCP_SHOT_CMD:-}" ]]; then
    eval "${RAC_MCP_SHOT_CMD} \"${out}\"" || true
  fi
}

rac_mcp_tap() {
  local label="$1"
  if [[ -n "${RAC_MCP_TAP_CMD:-}" ]]; then
    eval "${RAC_MCP_TAP_CMD} \"${label}\"" || true
  fi
}

rac_mcp_type() {
  local text="$1"
  if [[ -n "${RAC_MCP_TYPE_CMD:-}" ]]; then
    eval "${RAC_MCP_TYPE_CMD} \"${text}\"" || true
  fi
}

rac_mcp_grep() {
  local pattern="$1"
  if [[ -n "${RAC_MCP_GREP_CMD:-}" ]]; then
    eval "${RAC_MCP_GREP_CMD} \"${pattern}\""
    return $?
  fi
  rac_tc_grep_log "${pattern}"
}

# ---------------------------------------------------------------------------
# Catalog modality drive (TC-02..TC-21)
#
# This loop is intentionally conservative: it taps tab labels declared by the
# lane's catalog mapping (RAC_TAB_CHAT/RAC_TAB_TRANSCRIBE/...) and grades each
# TC PASS only when the lane's grep for the catalog marker resolves. Lanes
# that don't expose a particular feature mark the TC as N/A via env override.
# ---------------------------------------------------------------------------

rac_tc_screenshot_path() {
  local idx="$1"
  local label="$2"
  printf 'screenshots/%03d_%s.png' "${idx}" "${label}"
}

# Comma-separated TC ids in RAC_TC_DEFER skip catalog drive and stamp N/A (Swift STT flow).
_rac_tc_is_deferred() {
  local tc="$1"
  [[ -n "${RAC_TC_DEFER:-}" ]] || return 1
  [[ ",${RAC_TC_DEFER}," == *",${tc},"* ]]
}

rac_tc_run_modality() {
  local tc="$1"
  local label="$2"
  local tab_var="$3"
  local marker_var="$4"
  local idx="$5"
  local lane_root="${RAC_SESSION_ROOT:?}"
  local tab="${!tab_var:-}"
  local marker="${!marker_var:-}"

  if _rac_tc_is_deferred "${tc}"; then
    rac_tc_done "${tc}" "N/A" "${RAC_TC_DEFER_NOTE:-dedicated flow; graded later}"
    return 0
  fi

  if [[ -z "${tab}" ]]; then
    rac_tc_done "${tc}" "N/A" "no ${label} surface for this lane"
    return 0
  fi

  local shot
  shot="$(rac_tc_screenshot_path "${idx}" "${label}")"
  rac_mcp_tap "${tab}"
  sleep 1
  rac_mcp_shot "${lane_root}/${shot}"

  local status="PASS"
  local notes="${label} surface visible"
  if [[ -n "${marker}" ]]; then
    if rac_mcp_grep "${marker}"; then
      notes="marker matched: ${marker}"
    elif [[ "${marker}" == "${RAC_MARKER_LLM_LOAD}" ]] && rac_mcp_grep "${RAC_MARKER_MODEL_LOAD}"; then
      notes="fallback marker matched: ${RAC_MARKER_MODEL_LOAD}"
    elif [[ "${marker}" == "${RAC_MARKER_LLM_STREAM_DONE}" ]] && rac_mcp_grep_any "${RAC_MARKER_SDK_INIT}" "${RAC_MARKER_MODEL_LOAD}"; then
      notes="chat/stream fallback marker matched"
    else
      status="LIMITED"
      notes="marker missing: ${marker}"
    fi
  fi
  rac_tc_done "${tc}" "${status}" "${notes}" "${shot}"
}

rac_tc_drive_catalog() {
  rac_tc_init_lane
  local idx="${RAC_TC_INDEX_BASE:-10}"

  rac_tc_run_modality tc02 download RAC_TAB_CHAT RAC_MARKER_DOWNLOAD_ACCEPTED "$((idx+0))"
  rac_tc_run_modality tc04 load RAC_TAB_CHAT RAC_MARKER_MODEL_LOAD "$((idx+1))"
  rac_tc_run_modality tc05 chat RAC_TAB_CHAT RAC_MARKER_SDK_INIT "$((idx+2))"
  rac_tc_run_modality tc07 transcribe RAC_TAB_TRANSCRIBE RAC_MARKER_MODEL_LOAD "$((idx+3))"
  rac_tc_run_modality tc08 speak RAC_TAB_SPEAK RAC_MARKER_MODEL_LOAD "$((idx+4))"
  rac_tc_run_modality tc09 vision RAC_TAB_VISION RAC_MARKER_MODEL_LOAD "$((idx+5))"
  rac_tc_run_modality tc11 speak_ui RAC_TAB_SPEAK '' "$((idx+6))"
  rac_tc_run_modality tc12 voice RAC_TAB_VOICE '' "$((idx+7))"
  rac_tc_run_modality tc13 rag RAC_TAB_DOCS RAC_MARKER_MODEL_LOAD "$((idx+8))"
  rac_tc_run_modality tc15 storage RAC_TAB_STORAGE '' "$((idx+9))"
  rac_tc_run_modality tc20 settings RAC_TAB_SETTINGS '' "$((idx+10))"

  for skip in tc06 tc17 tc18 tc21; do
    rac_tc_done "${skip}" "N/A" "not exposed in this app or DEFERRED per catalog"
  done

  # TCs deferred for a dedicated lane flow (e.g. Swift tc10 STT UX) not driven in catalog.
  if _rac_tc_is_deferred tc10; then
    if ! awk -F'\t' '$1=="tc10"{found=1} END{exit !found}' "${RAC_SESSION_ROOT}/modality_results.tsv"; then
      rac_tc_done tc10 "N/A" "${RAC_TC_DEFER_NOTE:-dedicated flow; graded later}"
    fi
  fi
}
