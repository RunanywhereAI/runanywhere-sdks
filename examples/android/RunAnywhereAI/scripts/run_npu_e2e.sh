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
#     --local-bundle <dir>  stage ONE private bundle locally; use with one catalog model id
#     --local-download <dir> serve ONE private bundle over adb-reversed loopback and download it
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
REPO="" ; MODALITY="" ; FILES="" ; LOCAL_BUNDLE="" ; LOCAL_DOWNLOAD=""
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
    --local-bundle) LOCAL_BUNDLE="$2"; shift 2;;
    --local-download) LOCAL_DOWNLOAD="$2"; shift 2;;
    -h|--help) sed -n '2,30p' "$0"; exit 0;;
    *) MODELS+=("$1"); shift;;
  esac
done

ADB=(adb); [ -n "$SERIAL" ] && ADB=(adb -s "$SERIAL")

# Default per-modality sweeps use logical catalog ids. --arch is still passed
# into the test runner so it can assert the connected device matches the sweep.
if [ ${#MODELS[@]} -eq 0 ] && [ -z "$REPO" ] && [ -z "$LOCAL_BUNDLE" ] && [ -z "$LOCAL_DOWNLOAD" ]; then
  case "$ARCH" in
    v81) MODELS=(lfm2_5_230m moonshine_tiny melotts_en kokoro_en internvl3_5_1b);;  # kokoro is private → needs --token
    v79) MODELS=(lfm2_5_230m whisper_base melotts_en internvl3_5_1b);;
    *)   echo "no default model set for arch=$ARCH; pass model ids explicitly"; exit 2;;
  esac
fi

if [ -n "$LOCAL_BUNDLE" ] && [ -n "$LOCAL_DOWNLOAD" ]; then
  echo "--local-bundle and --local-download are mutually exclusive"
  exit 2
fi
LOCAL_SOURCE="${LOCAL_BUNDLE:-$LOCAL_DOWNLOAD}"
if [ -n "$LOCAL_SOURCE" ]; then
  [ -d "$LOCAL_SOURCE" ] || { echo "local bundle source is not a directory: $LOCAL_SOURCE"; exit 2; }
  [ -z "$REPO" ] || { echo "local bundle modes cannot be combined with --repo"; exit 2; }
  [ ${#MODELS[@]} -eq 1 ] || { echo "local bundle modes require exactly one catalog model id"; exit 2; }
  LOCAL_SOURCE="$(cd "$LOCAL_SOURCE" && pwd)"
  if [ -n "$LOCAL_BUNDLE" ]; then LOCAL_BUNDLE="$LOCAL_SOURCE"; else LOCAL_DOWNLOAD="$LOCAL_SOURCE"; fi
fi

TS="$(date +%Y%m%d_%H%M%S)"
OUT="$APP_ROOT/reports/npu_e2e/$TS"
mkdir -p "$OUT"
EXT="/sdcard/Android/data/$APP_PKG/files/npu_e2e"
LOCAL_INDEX=""
LOCAL_TREE_SHA256=""
LOCAL_DEVICE_ROOT=""
LOCAL_DEVICE_INDEX=""
LOCAL_DOWNLOAD_BASE_URL=""
LOCAL_SERVER_PID=""
LOCAL_SERVER_LOG=""
LOCAL_REVERSE_PORT=""

if [ -n "$LOCAL_SOURCE" ]; then
  LOCAL_INDEX="$OUT/local_bundle_index.json"
  python3 - "$LOCAL_SOURCE" "$LOCAL_INDEX" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
out = Path(sys.argv[2])
rows = []
for path in sorted(root.rglob("*")):
    if path.is_symlink():
        raise SystemExit(f"local bundle must not contain symlinks: {path}")
    if not path.is_file():
        continue
    relative = path.relative_to(root).as_posix()
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    rows.append({"path": relative, "bytes": path.stat().st_size, "sha256": digest.hexdigest()})
if not rows:
    raise SystemExit("local bundle contains no files")
tree_input = "".join(f"{row['sha256']} {row['bytes']} {row['path']}\n" for row in rows).encode()
payload = {
    "schema": "npu_local_bundle/v1",
    "source_label": root.name,
    "tree_sha256": hashlib.sha256(tree_input).hexdigest(),
    "files": rows,
}
out.write_text(json.dumps(payload, indent=2) + "\n")
PY
  LOCAL_TREE_SHA256="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["tree_sha256"])' "$LOCAL_INDEX")"
fi

echo "device : $("${ADB[@]}" shell getprop ro.soc.model | tr -d '\r') ($("${ADB[@]}" shell getprop ro.product.model | tr -d '\r'))"
echo "arch   : $ARCH   report: $OUT"
[ -n "$HF_TOKEN" ] && echo "hf auth: enabled (private repos)"

if [ $BUILD -eq 1 ]; then
  echo "=== staging AARs + building app + androidTest APKs ==="
  if [ -z "${ANDROID_HOME:-}" ]; then
    if [ -n "${ANDROID_SDK_ROOT:-}" ]; then
      export ANDROID_HOME="$ANDROID_SDK_ROOT"
    elif [ -d "$HOME/Library/Android/sdk" ]; then
      export ANDROID_HOME="$HOME/Library/Android/sdk"
    else
      echo "ANDROID_HOME is required for --build" >&2
      exit 2
    fi
  fi
  (cd "$APP_ROOT" && bash scripts/stage-sdk-aars.sh)
  (cd "$APP_ROOT" && ./gradlew :app:assembleDebug :app:assembleDebugAndroidTest)
  APK="$APP_ROOT/app/build/outputs/apk/debug/app-debug.apk"
  TAPK="$APP_ROOT/app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk"
  "${ADB[@]}" install -r -g "$APK"
  "${ADB[@]}" install -r -g "$TAPK"
fi

cleanup_local_bundle() {
  if [ -n "$LOCAL_DEVICE_ROOT" ]; then "${ADB[@]}" shell "rm -rf '$LOCAL_DEVICE_ROOT'" >/dev/null 2>&1 || true; fi
  if [ -n "$LOCAL_DEVICE_INDEX" ]; then "${ADB[@]}" shell "rm -f '$LOCAL_DEVICE_INDEX'" >/dev/null 2>&1 || true; fi
  if [ -n "$LOCAL_REVERSE_PORT" ]; then "${ADB[@]}" reverse --remove "tcp:$LOCAL_REVERSE_PORT" >/dev/null 2>&1 || true; fi
  if [ -n "$LOCAL_SERVER_PID" ]; then kill "$LOCAL_SERVER_PID" >/dev/null 2>&1 || true; wait "$LOCAL_SERVER_PID" >/dev/null 2>&1 || true; fi
}
trap cleanup_local_bundle EXIT

if [ -n "$LOCAL_SOURCE" ]; then
  local_id="${MODELS[0]}"
  LOCAL_DEVICE_INDEX="/sdcard/Android/data/$APP_PKG/files/npu_local_bundle_index_$local_id.json"
  if [ -n "$LOCAL_BUNDLE" ]; then
    LOCAL_DEVICE_ROOT="/sdcard/Android/data/$APP_PKG/files/npu_local_bundle/$local_id"
  fi
  cleanup_local_bundle
  "${ADB[@]}" push "$LOCAL_INDEX" "$LOCAL_DEVICE_INDEX" >/dev/null
  if [ -n "$LOCAL_BUNDLE" ]; then
    "${ADB[@]}" shell "mkdir -p '$LOCAL_DEVICE_ROOT'"
    "${ADB[@]}" push "$LOCAL_BUNDLE/." "$LOCAL_DEVICE_ROOT/" >/dev/null
    echo "local  : staged $(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print("{} files tree={}".format(len(d["files"]), d["tree_sha256"]))' "$LOCAL_INDEX")"
  else
    LOCAL_REVERSE_PORT="$(python3 - <<'PY'
import socket
with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
)"
    LOCAL_SERVER_LOG="$OUT/loopback_http_server.log"
    python3 -m http.server "$LOCAL_REVERSE_PORT" --bind 127.0.0.1 --directory "$LOCAL_DOWNLOAD" >"$LOCAL_SERVER_LOG" 2>&1 &
    LOCAL_SERVER_PID=$!
    LOCAL_DOWNLOAD_BASE_URL="http://127.0.0.1:$LOCAL_REVERSE_PORT"
    LOCAL_HTTP_READY=0
    LOCAL_PROBE_PATH="$(python3 -c 'import json,sys; print(min(json.load(open(sys.argv[1]))["files"], key=lambda row: row["bytes"])["path"])' "$LOCAL_INDEX")"
    for _ in $(seq 1 50); do
      if curl -fsS "$LOCAL_DOWNLOAD_BASE_URL/$LOCAL_PROBE_PATH" >/dev/null 2>&1; then LOCAL_HTTP_READY=1; break; fi
      sleep 0.1
    done
    kill -0 "$LOCAL_SERVER_PID" 2>/dev/null || { echo "loopback HTTP server failed; see $LOCAL_SERVER_LOG"; exit 1; }
    [ "$LOCAL_HTTP_READY" = 1 ] || { echo "loopback HTTP server did not become ready; see $LOCAL_SERVER_LOG"; exit 1; }
    "${ADB[@]}" reverse "tcp:$LOCAL_REVERSE_PORT" "tcp:$LOCAL_REVERSE_PORT" >/dev/null
    echo "local  : serving $(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print("{} files tree={}".format(len(d["files"]), d["tree_sha256"]))' "$LOCAL_INDEX") at adb-reversed loopback"
  fi
fi

installed_apk_sha256() {
  local package_name="$1" apk_path
  apk_path="$("${ADB[@]}" shell pm path "$package_name" 2>/dev/null | tr -d '\r' | sed -n '1s/^package://p')"
  [ -n "$apk_path" ] || return 0
  "${ADB[@]}" shell sha256sum "$apk_path" 2>/dev/null | tr -d '\r' | awk '{print $1}'
}
INSTALLED_APP_SHA256="$(installed_apk_sha256 "$APP_PKG")"
INSTALLED_TEST_SHA256="$(installed_apk_sha256 "$TEST_PKG")"
ACQUISITION="hf_download"
if [ -n "$LOCAL_BUNDLE" ]; then ACQUISITION="local_adb_import"; fi
if [ -n "$LOCAL_DOWNLOAD" ]; then ACQUISITION="local_loopback_download"; fi

# Sanitized, host-side inputs for provenance. The token itself is never recorded.
python3 - "$OUT/run_inputs.json" "$APP_ROOT" "$SDK_GIT_REVISION" "$SDK_GIT_DIRTY" \
  "$ARCH" "$BUILD" "$REPO" "$MODALITY" "$FILES" "$MAX_NEW" "$LOCAL_INDEX" "$LOCAL_TREE_SHA256" \
  "$ACQUISITION" "$([ -n "$HF_TOKEN" ] && printf true || printf false)" "$APP_PKG" "$TEST_PKG" \
  "$INSTALLED_APP_SHA256" "$INSTALLED_TEST_SHA256" "${MODELS[@]}" <<'PY'
import hashlib
import json
import sys
import time
from pathlib import Path

(
    out, app_root, revision, dirty, arch, build, repo, modality, files, max_new,
    local_index, local_tree_sha256, acquisition, auth,
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
    "app/build/outputs/apk/release/app-release.apk",
    "app/build/outputs/apk/debug/app-debug.apk",
    "app/build/outputs/apk/androidTest/release/app-release-androidTest.apk",
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


def matching_artifact(installed_sha, candidates):
    if not installed_sha:
        return None
    return next((path for path in candidates if artifact_hashes.get(path) == installed_sha), None)


app_artifact = matching_artifact(installed_app_sha, (
    "app/build/outputs/apk/release/app-release.apk",
    "app/build/outputs/apk/debug/app-debug.apk",
))
test_artifact = matching_artifact(installed_test_sha, (
    "app/build/outputs/apk/androidTest/release/app-release-androidTest.apk",
    "app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk",
))
installed_packages = [
    {
        "package": app_package,
        "sha256": installed_app_sha or None,
        "local_artifact": app_artifact,
        "matches_local": app_artifact is not None if installed_app_sha else None,
    },
    {
        "package": test_package,
        "sha256": installed_test_sha or None,
        "local_artifact": test_artifact,
        "matches_local": test_artifact is not None if installed_test_sha else None,
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
        "acquisition": acquisition,
        "local_bundle_tree_sha256": local_tree_sha256 or None,
    },
    "artifacts": artifacts,
    "installed_packages": installed_packages,
}
if local_index:
    index_path = Path(local_index)
    payload["local_bundle"] = json.loads(index_path.read_text())
    payload["local_bundle"]["index_sha256"] = sha256(index_path)
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
  if [ -n "$LOCAL_DEVICE_ROOT" ]; then
    extra+=(-e localBundlePath "$LOCAL_DEVICE_ROOT")
    extra+=(-e localBundleIndex "$LOCAL_DEVICE_INDEX")
    extra+=(-e localBundleTreeSha256 "$LOCAL_TREE_SHA256")
  fi
  if [ -n "$LOCAL_DOWNLOAD_BASE_URL" ]; then
    extra+=(-e localDownloadBaseUrl "$LOCAL_DOWNLOAD_BASE_URL")
    extra+=(-e localBundleIndex "$LOCAL_DEVICE_INDEX")
    extra+=(-e localBundleTreeSha256 "$LOCAL_TREE_SHA256")
    extra+=(-e lifecycleCycles 3)
  fi
  # -w blocks until the test finishes; the NPU_E2E result lands in logcat.
  "${ADB[@]}" shell am instrument -w -r "$@" "${extra[@]}" "$TEST_PKG/$RUNNER" 2>&1 \
    | sed 's/^/  [instr] /' || true
  # Preserve the execution-plane evidence used to distinguish a QHexRT route
  # from an HTP/CDSP graph execution. The runner cleared logcat immediately
  # before this model, so the capture is scoped to this one-model invocation.
  "${ADB[@]}" logcat -d -v threadtime 2>/dev/null \
    | grep -E 'NPU_E2E|qhexrt|QnnHtp|QNN API|adsprpc|cdsprpc|CDSP|cdsp|fastrpc' \
    > "$OUT/logcat_${id}.txt" || true
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
  # pull inpainting outputs for visual inspection and report provenance
  for image in $("${ADB[@]}" shell "ls $EXT/inpaint_${report_id}_*.png $EXT/inpaint_${id}_*.png 2>/dev/null" | tr -d '\r' | sort -u); do
    "${ADB[@]}" pull "$image" "$OUT/" 2>/dev/null || true
  done
}

"${ADB[@]}" shell "rm -rf $EXT" >/dev/null 2>&1 || true

if [ -n "$REPO" ]; then
  [ -n "$MODALITY" ] && [ -n "$FILES" ] || { echo "--repo needs --modality and --files"; exit 2; }
  run_one "$(basename "$REPO")_${ARCH}" -e hfRepo "$REPO" -e arch "$ARCH" -e modality "$MODALITY" -e files "$FILES"
else
  for id in "${MODELS[@]}"; do run_one "$id" -e modelId "$id" -e arch "$ARCH"; done
fi

if [ -n "$LOCAL_SOURCE" ]; then
  cleanup_local_bundle
  local_id="${MODELS[0]}"
  model_absent="$("${ADB[@]}" shell "run-as '$APP_PKG' sh -c 'test ! -e files/RunAnywhere/Models/QHexRT/$local_id && echo true || echo false'" | tr -d '\r')"
  temp_files_absent="$("${ADB[@]}" shell "run-as '$APP_PKG' sh -c 'test -z \"\$(find files/RunAnywhere/Models/QHexRT/$local_id -type f -name \".qhexrt-*\" 2>/dev/null)\" && echo true || echo false'" | tr -d '\r')"
  index_absent="$("${ADB[@]}" shell "test ! -e '$LOCAL_DEVICE_INDEX' && echo true || echo false" | tr -d '\r')"
  local_stage_absent=true
  if [ -n "$LOCAL_DEVICE_ROOT" ]; then
    local_stage_absent="$("${ADB[@]}" shell "test ! -e '$LOCAL_DEVICE_ROOT' && echo true || echo false" | tr -d '\r')"
  fi
  reverse_absent=true
  if [ -n "$LOCAL_REVERSE_PORT" ] && "${ADB[@]}" reverse --list | grep -q "tcp:$LOCAL_REVERSE_PORT"; then reverse_absent=false; fi
  server_absent=true
  if [ -n "$LOCAL_SERVER_PID" ] && kill -0 "$LOCAL_SERVER_PID" >/dev/null 2>&1; then server_absent=false; fi
  python3 - "$OUT/post_run_cleanup.json" "$local_id" "$model_absent" "$temp_files_absent" \
    "$index_absent" "$local_stage_absent" "$reverse_absent" "$server_absent" <<'PY'
import json
import sys
import time

out, model_id, model_absent, temp_absent, index_absent, stage_absent, reverse_absent, server_absent = sys.argv[1:]
checks = {
    "managed_model_folder_absent": model_absent == "true",
    "temporary_qhexrt_files_absent": temp_absent == "true",
    "runner_index_absent": index_absent == "true",
    "local_stage_absent": stage_absent == "true",
    "adb_reverse_absent": reverse_absent == "true",
    "loopback_server_absent": server_absent == "true",
}
payload = {
    "schema": "npu_e2e_cleanup/v1",
    "generated_unix_ms": int(time.time() * 1000),
    "model_id": model_id,
    "checks": checks,
    "passed": all(checks.values()),
}
with open(out, "w", encoding="utf-8") as stream:
    json.dump(payload, stream, indent=2)
    stream.write("\n")
PY
  python3 -c 'import json,sys; raise SystemExit(0 if json.load(open(sys.argv[1]))["passed"] else 1)' "$OUT/post_run_cleanup.json" \
    || { echo "post-run cleanup verification failed: $OUT/post_run_cleanup.json"; exit 1; }
  LOCAL_SERVER_PID=""
  LOCAL_REVERSE_PORT=""
  LOCAL_DEVICE_ROOT=""
  LOCAL_DEVICE_INDEX=""
fi

echo "=== aggregating -> $OUT/summary.md ==="
python3 "$SCRIPT_DIR/npu_e2e_report.py" "$OUT"
echo
echo "shareable report: $OUT/summary.md  (+ summary.json, run_inputs.json, per-model npu_e2e_*.json)"
