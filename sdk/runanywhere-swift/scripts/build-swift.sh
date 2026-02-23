#!/bin/bash
# =============================================================================
# RunAnywhere Swift SDK - Build Script
# =============================================================================
#
# Single entry point for building the Swift SDK.
#
# FIRST TIME SETUP:
#   cd sdk/runanywhere-swift
#   ./scripts/build-swift.sh --setup
#
# USAGE:
#   ./scripts/build-swift.sh [command]
#
# COMMANDS:
#   --setup             First-time setup: downloads deps, builds commons, installs frameworks
#   --local             Use local frameworks (install from commons/dist to Binaries/)
#   --remote            Use remote frameworks from GitHub releases
#   --build-commons     Build runanywhere-commons from source
#
# OPTIONS:
#   --skip-macos        Skip macOS build (iOS only). macOS is included by default.
#   --clean             Clean build artifacts before building
#   --release           Build in release mode (default: debug)
#   --skip-build        Skip swift build (only setup frameworks)
#   --set-local         Set testLocal = true in Package.swift
#   --set-remote        Set testLocal = false in Package.swift
#   --help              Show this help message
#
# EXAMPLES:
#   # First time setup (iOS + macOS, recommended)
#   ./scripts/build-swift.sh --setup
#
#   # First time setup (iOS only, skip macOS)
#   ./scripts/build-swift.sh --setup --skip-macos
#
#   # Rebuild after commons changes
#   ./scripts/build-swift.sh --local --build-commons
#
#   # Quick local (use existing commons build)
#   ./scripts/build-swift.sh --local
#
#   # Switch to remote mode (GitHub releases)
#   ./scripts/build-swift.sh --remote
#
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWIFT_SDK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SDK_DIR="$(cd "${SWIFT_SDK_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${SDK_DIR}/.." && pwd)"

# Source paths
COMMONS_DIR="$SDK_DIR/runanywhere-commons"
COMMONS_BUILD_SCRIPT="$COMMONS_DIR/scripts/build-ios.sh"

# Destination paths (XCFrameworks go here)
BINARIES_DIR="$SWIFT_SDK_DIR/Binaries"

# Root Package.swift (single source of truth)
PACKAGE_FILE="$REPO_ROOT/Package.swift"

# Build configuration
BUILD_MODE="debug"
MODE=""
BUILD_COMMONS=false
INCLUDE_MACOS=true
CLEAN_BUILD=false
SKIP_BUILD=false
SET_LOCAL_MODE=""
SETUP_MODE=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()   { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn()   { echo -e "${YELLOW}[!]${NC} $1"; }
log_error()  { echo -e "${RED}[✗]${NC} $1"; }
log_step()   { echo -e "${BLUE}==>${NC} $1"; }
log_header() { echo -e "\n${GREEN}═══════════════════════════════════════════${NC}"; echo -e "${GREEN} $1${NC}"; echo -e "${GREEN}═══════════════════════════════════════════${NC}"; }

show_help() {
    head -45 "$0" | tail -40
    exit 0
}

# =============================================================================
# Parse Arguments
# =============================================================================

for arg in "$@"; do
    case "$arg" in
        --setup)
            SETUP_MODE=true
            MODE="local"
            BUILD_COMMONS=true
            ;;
        --local)
            MODE="local"
            ;;
        --remote)
            MODE="remote"
            ;;
        --build-commons)
            BUILD_COMMONS=true
            MODE="local"
            ;;
        --include-macos)
            INCLUDE_MACOS=true
            ;;
        --skip-macos)
            INCLUDE_MACOS=false
            ;;
        --clean)
            CLEAN_BUILD=true
            ;;
        --release)
            BUILD_MODE="release"
            ;;
        --skip-build)
            SKIP_BUILD=true
            ;;
        --set-local)
            SET_LOCAL_MODE="local"
            ;;
        --set-remote)
            SET_LOCAL_MODE="remote"
            ;;
        --help|-h)
            show_help
            ;;
    esac
done

# Default to local mode if nothing specified
if [[ -z "$MODE" && -z "$SET_LOCAL_MODE" ]]; then
    # Check if Binaries/ has frameworks - if not, suggest --setup
    if [[ ! -d "$BINARIES_DIR/RACommons.xcframework" ]]; then
        echo ""
        echo "═══════════════════════════════════════════════════════════════"
        echo " RunAnywhere Swift SDK - Setup Required"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""
        echo "No frameworks found in Binaries/. Run first-time setup:"
        echo ""
        echo "  ./scripts/build-swift.sh --setup"
        echo ""
        echo "This will download dependencies and build all frameworks."
        echo "(Takes 5-15 minutes on first run)"
        echo ""
        exit 1
    fi
    MODE="local"
fi

# =============================================================================
# Set Package.swift Mode
# =============================================================================

set_package_mode() {
    local mode=$1

    if [[ ! -f "$PACKAGE_FILE" ]]; then
        log_error "Package.swift not found: $PACKAGE_FILE"
        exit 1
    fi

    if [[ "$mode" == "local" ]]; then
        log_step "Setting useLocalBinaries = true in Package.swift"
        if grep -q 'let useLocalBinaries = true' "$PACKAGE_FILE"; then
            log_info "Already in local mode"
            return 0
        fi
        sed -i '' 's/let useLocalBinaries = false/let useLocalBinaries = true/' "$PACKAGE_FILE"
        if grep -q 'let useLocalBinaries = true' "$PACKAGE_FILE"; then
            log_info "✓ Local mode enabled"
        else
            log_error "Failed to enable local mode"
            exit 1
        fi
    elif [[ "$mode" == "remote" ]]; then
        log_step "Setting useLocalBinaries = false in Package.swift"
        if grep -q 'let useLocalBinaries = false' "$PACKAGE_FILE"; then
            log_info "Already in remote mode"
            return 0
        fi
        sed -i '' 's/let useLocalBinaries = true/let useLocalBinaries = false/' "$PACKAGE_FILE"
        if grep -q 'let useLocalBinaries = false' "$PACKAGE_FILE"; then
            log_info "✓ Remote mode enabled"
        else
            log_error "Failed to enable remote mode"
            exit 1
        fi
    fi
}

# =============================================================================
# Build Commons
# =============================================================================

build_commons() {
    log_header "Building runanywhere-commons"

    if [[ ! -d "$COMMONS_DIR" ]]; then
        log_error "runanywhere-commons not found at: $COMMONS_DIR"
        log_error "Expected: sdk/runanywhere-commons/"
        exit 1
    fi

    if [[ ! -x "$COMMONS_BUILD_SCRIPT" ]]; then
        log_error "Build script not found: $COMMONS_BUILD_SCRIPT"
        exit 1
    fi

    local FLAGS=""
    [[ "$CLEAN_BUILD" == true ]] && FLAGS="$FLAGS --clean"
    [[ "$INCLUDE_MACOS" == true ]] && FLAGS="$FLAGS --include-macos"

    log_step "Running: build-ios.sh $FLAGS"
    log_info "This downloads dependencies and builds all frameworks..."
    [[ "$INCLUDE_MACOS" == true ]] && log_info "Including macOS support (this adds build time)"
    echo ""
    "$COMMONS_BUILD_SCRIPT" $FLAGS

    log_info "runanywhere-commons build complete"
}

# =============================================================================
# Install Frameworks
# =============================================================================

install_frameworks() {
    log_header "Installing XCFrameworks to Binaries/"

    mkdir -p "$BINARIES_DIR"

    # All frameworks are now in dist/ (flat structure from build-ios.sh)
    for framework in RACommons RABackendLLAMACPP RABackendONNX; do
        local src="$COMMONS_DIR/dist/${framework}.xcframework"
        if [[ -d "$src" ]]; then
            log_step "Copying ${framework}.xcframework"
            rm -rf "$BINARIES_DIR/${framework}.xcframework"
            cp -r "$src" "$BINARIES_DIR/"
            log_info "  ${framework}.xcframework ($(du -sh "$src" | cut -f1))"
        else
            if [[ "$framework" == "RACommons" ]]; then
                log_warn "RACommons.xcframework not found at $src"
            else
                log_warn "${framework}.xcframework not found (optional)"
            fi
        fi
    done

    # Install ONNX Runtime xcframeworks (split: iOS static library + macOS dynamic framework)
    # Remove old combined xcframework if present
    rm -rf "$BINARIES_DIR/onnxruntime.xcframework"

    if [[ "$INCLUDE_MACOS" == true ]]; then
        # macOS included: create split iOS + macOS xcframeworks
        local ONNX_SCRIPT="$SWIFT_SDK_DIR/scripts/create-onnxruntime-xcframework.sh"
        if [[ -x "$ONNX_SCRIPT" ]]; then
            log_step "Creating split ONNX Runtime xcframeworks (iOS + macOS)..."
            "$ONNX_SCRIPT"
        else
            log_warn "create-onnxruntime-xcframework.sh not found, skipping ONNX Runtime"
        fi
    else
        # iOS only: create library-format xcframework from pre-built iOS onnxruntime
        local ONNX_SRC="$COMMONS_DIR/third_party/onnxruntime-ios/onnxruntime.xcframework"
        if [[ -d "$ONNX_SRC" ]]; then
            log_step "Creating onnxruntime-ios.xcframework (library format)"
            local ONNX_TEMP=$(mktemp -d)
            local XCFW_ARGS=()
            for SLICE_DIR in "${ONNX_SRC}"/*/; do
                local SLICE_NAME=$(basename "$SLICE_DIR")
                [[ "$SLICE_NAME" == "Info.plist" ]] && continue
                local DEST="${ONNX_TEMP}/${SLICE_NAME}"
                mkdir -p "$DEST"
                if [[ -d "${SLICE_DIR}/onnxruntime.framework" ]]; then
                    cp "${SLICE_DIR}/onnxruntime.framework/onnxruntime" "${DEST}/libonnxruntime.a"
                    cp -R "${SLICE_DIR}/onnxruntime.framework/Headers" "${DEST}/Headers" 2>/dev/null || true
                fi
                XCFW_ARGS+=(-library "${DEST}/libonnxruntime.a")
                [[ -d "${DEST}/Headers" ]] && XCFW_ARGS+=(-headers "${DEST}/Headers")
            done
            rm -rf "$BINARIES_DIR/onnxruntime-ios.xcframework"
            xcodebuild -create-xcframework "${XCFW_ARGS[@]}" -output "$BINARIES_DIR/onnxruntime-ios.xcframework"
            rm -rf "$ONNX_TEMP"
            log_info "  onnxruntime-ios.xcframework created"
        else
            log_warn "onnxruntime.xcframework not found at $ONNX_SRC"
        fi
    fi

    log_info "Frameworks installed to: $BINARIES_DIR"
}

# =============================================================================
# Sync CRACommons Bridge Headers
# =============================================================================

sync_headers() {
    log_header "Syncing CRACommons bridge headers"

    local BRIDGE_INCLUDE="$SWIFT_SDK_DIR/Sources/RunAnywhere/CRACommons/include"
    local COMMONS_INCLUDE="$COMMONS_DIR/include/rac"

    if [[ ! -d "$BRIDGE_INCLUDE" ]]; then
        log_warn "CRACommons include dir not found: $BRIDGE_INCLUDE"
        return 0
    fi

    local synced=0

    # Backend headers that need to be exposed to Swift via CRACommons
    local BACKEND_HEADERS=(
        "backends/rac_stt_whisperkit_coreml.h"
    )

    for rel_path in "${BACKEND_HEADERS[@]}"; do
        local src="$COMMONS_INCLUDE/$rel_path"
        local filename="$(basename "$rel_path")"
        local dest="$BRIDGE_INCLUDE/$filename"

        if [[ -f "$src" ]]; then
            # Copy and fix include paths (CRACommons uses flat includes)
            sed -e 's|#include "rac/[^"]*/"||' \
                -e 's|#include "rac/core/\(.*\)"|#include "\1"|' \
                -e 's|#include "rac/features/[^"]*/"||' \
                -e 's|#include "rac/features/stt/\(.*\)"|#include "\1"|' \
                "$src" > "${dest}.tmp"

            # Use sed to fix the nested path includes properly
            sed -e 's|#include "rac/core/rac_types.h"|#include "rac_types.h"|g' \
                -e 's|#include "rac/features/stt/rac_stt_types.h"|#include "rac_stt_types.h"|g' \
                "$src" > "${dest}.tmp"

            if ! diff -q "$dest" "${dest}.tmp" >/dev/null 2>&1; then
                mv "${dest}.tmp" "$dest"
                log_info "  Synced: $filename"
                synced=$((synced + 1))
            else
                rm -f "${dest}.tmp"
            fi
        else
            log_warn "  Source not found: $src"
        fi
    done

    if [[ $synced -eq 0 ]]; then
        log_info "All bridge headers up to date"
    else
        log_info "Synced $synced header(s)"
    fi
}

# =============================================================================
# Build Swift SDK
# =============================================================================

build_sdk() {
    log_header "Building Swift SDK"

    cd "$REPO_ROOT"

    if $CLEAN_BUILD; then
        log_step "Cleaning build..."
        rm -rf .build/ 2>/dev/null || true
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
    if $SETUP_MODE; then
        log_header "RunAnywhere Swift SDK - First Time Setup"
        echo ""
        echo "This will:"
        echo "  1. Download ONNX Runtime & Sherpa-ONNX (iOS)"
        if [[ "$INCLUDE_MACOS" == true ]]; then
            echo "  1b. Download ONNX Runtime & build Sherpa-ONNX (macOS)"
        fi
        echo "  2. Build RACommons.xcframework"
        echo "  3. Build RABackendLLAMACPP.xcframework"
        echo "  4. Build RABackendONNX.xcframework"
        if [[ "$INCLUDE_MACOS" == true ]]; then
            echo "     (all xcframeworks will include macOS arm64 slices)"
            echo "  5. Create combined ONNX Runtime xcframework (iOS + macOS)"
            echo "  6. Copy frameworks to Binaries/"
            echo "  7. Set useLocalBinaries = true in Package.swift"
        else
            echo "  5. Copy frameworks to Binaries/"
            echo "  6. Set useLocalBinaries = true in Package.swift"
        fi
        echo ""
        if [[ "$INCLUDE_MACOS" == true ]]; then
            echo "This may take 15-30 minutes (includes macOS + Sherpa-ONNX build)..."
        else
            echo "This may take 5-15 minutes..."
        fi
        echo ""
    else
        log_header "RunAnywhere Swift SDK - Build"
        echo "Repo Root:      $REPO_ROOT"
        echo "Swift SDK:      $SWIFT_SDK_DIR"
        echo "Commons:        $COMMONS_DIR"
        echo "Package.swift:  $PACKAGE_FILE"
        echo "Mode:           $MODE"
        echo "Build Commons:  $BUILD_COMMONS"
        echo ""
    fi

    # Handle --set-local / --set-remote only
    if [[ -n "$SET_LOCAL_MODE" && "$MODE" == "" ]]; then
        set_package_mode "$SET_LOCAL_MODE"
        log_header "Done!"
        return 0
    fi

    # Build commons if requested
    if $BUILD_COMMONS; then
        build_commons
    fi

    # In local mode, install frameworks and set package mode
    if [[ "$MODE" == "local" ]]; then
        install_frameworks
        set_package_mode "local"
    elif [[ "$MODE" == "remote" ]]; then
        set_package_mode "remote"
    fi

    # Sync backend headers to CRACommons bridge
    sync_headers

    # Build the SDK
    if ! $SKIP_BUILD; then
        build_sdk
    else
        log_info "Skipping swift build (--skip-build)"
    fi

    log_header "Build Complete!"

    # Show status
    echo ""
    echo "Binaries directory: $BINARIES_DIR"
    if [[ -d "$BINARIES_DIR" ]]; then
        for xcfw in "$BINARIES_DIR"/*.xcframework; do
            [[ -d "$xcfw" ]] && echo "  $(du -sh "$xcfw" | cut -f1)  $(basename "$xcfw")"
        done
    fi

    echo ""
    echo "Package.swift: $(grep 'let useLocalBinaries' "$PACKAGE_FILE" | head -1 | xargs)"
    echo ""

    if $SETUP_MODE; then
        echo "Next steps:"
        echo "  1. Open the example app in Xcode"
        echo "  2. File > Packages > Reset Package Caches (if needed)"
        echo "  3. Build & Run!"
        echo ""
    fi
}

main "$@"
