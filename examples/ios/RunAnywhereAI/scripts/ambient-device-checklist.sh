#!/usr/bin/env bash
# Notes — physical-device validation harness.
#
# The risky behavior is all things a simulator cannot reproduce: a locked
# screen, a real phone call, a Bluetooth route change, thermal throttling, and
# multi-hour battery drain. This script does the parts a machine can do
# (install, launch, log capture, per-run artifacts) and prints the manual steps
# in order so a run is reproducible and comparable to the last one.
#
# Usage:
#   scripts/ambient-device-checklist.sh list
#   scripts/ambient-device-checklist.sh install <device-udid>
#   scripts/ambient-device-checklist.sh logs <device-udid> [minutes]
#   scripts/ambient-device-checklist.sh checklist
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUNDLE_ID="${AMBIENT_BUNDLE_ID:-com.runanywhere.RunAnywhere}"
RESULTS_DIR="${APP_ROOT}/.ambient-runs"

log() {
    printf '\n==> %s\n' "$*"
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "error: required command not found: $1" >&2
        exit 1
    fi
}

cmd_list() {
    require_command xcrun
    log "Connected devices"
    xcrun devicectl list devices
}

cmd_install() {
    local udid="${1:?usage: install <device-udid>}"
    require_command xcodebuild
    require_command xcrun

    log "Building for the device"
    xcodebuild \
        -project "${APP_ROOT}/RunAnywhereAI.xcodeproj" \
        -scheme RunAnywhereAI \
        -configuration Debug \
        -destination "id=${udid}" \
        -skipPackagePluginValidation \
        -derivedDataPath "${APP_ROOT}/.build-device" \
        build

    local app_path
    app_path="$(find "${APP_ROOT}/.build-device/Build/Products" -maxdepth 3 -name 'RunAnywhereAI.app' | head -1)"
    if [ -z "${app_path}" ]; then
        echo "error: could not locate the built RunAnywhereAI.app" >&2
        exit 1
    fi

    log "Installing ${app_path}"
    xcrun devicectl device install app --device "${udid}" "${app_path}"

    cat <<'NOTE'

Installed. Before the first run, on the device:
  1. Open Advanced > Notes. Under Models, Change each role, Get, then Use —
     pick any catalog models (including MLX) to stress-test. No defaults are
     pre-selected. Developer profiles only copy candidate IDs if you apply one.
  2. Grant microphone access and allow Live Activities for RunAnywhere.
  3. Settings > Action Button > Shortcut > "Start Memory Lab" (iPhone 15 Pro and later).
NOTE
}

cmd_logs() {
    local udid="${1:?usage: logs <device-udid> [minutes]}"
    local minutes="${2:-60}"
    require_command xcrun
    mkdir -p "${RESULTS_DIR}"

    local out="${RESULTS_DIR}/ambient-$(date +%Y%m%d-%H%M%S).log"
    log "Streaming AmbientSession / AmbientMemory logs for ${minutes} minutes to ${out}"
    xcrun devicectl device console \
        --device "${udid}" \
        > "${out}" 2>&1 &
    local pid=$!
    trap 'kill "${pid}" 2>/dev/null || true' EXIT
    sleep $(( minutes * 60 ))
    kill "${pid}" 2>/dev/null || true
    trap - EXIT

    log "Saved ${out}"
    echo "Export the in-app benchmark CSV (Notes > Developer > Benchmark samples > Export CSV) into the same folder."
}

cmd_checklist() {
    cat <<'CHECKLIST'

Notes — manual device checklist
==============================
Record the result of every line. A run is only comparable to another run when
the environment and placement labels were set under Developer before starting.

Models (from Notes, without visiting the Models tab)
  [ ] Slots start empty (None). Record is disabled until VAD + ASR are Ready.
  [ ] Change Speech detector → Get → Use any VAD; row shows Ready.
  [ ] Change Transcription → Get → Use any STT (try an MLX ASR once): soft
      warning appears for GPU ASR but Record is still allowed once Ready.
  [ ] Change Summarizing → Get → Use any LLM (optional); GPU digest soft-warns
      and defers merge when stopped from background.
  [ ] Developer → Apply a profile: IDs fill the slots; still need Get/Use for
      anything not already downloaded.
  [ ] Speaker model is NOT on the Notes home — only VAD + ASR are required.

Speakers (opt-in post-pass from a saved note)
  [ ] Record with Silero + Parakeet, stop, open the note: Speakers card shows
      Choose model; transcript already saved without labels.
  [ ] Choose → Get Sortformer (~492 MB) → Use; card shows Label speakers.
  [ ] Tap Label speakers in foreground: Loading → Labeling → Speakers labeled;
      transcript shows Speaker N turns; Summarize is disabled while busy.
  [ ] Background during labeling: interrupted state + Resume; transcript intact.
  [ ] Rename Speaker 1 → a name; Re-label keeps the manual rename.
  [ ] Summarize / Rewrite with speakers uses attributed transcript; after
      labeling an already-summarized note, Rewrite with speakers appears.
  [ ] Confirm ASR + Sortformer + LLM are never loaded together (console).

Lifecycle
  [ ] Tap Record, lock the screen, confirm the Live Activity shows elapsed time
      and never shows transcript text.
  [ ] Background the app for 10 minutes, return, confirm capture continued and
      the transcript grew (CPU ASR). With GPU ASR, note whether it stalled —
      that is expected limit-test data, not a hard failure.
  [ ] Record with the screen locked for 30 minutes on a CPU ASR, then read the
      console log: segments must keep transcribing the whole time.
  [ ] Stop from the Live Activity's Stop button; confirm the note saves.
  [ ] Stop from Shortcuts while the app is backgrounded. With a GPU summarizer
      selected, the note shows "Summary pending" and finishes on next launch.

Activation
  [ ] Action Button after a cold launch: app opens, shows preparation, then
      records. It must never capture without the recording state visible.
  [ ] Action Button with models not yet picked/downloaded: a clear missing-
      model state on Notes, not a silent failure.
  [ ] Action Button while already listening: no second session, no second
      Live Activity.
  [ ] Action Button right after an interruption ended.

Interruptions
  [ ] Incoming phone call: session stops, in-flight segment is saved.
  [ ] Siri invocation mid-session.
  [ ] Music/podcast playback starts mid-session.
  [ ] Bluetooth headset connect and disconnect mid-session (route change).
  [ ] Start Voice Keyboard dictation while a note is recording: one of the two
      must refuse — never two live microphones.

Resource pressure
  [ ] Low Power Mode on: capture continues, derived work is gated, and the gate
      is visible in the UI.
  [ ] Drive the device to a serious thermal state: summarizing pauses.
  [ ] Drive it to critical: capture stops and the reason is recorded on the
      note.
  [ ] Fill storage close to the floor mid-note: the recording stops and reports
      the storage gate; transcription keeps landing.

Permissions and teardown
  [ ] Revoke microphone access in Settings mid-session.
  [ ] Force quit mid-note; relaunch and confirm the note is saved up to its
      last finalized segment and no Live Activity is orphaned.

Search
  [ ] Search a word that appears only in a summary, only in an action item, and
      only deep in a transcript: each returns its note with the matching
      snippet.
  [ ] Search with the field cleared: every note is listed, newest first.

Notes isolation from Chat
  [ ] Attach a document in Chat and ask about it: no note content appears in
      the answer.
  [ ] Record a note, then ask Chat about the attached document again: the
      document answer still works, so nothing wiped Chat's index.

Privacy
  [ ] Enable Airplane Mode for a full note; every stage must still work.
  [ ] Delete one note; confirm its recording and transcript both go.
  [ ] Delete everything; confirm storage returns to near zero and Chat's
      attached document still answers.
  [ ] Set an audio expiry, wait past it, and confirm the note keeps its
      summary, action items, and transcript while the recording is gone.

Timed runs (repeat each three times, then a multi-hour dogfood run)
  [ ] 5 minutes locked
  [ ] 30 minutes locked
  [ ] 60 minutes locked
  [ ] Multi-hour dogfood session

Environments (label each under Developer before starting)
  [ ] quiet room   [ ] office      [ ] restaurant  [ ] vehicle
  [ ] wind         [ ] TV/podcast  [ ] in pocket   [ ] on a desk
  [ ] phone face down

Hardware spread
  [ ] iPhone 14   [ ] iPhone 15   [ ] iPhone 16   [ ] iPhone 17

After each run, export the benchmark CSV and keep it with the console log.
CHECKLIST
}

case "${1:-checklist}" in
    list)      cmd_list ;;
    install)   shift; cmd_install "$@" ;;
    logs)      shift; cmd_logs "$@" ;;
    checklist) cmd_checklist ;;
    *)
        echo "usage: $(basename "$0") {list|install <udid>|logs <udid> [minutes]|checklist}" >&2
        exit 1
        ;;
esac
