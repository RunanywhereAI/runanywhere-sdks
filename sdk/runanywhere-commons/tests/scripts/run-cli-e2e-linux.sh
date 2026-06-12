#!/usr/bin/env bash
# =============================================================================
# run-cli-e2e-linux.sh
#
# Fail-closed Linux/Docker e2e suite for the rcli desktop CLI.
# Builds the same image as run-real-inference-linux.sh (now with
# RAC_BUILD_CLI=ON) and exercises:
#   - modelless smoke:   version / backends / list --all / info
#   - hermetic pull/rm:  python3 -m http.server inside the container serves a
#                        mounted model file; pull exercises the curl transport,
#                        download orchestrator, registry and rm — no network
#   - real inference:    tts -> wav -> stt roundtrip, vad segments,
#                        run (LLM one-shot), voice turn, serve /health
#
# Model expectations match download-test-models.sh layout, mounted at /models.
# rcli's own storage uses a scratch home INSIDE the container; the canonical
# models (qwen3, whisper, piper, silero) are pulled hermetically or copied from
# the mount where layouts match.
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo ""
    echo -e "${BLUE}==========================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}==========================================${NC}"
    echo ""
}

print_step() { echo -e "${YELLOW}-> $1${NC}"; }
print_error() { echo -e "${RED}[ERROR] $1${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMONS_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
DOCKER_IMAGE="${RAC_REAL_INFERENCE_IMAGE:-rac-real-inference-linux}"
MODEL_DIR="${RAC_TEST_MODEL_DIR:-${HOME}/.local/share/runanywhere/Models}"
LOG_DIR="${RAC_TEST_LOG_DIR:-${COMMONS_ROOT}/build/cli-e2e-logs}"
RCLI="/build/sdk/runanywhere-cli/rcli"
BUILD_ONLY=false
SKIP_BUILD=false

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --build-only) BUILD_ONLY=true; shift ;;
        --skip-build) SKIP_BUILD=true; shift ;;
        --logs) LOG_DIR="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: $0 [--build-only] [--skip-build] [--logs <dir>]"
            echo ""
            echo "Environment:"
            echo "  RAC_TEST_MODEL_DIR        Host model dir mounted at /models (download-test-models.sh layout)"
            echo "  RAC_REAL_INFERENCE_IMAGE  Docker image name (shared with run-real-inference-linux.sh)"
            echo "  RAC_TEST_LOG_DIR          Host log directory"
            exit 0
            ;;
        *) print_error "Unknown option: $1"; exit 1 ;;
    esac
done

print_header "rcli CLI e2e (Linux Docker)"
echo "Repo root:  ${REPO_ROOT}"
echo "Model dir:  ${MODEL_DIR}"
echo "Log dir:    ${LOG_DIR}"
echo "Docker img: ${DOCKER_IMAGE}"

if ! command -v docker >/dev/null 2>&1; then
    print_error "Docker not found."
    exit 1
fi
mkdir -p "${LOG_DIR}"

if [[ "${SKIP_BUILD}" != true ]]; then
    print_header "Building Docker Image"
    docker build -f "${COMMONS_ROOT}/tests/Dockerfile.linux-tests" -t "${DOCKER_IMAGE}" "${REPO_ROOT}"
fi
if [[ "${BUILD_ONLY}" == true ]]; then
    echo -e "${GREEN}[OK] Build-only verification succeeded${NC}"
    exit 0
fi

run_case() {
    local name="$1"
    local script="$2"
    local log_file="${LOG_DIR}/${name}.log"
    echo -n "  ${name}... "
    if docker run --rm \
        -v "${MODEL_DIR}:/models:ro" \
        -e RUNANYWHERE_HOME=/root/.local/share/runanywhere \
        "${DOCKER_IMAGE}" \
        bash -lc "set -euo pipefail; RCLI='${RCLI}'; ${script}" >"${log_file}" 2>&1; then
        echo -e "${GREEN}PASS${NC} (${log_file})"
        return 0
    fi
    echo -e "${RED}FAIL${NC} (${log_file})"
    return 1
}

failed=0
failed_names=()
check() {
    if ! run_case "$1" "$2"; then
        failed=$((failed + 1))
        failed_names+=("$1")
    fi
}

print_header "Modelless Smoke"
check "smoke_version"  '"$RCLI" version | grep -E "^rcli [0-9]+\."'
check "smoke_backends" '"$RCLI" backends | grep -q llamacpp && "$RCLI" backends | grep -q sherpa'
check "smoke_list_all" '"$RCLI" list --all | grep -q qwen3-0.6b && "$RCLI" list --all | grep -q sherpa-onnx-whisper-tiny.en'
check "smoke_info_json" '"$RCLI" info --json | python3 -c "import json,sys; d=json.load(sys.stdin); assert d[\"rcli\"] and d[\"backends\"] >= 1"'
check "smoke_usage_error" '! "$RCLI" bogus-command; [ $? -eq 0 ]'

print_header "Hermetic Pull / rm (no network)"
# Serves the mounted silero model over loopback HTTP and pulls it through the
# full curl-transport + orchestrator + registry path into a scratch home.
# Background daemons must fully detach stdio (incl. stdin) or the container
# outlives the test command and `docker run` never returns.
check "hermetic_pull_rm" '
test -f /models/ONNX/silero-vad/silero_vad.onnx
(cd /models/ONNX/silero-vad && nohup python3 -m http.server 8077 >/dev/null 2>&1 </dev/null &)
for i in $(seq 1 10); do curl -sf http://127.0.0.1:8077/ >/dev/null 2>&1 && break; sleep 1; done
"$RCLI" pull http://127.0.0.1:8077/silero_vad.onnx --no-progress
"$RCLI" list | grep -q silero_vad
"$RCLI" rm silero_vad --force
! "$RCLI" list | grep -q silero_vad
pkill -f "http.server 8077" || true
'

print_header "Real Inference (canonical-layout models)"
# Stage canonical copies from the mount where the rig layout already matches
# commons conventions (LlamaCpp/<id>, ONNX/silero-vad).
STAGE='mkdir -p /root/.local/share/runanywhere/Models/LlamaCpp /root/.local/share/runanywhere/Models/ONNX
cp -r /models/LlamaCpp/qwen3-0.6b /root/.local/share/runanywhere/Models/LlamaCpp/ 2>/dev/null || true
cp -r /models/ONNX/silero-vad /root/.local/share/runanywhere/Models/ONNX/ 2>/dev/null || true'

check "llm_one_shot" "${STAGE}
test -f /root/.local/share/runanywhere/Models/LlamaCpp/qwen3-0.6b/Qwen3-0.6B-Q8_0.gguf
output=\$(\"\$RCLI\" run qwen3-0.6b 'Reply with exactly: OK' --no-think --max-tokens 32 2>/dev/null)
echo \"LLM said: \$output\"
[ -n \"\$output\" ]"

check "tts_stt_roundtrip" "${STAGE}
\"\$RCLI\" pull piper --no-progress
\"\$RCLI\" tts --text 'RunAnywhere runs models on device.' --output /tmp/tts.wav
test -s /tmp/tts.wav
\"\$RCLI\" pull whisper-tiny --no-progress
transcript=\$(\"\$RCLI\" stt --input /tmp/tts.wav 2>/dev/null)
echo \"Transcript: \$transcript\"
echo \"\$transcript\" | grep -iE 'run|anywhere|models|device'"

check "vad_segments" "${STAGE}
\"\$RCLI\" pull piper --no-progress
\"\$RCLI\" tts --text 'Testing voice activity detection.' --output /tmp/vad.wav
\"\$RCLI\" vad --input /tmp/vad.wav --json | python3 -c 'import json,sys; d=json.load(sys.stdin); assert len(d[\"segments\"]) >= 1'"

check "voice_turn" "${STAGE}
\"\$RCLI\" pull piper --no-progress
\"\$RCLI\" pull whisper-tiny --no-progress
\"\$RCLI\" tts --text 'Hello there.' --output /tmp/turn.wav
\"\$RCLI\" voice --input /tmp/turn.wav --output /tmp/reply.wav --json | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d[\"transcription\"] and d[\"response\"]'
test -s /tmp/reply.wav"

check "serve_health" "${STAGE}
test -f /root/.local/share/runanywhere/Models/LlamaCpp/qwen3-0.6b/Qwen3-0.6B-Q8_0.gguf
\"\$RCLI\" serve qwen3-0.6b --port 8090 >/tmp/serve.log 2>&1 </dev/null &
SERVER_PID=\$!
for i in \$(seq 1 30); do
    curl -sf http://127.0.0.1:8090/health >/dev/null 2>&1 && break
    sleep 1
done
curl -sf http://127.0.0.1:8090/health
curl -sf http://127.0.0.1:8090/v1/models | grep -q qwen3
kill \$SERVER_PID
# Bounded clean-shutdown check (SIGTERM must exit; see cmd_serve handler).
for i in \$(seq 1 15); do
    kill -0 \$SERVER_PID 2>/dev/null || break
    sleep 1
done
if kill -0 \$SERVER_PID 2>/dev/null; then
    echo 'server did not exit after SIGTERM'
    kill -9 \$SERVER_PID
    exit 1
fi
cat /tmp/serve.log"

print_header "CLI e2e Summary"
if [[ "${failed}" -gt 0 ]]; then
    print_error "Failed cases: ${failed_names[*]}"
    echo "Logs: ${LOG_DIR}"
    exit 1
fi
echo -e "${GREEN}[OK] All rcli e2e cases passed${NC}"
echo "Logs: ${LOG_DIR}"
