#!/usr/bin/env bash
# =============================================================================
# run-real-inference-linux.sh
#
# Fail-closed Linux/Docker runner for commons real-inference tests.
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

print_step() {
    echo -e "${YELLOW}-> $1${NC}"
}

print_error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMONS_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
DOCKER_IMAGE="${RAC_REAL_INFERENCE_IMAGE:-rac-real-inference-linux}"
MODEL_DIR="${RAC_TEST_MODEL_DIR:-${HOME}/.local/share/runanywhere/Models}"
LOG_DIR="${RAC_TEST_LOG_DIR:-${COMMONS_ROOT}/build/real-inference-logs}"
CONTAINER_TEST_DIR="/build/sdk/runanywhere-commons/tests"
DOWNLOAD_FIRST=false
BUILD_ONLY=false

TESTS=(
    test_vad
    test_stt
    test_tts
    test_llm
    test_voice_agent
)

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --download)
            DOWNLOAD_FIRST=true
            shift
            ;;
        --build-only)
            BUILD_ONLY=true
            shift
            ;;
        --logs)
            LOG_DIR="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [--download] [--build-only] [--logs <dir>]"
            echo ""
            echo "Environment:"
            echo "  RAC_TEST_MODEL_DIR          Host model directory mounted at /models"
            echo "  RAC_REAL_INFERENCE_IMAGE    Docker image name"
            echo "  RAC_TEST_LOG_DIR            Host log directory"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

print_header "runanywhere-commons Real Inference (Linux Docker)"
echo "Repo root:    ${REPO_ROOT}"
echo "Commons root: ${COMMONS_ROOT}"
echo "Model dir:    ${MODEL_DIR}"
echo "Log dir:      ${LOG_DIR}"
echo "Docker img:   ${DOCKER_IMAGE}"

if ! command -v docker >/dev/null 2>&1; then
    print_error "Docker not found. Install Docker to run Linux real-inference tests."
    exit 1
fi

mkdir -p "${LOG_DIR}"

if [[ "${DOWNLOAD_FIRST}" == true ]]; then
    print_step "Downloading required test models"
    RAC_TEST_MODEL_DIR="${MODEL_DIR}" "${SCRIPT_DIR}/download-test-models.sh"
fi

print_header "Building Docker Image"
print_step "Building ${DOCKER_IMAGE} with bounded parallelism"
docker build -f "${COMMONS_ROOT}/tests/Dockerfile.linux-tests" -t "${DOCKER_IMAGE}" "${REPO_ROOT}"

if [[ "${BUILD_ONLY}" == true ]]; then
    echo -e "${GREEN}[OK] Build-only verification succeeded${NC}"
    exit 0
fi

print_header "Validating Required Test Binaries"
for test_name in "${TESTS[@]}"; do
    if ! docker run --rm "${DOCKER_IMAGE}" bash -lc "test -x '${CONTAINER_TEST_DIR}/${test_name}'"; then
        print_error "Required real-inference binary is missing: ${test_name}"
        exit 1
    fi
done

print_header "Running Required Real-Inference Tests"
failed=0
failed_names=()

for test_name in "${TESTS[@]}"; do
    log_file="${LOG_DIR}/${test_name}.log"
    echo -n "  ${test_name}... "
    if docker run --rm \
        -v "${MODEL_DIR}:/models:ro" \
        -e RAC_TEST_MODEL_DIR=/models \
        -e RAC_TEST_REQUIRE_MODELS=1 \
        "${DOCKER_IMAGE}" \
        bash -lc "cd '${CONTAINER_TEST_DIR}' && './${test_name}' --run-all" >"${log_file}" 2>&1; then
        echo -e "${GREEN}PASS${NC} (${log_file})"
    else
        echo -e "${RED}FAIL${NC} (${log_file})"
        failed=$((failed + 1))
        failed_names+=("${test_name}")
    fi
done

print_header "Real-Inference Summary"
if [[ "${failed}" -gt 0 ]]; then
    print_error "Failed tests: ${failed_names[*]}"
    echo "Logs: ${LOG_DIR}"
    exit 1
fi

echo -e "${GREEN}[OK] All required real-inference tests passed${NC}"
echo "Logs: ${LOG_DIR}"
