#!/bin/bash
# =============================================================================
# RunAnywhereAI - Build & Run iOS Sample App
# =============================================================================
#
# Builds and runs the RunAnywhereAI sample app.
#
# PROJECT STRUCTURE:
# ─────────────────────────────────────────────────────────────────────────────
# runanywhere-commons/                 Unified C++ library with backends
#   scripts/build-all-ios.sh           Build everything for iOS
#
# runanywhere-swift/                   Swift SDK wrapper
#   scripts/build-swift.sh             Build Swift SDK
# ─────────────────────────────────────────────────────────────────────────────
#
# USAGE:
#   ./build_and_run_ios_sample.sh [target] [options]
#
# TARGETS:
#   simulator "Device Name"  Build and run on iOS Simulator
#   device                   Build and run on connected iOS device
#   mac                      Build and run on macOS
#
# BUILD OPTIONS:
#   --build-commons   Build runanywhere-commons (all frameworks)
#   --build-sdk       Build runanywhere-swift (Swift SDK)
#   --build-all       Build everything (commons + sdk)
#   --skip-app        Only build SDK components, skip Xcode app build
#   --local           Use local builds
#   --clean           Clean build artifacts
#   --help            Show this help message
#
# EXAMPLES:
#   ./build_and_run_ios_sample.sh device                     # Run app
#   ./build_and_run_ios_sample.sh device --build-all --local # Full local build
#   ./build_and_run_ios_sample.sh simulator --build-commons  # Rebuild commons
#   ./build_and_run_ios_sample.sh --build-all --skip-app     # Build SDK only
#
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../../../../" && pwd)"

# Project directories
COMMONS_DIR="$WORKSPACE_ROOT/sdk/runanywhere-commons"
SWIFT_SDK_DIR="$WORKSPACE_ROOT/sdk/runanywhere-swift"
APP_DIR="$SCRIPT_DIR/.."

# Build scripts
COMMONS_BUILD_SCRIPT="$COMMONS_DIR/scripts/build-all-ios.sh"
SWIFT_BUILD_SCRIPT="$SWIFT_SDK_DIR/scripts/build-swift.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_info()   { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn()   { echo -e "${YELLOW}[!]${NC} $1"; }
log_error()  { echo -e "${RED}[✗]${NC} $1"; }
log_step()   { echo -e "${BLUE}==>${NC} $1"; }
log_time()   { echo -e "${CYAN}[⏱]${NC} $1"; }
log_header() {
    echo -e "\n${GREEN}═══════════════════════════════════════════${NC}"
    echo -e "${GREEN} $1${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════${NC}"
}

show_help() {
    head -40 "$0" | tail -35
    exit 0
}

# Timing
TOTAL_START_TIME=0
TIME_COMMONS=0
TIME_SWIFT=0
TIME_APP=0
TIME_DEPLOY=0

format_duration() {
    local seconds=$1
    if (( seconds >= 60 )); then
        echo "$((seconds / 60))m $((seconds % 60))s"
    else
        echo "${seconds}s"
    fi
}

# =============================================================================
# Parse Arguments
# =============================================================================

TARGET="device"
DEVICE_NAME=""
BUILD_COMMONS=false
BUILD_SDK=false
SKIP_APP=false
CLEAN_BUILD=false
LOCAL_MODE=false

[[ "$1" == "--help" || "$1" == "-h" ]] && show_help

for arg in "$@"; do
    case "$arg" in
        simulator|device|mac)
            TARGET="$arg"
            ;;
        --build-all)
            BUILD_COMMONS=true
            BUILD_SDK=true
            ;;
        --build-commons)
            BUILD_COMMONS=true
            BUILD_SDK=true
            ;;
        --build-sdk)
            BUILD_SDK=true
            ;;
        --skip-app)
            SKIP_APP=true
            ;;
        --local)
            LOCAL_MODE=true
            ;;
        --clean)
            CLEAN_BUILD=true
            ;;
        --*)
            ;;
        *)
            [[ "$arg" != "simulator" && "$arg" != "device" && "$arg" != "mac" ]] && DEVICE_NAME="$arg"
            ;;
    esac
done

# =============================================================================
# Build Functions
# =============================================================================

build_commons() {
    log_header "Building runanywhere-commons"
    local start_time=$(date +%s)

    if [[ ! -x "$COMMONS_BUILD_SCRIPT" ]]; then
        log_error "Commons build script not found: $COMMONS_BUILD_SCRIPT"
        exit 1
    fi

    local FLAGS=""
    [[ "$CLEAN_BUILD" == true ]] && FLAGS="$FLAGS --clean"

    log_step "Running: build-all-ios.sh $FLAGS"
    "$COMMONS_BUILD_SCRIPT" $FLAGS

    TIME_COMMONS=$(($(date +%s) - start_time))
    log_time "Commons build time: $(format_duration $TIME_COMMONS)"
}

build_swift_sdk() {
    log_header "Building runanywhere-swift"
    local start_time=$(date +%s)

    if [[ ! -x "$SWIFT_BUILD_SCRIPT" ]]; then
        log_error "Swift build script not found: $SWIFT_BUILD_SCRIPT"
        exit 1
    fi

    local FLAGS=""
    $LOCAL_MODE && FLAGS="$FLAGS --local"
    $CLEAN_BUILD && FLAGS="$FLAGS --clean"

    log_step "Running: build-swift.sh $FLAGS"
    "$SWIFT_BUILD_SCRIPT" $FLAGS

    TIME_SWIFT=$(($(date +%s) - start_time))
    log_time "Swift SDK build time: $(format_duration $TIME_SWIFT)"
}

# =============================================================================
# App Build & Deploy
# =============================================================================

build_app() {
    log_header "Building RunAnywhereAI App"
    local start_time=$(date +%s)

    cd "$APP_DIR"

    local DESTINATION
    case "$TARGET" in
        simulator)
            DESTINATION="platform=iOS Simulator,name=${DEVICE_NAME:-iPhone 16}"
            ;;
        mac)
            DESTINATION="platform=macOS"
            ;;
        device|*)
            local DEVICE_ID=$(xcodebuild -project RunAnywhereAI.xcodeproj -scheme RunAnywhereAI -showdestinations 2>/dev/null | grep "platform:iOS" | grep -v "Simulator" | head -1 | sed -n 's/.*id:\([^,]*\).*/\1/p')
            [[ -z "$DEVICE_ID" ]] && { log_error "No connected iOS device found"; exit 1; }
            DESTINATION="platform=iOS,id=$DEVICE_ID"
            ;;
    esac

    log_step "Building for: $DESTINATION"

    $CLEAN_BUILD && xcodebuild clean -project RunAnywhereAI.xcodeproj -scheme RunAnywhereAI -configuration Debug >/dev/null 2>&1 || true

    if xcodebuild -project RunAnywhereAI.xcodeproj -scheme RunAnywhereAI -configuration Debug -destination "$DESTINATION" -allowProvisioningUpdates build > /tmp/xcodebuild.log 2>&1; then
        TIME_APP=$(($(date +%s) - start_time))
        log_info "App build succeeded"
        log_time "App build time: $(format_duration $TIME_APP)"
    else
        log_error "App build failed! Check /tmp/xcodebuild.log"
        tail -30 /tmp/xcodebuild.log
        exit 1
    fi
}

deploy_and_run() {
    log_header "Deploying to $TARGET"
    local start_time=$(date +%s)

    cd "$APP_DIR"

    local APP_PATH
    case "$TARGET" in
        simulator)
            APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "RunAnywhereAI.app" -path "*Debug-iphonesimulator*" -not -path "*/Index.noindex/*" 2>/dev/null | head -1)
            ;;
        mac)
            APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "RunAnywhereAI.app" -path "*/Debug/*" -not -path "*-iphone*" -not -path "*/Index.noindex/*" 2>/dev/null | head -1)
            ;;
        device|*)
            APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "RunAnywhereAI.app" -path "*Debug-iphoneos*" -not -path "*/Index.noindex/*" 2>/dev/null | head -1)
            ;;
    esac

    [[ ! -d "$APP_PATH" ]] && { log_error "Could not find built app"; exit 1; }

    log_info "Found app: $APP_PATH"

    case "$TARGET" in
        simulator)
            local SIM_ID=$(xcrun simctl list devices | grep "${DEVICE_NAME:-iPhone}" | grep -v "unavailable" | head -1 | sed 's/.*(\([^)]*\)).*/\1/')
            xcrun simctl boot "$SIM_ID" 2>/dev/null || true
            xcrun simctl install "$SIM_ID" "$APP_PATH"
            xcrun simctl launch "$SIM_ID" "com.runanywhere.RunAnywhere"
            open -a Simulator
            log_info "App launched on simulator"
            ;;
        mac)
            open "$APP_PATH"
            log_info "App launched on macOS"
            ;;
        device|*)
            local DEVICE_ID=$(xcrun devicectl list devices 2>/dev/null | grep "connected" | grep -oE '[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}' | head -1)
            [[ -z "$DEVICE_ID" ]] && { log_error "No connected iOS device found"; exit 1; }
            log_step "Installing on device: $DEVICE_ID"
            xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"
            xcrun devicectl device process launch --device "$DEVICE_ID" "com.runanywhere.RunAnywhere" || log_warn "Launch failed - unlock device and tap the app icon."
            log_info "App installed on device"
            ;;
    esac

    TIME_DEPLOY=$(($(date +%s) - start_time))
    log_time "Deploy time: $(format_duration $TIME_DEPLOY)"
}

# =============================================================================
# Summary
# =============================================================================

print_summary() {
    local total_time=$(($(date +%s) - TOTAL_START_TIME))

    echo ""
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════${NC}"
    echo -e "${BOLD}${GREEN}           BUILD TIME SUMMARY              ${NC}"
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════${NC}"
    echo ""

    (( TIME_COMMONS > 0 )) && printf "  %-25s %s\n" "runanywhere-commons:" "$(format_duration $TIME_COMMONS)"
    (( TIME_SWIFT > 0 )) && printf "  %-25s %s\n" "runanywhere-swift:" "$(format_duration $TIME_SWIFT)"
    (( TIME_APP > 0 )) && printf "  %-25s %s\n" "iOS App:" "$(format_duration $TIME_APP)"
    (( TIME_DEPLOY > 0 )) && printf "  %-25s %s\n" "Deploy:" "$(format_duration $TIME_DEPLOY)"

    echo "  ─────────────────────────────────────────"
    printf "  ${BOLD}%-25s %s${NC}\n" "TOTAL:" "$(format_duration $total_time)"
    echo ""
}

# =============================================================================
# Main
# =============================================================================

main() {
    TOTAL_START_TIME=$(date +%s)

    log_header "RunAnywhereAI Build Pipeline"
    echo "Target:       $TARGET"
    echo "Build:        commons=$BUILD_COMMONS sdk=$BUILD_SDK"
    echo "Local Mode:   $LOCAL_MODE"
    echo "Skip App:     $SKIP_APP"
    echo ""

    # Build commons if requested (and in local mode or explicitly requested)
    if $BUILD_COMMONS && $LOCAL_MODE; then
        build_commons
    fi

    # Build Swift SDK
    $BUILD_SDK && build_swift_sdk

    # Build and deploy app
    if ! $SKIP_APP; then
        build_app
        deploy_and_run
    else
        log_info "App build skipped (--skip-app)"
    fi

    print_summary
    log_header "Done!"
}

main "$@"
