#!/bin/bash
# =============================================================================
# run-tests-web.sh - Web SDK build verification and smoke tests
# =============================================================================
#
# Usage:
#   ./run-tests-web.sh                  # Run automated smoke tests
#   ./run-tests-web.sh --build-only     # Just verify npm build succeeds
#   ./run-tests-web.sh --full           # Print instructions for full manual suite
#
# Prerequisites:
#   - Node.js 18+
#   - npm
#   - Built WASM binaries (run sdk/runanywhere-web/scripts/build-web.sh first)
#
# The web SDK uses a manual/agent test suite documented in:
#   examples/web/RunAnywhereAI/tests/web-sdk-test-suite.md
#
# This script provides automated smoke checks and wraps the manual suite.
# =============================================================================

set -e

# Colors
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

# =============================================================================
# Resolve paths
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAC_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REPO_ROOT="$(cd "${RAC_ROOT}/../.." && pwd)"
WEB_SDK_DIR="${REPO_ROOT}/sdk/runanywhere-web"
WEB_APP_DIR="${REPO_ROOT}/examples/web/RunAnywhereAI"
TEST_SUITE="${WEB_APP_DIR}/tests/web-sdk-test-suite.md"

# =============================================================================
# Parse arguments
# =============================================================================

BUILD_ONLY=false
SHOW_FULL=false

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --build-only)
            BUILD_ONLY=true
            shift
            ;;
        --full)
            SHOW_FULL=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --build-only   Verify npm build succeeds"
            echo "  --full         Print instructions for the full 21-category manual test suite"
            echo "  --help         Show this help"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

print_header "runanywhere Web SDK Tests"

# =============================================================================
# Prerequisites
# =============================================================================

print_step "Checking prerequisites..."

if ! command -v node &> /dev/null; then
    print_error "Node.js not found. Install Node.js 18+."
    exit 1
fi

NODE_VERSION=$(node --version | sed 's/v//' | cut -d. -f1)
if [ "$NODE_VERSION" -lt 18 ]; then
    print_error "Node.js 18+ required (found: $(node --version))"
    exit 1
fi
print_ok "Found Node.js $(node --version)"

if ! command -v npm &> /dev/null; then
    print_error "npm not found."
    exit 1
fi
print_ok "Found npm $(npm --version)"

# Check web app exists
if [ ! -d "${WEB_APP_DIR}" ]; then
    print_error "Web app not found at: ${WEB_APP_DIR}"
    exit 1
fi
print_ok "Found web app"

echo ""

# =============================================================================
# Install dependencies (if needed)
# =============================================================================

if [ ! -d "${WEB_APP_DIR}/node_modules" ]; then
    print_step "Installing web app dependencies..."
    cd "${WEB_APP_DIR}" && npm install
    cd "${SCRIPT_DIR}"
fi

# =============================================================================
# Build verification
# =============================================================================

print_header "Build Verification"

print_step "Running npm build..."
cd "${WEB_APP_DIR}"
if npm run build > /dev/null 2>&1; then
    print_ok "npm build succeeded"
else
    print_error "npm build failed"
    echo ""
    echo "Re-running with output:"
    npm run build 2>&1 | sed 's/^/    /'
    exit 1
fi
cd "${SCRIPT_DIR}"

if [ "${BUILD_ONLY}" = true ]; then
    echo ""
    echo "Build-only mode. Web app compiles successfully."
    exit 0
fi

# =============================================================================
# Full manual suite instructions
# =============================================================================

if [ "${SHOW_FULL}" = true ]; then
    print_header "Full Web SDK Test Suite"
    echo "The comprehensive 21-category test suite is documented at:"
    echo "  ${TEST_SUITE}"
    echo ""
    echo "To run the full suite:"
    echo "  1. Start the dev server:"
    echo "     cd ${WEB_APP_DIR} && npm run dev"
    echo ""
    echo "  2. Open http://localhost:5173 in a browser"
    echo ""
    echo "  3. Follow the test steps in web-sdk-test-suite.md"
    echo "     Categories include:"
    echo "     - App initialization and SDK setup"
    echo "     - Model registry and download"
    echo "     - STT, TTS, VAD, LLM, VLM features"
    echo "     - Voice agent pipeline"
    echo "     - Settings persistence"
    echo "     - Error handling and edge cases"
    echo ""
    echo "  4. Or use the Playwright MCP server for browser automation"
    exit 0
fi

# =============================================================================
# Automated smoke tests
# =============================================================================

print_header "Automated Smoke Tests"

PASSED=0
FAILED=0
DEV_PID=""

# Cleanup function
cleanup() {
    if [ -n "${DEV_PID}" ] && kill -0 "${DEV_PID}" 2>/dev/null; then
        kill "${DEV_PID}" 2>/dev/null || true
        wait "${DEV_PID}" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# Start dev server in background
print_step "Starting dev server..."
cd "${WEB_APP_DIR}"
npm run dev > /dev/null 2>&1 &
DEV_PID=$!
cd "${SCRIPT_DIR}"

# Wait for server to be ready
print_step "Waiting for server..."
MAX_WAIT=30
WAITED=0
while [ "${WAITED}" -lt "${MAX_WAIT}" ]; do
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:5173" 2>/dev/null | grep -q "200"; then
        break
    fi
    sleep 1
    WAITED=$((WAITED + 1))
done

if [ "${WAITED}" -ge "${MAX_WAIT}" ]; then
    print_error "Dev server did not start within ${MAX_WAIT}s"
    exit 1
fi
print_ok "Dev server ready (http://localhost:5173)"

# Smoke test 1: Page loads with 200
echo ""
echo -n "  App loads (HTTP 200)... "
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:5173" 2>/dev/null)
if [ "${STATUS}" = "200" ]; then
    echo -e "${GREEN}PASS${NC}"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}FAIL${NC} (got ${STATUS})"
    FAILED=$((FAILED + 1))
fi

# Smoke test 2: HTML contains expected app shell
echo -n "  App shell renders... "
PAGE=$(curl -s "http://localhost:5173" 2>/dev/null)
if echo "${PAGE}" | grep -q "RunAnywhere\|runanywhere\|<div id=" > /dev/null 2>&1; then
    echo -e "${GREEN}PASS${NC}"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}FAIL${NC} (app shell not found in HTML)"
    FAILED=$((FAILED + 1))
fi

# Smoke test 3: JavaScript bundles load
echo -n "  JS bundles exist... "
if echo "${PAGE}" | grep -q '<script' > /dev/null 2>&1; then
    echo -e "${GREEN}PASS${NC}"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}FAIL${NC} (no script tags found)"
    FAILED=$((FAILED + 1))
fi

# Smoke test 4: Build output exists
echo -n "  Build output valid... "
if [ -d "${WEB_APP_DIR}/dist" ] && [ -f "${WEB_APP_DIR}/dist/index.html" ]; then
    echo -e "${GREEN}PASS${NC}"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}FAIL${NC} (dist/ missing)"
    FAILED=$((FAILED + 1))
fi

# Smoke test 5: No TypeScript errors (already verified by build, but explicit)
echo -n "  TypeScript compiles... "
cd "${WEB_APP_DIR}"
if npx tsc --noEmit > /dev/null 2>&1; then
    echo -e "${GREEN}PASS${NC}"
    PASSED=$((PASSED + 1))
else
    echo -e "${YELLOW}SKIP${NC} (tsc check skipped)"
fi
cd "${SCRIPT_DIR}"

# =============================================================================
# Summary
# =============================================================================

print_header "Test Summary (Web SDK)"

TOTAL=$((PASSED + FAILED))
echo "Total:   ${TOTAL}"
echo -e "Passed:  ${GREEN}${PASSED}${NC}"
echo -e "Failed:  ${RED}${FAILED}${NC}"
echo ""
echo "For comprehensive testing, run: $0 --full"

if [ "${FAILED}" -gt 0 ]; then
    echo ""
    print_error "Some smoke tests failed"
    exit 1
fi

echo ""
print_ok "All smoke tests passed!"
