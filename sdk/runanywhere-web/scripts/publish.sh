#!/bin/bash
# =============================================================================
# RunAnywhere Web SDK — Publish to npm
# =============================================================================
#
# Builds all packages, verifies artifacts, and publishes to npm in the
# correct dependency order (core -> llamacpp, onnx).
#
# USAGE:
#   ./scripts/publish.sh [options]
#
# OPTIONS:
#   --dry-run         Run npm publish --dry-run (no actual publish)
#   --skip-build      Skip the TypeScript build (use existing artifacts)
#   --otp <code>      Pass an npm OTP code for 2FA
#   --tag <tag>       npm dist-tag (default: beta)
#   --help            Show this help message
#
# EXAMPLES:
#   ./scripts/publish.sh --dry-run              # Verify everything without publishing
#   ./scripts/publish.sh --otp 123456           # Publish with 2FA code
#   ./scripts/publish.sh --tag latest           # Publish as @latest
#   ./scripts/publish.sh --skip-build --dry-run # Quick dry-run with existing build
# Keeping this manual process for now, will be adding it to ci/cd later.
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEB_SDK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

DRY_RUN=false
SKIP_BUILD=false
OTP=""
DIST_TAG="beta"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_header() { echo -e "\n${GREEN}═══════════════════════════════════════════${NC}\n${GREEN} $1${NC}\n${GREEN}═══════════════════════════════════════════${NC}"; }
log_step()   { echo -e "${BLUE}==>${NC} $1"; }
log_info()   { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn()   { echo -e "${YELLOW}[!]${NC} $1"; }
log_error()  { echo -e "${RED}[✗]${NC} $1"; }

show_help() {
    head -27 "$0" | tail -20 | sed 's/^# \?//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)    DRY_RUN=true; shift ;;
        --skip-build) SKIP_BUILD=true; shift ;;
        --otp)        OTP="$2"; shift 2 ;;
        --tag)        DIST_TAG="$2"; shift 2 ;;
        --help|-h)    show_help ;;
        *)            log_error "Unknown option: $1"; exit 1 ;;
    esac
done

cd "${WEB_SDK_DIR}"

CORE_VERSION=$(node -p "require('./packages/core/package.json').version")
LLAMACPP_VERSION=$(node -p "require('./packages/llamacpp/package.json').version")
ONNX_VERSION=$(node -p "require('./packages/onnx/package.json').version")

log_header "RunAnywhere Web SDK — Publish"
echo ""
echo "  Packages:"
echo "    @runanywhere/web           v${CORE_VERSION}"
echo "    @runanywhere/web-llamacpp  v${LLAMACPP_VERSION}"
echo "    @runanywhere/web-onnx      v${ONNX_VERSION}"
echo ""
echo "  Options:"
echo "    Dry run:    ${DRY_RUN}"
echo "    Skip build: ${SKIP_BUILD}"
echo "    Dist tag:   ${DIST_TAG}"
echo ""

if [ "$CORE_VERSION" != "$LLAMACPP_VERSION" ] || [ "$CORE_VERSION" != "$ONNX_VERSION" ]; then
    log_warn "Version mismatch detected!"
    log_warn "  core:     ${CORE_VERSION}"
    log_warn "  llamacpp: ${LLAMACPP_VERSION}"
    log_warn "  onnx:     ${ONNX_VERSION}"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] || exit 1
fi

# =============================================================================
# Step 1: Build
# =============================================================================

if [ "$SKIP_BUILD" = false ]; then
    log_header "Step 1: Build TypeScript (all packages)"
    npm run build:ts
    log_info "TypeScript build complete"
else
    log_header "Step 1: Build (skipped)"
fi

# =============================================================================
# Step 2: Verify Artifacts
# =============================================================================

log_header "Step 2: Verify Artifacts"

MISSING=false

check_file() {
    local path="$1"
    local required="$2"
    if [ -f "$path" ]; then
        local size
        size=$(du -h "$path" | cut -f1)
        log_info "${path} (${size})"
    elif [ "$required" = true ]; then
        log_error "${path} MISSING"
        MISSING=true
    else
        log_warn "${path} missing (optional)"
    fi
}

check_dir() {
    local path="$1"
    if [ -d "$path" ]; then
        log_info "${path}/"
    else
        log_error "${path}/ MISSING"
        MISSING=true
    fi
}

log_step "Core (@runanywhere/web)"
check_dir  "packages/core/dist"
check_file "packages/core/README.md" false

log_step "LlamaCpp (@runanywhere/web-llamacpp)"
check_dir  "packages/llamacpp/dist"
check_file "packages/llamacpp/wasm/racommons-llamacpp.wasm" true
check_file "packages/llamacpp/wasm/racommons-llamacpp.js" true
check_file "packages/llamacpp/wasm/racommons-llamacpp-webgpu.wasm" false
check_file "packages/llamacpp/wasm/racommons-llamacpp-webgpu.js" false
check_file "packages/llamacpp/README.md" false

log_step "ONNX (@runanywhere/web-onnx)"
check_dir  "packages/onnx/dist"
check_file "packages/onnx/wasm/sherpa/sherpa-onnx.wasm" true
check_file "packages/onnx/wasm/sherpa/sherpa-onnx-asr.js" true
check_file "packages/onnx/wasm/sherpa/sherpa-onnx-tts.js" true
check_file "packages/onnx/wasm/sherpa/sherpa-onnx-vad.js" true
check_file "packages/onnx/wasm/sherpa/sherpa-onnx-glue.js" true
check_file "packages/onnx/README.md" false

if [ "$MISSING" = true ]; then
    echo ""
    log_error "Required artifacts missing. Build first:"
    log_error "  ./scripts/build-web.sh         (WASM + TypeScript)"
    log_error "  ./scripts/build-web.sh --setup  (first time)"
    exit 1
fi

log_info "All required artifacts present"

# =============================================================================
# Step 3: Pack preview
# =============================================================================

log_header "Step 3: Package Contents"

pkg_display_name() {
    if [ "$1" = "core" ]; then echo "@runanywhere/web"; else echo "@runanywhere/web-${1}"; fi
}

for pkg in core llamacpp onnx; do
    log_step "$(pkg_display_name "$pkg"):"
    cd "${WEB_SDK_DIR}/packages/${pkg}"
    npm pack --dry-run 2>&1 | tail -5
    cd "${WEB_SDK_DIR}"
    echo ""
done

# =============================================================================
# Step 4: Publish
# =============================================================================

log_header "Step 4: Publish"

PUBLISH_FLAGS="--tag ${DIST_TAG}"
if [ "$DRY_RUN" = true ]; then
    PUBLISH_FLAGS+=" --dry-run"
fi
if [ -n "$OTP" ]; then
    PUBLISH_FLAGS+=" --otp ${OTP}"
fi

for pkg in core llamacpp onnx; do
    name="$(pkg_display_name "$pkg")"
    log_step "Publishing ${name}..."
    cd "${WEB_SDK_DIR}/packages/${pkg}"

    # shellcheck disable=SC2086
    if npm publish ${PUBLISH_FLAGS}; then
        log_info "${name} published"
    else
        log_error "${name} publish failed"
        exit 1
    fi

    cd "${WEB_SDK_DIR}"
done

# =============================================================================
# Done
# =============================================================================

log_header "Done"
if [ "$DRY_RUN" = true ]; then
    echo "  Dry run complete — no packages were published."
    echo "  Remove --dry-run to publish for real."
else
    echo "  Published:"
    echo "    @runanywhere/web@${CORE_VERSION}"
    echo "    @runanywhere/web-llamacpp@${LLAMACPP_VERSION}"
    echo "    @runanywhere/web-onnx@${ONNX_VERSION}"
    echo ""
    echo "  Dist tag: ${DIST_TAG}"
fi
echo ""
