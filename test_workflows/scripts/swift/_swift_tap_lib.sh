#!/usr/bin/env bash
# iOS Simulator tap helpers — simctl ui tap --label is unavailable on Xcode 16+.

_swift_sim_udid() {
  printf '%s' "${RAC_IOS_SIM_UDID:-booted}"
}

_swift_sim_uuid() {
  local udid="$(_swift_sim_udid)"
  if [[ "${udid}" == "booted" ]]; then
    udid="$(xcrun simctl list devices booted 2>/dev/null | rg -o '[0-9A-F-]{36}' | head -1)"
  fi
  [[ -n "${udid}" ]] || return 1
  printf '%s' "${udid}"
}

_swift_dismiss_system_dialogs() {
  _swift_tap_raw "Open" || _swift_tap_raw "Allow" || _swift_tap_raw "OK" || true
  sleep 0.5
}

_swift_launch_app() {
  local bundle="${BUNDLE_ID:-com.runanywhere.RunAnywhere}"
  open -a Simulator >/dev/null 2>&1 || true
  osascript >/dev/null 2>&1 <<'APPLESCRIPT' || true
tell application "Simulator" to activate
APPLESCRIPT
  xcrun simctl launch "$(_swift_sim_udid)" "${bundle}" >/dev/null 2>&1 || true
  sleep 2
  _swift_dismiss_system_dialogs
  _swift_tap_raw "RunAnywhere" || _swift_tap_xy_logical 154 335 || true
  sleep 1
  _swift_dismiss_system_dialogs
  sleep 1
}

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
  local origin sx sy mobilecli="${RAC_MOBILECLI:-}"
  if [[ -z "${mobilecli}" ]]; then
    mobilecli="$(ls "${HOME}"/.npm/_npx/*/node_modules/mobilecli/bin/mobilecli-darwin-arm64 2>/dev/null | head -1 || true)"
  fi
  if [[ -x "${mobilecli}" ]]; then
    "${mobilecli}" io tap --device "$(_swift_sim_uuid)" "${lx},${ly}" >/dev/null 2>&1 && {
      sleep 0.35
      return 0
    }
  fi
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
    Open|Allow|OK) printf '%s %s\n' 275 474 ;;
    Benchmarks) printf '%s %s\n' 200 620 ;;
    "Run All Benchmarks") printf '%s %s\n' 201 340 ;;
    All) printf '%s %s\n' 360 480 ;;
    RunAnywhere) printf '%s %s\n' 154 335 ;;
    SmolLM2|SmolLM|"SmolLM2 360M") printf '%s %s\n' 200 260 ;;
    "Vision Chat") printf '%s %s
' 200 220 ;;
    Photos) printf '%s %s
' 120 720 ;;
    "SmolVLM 500M Instruct"|SmolVLM) printf '%s %s
' 200 280 ;;
    Piper|"Piper TTS (US English - Medium)"|"US English") printf '%s %s
' 200 300 ;;
    "Embedding Model") printf '%s %s
' 200 200 ;;
    "All MiniLM"|"All MiniLM L6 v2 (Embedding)") printf '%s %s
' 200 300 ;;
    "LLM Model") printf '%s %s
' 200 260 ;;
    "Select Document") printf '%s %s
' 201 400 ;;
    Downloads) printf '%s %s
' 200 320 ;;
    rag-sample.json) printf '%s %s
' 200 350 ;;
    Back) printf '%s %s
' 30 60 ;;
    Batch) printf '%s %s\n' 100 200 ;;
    Microphone) printf '%s %s\n' 201 650 ;;
    *) return 1 ;;
  esac
}

_swift_scroll_settings_down() {
  local i
  for i in 1 2 3; do
    _swift_tap_xy_logical 201 650 || true
    _swift_tap_xy_logical 201 350 || true
    sleep 0.4
  done
}

_swift_tap_ax_name() {
  local name="$1"
  osascript >/dev/null 2>&1 <<APPLESCRIPT || return 1
tell application "Simulator" to activate
delay 0.15
tell application "System Events"
  tell process "Simulator"
    set frontmost to true
    set w to front window
    try
      click (first button of w whose name is "$name")
    on error
      try
        click (first UI element of w whose name is "$name")
      end try
    end try
  end tell
end tell
APPLESCRIPT
  sleep 0.35
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
  _swift_tap_ax_name "${label}" || true
  _swift_tap_xy_logical 201 437 || true
  return 0
}
