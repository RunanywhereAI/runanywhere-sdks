#!/bin/bash
# =============================================================================
# RunAnywhere Swift SDK - iOS Build Script
# =============================================================================
#
# Builds the Swift SDK for iOS.
#
# USAGE:
#   ./build-ios.sh [options]
#
# OPTIONS:
#   --install-frameworks    Copy XCFrameworks from commons/core to Binaries/
#   --sync-headers          Sync C headers from commons to CRACommons/include/
#   --clean                 Clean build artifacts before building
#   --release               Build in release mode (default: debug)
#   --help                  Show this help message
#
# PREREQUISITES:
#   - XCFrameworks must exist in:
#     - ../runanywhere-commons/dist/ (RACommons)
#     - ../../runanywhere-core/dist/ (RunAnywhereCore, RABackendLlamaCPP, RABackendONNX, RABackendWhisperCPP)
#     - ../../runanywhere-core/third_party/onnxruntime-ios/ (onnxruntime)
#
# NOTE: LlamaCPP, ONNX, and WhisperCPP backends are now built from runanywhere-core,
# not from runanywhere-commons. The backends directly export RAC APIs.
#
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WORKSPACE_ROOT="$(cd "${PROJECT_ROOT}/../../.." && pwd)"

# Source paths
COMMONS_DIR="$PROJECT_ROOT/../runanywhere-commons"
CORE_DIR="$WORKSPACE_ROOT/runanywhere-core"

# Destination paths
BINARIES_DIR="$PROJECT_ROOT/Binaries"
HEADERS_DIR="$PROJECT_ROOT/Sources/CRACommons/include"

# Build configuration
BUILD_MODE="debug"
INSTALL_FRAMEWORKS=false
SYNC_HEADERS=false
CLEAN_BUILD=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()   { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn()   { echo -e "${YELLOW}[!]${NC} $1"; }
log_error()  { echo -e "${RED}[✗]${NC} $1"; }
log_step()   { echo -e "${BLUE}==>${NC} $1"; }
log_header() { echo -e "\n${GREEN}═══════════════════════════════════════════${NC}"; echo -e "${GREEN} $1${NC}"; echo -e "${GREEN}═══════════════════════════════════════════${NC}"; }

show_help() {
    head -25 "$0" | tail -20
    exit 0
}

# =============================================================================
# Parse Arguments
# =============================================================================

for arg in "$@"; do
    case "$arg" in
        --install-frameworks)
            INSTALL_FRAMEWORKS=true
            ;;
        --sync-headers)
            SYNC_HEADERS=true
            ;;
        --clean)
            CLEAN_BUILD=true
            ;;
        --release)
            BUILD_MODE="release"
            ;;
        --help|-h)
            show_help
            ;;
    esac
done

# =============================================================================
# Install XCFrameworks
# =============================================================================

install_frameworks() {
    log_header "Installing XCFrameworks"

    mkdir -p "$BINARIES_DIR"

    # From runanywhere-commons (RACommons only - backends moved to core)
    local commons_src="$COMMONS_DIR/dist/RACommons.xcframework"
    if [[ -d "$commons_src" ]]; then
        log_step "Installing RACommons.xcframework"
        rm -rf "$BINARIES_DIR/RACommons.xcframework"
        cp -r "$commons_src" "$BINARIES_DIR/"
        log_info "  RACommons.xcframework"
    else
        log_warn "  RACommons.xcframework not found at $commons_src"
    fi

    # From runanywhere-core (core + RAC backends)
    # NOTE: LlamaCPP, ONNX, and WhisperCPP backends are now built as part of core
    local core_src="$CORE_DIR/dist/RunAnywhereCore.xcframework"
    if [[ -d "$core_src" ]]; then
        log_step "Installing RunAnywhereCore.xcframework"
        rm -rf "$BINARIES_DIR/RunAnywhereCore.xcframework"
        cp -r "$core_src" "$BINARIES_DIR/"
        log_info "  RunAnywhereCore.xcframework"
    else
        log_warn "  RunAnywhereCore.xcframework not found at $core_src"
    fi

    # RAC Backend frameworks from runanywhere-core
    for framework in RABackendLlamaCPP RABackendONNX RABackendWhisperCPP; do
        local src="$CORE_DIR/dist/${framework}.xcframework"
        if [[ -d "$src" ]]; then
            log_step "Installing ${framework}.xcframework"
            rm -rf "$BINARIES_DIR/${framework}.xcframework"
            cp -r "$src" "$BINARIES_DIR/"
            log_info "  ${framework}.xcframework"
        else
            log_warn "  ${framework}.xcframework not found at $src (optional)"
        fi
    done

    # onnxruntime (vendored dependency)
    local onnx_src="$CORE_DIR/third_party/onnxruntime-ios/onnxruntime.xcframework"
    if [[ -d "$onnx_src" ]]; then
        log_step "Installing onnxruntime.xcframework"
        rm -rf "$BINARIES_DIR/onnxruntime.xcframework"
        cp -r "$onnx_src" "$BINARIES_DIR/"
        log_info "  onnxruntime.xcframework"
    else
        log_warn "  onnxruntime.xcframework not found at $onnx_src"
    fi

    log_info "Frameworks installed to: $BINARIES_DIR"
}

# =============================================================================
# Sync Headers
# =============================================================================

sync_headers() {
    log_header "Syncing Headers"

    mkdir -p "$HEADERS_DIR"

    # Sync RAC type headers from runanywhere-commons
    local commons_headers="$COMMONS_DIR/include/rac"
    if [[ -d "$commons_headers" ]]; then
        log_step "Copying RAC type headers from commons"
        find "$commons_headers" -name "*.h" -type f | while read -r header; do
            local filename=$(basename "$header")
            # Convert nested includes to flat includes
            sed 's|#include "rac/.*/\([^/"]*\)"|#include "\1"|g' "$header" > "$HEADERS_DIR/$filename"
        done
    else
        log_warn "Commons headers not found at: $commons_headers"
    fi

    # Sync RAC backend API headers from runanywhere-core
    local core_headers="$CORE_DIR/include"
    if [[ -d "$core_headers" ]]; then
        log_step "Copying RAC backend headers from core"
        find "$core_headers" -name "rac_*.h" -type f | while read -r header; do
            local filename=$(basename "$header")
            # Convert nested includes to flat includes
            sed 's|#include "rac/.*/\([^/"]*\)"|#include "\1"|g' "$header" > "$HEADERS_DIR/$filename"
        done
    else
        log_warn "Core headers not found at: $core_headers"
    fi

    local count=$(find "$HEADERS_DIR" -name "*.h" | wc -l | tr -d ' ')
    log_info "Synced $count headers to: $HEADERS_DIR"
}

# =============================================================================
# Build Swift SDK
# =============================================================================

build_sdk() {
    log_header "Building Swift SDK"

    cd "$PROJECT_ROOT"

    if $CLEAN_BUILD; then
        log_step "Cleaning build..."
        rm -rf .build/
    fi

    log_step "Running swift build ($BUILD_MODE)..."

    local BUILD_FLAGS="-Xswiftc -suppress-warnings"
    if [[ "$BUILD_MODE" == "release" ]]; then
        BUILD_FLAGS="$BUILD_FLAGS -c release"
    fi

    if swift build $BUILD_FLAGS; then
        log_info "Swift SDK built successfully"
    else
        log_error "Swift SDK build failed"
        exit 1
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    log_header "RunAnywhere Swift SDK - iOS Build"
    echo "Project: $PROJECT_ROOT"
    echo "Mode: $BUILD_MODE"
    echo ""

    # Install frameworks if requested
    $INSTALL_FRAMEWORKS && install_frameworks

    # Sync headers if requested
    $SYNC_HEADERS && sync_headers

    # Build the SDK
    build_sdk

    log_header "Build Complete!"

    # Show framework status
    echo "Binaries directory: $BINARIES_DIR"
    if [[ -d "$BINARIES_DIR" ]]; then
        ls -la "$BINARIES_DIR"/*.xcframework 2>/dev/null | while read -r line; do
            echo "  $line"
        done
    fi
}

main "$@"
