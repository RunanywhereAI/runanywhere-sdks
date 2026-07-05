#!/bin/bash
# Unified test orchestrator for all platforms. See --help for options.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step() {
    echo -e "${YELLOW}-> $1${NC}"
}

print_ok() {
    echo -e "${GREEN}[OK] $1${NC}"
}

print_error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

print_header() {
    echo ""
    echo -e "${BLUE}==========================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}==========================================${NC}"
    echo ""
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PLATFORMS=""
BUILD_ONLY=false

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --platforms)
            PLATFORMS="$2"
            shift 2
            ;;
        --build-only)
            BUILD_ONLY=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --platforms P    Comma-separated list: macos,linux,android,ios,web"
            echo "  --build-only     Compile verification only (no test execution)"
            echo "  --help           Show this help"
            echo ""
            echo "Environment:"
            echo "  RAC_TEST_MODEL_DIR   Override model directory for tests"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

print_header "Platform Detection"

HAS_MACOS=false
HAS_LINUX=false
HAS_ANDROID=false
HAS_IOS=false
HAS_WEB=false

if [ "$(uname)" = "Darwin" ]; then
    HAS_MACOS=true
    print_ok "macOS: available (native)"
fi

if command -v docker &> /dev/null; then
    HAS_LINUX=true
    print_ok "Linux: available (Docker)"
else
    echo -e "  ${YELLOW}[--]${NC} Linux: Docker not found"
fi

NDK_FOUND=false
if [ -n "${ANDROID_NDK_HOME:-}" ] && [ -d "${ANDROID_NDK_HOME:-}" ]; then
    NDK_FOUND=true
elif [ -d "$HOME/Library/Android/sdk/ndk" ]; then
    NDK_FOUND=true
elif [ -d "$HOME/Android/Sdk/ndk" ]; then
    NDK_FOUND=true
fi
if [ "${NDK_FOUND}" = true ]; then
    HAS_ANDROID=true
    print_ok "Android: available (NDK found)"
else
    echo -e "  ${YELLOW}[--]${NC} Android: NDK not found"
fi

if command -v xcodebuild &> /dev/null; then
    HAS_IOS=true
    print_ok "iOS: available (Xcode)"
else
    echo -e "  ${YELLOW}[--]${NC} iOS: Xcode not found"
fi

if command -v node &> /dev/null; then
    HAS_WEB=true
    print_ok "Web: available (Node.js $(node --version))"
else
    echo -e "  ${YELLOW}[--]${NC} Web: Node.js not found"
fi

RUN_MACOS=false
RUN_LINUX=false
RUN_ANDROID=false
RUN_IOS=false
RUN_WEB=false

if [ -n "${PLATFORMS}" ]; then
    IFS=',' read -ra PLATFORM_ARRAY <<< "${PLATFORMS}"
    for platform in "${PLATFORM_ARRAY[@]}"; do
        case "${platform}" in
            macos)   RUN_MACOS=true ;;
            linux)   RUN_LINUX=true ;;
            android) RUN_ANDROID=true ;;
            ios)     RUN_IOS=true ;;
            web)     RUN_WEB=true ;;
            *)       print_error "Unknown platform: ${platform}"; exit 1 ;;
        esac
    done
else
    RUN_MACOS=${HAS_MACOS}
    RUN_LINUX=${HAS_LINUX}
    RUN_ANDROID=${HAS_ANDROID}
    RUN_IOS=${HAS_IOS}
    RUN_WEB=${HAS_WEB}
fi

PLATFORM_PASSED=0
PLATFORM_FAILED=0
PLATFORM_SKIPPED=0
RESULTS=""

run_platform() {
    local name="$1"
    local script="$2"
    shift 2
    local args=("$@")

    echo ""
    echo -e "${BLUE}--- ${name} ---${NC}"

    if "${script}" "${args[@]}"; then
        PLATFORM_PASSED=$((PLATFORM_PASSED + 1))
        RESULTS="${RESULTS}\n  ${GREEN}[PASS]${NC} ${name}"
    else
        PLATFORM_FAILED=$((PLATFORM_FAILED + 1))
        RESULTS="${RESULTS}\n  ${RED}[FAIL]${NC} ${name}"
    fi
}

skip_platform() {
    local name="$1"
    local reason="$2"
    PLATFORM_SKIPPED=$((PLATFORM_SKIPPED + 1))
    RESULTS="${RESULTS}\n  ${YELLOW}[SKIP]${NC} ${name} (${reason})"
}

if [ "${RUN_MACOS}" = true ]; then
    if [ "${HAS_MACOS}" = true ]; then
        if [ "${BUILD_ONLY}" = true ]; then
            run_platform "macOS" "${SCRIPT_DIR}/run-tests.sh" --build-only
        else
            run_platform "macOS" "${SCRIPT_DIR}/run-tests.sh"
        fi
    else
        skip_platform "macOS" "not on macOS"
    fi
fi

if [ "${RUN_LINUX}" = true ]; then
    if [ "${HAS_LINUX}" = true ]; then
        if [ "${BUILD_ONLY}" = true ]; then
            run_platform "Linux (Docker)" "${SCRIPT_DIR}/run-tests-linux.sh" --build-only
        else
            run_platform "Linux (Docker)" "${SCRIPT_DIR}/run-tests-linux.sh"
        fi
    else
        skip_platform "Linux" "Docker not found"
    fi
fi

if [ "${RUN_ANDROID}" = true ]; then
    if [ "${HAS_ANDROID}" = true ]; then
        # Android always does build-only unless device is connected
        run_platform "Android (NDK)" "${SCRIPT_DIR}/run-tests-android.sh" --build-only
    else
        skip_platform "Android" "NDK not found"
    fi
fi

if [ "${RUN_IOS}" = true ]; then
    if [ "${HAS_IOS}" = true ]; then
        if [ "${BUILD_ONLY}" = true ]; then
            run_platform "iOS (Simulator)" "${SCRIPT_DIR}/run-tests-ios.sh" --build-only
        else
            run_platform "iOS (Simulator + macOS)" "${SCRIPT_DIR}/run-tests-ios.sh" --run
        fi
    else
        skip_platform "iOS" "Xcode not found"
    fi
fi

if [ "${RUN_WEB}" = true ]; then
    if [ "${HAS_WEB}" = true ]; then
        if [ "${BUILD_ONLY}" = true ]; then
            run_platform "Web SDK" "${SCRIPT_DIR}/run-tests-web.sh" --build-only
        else
            run_platform "Web SDK" "${SCRIPT_DIR}/run-tests-web.sh"
        fi
    else
        skip_platform "Web" "Node.js not found"
    fi
fi

print_header "Unified Test Summary"

TOTAL=$((PLATFORM_PASSED + PLATFORM_FAILED + PLATFORM_SKIPPED))
echo "Platforms tested: ${TOTAL}"
echo -e "Passed:  ${GREEN}${PLATFORM_PASSED}${NC}"
echo -e "Failed:  ${RED}${PLATFORM_FAILED}${NC}"
echo -e "Skipped: ${YELLOW}${PLATFORM_SKIPPED}${NC}"
echo ""
echo "Results:"
echo -e "${RESULTS}"

if [ "${PLATFORM_FAILED}" -gt 0 ]; then
    echo ""
    print_error "Some platforms failed"
    exit 1
fi

echo ""
print_ok "All platform tests passed!"
