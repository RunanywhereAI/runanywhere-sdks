#!/usr/bin/env bash
# Notes — long-audio offline dogfood (Finn / Diana fixtures).
#
# 1. afconvert m4a → 16 kHz mono WAV
# 2. Build/install/launch app on a connected device
# 3. Push fixtures into the app container
# 4. Trigger runanywhere://notesDogfood
# 5. Pull benchmarks.json + file-runs.json + console logs into .ambient-runs/
#
# Usage:
#   scripts/notes-longform-dogfood.sh prepare
#   scripts/notes-longform-dogfood.sh install <device-udid>
#   scripts/notes-longform-dogfood.sh push <device-udid>
#   scripts/notes-longform-dogfood.sh run <device-udid> [--asr-only|--no-speakers|--no-summarize]
#   scripts/notes-longform-dogfood.sh pull <device-udid>
#   scripts/notes-longform-dogfood.sh all <device-udid>   # prepare+install+push+run+pull
#
# Env:
#   FINN_M4A / DIANA_M4A   override source paths
#   AMBIENT_BUNDLE_ID      default com.runanywhere.RunAnywhere
#   DOGFOOD_WAIT_MINUTES   how long to wait before pull (default 90)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUNDLE_ID="${AMBIENT_BUNDLE_ID:-com.runanywhere.RunAnywhere}"
RESULTS_DIR="${APP_ROOT}/.ambient-runs"
FIXTURES_HOST="${APP_ROOT}/.ambient-fixtures"
FINN_M4A="${FINN_M4A:-/Users/shubhammalhotra/Downloads/Finn barr YC arrogance.m4a}"
DIANA_M4A="${DIANA_M4A:-/Users/shubhammalhotra/Downloads/Diana YC.m4a}"
WAIT_MINUTES="${DOGFOOD_WAIT_MINUTES:-90}"

log() { printf '\n==> %s\n' "$*"; }

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "error: required command not found: $1" >&2
        exit 1
    fi
}

convert_one() {
    local src="$1"
    local dst="$2"
    if [ ! -f "${src}" ]; then
        echo "error: missing source audio: ${src}" >&2
        exit 1
    fi
    mkdir -p "$(dirname "${dst}")"
    log "afconvert $(basename "${src}") → $(basename "${dst}")"
    afconvert -f WAVE -d LEI16@16000 -c 1 "${src}" "${dst}"
    ls -lh "${dst}"
}

cmd_prepare() {
    require_command afconvert
    mkdir -p "${FIXTURES_HOST}"
    convert_one "${FINN_M4A}" "${FIXTURES_HOST}/finn-yc.wav"
    convert_one "${DIANA_M4A}" "${FIXTURES_HOST}/diana-yc.wav"
    log "Fixtures ready in ${FIXTURES_HOST}"
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
}

cmd_push() {
    local udid="${1:?usage: push <device-udid>}"
    require_command xcrun
    if [ ! -d "${FIXTURES_HOST}" ]; then
        cmd_prepare
    fi

    log "Pushing fixtures into app container Documents/AmbientMemory/Fixtures"
    # Best-effort: copy each WAV. Container paths vary by iOS/devicectl version.
    local remote_dir="Documents/AmbientMemory/Fixtures"
    for wav in "${FIXTURES_HOST}"/*.wav; do
        [ -f "${wav}" ] || continue
        local name
        name="$(basename "${wav}")"
        log "copy ${name}"
        if xcrun devicectl device copy to \
            --device "${udid}" \
            --domain-type appDataContainer \
            --domain-identifier "${BUNDLE_ID}" \
            --source "${wav}" \
            --destination "${remote_dir}/${name}" 2>/dev/null; then
            continue
        fi
        # Fallback destination layout used by some toolchains.
        xcrun devicectl device copy to \
            --device "${udid}" \
            --domain-type appDataContainer \
            --domain-identifier "${BUNDLE_ID}" \
            --source "${wav}" \
            --destination "/Documents/AmbientMemory/Fixtures/${name}" \
            || echo "warn: push failed for ${name}; copy manually via Files/Xcode" >&2
    done
}

cmd_run() {
    local udid="${1:?usage: run <device-udid> [--asr-only|--no-speakers|--no-summarize]}"
    shift || true
    local speakers=1
    local summarize=1
    while [ $# -gt 0 ]; do
        case "$1" in
            --asr-only) speakers=0; summarize=0 ;;
            --no-speakers) speakers=0 ;;
            --no-summarize) summarize=0 ;;
            *) echo "unknown flag: $1" >&2; exit 1 ;;
        esac
        shift
    done

    require_command xcrun
    local url="runanywhere://notesDogfood?speakers=${speakers}&summarize=${summarize}"
    log "Launching dogfood via ${url}"
    # Flags must come before the bundle id; --payload-url after it is treated as an app arg.
    xcrun devicectl device process launch \
        --device "${udid}" \
        --terminate-existing \
        --activate \
        --payload-url "${url}" \
        "${BUNDLE_ID}"

    cat <<NOTE

Dogfood launched. On device, ensure VAD + ASR (+ optional Sortformer / digest)
are downloaded under Notes → Models before / while the run starts.

Waiting up to ${WAIT_MINUTES} minutes before suggesting pull…
NOTE
}

cmd_pull() {
    local udid="${1:?usage: pull <device-udid>}"
    require_command xcrun
    local stamp
    stamp="$(date +%Y%m%d-%H%M%S)"
    local out="${RESULTS_DIR}/${stamp}"
    mkdir -p "${out}"

    log "Pulling metrics into ${out}"
    for remote in \
        "Documents/AmbientMemory/benchmarks.json" \
        "Documents/AmbientMemory/file-runs.json"
    do
        local base
        base="$(basename "${remote}")"
        if xcrun devicectl device copy from \
            --device "${udid}" \
            --domain-type appDataContainer \
            --domain-identifier "${BUNDLE_ID}" \
            --source "${remote}" \
            --destination "${out}/${base}" 2>/dev/null; then
            log "got ${base}"
        else
            echo "warn: could not pull ${remote}" >&2
        fi
    done

    local log_out="${out}/console.log"
    log "Capturing brief console snapshot → ${log_out}"
    ( xcrun devicectl device console --device "${udid}" > "${log_out}" 2>&1 & echo $! > "${out}/console.pid" )
    sleep 8
    if [ -f "${out}/console.pid" ]; then
        kill "$(cat "${out}/console.pid")" 2>/dev/null || true
        rm -f "${out}/console.pid"
    fi

    if [ -f "${out}/file-runs.json" ]; then
        log "Stage timing table (from file-runs.json)"
        python3 - <<'PY' "${out}/file-runs.json" || true
import json, sys
path = sys.argv[1]
with open(path) as f:
    rows = json.load(f)
print(f"{'fixture':28} {'convert':>8} {'asr':>8} {'first':>8} {'diar':>8} {'digest':>8} {'total':>8} {'segs':>5} {'spk':>4} {'sec':>4}")
for r in rows:
    print(
        f"{r.get('fixtureName','')[:28]:28} "
        f"{r.get('convertMs',0):8} "
        f"{r.get('asrMs',0):8} "
        f"{r.get('firstTranscriptMs',0):8} "
        f"{r.get('diarizationMs',0):8} "
        f"{r.get('digestMs',0):8} "
        f"{r.get('totalMs',0):8} "
        f"{r.get('segmentCount',0):5} "
        f"{r.get('speakerCount',0):4} "
        f"{r.get('sectionCount',0):4}"
    )
PY
    fi

    log "Artifacts in ${out}"
    ls -la "${out}"
}

cmd_all() {
    local udid="${1:?usage: all <device-udid>}"
    cmd_prepare
    cmd_install "${udid}"
    cmd_push "${udid}"
    cmd_run "${udid}"
    log "Sleeping ${WAIT_MINUTES}m for on-device pipeline…"
    sleep $(( WAIT_MINUTES * 60 ))
    cmd_pull "${udid}"
}

case "${1:-}" in
    prepare)  cmd_prepare ;;
    install)  shift; cmd_install "$@" ;;
    push)     shift; cmd_push "$@" ;;
    run)      shift; cmd_run "$@" ;;
    pull)     shift; cmd_pull "$@" ;;
    all)      shift; cmd_all "$@" ;;
    *)
        echo "usage: $(basename "$0") {prepare|install|push|run|pull|all} [device-udid] [flags]" >&2
        exit 1
        ;;
esac
