#!/usr/bin/env bash
# React Native Android Mobile-MCP helpers — uiautomator tap by testID, label, or tab.
# Sourced by run-rn-android-executor.sh and _rn_tc_flows.sh validation harness.
set -euo pipefail

: "${RAC_ANDROID_SERIAL:?RAC_ANDROID_SERIAL required for _rn_android_lib.sh}"

PACKAGE_ID="${PACKAGE_ID:-com.runanywhereaI}"

# Canonical Validation harness action ids (README + ValidationHarnessScreen).
_RN_VALIDATION_ACTION_IDS=(
  structured.extract_fixture
  structured.generate_fixture
  tools.get_device_label
  vad.synthetic_silence
  vad.synthetic_tone
  lora.list
  lora.compatibility
  lora.apply_fixture
  lora.remove_fixture
  pluginloader.snapshot
  pluginloader.load_empty_error
)

_rn_android_adb() {
  adb -s "${RAC_ANDROID_SERIAL}" "$@"
}

_rn_android_pull_ui_xml() {
  local dest="$1"
  if ! _rn_android_adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1; then
    return 1
  fi
  _rn_android_adb pull /sdcard/ui.xml "${dest}" >/dev/null 2>&1
}

_rn_android_bounds_center_tap() {
  local bounds="$1"
  local x1 y1 x2 y2
  x1="$(echo "${bounds}" | sed -E 's/\[([0-9]+),([0-9]+)\].*/\1/')"
  y1="$(echo "${bounds}" | sed -E 's/\[([0-9]+),([0-9]+)\].*/\2/')"
  x2="$(echo "${bounds}" | sed -E 's/.*\[([0-9]+),([0-9]+)\]/\1/')"
  y2="$(echo "${bounds}" | sed -E 's/.*\[([0-9]+),([0-9]+)\]/\2/')"
  _rn_android_adb shell input tap $((x1 + (x2 - x1) / 2)) $((y1 + (y2 - y1) / 2)) >/dev/null 2>&1
  sleep 1
}

_rn_android_find_bounds() {
  local mode="$1"
  local needle="$2"
  local xml="$3"
  python3 - "${mode}" "${needle}" "${xml}" <<'PY'
import sys
import xml.etree.ElementTree as ET

mode, needle, xml_path = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    root = ET.parse(xml_path).getroot()
except ET.ParseError:
    raise SystemExit(1)

def enabled(node):
    return node.attrib.get("enabled", "true") != "false"

def bounds_of(node):
    b = node.attrib.get("bounds")
    return b if b else None

for node in root.iter("node"):
    rid = node.attrib.get("resource-id") or ""
    text = node.attrib.get("text") or ""
    desc = node.attrib.get("content-desc") or ""

    if mode == "testid":
        test_id = f"validation-action-{needle}"
        if test_id in rid or needle in rid:
            b = bounds_of(node)
            if b and enabled(node):
                print(b)
                break
    elif mode == "label":
        if needle == text or needle == desc or needle in text or needle in desc:
            b = bounds_of(node)
            if b and enabled(node):
                print(b)
                break
    elif mode == "screen":
        if needle in rid or needle in text or needle in desc:
            b = bounds_of(node)
            if b:
                print(b)
                break
else:
    raise SystemExit(1)
PY
}

_rn_android_tap_bounds_from_xml() {
  local mode="$1"
  local needle="$2"
  local tmp bounds
  tmp="$(mktemp)"
  if ! _rn_android_pull_ui_xml "${tmp}"; then
    rm -f "${tmp}"
    return 1
  fi
  bounds="$(_rn_android_find_bounds "${mode}" "${needle}" "${tmp}" 2>/dev/null || true)"
  rm -f "${tmp}"
  [[ -z "${bounds}" ]] && return 1
  _rn_android_bounds_center_tap "${bounds}"
  return 0
}

_rn_android_scroll_down() {
  _rn_android_adb shell input swipe 540 1800 540 600 400 >/dev/null 2>&1 || true
  sleep 1
}

_rn_android_scroll_tab_bar_left() {
  _rn_android_adb shell input swipe 900 2280 200 2280 300 >/dev/null 2>&1 || true
  sleep 1
}

_rn_android_tap_testid() {
  local action_id="$1"
  local test_id="validation-action-${action_id}"
  _rn_android_tap_bounds_from_xml testid "${action_id}" \
    || _rn_android_tap_bounds_from_xml screen "${test_id}" \
    || return 1
}

_rn_android_tap_label() {
  local label="$1"
  _rn_android_tap_bounds_from_xml label "${label}" || return 1
}

# Smart tap: validation action ids, testIDs, then accessibility labels.
_rn_android_tap() {
  local target="$1"
  local attempt scroll

  if [[ "${target}" == validation-action-* ]]; then
    _rn_android_tap_testid "${target#validation-action-}" && return 0
  fi
  if [[ "${target}" == *.* ]]; then
    for attempt in 1 2 3; do
      _rn_android_tap_testid "${target}" && return 0
      _rn_android_scroll_down
    done
  fi

  for attempt in 1 2 3; do
    _rn_android_tap_label "${target}" && return 0
    _rn_android_scroll_down
  done
  return 1
}

_rn_android_tap_validation_action() {
  local action_id="$1"
  local title=""
  case "${action_id}" in
    structured.extract_fixture) title="Structured Parse" ;;
    structured.generate_fixture) title="Structured Generate" ;;
    tools.get_device_label) title="Tool Call" ;;
    vad.synthetic_silence) title="VAD Silence" ;;
    vad.synthetic_tone) title="VAD Tone" ;;
    lora.list) title="LoRA List" ;;
    lora.compatibility) title="LoRA Compatibility" ;;
    lora.apply_fixture) title="LoRA Apply" ;;
    lora.remove_fixture) title="LoRA Remove" ;;
    pluginloader.snapshot) title="Plugin Snapshot" ;;
    pluginloader.load_empty_error) title="Plugin Error" ;;
  esac

  local scroll
  for scroll in 1 2 3 4; do
    _rn_android_tap_testid "${action_id}" && return 0
    [[ -n "${title}" ]] && _rn_android_tap_label "${title}" && return 0
    _rn_android_scroll_down
  done
  return 1
}

_rn_android_tap_validation_tab() {
  local attempt
  for attempt in 1 2 3; do
    _rn_android_tap_label "Validation" && return 0
    _rn_android_scroll_tab_bar_left
  done
  _rn_android_tap "Validation" || return 1
}

_rn_android_wait_vad_ready() {
  local timeout="${1:-300}"
  local elapsed=0
  local tmp
  while [[ "${elapsed}" -lt "${timeout}" ]]; do
    if _rn_grep_logs "VAD ready" || _rn_grep_logs "silero-vad"; then
      return 0
    fi
    tmp="$(mktemp)"
    if _rn_android_pull_ui_xml "${tmp}"; then
      if grep -q "VAD ready" "${tmp}" 2>/dev/null; then
        rm -f "${tmp}"
        return 0
      fi
      if grep -q "VAD load failed" "${tmp}" 2>/dev/null; then
        rm -f "${tmp}"
        return 1
      fi
    fi
    rm -f "${tmp}"
    sleep 5
    elapsed=$((elapsed + 5))
  done
  return 1
}

_rn_android_sync_rnjs_logs() {
  local lane_root="${RAC_SESSION_ROOT:?}/logs"
  mkdir -p "${lane_root}"
  _rn_android_adb logcat -d 2>/dev/null | grep ReactNativeJS >> "${lane_root}/metro_rnjs.log" || true
}

_rn_android_grep_validation_marker() {
  local action_id="${1:-}"
  local lane_root="${RAC_SESSION_ROOT:?}/logs"
  _rn_android_sync_rnjs_logs
  local f
  for f in \
    "${lane_root}/metro.log" \
    "${lane_root}/metro_rnjs.log" \
    "${lane_root}/logcat_runanywhere_filtered.log" \
    "${lane_root}/android_logcat.log"; do
    [[ -f "${f}" ]] || continue
    if [[ -n "${action_id}" ]]; then
      grep -F "[RN_VALIDATION_ACTION]" "${f}" 2>/dev/null | grep -F "${action_id}" | grep -qE '"status":"PASS"|"status":"EXPECTED_ERROR"' && return 0
    else
      grep -F "[RN_VALIDATION_ACTION]" "${f}" 2>/dev/null | grep -q . && return 0
    fi
  done
  return 1
}

_rn_android_validation_marker_count() {
  local lane_root="${RAC_SESSION_ROOT:?}/logs"
  _rn_android_sync_rnjs_logs
  local total=0 f n
  for f in \
    "${lane_root}/metro.log" \
    "${lane_root}/metro_rnjs.log" \
    "${lane_root}/logcat_runanywhere_filtered.log"; do
    [[ -f "${f}" ]] || continue
    n="$(grep -F "[RN_VALIDATION_ACTION]" "${f}" 2>/dev/null | wc -l | tr -d ' ')"
    total=$((total + n))
  done
  printf '%s' "${total}"
}

_rn_android_shot() {
  local out="$1"
  _rn_android_adb exec-out screencap -p > "${out}" 2>/dev/null || true
}

_rn_android_type() {
  local text="$1"
  _rn_android_adb shell input text "${text// /%s}" >/dev/null 2>&1 || true
}

_rn_android_grep() {
  local pattern="$1"
  _rn_grep_logs "${pattern}" && return 0
  local pid
  pid="$(_rn_android_adb shell pidof "${PACKAGE_ID}" 2>/dev/null | tr -d '\r' | awk '{print $1}')"
  if [[ -n "${pid}" ]]; then
    _rn_android_adb logcat -d --pid="${pid}" 2>/dev/null | grep -F "${pattern}" >/dev/null 2>&1
  else
    _rn_android_adb logcat -d 2>/dev/null | grep -F "${pattern}" >/dev/null 2>&1
  fi
}
