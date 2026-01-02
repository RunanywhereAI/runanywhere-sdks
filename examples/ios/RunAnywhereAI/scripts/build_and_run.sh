#!/bin/bash
# =============================================================================
# RunAnywhereAI - Build & Run Script
# =============================================================================
#
# Single source of truth for building and running the RunAnywhereAI sample app.
# Orchestrates builds across three independent projects, each with their own scripts.
#
# PROJECT STRUCTURE & SCRIPTS:
# ─────────────────────────────────────────────────────────────────────────────
# runanywhere-core/
#   scripts/ios/build.sh              Build iOS static libraries
#   scripts/build-xcframework.sh      Create RunAnywhereCore.xcframework
#   scripts/macos/build.sh            Build macOS libraries
#   scripts/android/build.sh          Build Android libraries
#
# runanywhere-commons/
#   scripts/build-ios.sh              Build iOS XCFrameworks (RACommons, backends)
#   scripts/build-android.sh          Build Android libraries
#   scripts/build-all.sh              Build all platforms
#
# runanywhere-swift/
#   scripts/build-ios.sh              Build Swift SDK, install frameworks
# ─────────────────────────────────────────────────────────────────────────────
#
# USAGE:
#   ./build_and_run.sh [target] [options]
#
# TARGETS:
#   simulator "Device Name"  Build and run on iOS Simulator
#   device                   Build and run on connected iOS device
#   mac                      Build and run on macOS
#
# BUILD OPTIONS:
#   --build-core      Build runanywhere-core (C++ inference engine)
#   --build-commons   Build runanywhere-commons (C++ SDK layer)
#   --build-sdk       Build runanywhere-swift (Swift SDK)
#   --build-all       Build everything (core + commons + sdk)
#   --skip-app        Only build SDK components, skip Xcode app build
#   --local           Use local builds (copies core to commons, frameworks to swift, enables testLocal)
#
# OTHER OPTIONS:
#   --clean           Clean build artifacts before building
#   --help            Show this help message
#
# EXAMPLES:
#   ./build_and_run.sh device                      # Run app (use cached frameworks)
#   ./build_and_run.sh device --build-all          # Rebuild everything, run on device
#   ./build_and_run.sh simulator --build-commons   # Rebuild commons + SDK, run on sim
#   ./build_and_run.sh --build-all --skip-app      # Just rebuild all SDK components
#   ./build_and_run.sh device --build-all --local  # Full local build (core->commons->swift->app)
#
# INDIVIDUAL PROJECT BUILDS (can be run standalone):
#   cd runanywhere-core && ./scripts/ios/build.sh && ./scripts/build-xcframework.sh
#   cd runanywhere-commons && ./scripts/build-ios.sh
#   cd runanywhere-swift && ./scripts/build-ios.sh --install-frameworks --sync-headers
#
# =============================================================================

set -e

# =============================================================================
# PATHS
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../../../../" && pwd)"

# Project directories
CORE_DIR="$WORKSPACE_ROOT/../runanywhere-core"
COMMONS_DIR="$WORKSPACE_ROOT/sdk/runanywhere-commons"
SWIFT_SDK_DIR="$WORKSPACE_ROOT/sdk/runanywhere-swift"
APP_DIR="$SCRIPT_DIR/.."

# Build scripts (each project has its own)
CORE_BUILD_SCRIPT="$CORE_DIR/scripts/ios/build.sh"
CORE_XCFRAMEWORK_SCRIPT="$CORE_DIR/scripts/build-xcframework.sh"
COMMONS_BUILD_SCRIPT="$COMMONS_DIR/scripts/build-ios.sh"
SWIFT_BUILD_SCRIPT="$SWIFT_SDK_DIR/scripts/build-ios.sh"

# =============================================================================
# COLORS & LOGGING
# =============================================================================

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
    head -56 "$0" | tail -51
    exit 0
}

# =============================================================================
# TIMING
# =============================================================================

TOTAL_START_TIME=0
TIME_CORE=0
TIME_COMMONS=0
TIME_SWIFT=0
TIME_APP=0
TIME_DEPLOY=0

format_duration() {
    local seconds=$1
    if (( seconds >= 60 )); then
        local mins=$((seconds / 60))
        local secs=$((seconds % 60))
        echo "${mins}m ${secs}s"
    else
        echo "${seconds}s"
    fi
}

# =============================================================================
# PARSE ARGUMENTS
# =============================================================================

TARGET="device"
DEVICE_NAME=""
BUILD_CORE=false
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
            BUILD_CORE=true
            BUILD_COMMONS=true
            BUILD_SDK=true
            ;;
        --build-core)
            BUILD_CORE=true
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
# BUILD FUNCTIONS - Call individual project scripts
# =============================================================================

build_core() {
    log_header "Building runanywhere-core"
    local start_time=$(date +%s)

    if [[ ! -d "$CORE_DIR" ]]; then
        log_error "runanywhere-core not found at: $CORE_DIR"
        log_error "Expected location: $WORKSPACE_ROOT/../runanywhere-core"
        exit 1
    fi

    if [[ ! -x "$CORE_BUILD_SCRIPT" ]]; then
        log_error "Core build script not found: $CORE_BUILD_SCRIPT"
        exit 1
    fi

    log_step "Running: $CORE_BUILD_SCRIPT"
    cd "$CORE_DIR"
    "$CORE_BUILD_SCRIPT"

    if [[ -x "$CORE_XCFRAMEWORK_SCRIPT" ]]; then
        log_step "Running: $CORE_XCFRAMEWORK_SCRIPT --ios-only"
        "$CORE_XCFRAMEWORK_SCRIPT" --ios-only
    fi

    local end_time=$(date +%s)
    TIME_CORE=$((end_time - start_time))
    log_info "runanywhere-core build complete"
    log_time "Core build time: $(format_duration $TIME_CORE)"
}

copy_core_to_commons() {
    if ! $LOCAL_MODE; then
        return 0
    fi

    log_header "Copying runanywhere-core to runanywhere-commons (Local Mode)"
    
    local core_dest="$COMMONS_DIR/third_party/runanywhere-core"
    
    if [[ ! -d "$CORE_DIR" ]]; then
        log_error "runanywhere-core not found at: $CORE_DIR"
        exit 1
    fi

    log_step "Copying runanywhere-core source to $core_dest"
    mkdir -p "$(dirname "$core_dest")"
    
    # Remove existing if present
    if [[ -d "$core_dest" ]]; then
        log_step "Removing existing copy..."
        rm -rf "$core_dest"
    fi
    
    # Copy source (exclude build artifacts)
    log_step "Copying source files..."
    if command -v rsync &> /dev/null; then
        rsync -av --exclude='build/' --exclude='.git/' --exclude='dist/' --exclude='*.xcframework' "$CORE_DIR/" "$core_dest/" || {
            log_warn "rsync failed, using cp..."
            cp -r "$CORE_DIR" "$(dirname "$core_dest")/"
        }
    else
        cp -r "$CORE_DIR" "$(dirname "$core_dest")/"
        # Clean up build artifacts after copy
        find "$core_dest" -type d -name "build" -exec rm -rf {} + 2>/dev/null || true
        find "$core_dest" -type d -name ".git" -exec rm -rf {} + 2>/dev/null || true
    fi
    
    log_info "Copied runanywhere-core to commons third_party"
}

build_commons() {
    log_header "Building runanywhere-commons"
    local start_time=$(date +%s)

    if [[ ! -x "$COMMONS_BUILD_SCRIPT" ]]; then
        log_error "Commons build script not found: $COMMONS_BUILD_SCRIPT"
        exit 1
    fi

    # In local mode, download PRE-BUILT core libraries (not source)
    # Commons will link against pre-built libraries instead of compiling core
    if $LOCAL_MODE; then
        local download_script="$COMMONS_DIR/scripts/download-core-prebuilt.sh"
        if [[ -x "$download_script" ]]; then
            if [[ ! -d "$COMMONS_DIR/third_party/runanywhere-core-prebuilt" ]]; then
                log_info "Local mode: Downloading PRE-BUILT runanywhere-core libraries"
                log_info "  (Commons will link against pre-built libraries, not compile core)"
                log_step "Running: $download_script"
                cd "$COMMONS_DIR"
                "$download_script"
            else
                log_info "Local mode: Using downloaded PRE-BUILT core libraries"
                log_info "  (Commons will link against pre-built libraries, not compile core)"
            fi
        else
            log_warn "download-core-prebuilt.sh not found - commons build may fail if core is missing"
        fi
    fi

    log_step "Running: $COMMONS_BUILD_SCRIPT"
    cd "$COMMONS_DIR"
    # In local mode, use pre-built core libraries
    if $LOCAL_MODE; then
        USE_PREBUILT_CORE=ON "$COMMONS_BUILD_SCRIPT"
    else
        "$COMMONS_BUILD_SCRIPT"
    fi

    local end_time=$(date +%s)
    TIME_COMMONS=$((end_time - start_time))
    log_info "runanywhere-commons build complete"
    log_time "Commons build time: $(format_duration $TIME_COMMONS)"
}

copy_frameworks_to_swift() {
    if ! $LOCAL_MODE; then
        return 0
    fi

    log_header "Copying XCFrameworks to runanywhere-swift/Binaries (Local Mode - Commons Only)"
    log_info "Note: onnxruntime will be consumed from remote releases"
    
    local binaries_dir="$SWIFT_SDK_DIR/Binaries"
    mkdir -p "$binaries_dir"

    # Copy all runanywhere-commons frameworks (built locally)
    # onnxruntime comes from remote GitHub releases
    local frameworks=("RACommons" "RABackendLlamaCPP" "RABackendONNX")
    for framework in "${frameworks[@]}"; do
        local src="$COMMONS_DIR/dist/${framework}.xcframework"
        if [[ -d "$src" ]]; then
            log_step "Copying ${framework}.xcframework (local build)"
            rm -rf "$binaries_dir/${framework}.xcframework"
            cp -r "$src" "$binaries_dir/"
            log_info "  ✓ ${framework}.xcframework"
        else
            log_warn "  ✗ ${framework}.xcframework not found at $src"
        fi
    done

    log_info "XCFrameworks copied to: $binaries_dir"
    log_info "onnxruntime will be downloaded from GitHub releases"
}

set_package_mode() {
    local package_file="$SWIFT_SDK_DIR/Package.swift"
    
    if [[ ! -f "$package_file" ]]; then
        log_error "Package.swift not found: $package_file"
        exit 1
    fi

    if $LOCAL_MODE; then
        log_header "Enabling Local Mode in Package.swift"
        
        # Check if already in local mode
        if grep -q 'let testLocal = true' "$package_file"; then
            log_info "Already in local mode"
            return 0
        fi

        # Change testLocal to true
        log_step "Setting testLocal = true"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' 's/let testLocal = false/let testLocal = true/' "$package_file"
        else
            sed -i 's/let testLocal = false/let testLocal = true/' "$package_file"
        fi
        
        if grep -q 'let testLocal = true' "$package_file"; then
            log_info "✓ Local mode enabled"
        else
            log_error "Failed to enable local mode"
            exit 1
        fi
    else
        # Restore remote mode if currently in local mode
        if grep -q 'let testLocal = true' "$package_file"; then
            log_header "Restoring Remote Mode in Package.swift"
            log_step "Setting testLocal = false"
            if [[ "$OSTYPE" == "darwin"* ]]; then
                sed -i '' 's/let testLocal = true/let testLocal = false/' "$package_file"
            else
                sed -i 's/let testLocal = true/let testLocal = false/' "$package_file"
            fi
            
            if grep -q 'let testLocal = false' "$package_file"; then
                log_info "✓ Remote mode restored"
            fi
        fi
    fi
}

build_swift_sdk() {
    log_header "Building runanywhere-swift"
    local start_time=$(date +%s)

    if [[ ! -x "$SWIFT_BUILD_SCRIPT" ]]; then
        log_error "Swift build script not found: $SWIFT_BUILD_SCRIPT"
        exit 1
    fi

    # In local mode, copy frameworks and set package mode
    if $LOCAL_MODE; then
        copy_frameworks_to_swift
    fi
    set_package_mode

    # Determine what flags to pass
    local FLAGS=""

    # Install frameworks if core or commons was rebuilt (only if not in local mode)
    if ! $LOCAL_MODE && ($BUILD_CORE || $BUILD_COMMONS); then
        FLAGS="$FLAGS --install-frameworks --sync-headers"
    fi

    if $CLEAN_BUILD; then
        FLAGS="$FLAGS --clean"
    fi

    log_step "Running: $SWIFT_BUILD_SCRIPT $FLAGS"
    cd "$SWIFT_SDK_DIR"
    "$SWIFT_BUILD_SCRIPT" $FLAGS

    local end_time=$(date +%s)
    TIME_SWIFT=$((end_time - start_time))
    log_info "runanywhere-swift build complete"
    log_time "Swift SDK build time: $(format_duration $TIME_SWIFT)"
}

# =============================================================================
# APP BUILD & DEPLOY
# =============================================================================

build_app() {
    log_header "Building RunAnywhereAI App"
    local start_time=$(date +%s)

    cd "$APP_DIR"

    # Determine destination
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
        local end_time=$(date +%s)
        TIME_APP=$((end_time - start_time))
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

    # Find built app (exclude Index.noindex)
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
            xcrun devicectl device process launch --device "$DEVICE_ID" "com.runanywhere.RunAnywhere" || log_warn "Launch failed - device may be locked. Unlock and tap the app icon."
            log_info "App installed on device"
            ;;
    esac

    local end_time=$(date +%s)
    TIME_DEPLOY=$((end_time - start_time))
    log_time "Deploy time: $(format_duration $TIME_DEPLOY)"
}

# =============================================================================
# BUILD SUMMARY
# =============================================================================

print_summary() {
    local total_end_time=$(date +%s)
    local total_time=$((total_end_time - TOTAL_START_TIME))

    echo ""
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════${NC}"
    echo -e "${BOLD}${GREEN}           BUILD TIME SUMMARY              ${NC}"
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════${NC}"
    echo ""

    if (( TIME_CORE > 0 )); then
        printf "  %-25s %s\n" "runanywhere-core:" "$(format_duration $TIME_CORE)"
    fi
    if (( TIME_COMMONS > 0 )); then
        printf "  %-25s %s\n" "runanywhere-commons:" "$(format_duration $TIME_COMMONS)"
    fi
    if (( TIME_SWIFT > 0 )); then
        printf "  %-25s %s\n" "runanywhere-swift:" "$(format_duration $TIME_SWIFT)"
    fi
    if (( TIME_APP > 0 )); then
        printf "  %-25s %s\n" "iOS App:" "$(format_duration $TIME_APP)"
    fi
    if (( TIME_DEPLOY > 0 )); then
        printf "  %-25s %s\n" "Deploy:" "$(format_duration $TIME_DEPLOY)"
    fi

    echo "  ─────────────────────────────────────────"
    printf "  ${BOLD}%-25s %s${NC}\n" "TOTAL:" "$(format_duration $total_time)"
    echo ""
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    TOTAL_START_TIME=$(date +%s)

    log_header "RunAnywhereAI Build Pipeline"
    echo "Target: $TARGET"
    echo "Build Core: $BUILD_CORE"
    echo "Build Commons: $BUILD_COMMONS"
    echo "Build SDK: $BUILD_SDK"
    echo "Skip App: $SKIP_APP"
    echo "Local Mode: $LOCAL_MODE"
    echo ""
    echo "Scripts:"
    echo "  Core:    $CORE_BUILD_SCRIPT"
    echo "  Commons: $COMMONS_BUILD_SCRIPT"
    echo "  Swift:   $SWIFT_BUILD_SCRIPT"
    echo ""

    # Execute build steps by calling individual project scripts
    # 
    # WITHOUT --local flag (REMOTE MODE):
    #   - Everything consumed from remote GitHub releases
    #   - No local builds, all XCFrameworks downloaded
    #
    # WITH --local flag (LOCAL DEVELOPMENT MODE):
    #   - Downloads PRE-BUILT core libraries (not source, not compiled)
    #   - Only runanywhere-commons is built locally
    #   - Commons links against pre-built core libraries (remote)
    #   - Commons frameworks copied to Swift SDK for local use
    if $LOCAL_MODE; then
        log_info "Local mode: Using pre-built core libraries (remote), building commons locally"
        # Build commons locally (links against pre-built core libraries)
        $BUILD_COMMONS && build_commons
    else
        # Remote mode: Everything from GitHub releases, no local builds
        log_info "Remote mode: All frameworks from GitHub releases"
        # Note: build_core and build_commons are skipped in remote mode
        # All XCFrameworks come from Package.swift remote URLs
    fi
    $BUILD_SDK && build_swift_sdk

    # Build and deploy app
    if ! $SKIP_APP; then
        build_app
        deploy_and_run
    else
        log_info "App build skipped (--skip-app)"
    fi

    # Print timing summary
    print_summary

    log_header "Done!"
}

main "$@"
