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
#   --clean             Clean build artifacts before building
#   --release           Build in release mode (default: debug)
#   --skip-build        Skip swift build (only setup frameworks)
#   --set-local         Set testLocal = true in Package.swift
#   --set-remote        Set testLocal = false in Package.swift
#   --help              Show this help message
#
# EXAMPLES:
#   # First time setup (recommended)
#   ./scripts/build-swift.sh --setup
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
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SDK_ROOT="$(cd "${PROJECT_ROOT}/.." && pwd)"

# Source paths
COMMONS_DIR="$SDK_ROOT/runanywhere-commons"
COMMONS_BUILD_SCRIPT="$COMMONS_DIR/scripts/build-ios.sh"

# Destination paths
BINARIES_DIR="$PROJECT_ROOT/Binaries"

# Build configuration
BUILD_MODE="debug"
MODE=""
BUILD_COMMONS=false
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
    local package_file="$PROJECT_ROOT/Package.swift"

    if [[ ! -f "$package_file" ]]; then
        log_error "Package.swift not found: $package_file"
        exit 1
    fi

    if [[ "$mode" == "local" ]]; then
        log_step "Setting testLocal = true in Package.swift"
        if grep -q 'let testLocal = true' "$package_file"; then
            log_info "Already in local mode"
            return 0
        fi
        sed -i '' 's/let testLocal = false/let testLocal = true/' "$package_file"
        if grep -q 'let testLocal = true' "$package_file"; then
            log_info "✓ Local mode enabled"
        else
            log_error "Failed to enable local mode"
            exit 1
        fi
    elif [[ "$mode" == "remote" ]]; then
        log_step "Setting testLocal = false in Package.swift"
        if grep -q 'let testLocal = false' "$package_file"; then
            log_info "Already in remote mode"
            return 0
        fi
        sed -i '' 's/let testLocal = true/let testLocal = false/' "$package_file"
        if grep -q 'let testLocal = false' "$package_file"; then
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

    log_step "Running: build-ios.sh $FLAGS"
    log_info "This downloads dependencies and builds all frameworks..."
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

    log_info "Frameworks installed to: $BINARIES_DIR"
}

# =============================================================================
# Build Swift SDK
# =============================================================================

build_sdk() {
    log_header "Building Swift SDK"

    cd "$PROJECT_ROOT"

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
        echo "  1. Download ONNX Runtime & Sherpa-ONNX"
        echo "  2. Build RACommons.xcframework"
        echo "  3. Build RABackendLLAMACPP.xcframework"
        echo "  4. Build RABackendONNX.xcframework"
        echo "  5. Copy frameworks to Binaries/"
        echo "  6. Set testLocal = true in Package.swift"
        echo ""
        echo "This may take 5-15 minutes..."
        echo ""
    else
        log_header "RunAnywhere Swift SDK - Build"
        echo "Project:        $PROJECT_ROOT"
        echo "Commons:        $COMMONS_DIR"
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
    echo "Package.swift: $(grep 'let testLocal' "$PROJECT_ROOT/Package.swift" | head -1 | xargs)"
    echo ""

    if $SETUP_MODE; then
        echo "Next steps:"
        echo "  1. Open Xcode: open Package.swift"
        echo "  2. If needed: File > Packages > Reset Package Caches"
        echo "  3. Build & Run!"
        echo ""
    fi
}

main "$@"
