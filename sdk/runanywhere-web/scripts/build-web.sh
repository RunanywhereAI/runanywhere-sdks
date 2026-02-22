#!/bin/bash
# =============================================================================
# RunAnywhere Web SDK - Build Script
# =============================================================================
#
# Single entry point for building the Web SDK (WASM + TypeScript).
# Orchestrates Emscripten/CMake WASM compilation and npm TypeScript build.
#
# FIRST TIME SETUP:
#   cd sdk/runanywhere-web
#   ./scripts/build-web.sh --setup
#
# USAGE:
#   ./scripts/build-web.sh [command] [options]
#
# COMMANDS:
#   --setup             First-time setup: install emsdk, npm install, build all
#   --build-wasm        Build WASM module only (core racommons)
#   --build-ts          Build TypeScript only
#   --build-sherpa      Build sherpa-onnx WASM module (TTS/VAD)
#
# OPTIONS:
#   --llamacpp          Include llama.cpp LLM backend
#   --vlm               Include VLM (Vision Language Model) via llama.cpp mtmd
#   --webgpu            Enable WebGPU GPU acceleration
#   --all-backends      Enable WASM-compatible backends (llama.cpp + VLM)
#   --debug             Debug WASM build with assertions and safe heap
#   --pthreads          Enable pthreads (requires Cross-Origin Isolation)
#   --clean             Clean all build artifacts before building
#   --help              Show this help message
#
# EXAMPLES:
#   # First-time setup (downloads emsdk, builds everything)
#   ./scripts/build-web.sh --setup
#
#   # Build WASM with all backends + TypeScript (default)
#   ./scripts/build-web.sh
#
#   # Build WASM with specific backends
#   ./scripts/build-web.sh --build-wasm --llamacpp --vlm
#
#   # Build only TypeScript (after WASM is already built)
#   ./scripts/build-web.sh --build-ts
#
#   # Clean rebuild with all backends
#   ./scripts/build-web.sh --clean --all-backends
#
#   # Debug build for development
#   ./scripts/build-web.sh --debug --llamacpp
#
#   # Build sherpa-onnx WASM module separately
#   ./scripts/build-web.sh --build-sherpa
#
# =============================================================================

set -e

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEB_SDK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
WASM_DIR="${WEB_SDK_DIR}/wasm"
WASM_BUILD_SCRIPT="${WASM_DIR}/scripts/build.sh"
WASM_SETUP_SCRIPT="${WASM_DIR}/scripts/setup-emsdk.sh"
WASM_SHERPA_SCRIPT="${WASM_DIR}/scripts/build-sherpa-onnx.sh"
WASM_OUTPUT_DIR="${WEB_SDK_DIR}/packages/llamacpp/wasm"
TS_OUTPUT_DIR="${WEB_SDK_DIR}/packages/core/dist"

# Defaults
SETUP_MODE=false
BUILD_WASM=false
BUILD_TS=false
BUILD_SHERPA=false
CLEAN_BUILD=false
EXPLICIT_COMMAND=false

# WASM flags (passed through to wasm/scripts/build.sh)
WASM_FLAGS=()

# =============================================================================
# Colors & Logging
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_header() {
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════${NC}"
    echo -e "${GREEN} $1${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════${NC}"
}

log_step() {
    echo -e "${BLUE}==>${NC} $1"
}

log_info() {
    echo -e "${CYAN}[✓]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# =============================================================================
# Argument Parsing
# =============================================================================

show_help() {
    cat <<'HELPEOF'
RunAnywhere Web SDK — Build Script

FIRST TIME SETUP:
  cd sdk/runanywhere-web
  ./scripts/build-web.sh --setup

COMMANDS:
  --setup             First-time setup: install emsdk, npm install, build all
                      (CPU WASM + WebGPU WASM + Sherpa-ONNX + TypeScript)
  --build-wasm        Build WASM module only (core racommons)
  --build-ts          Build TypeScript only
  --build-sherpa      Build sherpa-onnx WASM module (STT/TTS/VAD)

OPTIONS:
  --llamacpp          Include llama.cpp LLM backend
  --vlm               Include VLM (Vision Language Model) via llama.cpp mtmd
  --webgpu            Enable WebGPU GPU acceleration
  --all-backends      Enable WASM-compatible backends (llama.cpp + VLM)
  --debug             Debug WASM build with assertions and safe heap
  --pthreads          Enable pthreads (requires Cross-Origin Isolation)
  --clean             Clean all build artifacts before building
  --help              Show this help message

EXAMPLES:
  ./scripts/build-web.sh --setup                    # First-time full build
  ./scripts/build-web.sh                            # Rebuild all (WASM + TS)
  ./scripts/build-web.sh --build-wasm --llamacpp    # WASM with llama.cpp only
  ./scripts/build-web.sh --build-ts                 # TypeScript only
  ./scripts/build-web.sh --build-sherpa             # Sherpa-ONNX only
  ./scripts/build-web.sh --clean --all-backends     # Clean rebuild
  ./scripts/build-web.sh --debug --llamacpp         # Debug build
HELPEOF
    exit 0
}

for arg in "$@"; do
    case $arg in
        --setup)
            SETUP_MODE=true
            EXPLICIT_COMMAND=true
            ;;
        --build-wasm)
            BUILD_WASM=true
            EXPLICIT_COMMAND=true
            ;;
        --build-ts)
            BUILD_TS=true
            EXPLICIT_COMMAND=true
            ;;
        --build-sherpa)
            BUILD_SHERPA=true
            EXPLICIT_COMMAND=true
            ;;
        --clean)
            CLEAN_BUILD=true
            ;;
        --debug)
            WASM_FLAGS+=("--debug")
            ;;
        --pthreads)
            WASM_FLAGS+=("--pthreads")
            ;;
        --llamacpp)
            WASM_FLAGS+=("--llamacpp")
            ;;
        --vlm)
            WASM_FLAGS+=("--vlm")
            ;;
        --webgpu)
            WASM_FLAGS+=("--webgpu")
            ;;
        --all-backends)
            WASM_FLAGS+=("--all-backends")
            ;;
        --help|-h)
            show_help
            ;;
        *)
            log_error "Unknown option: $arg"
            echo "Run with --help for usage information."
            exit 1
            ;;
    esac
done

# Default: build both WASM (all backends) and TypeScript
if [ "$EXPLICIT_COMMAND" = false ]; then
    BUILD_WASM=true
    BUILD_TS=true
    # Default to all backends when no explicit command is given
    if [ ${#WASM_FLAGS[@]} -eq 0 ]; then
        WASM_FLAGS+=("--all-backends")
    fi
fi

# =============================================================================
# Prerequisite Checks
# =============================================================================

check_prerequisites() {
    local missing=false

    log_step "Checking prerequisites..."

    if ! command -v node &> /dev/null; then
        log_error "node not found. Install Node.js 18+ from https://nodejs.org/"
        missing=true
    else
        log_info "Found node $(node --version)"
    fi

    if ! command -v npm &> /dev/null; then
        log_error "npm not found. Install Node.js 18+ from https://nodejs.org/"
        missing=true
    else
        log_info "Found npm $(npm --version)"
    fi

    if [ "$BUILD_WASM" = true ] || [ "$SETUP_MODE" = true ]; then
        if ! command -v cmake &> /dev/null; then
            log_error "cmake not found. Install with: brew install cmake (macOS) or apt install cmake (Linux)"
            missing=true
        else
            log_info "Found cmake $(cmake --version | head -1 | awk '{print $3}')"
        fi

        if ! command -v emcmake &> /dev/null; then
            if [ "$SETUP_MODE" = true ]; then
                log_warn "Emscripten not found. Will install during setup."
            else
                log_error "Emscripten not found. Run: ./scripts/build-web.sh --setup"
                log_error "  Or manually: source <emsdk-path>/emsdk_env.sh"
                missing=true
            fi
        else
            log_info "Found emcmake (Emscripten)"
        fi
    fi

    if [ "$missing" = true ] && [ "$SETUP_MODE" = false ]; then
        log_error "Missing prerequisites. Cannot continue."
        exit 1
    fi
}

# =============================================================================
# Build Functions
# =============================================================================

setup_emsdk() {
    log_header "Setting up Emscripten SDK"

    if command -v emcmake &> /dev/null; then
        log_info "Emscripten already available"
        return 0
    fi

    if [ ! -f "${WASM_SETUP_SCRIPT}" ]; then
        log_error "Setup script not found: ${WASM_SETUP_SCRIPT}"
        exit 1
    fi

    bash "${WASM_SETUP_SCRIPT}"

    # Try to activate emsdk for this session
    local emsdk_dir="${WEB_SDK_DIR}/emsdk"
    if [ -f "${emsdk_dir}/emsdk_env.sh" ]; then
        log_step "Activating emsdk for this session..."
        source "${emsdk_dir}/emsdk_env.sh"
    else
        log_warn "emsdk installed but not in expected location."
        log_warn "Activate manually: source <emsdk-path>/emsdk_env.sh"
    fi
}

npm_install() {
    log_header "Installing npm Dependencies"

    cd "${WEB_SDK_DIR}"
    log_step "Running npm install..."
    npm install
    log_info "npm dependencies installed"
}

clean_all() {
    log_header "Cleaning Build Artifacts"

    # Clean WASM build directories
    if [ -d "${WASM_DIR}/build" ]; then
        log_step "Removing wasm/build/"
        rm -rf "${WASM_DIR}/build"
    fi
    if [ -d "${WASM_DIR}/build-webgpu" ]; then
        log_step "Removing wasm/build-webgpu/"
        rm -rf "${WASM_DIR}/build-webgpu"
    fi
    if [ -d "${WASM_DIR}/build-sherpa-onnx" ]; then
        log_step "Removing wasm/build-sherpa-onnx/"
        rm -rf "${WASM_DIR}/build-sherpa-onnx"
    fi

    # Clean WASM output (llamacpp)
    if [ -d "${WASM_OUTPUT_DIR}" ]; then
        log_step "Cleaning WASM outputs (packages/llamacpp/wasm/)"
        rm -f "${WASM_OUTPUT_DIR}"/*.wasm "${WASM_OUTPUT_DIR}"/*.js 2>/dev/null || true
    fi

    # Clean sherpa-onnx WASM output
    local sherpa_output="${WEB_SDK_DIR}/packages/onnx/wasm/sherpa"
    if [ -d "${sherpa_output}" ]; then
        log_step "Cleaning sherpa-onnx outputs (packages/onnx/wasm/sherpa/)"
        rm -f "${sherpa_output}"/sherpa-onnx.wasm "${sherpa_output}"/sherpa-onnx-glue.js 2>/dev/null || true
    fi

    # Clean TypeScript output for all packages
    for pkg_dist in "${WEB_SDK_DIR}/packages/core/dist" "${WEB_SDK_DIR}/packages/llamacpp/dist" "${WEB_SDK_DIR}/packages/onnx/dist"; do
        if [ -d "${pkg_dist}" ]; then
            log_step "Removing ${pkg_dist#"${WEB_SDK_DIR}"/}"
            rm -rf "${pkg_dist}"
        fi
    done

    log_info "All build artifacts cleaned"
}

build_wasm() {
    log_header "Building WASM Module"

    if [ ! -f "${WASM_BUILD_SCRIPT}" ]; then
        log_error "WASM build script not found: ${WASM_BUILD_SCRIPT}"
        exit 1
    fi

    local flags=("${WASM_FLAGS[@]}")
    if [ "$CLEAN_BUILD" = true ]; then
        flags+=("--clean")
    fi

    log_step "Running wasm/scripts/build.sh ${flags[*]}"
    bash "${WASM_BUILD_SCRIPT}" "${flags[@]}"

    # Verify output — check for either CPU or WebGPU variant
    if [ -f "${WASM_OUTPUT_DIR}/racommons-llamacpp.wasm" ] || [ -f "${WASM_OUTPUT_DIR}/racommons-llamacpp-webgpu.wasm" ]; then
        log_info "WASM build successful"
    else
        log_error "WASM build failed - no racommons-llamacpp*.wasm found in ${WASM_OUTPUT_DIR}"
        exit 1
    fi
}

build_typescript() {
    log_header "Building TypeScript"

    cd "${WEB_SDK_DIR}"

    # Ensure dependencies are installed
    if [ ! -d "node_modules" ]; then
        log_step "Dependencies not found, running npm install..."
        npm install
    fi

    log_step "Compiling TypeScript..."
    npm run build:ts

    # Verify output for all packages
    local ts_ok=true
    if [ ! -d "${TS_OUTPUT_DIR}" ]; then
        log_error "TypeScript build failed - core dist/ not found"
        ts_ok=false
    fi
    if [ ! -d "${WEB_SDK_DIR}/packages/llamacpp/dist" ]; then
        log_warn "llamacpp dist/ not found — may not have been built"
    fi
    if [ ! -d "${WEB_SDK_DIR}/packages/onnx/dist" ]; then
        log_warn "onnx dist/ not found — may not have been built"
    fi
    if [ "$ts_ok" = false ]; then
        exit 1
    fi
    log_info "TypeScript build successful"
}

build_sherpa() {
    log_header "Building Sherpa-ONNX WASM Module"

    if [ ! -f "${WASM_SHERPA_SCRIPT}" ]; then
        log_error "Sherpa build script not found: ${WASM_SHERPA_SCRIPT}"
        exit 1
    fi

    local flags=()
    if [ "$CLEAN_BUILD" = true ]; then
        flags+=("--clean")
    fi

    log_step "Running wasm/scripts/build-sherpa-onnx.sh ${flags[*]}"
    bash "${WASM_SHERPA_SCRIPT}" "${flags[@]}"

    log_info "Sherpa-ONNX WASM build complete"
}

# =============================================================================
# Build Summary
# =============================================================================

print_summary() {
    log_header "Build Complete"

    echo ""
    echo "  Artifacts:"

    # WASM artifacts (llamacpp backend)
    if [ -f "${WASM_OUTPUT_DIR}/racommons-llamacpp.wasm" ]; then
        local wasm_size
        wasm_size=$(du -h "${WASM_OUTPUT_DIR}/racommons-llamacpp.wasm" | cut -f1)
        echo "    racommons-llamacpp.wasm:       ${wasm_size}"
    fi
    if [ -f "${WASM_OUTPUT_DIR}/racommons-llamacpp.js" ]; then
        local js_size
        js_size=$(du -h "${WASM_OUTPUT_DIR}/racommons-llamacpp.js" | cut -f1)
        echo "    racommons-llamacpp.js:         ${js_size}"
    fi
    if [ -f "${WASM_OUTPUT_DIR}/racommons-llamacpp-webgpu.wasm" ]; then
        local webgpu_size
        webgpu_size=$(du -h "${WASM_OUTPUT_DIR}/racommons-llamacpp-webgpu.wasm" | cut -f1)
        echo "    racommons-llamacpp-webgpu.wasm: ${webgpu_size}"
    fi
    local sherpa_wasm="${WEB_SDK_DIR}/packages/onnx/wasm/sherpa/sherpa-onnx.wasm"
    if [ -f "${sherpa_wasm}" ]; then
        local sherpa_size
        sherpa_size=$(du -h "${sherpa_wasm}" | cut -f1)
        echo "    sherpa-onnx.wasm:              ${sherpa_size}"
    else
        echo "    sherpa-onnx.wasm:              (not built — STT/TTS/VAD unavailable)"
    fi

    # TypeScript artifacts
    if [ -d "${TS_OUTPUT_DIR}" ]; then
        local ts_files
        ts_files=$(find "${TS_OUTPUT_DIR}" -name "*.js" -o -name "*.d.ts" | wc -l | tr -d ' ')
        echo "    TypeScript dist/:     ${ts_files} files"
    fi

    echo ""
    echo "  Output locations:"
    echo "    LLM/VLM WASM:   packages/llamacpp/wasm/"
    echo "    STT/TTS/VAD:    packages/onnx/wasm/sherpa/"
    echo "    TypeScript:     packages/core/dist/ + packages/llamacpp/dist/ + packages/onnx/dist/"
    echo ""

    if [ "$SETUP_MODE" = true ]; then
        echo "  Next steps — run the example app:"
        echo "    cd ../../examples/web/RunAnywhereAI"
        echo "    npm install"
        echo "    npm run dev"
        echo ""
        echo "  Rebuild commands:"
        echo "    WASM only:        ./scripts/build-web.sh --build-wasm --all-backends"
        echo "    TypeScript only:  ./scripts/build-web.sh --build-ts"
        echo "    Sherpa-ONNX only: ./scripts/build-web.sh --build-sherpa"
        echo ""
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    log_header "RunAnywhere Web SDK - Build"
    echo ""
    echo "  Mode:       $([ "$SETUP_MODE" = true ] && echo "setup" || echo "build")"
    echo "  WASM:       $([ "$BUILD_WASM" = true ] && echo "yes" || echo "skip")"
    echo "  TypeScript: $([ "$BUILD_TS" = true ] && echo "yes" || echo "skip")"
    echo "  Sherpa:     $([ "$BUILD_SHERPA" = true ] && echo "yes" || echo "skip")"
    echo "  Clean:      $([ "$CLEAN_BUILD" = true ] && echo "yes" || echo "no")"
    if [ ${#WASM_FLAGS[@]} -gt 0 ]; then
        echo "  WASM flags: ${WASM_FLAGS[*]}"
    fi
    echo ""

    # Check prerequisites
    check_prerequisites

    # Clean if requested
    if [ "$CLEAN_BUILD" = true ]; then
        clean_all
    fi

    # Setup mode: full first-time setup
    if [ "$SETUP_MODE" = true ]; then
        setup_emsdk
        npm_install

        # Build WASM with all backends by default during setup
        if [ ${#WASM_FLAGS[@]} -eq 0 ]; then
            WASM_FLAGS+=("--all-backends")
        fi

        # Build CPU variant
        build_wasm

        # Build WebGPU variant (separate build dir, separate output binary)
        log_header "Building WebGPU WASM Variant"
        local webgpu_flags=("${WASM_FLAGS[@]}" "--webgpu")
        if [ "$CLEAN_BUILD" = true ]; then
            webgpu_flags+=("--clean")
        fi
        log_step "Running wasm/scripts/build.sh ${webgpu_flags[*]}"
        bash "${WASM_BUILD_SCRIPT}" "${webgpu_flags[@]}"
        if [ -f "${WASM_OUTPUT_DIR}/racommons-llamacpp-webgpu.wasm" ]; then
            log_info "WebGPU WASM build successful"
        else
            log_warn "WebGPU WASM build failed — app will fall back to CPU"
        fi

        # Build sherpa-onnx WASM (STT/TTS/VAD). Non-fatal — LLM/VLM still work without it.
        if [ -f "${WASM_SHERPA_SCRIPT}" ]; then
            log_header "Building Sherpa-ONNX WASM Module (STT/TTS/VAD)"
            if bash "${WASM_SHERPA_SCRIPT}"; then
                log_info "Sherpa-ONNX WASM build successful"
            else
                log_warn "Sherpa-ONNX build failed — STT/TTS/VAD will not be available"
                log_warn "You can retry later with: ./scripts/build-web.sh --build-sherpa"
            fi
        else
            log_warn "Sherpa-ONNX build script not found — skipping STT/TTS/VAD build"
        fi

        build_typescript
        print_summary
        return 0
    fi

    # Individual build commands
    if [ "$BUILD_WASM" = true ]; then
        build_wasm

        # When building with default flags (--all-backends), also build WebGPU variant
        # so both CPU fallback and GPU-accelerated binaries are available.
        local has_webgpu=false
        for f in "${WASM_FLAGS[@]}"; do
            [[ "$f" == "--webgpu" ]] && has_webgpu=true
        done
        if [ "$has_webgpu" = false ]; then
            log_header "Building WebGPU WASM Variant"
            local webgpu_flags=("${WASM_FLAGS[@]}" "--webgpu")
            if [ "$CLEAN_BUILD" = true ]; then
                webgpu_flags+=("--clean")
            fi
            log_step "Running wasm/scripts/build.sh ${webgpu_flags[*]}"
            if bash "${WASM_BUILD_SCRIPT}" "${webgpu_flags[@]}"; then
                if [ -f "${WASM_OUTPUT_DIR}/racommons-llamacpp-webgpu.wasm" ]; then
                    log_info "WebGPU WASM build successful"
                else
                    log_warn "WebGPU WASM build produced no output — app will fall back to CPU"
                fi
            else
                log_warn "WebGPU WASM build failed — app will fall back to CPU"
            fi
        fi
    fi

    if [ "$BUILD_SHERPA" = true ]; then
        build_sherpa
    fi

    if [ "$BUILD_TS" = true ]; then
        build_typescript
    fi

    print_summary
}

main "$@"
