#!/usr/bin/env bash
# iOS Simulator tap helpers — simctl ui tap --label is unavailable on Xcode 16+;
# use Simulator window geometry (402×874 pt) or optional RAC_MCP_TAP_HTTP / mobile-mcp.
set -euo pipefail

_swift_sim_udid() {
  printf '%s' "${RAC_IOS_SIM_UDID:-booted}"
}

# Screen-space origin of the embedded device view (logical points width=402 height=874).
_swift_sim_device_origin() {
  local out
  out="$(osascript 2>/dev/null <<'APPLESCRIPT' || true
tell application "Simulator" to activate
delay 0.15
tell application "System Events"
  tell process "Simulator"
    set win to front window
    repeat with g in groups of win
      try
        set gs to size of g
        if (item 1 of gs) ≥ 400 and (item 2 of gs) ≥ 800 then
          set {gx, gy} to position of g
          return (gx as text) & "," & (gy as text)
        end if
      end try
    end repeat
    set {gx, gy} to position of win
    return (gx as text) & "," & (gy as text)
  end tell
end tell
APPLESCRIPT
)"
  [[ -n "${out}" ]] || return 1
  printf '%s' "${out}"
}

_swift_tap_xy_logical() {
  local lx="$1" ly="$2"
  local origin sx sy
  origin="$(_swift_sim_device_origin)" || return 1
  sx="${origin%%,*}"
  sy="${origin#*,}"
  osascript >/dev/null 2>&1 <<APPLESCRIPT || return 1
tell application "Simulator" to activate
delay 0.1
tell application "System Events"
  tell process "Simulator"
    click at {${sx} + ${lx}, ${sy} + ${ly}}
  end tell
end tell
APPLESCRIPT
  sleep 0.35
}

# Catalog labels → logical (x y) on iPhone Pro class 402×874 layout.
_swift_label_coords() {
  local label="$1"
  case "${label}" in
    Chat) printf '%s %s\n' 40 839 ;;
    Vision) printf '%s %s\n' 120 839 ;;
    Voice) printf '%s %s\n' 201 839 ;;
    More) printf '%s %s\n' 282 839 ;;
    Settings) printf '%s %s\n' 362 839 ;;
    Transcribe) printf '%s %s\n' 200 270 ;;
    Speak) printf '%s %s\n' 200 340 ;;
    "Document Q&A") printf '%s %s\n' 200 200 ;;
    Storage) printf '%s %s\n' 200 480 ;;
    "Voice Detection") printf '%s %s\n' 200 410 ;;
    "Get Started") printf '%s %s\n' 201 780 ;;
    "Select Model"|"Select STT Model"|"Change") printf '%s %s\n' 320 120 ;;
    Get|"71.5 MB"|"Get 71.5 MB") printf '%s %s\n' 340 300 ;;
    Use) printf '%s %s\n' 340 300 ;;
    "Sherpa Whisper Tiny"|"sherpa-onnx-whisper-tiny.en"|Whisper) printf '%s %s\n' 200 300 ;;
    Batch) printf '%s %s\n' 100 200 ;;
    Microphone) printf '%s %s\n' 201 650 ;;
    *) return 1 ;;
  esac
}

_swift_tap_raw() {
  local label="$1"
  if [[ -n "${RAC_MCP_TAP_HTTP:-}" ]]; then
    curl -fsS -X POST "${RAC_MCP_TAP_HTTP}" --data-urlencode "label=${label}" >/dev/null 2>&1 || true
    return 0
  fi
  local coords lx ly
  if coords="$(_swift_label_coords "${label}" 2>/dev/null)"; then
    read -r lx ly <<< "${coords}"
    _swift_tap_xy_logical "${lx}" "${ly}" && return 0
  fi
  # Last resort: center tap (better than silent no-op)
  _swift_tap_xy_logical 201 437 || true
}
