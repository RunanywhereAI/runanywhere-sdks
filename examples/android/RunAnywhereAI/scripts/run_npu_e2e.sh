#!/usr/bin/env bash
# run_npu_e2e.sh — on-device NPU (QHexRT) benchmark + parity harness runner.
#
# Loops the NPU catalog ONE MODEL AT A TIME: download -> load -> inference ->
# baseline gate -> delete (the instrumentation test deletes each bundle in a
# finally block, so only one lives on the device at a time). For each model it
# captures the compact `NPU_E2E …` logcat line, pulls the rich per-run JSON report
# (and any TTS wavs), then aggregates everything into a shareable report via
# scripts/npu_e2e_report.py (which also does the offline-whisper TTS round-trip).
#
# Prereqs (see the QHexRT `android_npu_e2e` skill / BUILD.md): the QHexRT static
# libs are built + staged, the SDK plugin .so are built + staged into jniLibs,
# and the Kotlin SDK is published to mavenLocal. `--build` (below) then stages the
# AARs and builds+installs the app + androidTest APKs.
#
# Usage:
#   scripts/run_npu_e2e.sh [flags] [modelId ...]
#     modelId ...        catalog ids to run (default: the per-modality v81 sweep)
#   Flags:
#     --serial <adb>     device serial (default: the only connected device)
#     --token <hf_...>   HF token for PRIVATE runanywhere/*_HNPU repos (never stored)
#     --build            stage AARs + assemble & install app + androidTest APKs first
#     --arch <v81>       arch filter used only to pick the default model set
#     --max-new <n>      override LLM/VLM max new tokens
#     --repo/--modality/--files  run ONE ad-hoc HF repo instead of a catalog id
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SERIAL="${SERIAL:-}"
APP_PKG="${APP_PKG:-com.runanywhere.runanywhereai}"
TEST_PKG="${TEST_PKG:-${APP_PKG}.test}"
RUNNER="${RUNNER:-androidx.test.runner.AndroidJUnitRunner}"
TEST_CLASS="com.runanywhere.runanywhereai.NpuModelE2ETest"
HF_TOKEN="${HF_TOKEN:-}"
ARCH="${ARCH:-v81}"
MAX_NEW="${MAX_NEW:-}"
BUILD=0
REPO="" ; MODALITY="" ; FILES=""
MODELS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --serial) SERIAL="$2"; shift 2;;
    --token)  HF_TOKEN="$2"; shift 2;;
    --build)  BUILD=1; shift;;
    --arch)   ARCH="$2"; shift 2;;
    --max-new) MAX_NEW="$2"; shift 2;;
    --repo)   REPO="$2"; shift 2;;
    --modality) MODALITY="$2"; shift 2;;
    --files)  FILES="$2"; shift 2;;
    -h|--help) sed -n '2,30p' "$0"; exit 0;;
    *) MODELS+=("$1"); shift;;
  esac
done

ADB=(adb); [ -n "$SERIAL" ] && ADB=(adb -s "$SERIAL")

# default per-modality sweep by arch (the small public bundles)
if [ ${#MODELS[@]} -eq 0 ] && [ -z "$REPO" ]; then
  case "$ARCH" in
    v81) MODELS=(lfm2_5_230m_v81 moonshine_tiny_v81 melotts_en_v81 kokoro_en_v81 internvl3_5_1b_v81);;  # kokoro is private → needs --token
    v79) MODELS=(lfm2_5_230m_v79 whisper_base_v79 melotts_en_v79 internvl3_5_1b_v79);;
    *)   echo "no default model set for arch=$ARCH; pass model ids explicitly"; exit 2;;
  esac
fi

TS="$(date +%Y%m%d_%H%M%S)"
OUT="$APP_ROOT/reports/npu_e2e/$TS"
mkdir -p "$OUT"
EXT="/sdcard/Android/data/$APP_PKG/files/npu_e2e"

echo "device : $("${ADB[@]}" shell getprop ro.soc.model | tr -d '\r') ($("${ADB[@]}" shell getprop ro.product.model | tr -d '\r'))"
echo "arch   : $ARCH   report: $OUT"
[ -n "$HF_TOKEN" ] && echo "hf auth: enabled (private repos)"

if [ $BUILD -eq 1 ]; then
  echo "=== staging AARs + building app + androidTest APKs ==="
  (cd "$APP_ROOT" && bash scripts/stage-sdk-aars.sh)
  (cd "$APP_ROOT" && ./gradlew :app:assembleDebug :app:assembleDebugAndroidTest)
  APK="$APP_ROOT/app/build/outputs/apk/debug/app-debug.apk"
  TAPK="$APP_ROOT/app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk"
  "${ADB[@]}" install -r -g "$APK"
  "${ADB[@]}" install -r -g "$TAPK"
fi

run_one() { # $1=model-id  $2..=extra `-e k v` pairs
  local id="$1"; shift
  echo "=== $id ==="
  "${ADB[@]}" logcat -c || true
  local extra=(-e class "$TEST_CLASS")
  [ -n "$HF_TOKEN" ] && extra+=(-e hfToken "$HF_TOKEN")
  [ -n "$MAX_NEW" ] && extra+=(-e maxNew "$MAX_NEW")
  # -w blocks until the test finishes; the NPU_E2E result lands in logcat.
  "${ADB[@]}" shell am instrument -w -r "$@" "${extra[@]}" "$TEST_PKG/$RUNNER" 2>&1 \
    | sed 's/^/  [instr] /' || true
  "${ADB[@]}" logcat -d -s NPU_E2E:I 2>/dev/null | grep "NPU_E2E id=" | tail -1 | tee -a "$OUT/lines.txt" || true
  if ! "${ADB[@]}" pull "$EXT/npu_e2e_${id}.json" "$OUT/" 2>/dev/null; then
    # No report => the app process died (native crash) before the test could write it. Record a CRASH
    # row so the summary stays complete + honest, with the top native frame for triage.
    local sig
    sig="$("${ADB[@]}" logcat -d 2>/dev/null | tr -d '\r' \
      | grep -oE 'signal [0-9]+ \([A-Z_]+\)|#00 pc [0-9a-f]+  [^ ]+\.so \([^)]*\)' | tail -2 | tr '\n' ' ' | tr '"' "'")"
    echo "  (no json for $id — native crash: $sig)"
    printf '{"model_id":"%s","modality":"?","arch":"%s","status":"CRASH","detail":"native crash: %s"}\n' \
      "$id" "$ARCH" "$sig" > "$OUT/npu_e2e_${id}.json"
  fi
  # pull any TTS wavs this model produced
  for w in $("${ADB[@]}" shell "ls $EXT/tts_${id}_*.wav 2>/dev/null" | tr -d '\r'); do
    "${ADB[@]}" pull "$w" "$OUT/" 2>/dev/null || true
  done
}

"${ADB[@]}" shell "rm -rf $EXT" >/dev/null 2>&1 || true

if [ -n "$REPO" ]; then
  [ -n "$MODALITY" ] && [ -n "$FILES" ] || { echo "--repo needs --modality and --files"; exit 2; }
  run_one "$(basename "$REPO")_${ARCH}" -e hfRepo "$REPO" -e arch "$ARCH" -e modality "$MODALITY" -e files "$FILES"
else
  for id in "${MODELS[@]}"; do run_one "$id" -e modelId "$id"; done
fi

echo "=== aggregating -> $OUT/summary.md ==="
python3 "$SCRIPT_DIR/npu_e2e_report.py" "$OUT" || echo "(aggregation skipped: $?)"
echo
echo "shareable report: $OUT/summary.md  (+ summary.json, per-model npu_e2e_*.json)"
