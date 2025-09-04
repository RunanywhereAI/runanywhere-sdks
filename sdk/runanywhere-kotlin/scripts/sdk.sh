#!/bin/bash

# ============================================================================
# RunAnywhere Kotlin Multiplatform SDK Build & Management Script
# ============================================================================
#
# This is the main build and management script for the RunAnywhere KMP SDK.
# It provides all necessary operations for building, testing, and publishing
# the SDK across different platforms (JVM, Android, Native).
#
# The SDK is designed to work with:
# - IntelliJ/JetBrains plugins (JVM target) - PRIMARY TARGET
# - Android applications (Android target)
# - Native applications (Linux, macOS, Windows)
#
# Version: 0.1.0
# Repository: sdk/runanywhere-kotlin
#
# ============================================================================
# USAGE
# ============================================================================
#
# ./scripts/sdk.sh [command] [options]
#
# QUICK START FOR PLUGIN DEVELOPERS:
# -----------------------------------
# ./scripts/sdk.sh jvm              # Build JVM SDK for IntelliJ plugin
# ./scripts/sdk.sh jvm --publish    # Build and publish to local Maven
# ./scripts/sdk.sh clean jvm        # Clean and rebuild JVM target
#
# COMMON WORKFLOWS:
# -----------------
# ./scripts/sdk.sh all              # Build all targets
# ./scripts/sdk.sh test             # Run all tests
# ./scripts/sdk.sh clean all        # Clean rebuild everything
# ./scripts/sdk.sh jvm --watch      # Watch mode for JVM development
#
# ============================================================================

set -e  # Exit on error

# ============================================================================
# CONFIGURATION
# ============================================================================

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Script paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_FILE="$PROJECT_DIR/build.gradle.kts"

# SDK information
SDK_GROUP="com.runanywhere.sdk"
SDK_NAME="runanywhere-kotlin"
SDK_JAR_NAME="RunAnywhereKotlinSDK"
SDK_VERSION=$(grep '^version = ' "$BUILD_FILE" 2>/dev/null | sed 's/.*"\(.*\)".*/\1/' || echo "0.1.0")

# Navigate to project directory
cd "$PROJECT_DIR"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Print formatted headers for better readability
print_header() {
    echo -e "\n${BLUE}┌─────────────────────────────────────────────────────────┐${NC}"
    printf "${BLUE}│ %-55s │${NC}\n" "$1"
    echo -e "${BLUE}└─────────────────────────────────────────────────────────┘${NC}\n"
}

# Status messages with icons
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_info() { echo -e "${CYAN}ℹ️  $1${NC}"; }
print_step() { echo -e "${MAGENTA}▶ $1${NC}"; }

# Show comprehensive help documentation
show_help() {
    cat << EOF
${BOLD}${BLUE}RunAnywhere KMP SDK Management Tool${NC}
${CYAN}Version: $SDK_VERSION${NC}

${BOLD}${GREEN}USAGE:${NC}
    ./scripts/sdk.sh ${YELLOW}[command]${NC} ${CYAN}[options]${NC}

${BOLD}${GREEN}PRIMARY COMMANDS:${NC} ${CYAN}(Most commonly used)${NC}
    ${YELLOW}jvm${NC}             Build JVM target for IntelliJ/JetBrains plugins
    ${YELLOW}android${NC}         Build Android AAR library
    ${YELLOW}all${NC}             Build all targets (JVM, Android, Native)
    ${YELLOW}clean${NC}           Clean all build artifacts
    ${YELLOW}test${NC}            Run tests for all platforms

${BOLD}${GREEN}BUILD COMMANDS:${NC}
    ${YELLOW}jar${NC}             Build JVM JAR artifact only
    ${YELLOW}aar${NC}             Build Android AAR artifact only
    ${YELLOW}native${NC}          Build native targets (Linux, macOS, Windows)
    ${YELLOW}compile${NC}         Compile all sources without packaging

${BOLD}${GREEN}TESTING COMMANDS:${NC}
    ${YELLOW}test-jvm${NC}        Run JVM tests only
    ${YELLOW}test-android${NC}    Run Android tests only
    ${YELLOW}test-native${NC}     Run native platform tests
    ${YELLOW}coverage${NC}        Generate test coverage reports

${BOLD}${GREEN}PUBLISHING COMMANDS:${NC}
    ${YELLOW}publish${NC}         Publish all artifacts to local Maven
    ${YELLOW}publish-jvm${NC}     Publish JVM artifact to local Maven
    ${YELLOW}publish-remote${NC}  Publish to remote repository (requires credentials)

${BOLD}${GREEN}UTILITY COMMANDS:${NC}
    ${YELLOW}deps${NC}            Show dependency tree
    ${YELLOW}updates${NC}         Check for dependency updates
    ${YELLOW}docs${NC}            Generate API documentation
    ${YELLOW}lint${NC}            Run code quality checks
    ${YELLOW}format${NC}          Auto-format code with ktlint
    ${YELLOW}reset${NC}           Reset Gradle daemon and caches
    ${YELLOW}info${NC}            Show SDK information
    ${YELLOW}help${NC}            Show this help message

${BOLD}${GREEN}OPTIONS:${NC}
    ${CYAN}--publish${NC}       Also publish to local Maven after build
    ${CYAN}--watch${NC}         Watch for changes and rebuild automatically
    ${CYAN}--debug${NC}         Run with debug output
    ${CYAN}--info${NC}          Run with info-level logging
    ${CYAN}--offline${NC}       Run in offline mode (no network)
    ${CYAN}--parallel${NC}      Enable parallel execution
    ${CYAN}--no-cache${NC}      Disable build cache
    ${CYAN}--refresh${NC}       Refresh all dependencies

${BOLD}${GREEN}EXAMPLES:${NC}
    ${CYAN}# Quick JVM build for plugin development${NC}
    ./scripts/sdk.sh jvm

    ${CYAN}# Build and publish JVM to local Maven${NC}
    ./scripts/sdk.sh jvm --publish

    ${CYAN}# Clean and rebuild everything${NC}
    ./scripts/sdk.sh clean all

    ${CYAN}# Run tests with coverage${NC}
    ./scripts/sdk.sh test coverage

    ${CYAN}# Watch mode for continuous JVM builds${NC}
    ./scripts/sdk.sh jvm --watch

    ${CYAN}# Build with debug output${NC}
    ./scripts/sdk.sh jvm --debug

${BOLD}${GREEN}MAVEN COORDINATES:${NC}
    ${CYAN}Group:${NC}    $SDK_GROUP
    ${CYAN}Artifact:${NC} $SDK_NAME-jvm (for JVM/IntelliJ)
    ${CYAN}Version:${NC}  $SDK_VERSION
    ${CYAN}Location:${NC} ~/.m2/repository/com/runanywhere/sdk/

${BOLD}${GREEN}OUTPUT LOCATIONS:${NC}
    ${CYAN}JVM JAR:${NC}  build/libs/$SDK_JAR_NAME-jvm-$SDK_VERSION.jar
    ${CYAN}AAR:${NC}      build/outputs/aar/$SDK_JAR_NAME-release.aar
    ${CYAN}Docs:${NC}     build/dokka/html/index.html
    ${CYAN}Reports:${NC}  build/reports/

${BOLD}${BLUE}For more information, visit the documentation or README.md${NC}
EOF
}

# ============================================================================
# GRADLE EXECUTION WRAPPER
# ============================================================================

# Execute Gradle with appropriate flags based on options
gradle_exec() {
    local gradle_args="$@"

    # Add option flags if set
    [[ "$OPT_DEBUG" == "true" ]] && gradle_args="--debug $gradle_args"
    [[ "$OPT_INFO" == "true" ]] && gradle_args="--info $gradle_args"
    [[ "$OPT_OFFLINE" == "true" ]] && gradle_args="--offline $gradle_args"
    [[ "$OPT_PARALLEL" == "true" ]] && gradle_args="--parallel $gradle_args"
    [[ "$OPT_NO_CACHE" == "true" ]] && gradle_args="--no-build-cache $gradle_args"
    [[ "$OPT_REFRESH" == "true" ]] && gradle_args="--refresh-dependencies $gradle_args"

    # Execute with Gradle wrapper
    ./gradlew $gradle_args
}

# ============================================================================
# BUILD COMMANDS
# ============================================================================

# Clean all build artifacts
cmd_clean() {
    print_header "Cleaning Build Artifacts"
    gradle_exec clean
    rm -rf build/
    print_success "Build artifacts cleaned"
}

# Build JVM target (primary for IntelliJ plugins)
cmd_jvm() {
    print_header "Building JVM Target for IntelliJ Plugin"

    print_step "Compiling JVM sources..."
    gradle_exec :compileKotlinJvm

    print_step "Building JAR artifact..."
    gradle_exec :jvmJar

    local jar_file="build/libs/$SDK_JAR_NAME-jvm-$SDK_VERSION.jar"
    if [[ -f "$jar_file" ]]; then
        print_success "JVM JAR built successfully!"
        print_info "Location: $jar_file"
        print_info "Size: $(du -h "$jar_file" | cut -f1)"

        # Optionally publish
        if [[ "$OPT_PUBLISH" == "true" ]]; then
            cmd_publish_jvm
        fi
    else
        print_error "JAR file not found at expected location"
        exit 1
    fi
}

# Build Android target
cmd_android() {
    print_header "Building Android Target"

    print_step "Assembling Android library..."
    gradle_exec :assembleRelease

    local aar_file="build/outputs/aar/$SDK_NAME-release.aar"
    if [[ -f "$aar_file" ]]; then
        print_success "Android AAR built successfully!"
        print_info "Location: $aar_file"
        print_info "Size: $(du -h "$aar_file" | cut -f1)"
    fi
}

# Build all targets
cmd_all() {
    print_header "Building All Targets"
    gradle_exec build
    print_success "All targets built successfully"
}

# Build native targets
cmd_native() {
    print_header "Building Native Targets"
    gradle_exec :linkReleaseFrameworkMacosArm64
    gradle_exec :linkReleaseFrameworkMacosX64
    gradle_exec :linkReleaseFrameworkLinuxX64
    gradle_exec :linkReleaseFrameworkMingwX64
    print_success "Native targets built"
}

# ============================================================================
# TESTING COMMANDS
# ============================================================================

# Run all tests
cmd_test() {
    print_header "Running All Tests"
    gradle_exec test
    gradle_exec allTests
    print_success "All tests completed"

    # Show test report location if exists
    if [[ -d "build/reports/tests" ]]; then
        print_info "Test report: build/reports/tests/test/index.html"
    fi
}

# Run JVM tests only
cmd_test_jvm() {
    print_header "Running JVM Tests"
    gradle_exec :jvmTest
    print_success "JVM tests completed"
}

# Run Android tests
cmd_test_android() {
    print_header "Running Android Tests"
    gradle_exec :testDebugUnitTest :testReleaseUnitTest
    print_success "Android tests completed"
}

# Generate coverage reports
cmd_coverage() {
    print_header "Generating Test Coverage Reports"
    gradle_exec test jacocoTestReport
    print_success "Coverage reports generated"
    print_info "Report: build/reports/jacoco/test/html/index.html"
}

# ============================================================================
# PUBLISHING COMMANDS
# ============================================================================

# Publish JVM to local Maven (most important for plugin development)
cmd_publish_jvm() {
    print_header "Publishing JVM to Local Maven Repository"

    print_step "Publishing JVM artifact..."
    gradle_exec :publishJvmPublicationToMavenLocal || {
        print_warning "Full publish failed, trying JVM-only tasks..."
        gradle_exec :jvmJar :generatePomFileForJvmPublication :publishJvmPublicationToMavenLocal
    }

    print_success "JVM artifact published to local Maven"
    print_info "Maven coordinates: $SDK_GROUP:$SDK_NAME-jvm:$SDK_VERSION"
    print_info "Location: ~/.m2/repository/com/runanywhere/sdk/$SDK_NAME-jvm/$SDK_VERSION/"

    echo -e "\n${CYAN}To use in your IntelliJ plugin, add to build.gradle.kts:${NC}"
    echo -e "${YELLOW}dependencies {${NC}"
    echo -e "${YELLOW}    implementation(\"$SDK_GROUP:$SDK_NAME-jvm:$SDK_VERSION\")${NC}"
    echo -e "${YELLOW}}${NC}"
}

# Publish all artifacts
cmd_publish() {
    print_header "Publishing to Local Maven Repository"
    gradle_exec publishToMavenLocal
    print_success "All artifacts published"
}

# ============================================================================
# UTILITY COMMANDS
# ============================================================================

# Show SDK information
cmd_info() {
    print_header "SDK Information"
    echo -e "${CYAN}SDK Name:${NC}        $SDK_NAME"
    echo -e "${CYAN}Group ID:${NC}        $SDK_GROUP"
    echo -e "${CYAN}Version:${NC}         $SDK_VERSION"
    echo -e "${CYAN}Project Dir:${NC}     $PROJECT_DIR"
    echo -e "${CYAN}Kotlin Version:${NC}  $(./gradlew -q dependencies | grep 'kotlin-stdlib' | head -1 | cut -d':' -f3 || echo 'Unknown')"
    echo ""

    # Show artifact status
    local jar_file="build/libs/$SDK_JAR_NAME-jvm-$SDK_VERSION.jar"
    if [[ -f "$jar_file" ]]; then
        print_success "JVM JAR exists: $(du -h "$jar_file" | cut -f1)"
    else
        print_warning "JVM JAR not built yet"
    fi

    # Check Maven local
    local maven_dir="$HOME/.m2/repository/com/runanywhere/sdk/$SDK_NAME-jvm/$SDK_VERSION"
    if [[ -d "$maven_dir" ]]; then
        print_success "Published to local Maven"
    else
        print_warning "Not published to local Maven"
    fi
}

# Reset Gradle daemon and caches
cmd_reset() {
    print_header "Resetting Gradle Environment"

    print_step "Stopping Gradle daemon..."
    ./gradlew --stop

    print_step "Cleaning caches..."
    rm -rf ~/.gradle/caches/modules-2/files-2.1/$SDK_GROUP
    rm -rf build/
    rm -rf .gradle/

    print_step "Running clean..."
    gradle_exec clean

    print_success "Gradle environment reset"
}

# Show dependency tree
cmd_deps() {
    print_header "Dependency Tree"
    gradle_exec :dependencies
}

# Check for updates
cmd_updates() {
    print_header "Checking for Dependency Updates"
    gradle_exec dependencyUpdates
}

# Generate documentation
cmd_docs() {
    print_header "Generating API Documentation"
    gradle_exec dokkaHtml
    print_success "Documentation generated"
    print_info "Location: build/dokka/html/index.html"
}

# Run lint checks
cmd_lint() {
    print_header "Running Code Quality Checks"
    gradle_exec ktlintCheck || true
    gradle_exec detekt || true
    print_info "Lint checks completed"
}

# Format code
cmd_format() {
    print_header "Formatting Code"
    gradle_exec ktlintFormat
    print_success "Code formatted"
}

# ============================================================================
# WATCH MODE
# ============================================================================

# Watch for changes and rebuild
watch_mode() {
    local command=$1
    print_header "Watch Mode - Press Ctrl+C to stop"
    print_info "Watching for changes in src/ directory..."

    # Initial build
    $command

    # Watch for changes (requires fswatch or inotify-tools)
    if command -v fswatch &> /dev/null; then
        fswatch -o -r src/ | while read; do
            clear
            print_header "Change detected - Rebuilding..."
            $command
        done
    elif command -v inotifywait &> /dev/null; then
        while true; do
            inotifywait -r -e modify,create,delete src/
            clear
            print_header "Change detected - Rebuilding..."
            $command
        done
    else
        print_error "Watch mode requires fswatch (macOS) or inotify-tools (Linux)"
        print_info "Install with: brew install fswatch (macOS) or apt-get install inotify-tools (Linux)"
        exit 1
    fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

# Parse global options
OPT_PUBLISH=false
OPT_WATCH=false
OPT_DEBUG=false
OPT_INFO=false
OPT_OFFLINE=false
OPT_PARALLEL=false
OPT_NO_CACHE=false
OPT_REFRESH=false

COMMANDS=()

# Process all arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --publish)   OPT_PUBLISH=true; shift ;;
        --watch)     OPT_WATCH=true; shift ;;
        --debug)     OPT_DEBUG=true; shift ;;
        --info)      OPT_INFO=true; shift ;;
        --offline)   OPT_OFFLINE=true; shift ;;
        --parallel)  OPT_PARALLEL=true; shift ;;
        --no-cache)  OPT_NO_CACHE=true; shift ;;
        --refresh)   OPT_REFRESH=true; shift ;;
        --help|-h)   show_help; exit 0 ;;
        --*)         print_error "Unknown option: $1"; show_help; exit 1 ;;
        *)           COMMANDS+=("$1"); shift ;;
    esac
done

# Default to help if no commands
if [[ ${#COMMANDS[@]} -eq 0 ]]; then
    show_help
    exit 0
fi

# Execute commands in order
for cmd in "${COMMANDS[@]}"; do
    # Map command to function
    case $cmd in
        # Primary commands
        clean)          cmd_clean ;;
        jvm)
            if [[ "$OPT_WATCH" == "true" ]]; then
                watch_mode cmd_jvm
            else
                cmd_jvm
            fi
            ;;
        android)        cmd_android ;;
        native)         cmd_native ;;
        all)            cmd_all ;;

        # Build commands
        jar)            cmd_jvm ;;
        aar)            cmd_android ;;
        compile)        gradle_exec compileKotlin ;;

        # Test commands
        test)           cmd_test ;;
        test-jvm)       cmd_test_jvm ;;
        test-android)   cmd_test_android ;;
        test-native)    gradle_exec nativeTest ;;
        coverage)       cmd_coverage ;;

        # Publishing
        publish)        cmd_publish ;;
        publish-jvm)    cmd_publish_jvm ;;
        publish-remote) print_warning "Remote publishing not configured"; exit 1 ;;

        # Utilities
        deps)           cmd_deps ;;
        updates)        cmd_updates ;;
        docs)           cmd_docs ;;
        lint)           cmd_lint ;;
        format)         cmd_format ;;
        reset)          cmd_reset ;;
        info)           cmd_info ;;
        help)           show_help ;;

        # Unknown command
        *)
            print_error "Unknown command: $cmd"
            echo ""
            show_help
            exit 1
            ;;
    esac
done

print_success "All operations completed successfully!"
