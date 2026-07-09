#!/usr/bin/env bash
# run_npu_e2e.sh — on-device NPU (QHexRT) benchmark + parity harness runner.
#
# Loops the NPU catalog ONE MODEL AT A TIME: download -> load -> inference ->
# baseline gate -> delete (the instrumentation test deletes each bundle in a
# finally block, so only one lives on the device at a time). For each model it
# captures the compact `NPU_E2E …` logcat line, pulls the rich per-run JSON report
# (and any TTS wavs), records sanitized source/artifact inputs in `run_inputs.json`,
# then aggregates via scripts/npu_e2e_report.py (which also does the offline-whisper TTS round-trip).
#
# Prereqs (see the QHexRT `android_npu_e2e` skill / BUILD.md): the QHexRT static
# libs are built + staged, the SDK plugin .so are built + staged into jniLibs,
# and the Kotlin SDK is published to mavenLocal. `--build` (below) then stages the
# AARs and builds+installs the app + androidTest APKs.
#
# Usage:
#   scripts/run_npu_e2e.sh [flags] [modelId ...]
#     modelId ...        logical catalog ids to run (default: a per-modality sweep)
#   Flags:
#     --serial <adb>     device serial (default: the only connected device)
#     --token <hf_...>   HF token for PRIVATE runanywhere/*_HNPU repos (never stored)
#     --build            stage AARs + assemble & install app + androidTest APKs first
#     --arch <v81>       expected device arch for the default/ad-hoc sweep
#     --max-new <n>      override LLM/VLM max new tokens
#     --repo/--modality/--files  run ONE ad-hoc HF repo instead of a catalog id
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SDK_GIT_REVISION="$(git -C "$APP_ROOT" rev-parse HEAD 2>/dev/null || true)"
SDK_GIT_DIRTY="unknown"
if [ -n "$SDK_GIT_REVISION" ]; then
  if git -C "$APP_ROOT" diff --quiet --ignore-submodules HEAD -- &&
     [ -z "$(git -C "$APP_ROOT" ls-files --others --exclude-standard)" ]; then
    SDK_GIT_DIRTY="false"
  else
    SDK_GIT_DIRTY="true"
  fi
fi

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

# Default per-modality sweeps use logical catalog ids. --arch is still passed
# into the test runner so it can assert the connected device matches the sweep.
if [ ${#MODELS[@]} -eq 0 ] && [ -z "$REPO" ]; then
  case "$ARCH" in
    v81) MODELS=(lfm2_5_230m moonshine_tiny melotts_en kokoro_en internvl3_5_1b);;  # kokoro is private → needs --token
    v79) MODELS=(lfm2_5_230m whisper_base melotts_en internvl3_5_1b);;
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

installed_apk_sha256() {
  local package_name="$1" apk_path
  apk_path="$("${ADB[@]}" shell pm path "$package_name" 2>/dev/null | tr -d '\r' | sed -n '1s/^package://p')"
  [ -n "$apk_path" ] || return 0
  "${ADB[@]}" shell sha256sum "$apk_path" 2>/dev/null | tr -d '\r' | awk '{print $1}'
}
INSTALLED_APP_SHA256="$(installed_apk_sha256 "$APP_PKG")"
INSTALLED_TEST_SHA256="$(installed_apk_sha256 "$TEST_PKG")"

# Sanitized, host-side inputs for provenance. The token itself is never recorded.
python3 - "$OUT/run_inputs.json" "$APP_ROOT" "$SDK_GIT_REVISION" "$SDK_GIT_DIRTY" \
  "$ARCH" "$BUILD" "$REPO" "$MODALITY" "$FILES" "$MAX_NEW" \
  "$([ -n "$HF_TOKEN" ] && printf true || printf false)" "$APP_PKG" "$TEST_PKG" \
  "$INSTALLED_APP_SHA256" "$INSTALLED_TEST_SHA256" "${MODELS[@]}" <<'PY'
import hashlib
import json
import sys
import time
from pathlib import Path

(
    out, app_root, revision, dirty, arch, build, repo, modality, files, max_new, auth,
    app_package, test_package, installed_app_sha, installed_test_sha, *models,
) = sys.argv[1:]
root = Path(app_root)


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


artifacts = []
for relative in (
    "app/build/outputs/apk/debug/app-debug.apk",
    "app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk",
    "libs/runanywhere-sdk.aar",
    "libs/runanywhere-qhexrt.aar",
    "scripts/run_npu_e2e.sh",
    "scripts/npu_e2e_report.py",
):
    path = root / relative
    if path.is_file():
        artifacts.append({
            "path": relative,
            "bytes": path.stat().st_size,
            "sha256": sha256(path),
        })
artifact_hashes = {item["path"]: item["sha256"] for item in artifacts}
installed_packages = [
    {
        "package": app_package,
        "sha256": installed_app_sha or None,
        "local_artifact": "app/build/outputs/apk/debug/app-debug.apk",
        "matches_local": installed_app_sha == artifact_hashes.get("app/build/outputs/apk/debug/app-debug.apk")
        if installed_app_sha else None,
    },
    {
        "package": test_package,
        "sha256": installed_test_sha or None,
        "local_artifact": "app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk",
        "matches_local": installed_test_sha == artifact_hashes.get(
            "app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk"
        ) if installed_test_sha else None,
    },
]
payload = {
    "schema": "npu_e2e_inputs/v1",
    "generated_unix_ms": int(time.time() * 1000),
    "sdk_git": {"revision": revision or None, "dirty": None if dirty == "unknown" else dirty == "true"},
    "request": {
        "arch": arch,
        "build_requested": build == "1",
        "selection": "ad_hoc" if repo else "catalog",
        "model_ids": models,
        "hf_repo": repo or None,
        "modality": modality or None,
        "manifest_or_files": files or None,
        "max_new": int(max_new) if max_new else None,
        "hf_auth_enabled": auth == "true",
    },
    "artifacts": artifacts,
    "installed_packages": installed_packages,
}
Path(out).write_text(json.dumps(payload, indent=2) + "\n")
PY

run_one() { # $1=model-id  $2..=extra `-e k v` pairs
  local id="$1"; shift
  echo "=== $id ==="
  "${ADB[@]}" logcat -c || true
  local extra=(-e class "$TEST_CLASS")
  [ -n "$HF_TOKEN" ] && extra+=(-e hfToken "$HF_TOKEN")
  [ -n "$MAX_NEW" ] && extra+=(-e maxNew "$MAX_NEW")
  [ -n "$SDK_GIT_REVISION" ] && extra+=(-e sdkGitRevision "$SDK_GIT_REVISION")
  [ "$SDK_GIT_DIRTY" != "unknown" ] && extra+=(-e sdkGitDirty "$SDK_GIT_DIRTY")
  # -w blocks until the test finishes; the NPU_E2E result lands in logcat.
  "${ADB[@]}" shell am instrument -w -r "$@" "${extra[@]}" "$TEST_PKG/$RUNNER" 2>&1 \
    | sed 's/^/  [instr] /' || true
  local line report_id
  line="$("${ADB[@]}" logcat -d -s NPU_E2E:I 2>/dev/null | grep "NPU_E2E id=" | tail -1 || true)"
  [ -n "$line" ] && printf '%s\n' "$line" | tee -a "$OUT/lines.txt" || true
  report_id="$id"
  if [[ "$line" =~ NPU_E2E[[:space:]]id=([^[:space:]]+) ]]; then
    report_id="${BASH_REMATCH[1]}"
  fi
  if ! "${ADB[@]}" pull "$EXT/npu_e2e_${report_id}.json" "$OUT/" 2>/dev/null; then
    if [ "$report_id" != "$id" ]; then
      "${ADB[@]}" pull "$EXT/npu_e2e_${id}.json" "$OUT/" 2>/dev/null || true
    fi
  fi
  if [ ! -f "$OUT/npu_e2e_${report_id}.json" ] && [ ! -f "$OUT/npu_e2e_${id}.json" ]; then
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
  for w in $("${ADB[@]}" shell "ls $EXT/tts_${report_id}_*.wav $EXT/tts_${id}_*.wav 2>/dev/null" | tr -d '\r' | sort -u); do
    "${ADB[@]}" pull "$w" "$OUT/" 2>/dev/null || true
  done
}

"${ADB[@]}" shell "rm -rf $EXT" >/dev/null 2>&1 || true

if [ -n "$REPO" ]; then
  [ -n "$MODALITY" ] && [ -n "$FILES" ] || { echo "--repo needs --modality and --files"; exit 2; }
  run_one "$(basename "$REPO")_${ARCH}" -e hfRepo "$REPO" -e arch "$ARCH" -e modality "$MODALITY" -e files "$FILES"
else
  for id in "${MODELS[@]}"; do run_one "$id" -e modelId "$id" -e arch "$ARCH"; done
fi

echo "=== aggregating -> $OUT/summary.md ==="
python3 "$SCRIPT_DIR/npu_e2e_report.py" "$OUT"
echo
echo "shareable report: $OUT/summary.md  (+ summary.json, run_inputs.json, per-model npu_e2e_*.json)"
