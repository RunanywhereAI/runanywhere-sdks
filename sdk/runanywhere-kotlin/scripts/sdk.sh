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
    ${YELLOW}plugin${NC}          Build SDK and plugin for IntelliJ IDEA
    ${YELLOW}plugin-as${NC}       Build SDK and plugin for Android Studio
    ${YELLOW}run-plugin${NC}      Build and run IntelliJ IDEA with plugin
    ${YELLOW}run-plugin-as${NC}   Build and run Android Studio with plugin
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

${BOLD}${GREEN}CONFIGURATION COMMANDS:${NC}
    ${YELLOW}config-dev${NC}      Configure SDK for development environment
    ${YELLOW}config-staging${NC}  Configure SDK for staging environment
    ${YELLOW}config-prod${NC}     Configure SDK for production environment
    ${YELLOW}config-show${NC}     Show current configuration (masked)
    ${YELLOW}config-validate${NC} Validate current configuration

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
    ${CYAN}--ide-type${NC}      Override IDE type (IC, IU, AS)
    ${CYAN}--ide-version${NC}   Override IDE version (e.g., 2023.3, 2024.1)

${BOLD}${GREEN}EXAMPLES:${NC}
    ${CYAN}# Quick JVM build for plugin development${NC}
    ./scripts/sdk.sh jvm

    ${CYAN}# Build and run plugin in IntelliJ IDEA${NC}
    ./scripts/sdk.sh run-plugin

    ${CYAN}# Build and run plugin in Android Studio${NC}
    ./scripts/sdk.sh run-plugin-as

    ${CYAN}# Build plugin for Android Studio only${NC}
    ./scripts/sdk.sh plugin-as

    ${CYAN}# Clean and rebuild everything${NC}
    ./scripts/sdk.sh clean all

    ${CYAN}# Build with debug output${NC}
    ./scripts/sdk.sh jvm --debug

    ${CYAN}# Force Android Studio configuration${NC}
    ./scripts/sdk.sh run-plugin-as --ide-type AS --ide-version 2024.1.1

    ${CYAN}# Override IntelliJ version${NC}
    ./scripts/sdk.sh plugin --ide-type IC --ide-version 2024.2

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
    # Set up configuration if environment specified
    if [[ -n "$OPT_ENV" ]]; then
        print_step "Setting up $OPT_ENV configuration..."
        "$SCRIPT_DIR/config-manager.sh" setup "$OPT_ENV"
    fi

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
# CONFIGURATION COMMANDS
# ============================================================================

# Configure SDK for development
cmd_config_dev() {
    print_header "Configuring SDK for Development"
    "$SCRIPT_DIR/config-manager.sh" setup dev
    print_success "SDK configured for development"
}

# Configure SDK for staging
cmd_config_staging() {
    print_header "Configuring SDK for Staging"
    "$SCRIPT_DIR/config-manager.sh" setup staging
    print_success "SDK configured for staging"
}

# Configure SDK for production
cmd_config_prod() {
    print_header "Configuring SDK for Production"
    "$SCRIPT_DIR/config-manager.sh" setup prod
    print_success "SDK configured for production"
}

# Show current configuration
cmd_config_show() {
    print_header "Current Configuration"
    "$SCRIPT_DIR/config-manager.sh" show
}

# Validate current configuration
cmd_config_validate() {
    print_header "Validating Configuration"
    "$SCRIPT_DIR/config-manager.sh" validate
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
OPT_IDE_TYPE=""
OPT_IDE_VERSION=""
OPT_ENV=""

COMMANDS=()

# Process all arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --publish)      OPT_PUBLISH=true; shift ;;
        --watch)        OPT_WATCH=true; shift ;;
        --debug)        OPT_DEBUG=true; shift ;;
        --info)         OPT_INFO=true; shift ;;
        --offline)      OPT_OFFLINE=true; shift ;;
        --parallel)     OPT_PARALLEL=true; shift ;;
        --no-cache)     OPT_NO_CACHE=true; shift ;;
        --refresh)      OPT_REFRESH=true; shift ;;
        --ide-type)     OPT_IDE_TYPE="$2"; shift 2 ;;
        --ide-version)  OPT_IDE_VERSION="$2"; shift 2 ;;
        --env)          OPT_ENV="$2"; shift 2 ;;
        --help|-h)      show_help; exit 0 ;;
        --*)            print_error "Unknown option: $1"; show_help; exit 1 ;;
        *)              COMMANDS+=("$1"); shift ;;
    esac
done

# Default to help if no commands
if [[ ${#COMMANDS[@]} -eq 0 ]]; then
    show_help
    exit 0
fi

# Detect installed IDEs
detect_ide() {
    local ide_type=$1
    local detect_script="$SCRIPT_DIR/detect-ide.sh"

    if [[ -f "$detect_script" ]]; then
        local result
        if [[ "$ide_type" == "AS" ]]; then
            result=$("$detect_script" | grep "^AS:" | head -1)
        else
            result=$("$detect_script" | grep -E "^(IC|IU):" | head -1)
        fi

        if [[ -n "$result" ]]; then
            echo "$result"
        fi
    fi
}

# Helper function to get compatible plugin configuration for IDE
get_ide_config() {
    local ide_type=$1
    local ide_info=$2

    # Default configurations
    local config_type="IC"
    local config_version="2023.3"
    local config_plugins='"java"'
    local config_until_build="251.*"

    # Apply command line overrides first
    if [[ -n "$OPT_IDE_TYPE" ]]; then
        ide_type="$OPT_IDE_TYPE"
    fi

    if [[ -n "$OPT_IDE_VERSION" ]]; then
        # Create synthetic ide_info with overridden version
        ide_info="$ide_type:$OPT_IDE_VERSION:overridden:"
    fi

    if [[ -n "$ide_info" ]]; then
        local detected_version=$(echo "$ide_info" | cut -d':' -f2)
        local build_major=$(echo "$ide_info" | cut -d':' -f4)

        # Map detected version to compatible plugin platform version
        if [[ "$ide_type" == "AS" ]]; then
            # Android Studio version mapping
            # For Android Studio, we use IntelliJ platform with compatible version
            case "$detected_version" in
                2023.*|2024.1.*)
                    config_type="IC"
                    config_version="2023.3"
                    config_plugins='"java"'
                    config_until_build="241.*"
                    ;;
                2024.2.*|2025.*)
                    config_type="IC"
                    config_version="2024.1"
                    config_plugins='"java"'
                    config_until_build="251.*"
                    ;;
                *)
                    # Fallback for newer versions
                    config_type="IC"
                    config_version="2024.1"
                    config_plugins='"java"'
                    config_until_build="251.*"
                    ;;
            esac
        else
            # IntelliJ IDEA version mapping
            case "$detected_version" in
                2023.*)
                    config_type="IC"
                    config_version="2023.3"
                    config_plugins='"java"'
                    config_until_build="241.*"
                    ;;
                2024.1.*)
                    config_type="IC"
                    config_version="2024.1"
                    config_plugins='"java"'
                    config_until_build="251.*"
                    ;;
                2024.2.*|2024.3.*|2025.*)
                    config_type="IC"
                    config_version="2024.2"
                    config_plugins='"java"'
                    config_until_build="251.*"
                    ;;
                *)
                    # Fallback for newer versions - be more permissive
                    config_type="IC"
                    config_version="2024.2"
                    config_plugins='"java"'
                    config_until_build="261.*"
                    ;;
            esac
        fi

        # Override until_build if we detected build number
        if [[ -n "$build_major" && "$build_major" -gt 0 ]]; then
            local next_major=$((build_major + 20))  # More conservative buffer
            config_until_build="${next_major}.*"
        fi
    fi

    echo "$config_type:$config_version:$config_plugins:$config_until_build"
}

# Helper function to update plugin build configuration for IDE type
update_plugin_for_ide() {
    local plugin_dir=$1
    local ide_type=$2
    local ide_info=$3

    # Show override info before getting config
    if [[ -n "$OPT_IDE_TYPE" ]]; then
        print_info "Using command line IDE type override: $OPT_IDE_TYPE"
    fi

    if [[ -n "$OPT_IDE_VERSION" ]]; then
        print_info "Using command line IDE version override: $OPT_IDE_VERSION"
    fi

    # Get optimal configuration for this IDE
    local config=$(get_ide_config "$ide_type" "$ide_info")
    local config_type=$(echo "$config" | cut -d':' -f1)
    local config_version=$(echo "$config" | cut -d':' -f2)
    local config_plugins=$(echo "$config" | cut -d':' -f3)
    local config_until_build=$(echo "$config" | cut -d':' -f4)

    print_info "Configuring plugin:"
    print_info "  - Platform: $config_type $config_version"
    print_info "  - Plugins: $config_plugins"
    print_info "  - Compatibility: up to $config_until_build"

    # Update build.gradle.kts for the specific IDE
    cat > "$plugin_dir/build.gradle.kts.tmp" << EOF
plugins {
    id("org.jetbrains.intellij") version "1.17.4"
    kotlin("jvm") version "1.9.20"
}

group = "com.runanywhere"
version = "1.0.0"

intellij {
    version.set("$config_version")
    type.set("$config_type")
    plugins.set(listOf($config_plugins))
}

repositories {
    mavenLocal()
    mavenCentral()
}

dependencies {
    // RunAnywhere KMP SDK
    implementation("com.runanywhere.sdk:RunAnywhereKotlinSDK-jvm:$SDK_VERSION")

    // Coroutines
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.7.3")
}

tasks {
    patchPluginXml {
        sinceBuild.set("233")
        untilBuild.set("$config_until_build")
        changeNotes.set(
            """
            <h2>1.0.0</h2>
            <ul>
                <li>Initial release</li>
                <li>Voice command support</li>
                <li>Voice dictation mode</li>
                <li>Whisper-based transcription</li>
            </ul>
        """.trimIndent()
        )
    }

    buildPlugin {
        archiveFileName.set("runanywhere-voice-\${project.version}.zip")
    }

    publishPlugin {
        token.set(System.getenv("JETBRAINS_TOKEN"))
    }
}

kotlin {
    jvmToolchain(17)
}
EOF
    mv "$plugin_dir/build.gradle.kts.tmp" "$plugin_dir/build.gradle.kts"
}

# Plugin command - build SDK and plugin together for IntelliJ IDEA
cmd_plugin() {
    build_plugin_for_ide "IC" "IntelliJ IDEA"
}

# Plugin command for Android Studio
cmd_plugin_as() {
    build_plugin_for_ide "AS" "Android Studio"
}

# Generic plugin builder for any IDE
build_plugin_for_ide() {
    local ide_type=$1
    local ide_name=$2

    print_header "Building SDK and $ide_name Plugin"

    # Step 1: Build and publish SDK
    print_step "Building and publishing SDK to local Maven..."
    cmd_jvm
    cmd_publish_jvm

    # Step 2: Find plugin directory using relative path
    # Script is in sdk/runanywhere-kotlin/scripts, plugin is in examples/intellij-plugin-demo/plugin
    local plugin_dir="$(cd "$SCRIPT_DIR/../../../examples/intellij-plugin-demo/plugin" 2>/dev/null && pwd)"

    if [[ -z "$plugin_dir" ]] || [[ ! -d "$plugin_dir" ]]; then
        print_warning "Plugin directory not found. Looking for alternative locations..."
        # Try to find it relative to git root if in a git repo
        local git_root="$(git rev-parse --show-toplevel 2>/dev/null)"
        if [[ -n "$git_root" ]]; then
            plugin_dir="$git_root/examples/intellij-plugin-demo/plugin"
        fi

        if [[ ! -d "$plugin_dir" ]]; then
            print_error "Could not find plugin directory. Expected at: examples/intellij-plugin-demo/plugin"
            print_info "Please ensure the plugin project exists relative to the SDK"
            exit 1
        fi
    fi

    print_info "Plugin directory: $plugin_dir"

    # Step 3: Detect IDE and configure
    local ide_info=$(detect_ide "$ide_type")

    if [[ -n "$ide_info" ]]; then
        local detected_version=$(echo "$ide_info" | cut -d':' -f2)
        print_info "Detected $ide_name version: $detected_version"
    else
        print_warning "Could not auto-detect $ide_name installation"
        print_info "Using default configuration"
    fi

    # Configure plugin for detected/default IDE
    print_step "Configuring plugin for $ide_name..."
    update_plugin_for_ide "$plugin_dir" "$ide_type" "$ide_info"

    # Step 4: Build the plugin
    print_step "Building IntelliJ plugin..."
    cd "$plugin_dir"

    # Check if gradlew exists, if not use system gradle
    if [[ -f "./gradlew" ]]; then
        ./gradlew clean buildPlugin
    elif command -v gradle &> /dev/null; then
        gradle clean buildPlugin
    else
        print_error "Neither gradlew nor gradle found. Please install Gradle or add gradle wrapper."
        exit 1
    fi

    # Check for built plugin
    local plugin_zip=$(find "$plugin_dir/build/distributions" -name "*.zip" 2>/dev/null | head -1)
    if [[ -f "$plugin_zip" ]]; then
        print_success "Plugin built successfully!"
        print_info "Plugin ZIP: $plugin_zip"
        print_info "To install: File > Settings > Plugins > Install Plugin from Disk"
    else
        print_error "Plugin build failed - no ZIP file found"
        exit 1
    fi
}

# Run plugin - build and run IntelliJ with plugin
cmd_run_plugin() {
    run_plugin_for_ide "IC" "IntelliJ IDEA"
}

# Run plugin in Android Studio
cmd_run_plugin_as() {
    run_plugin_for_ide "AS" "Android Studio"
}

# Generic runner for any IDE
run_plugin_for_ide() {
    local ide_type=$1
    local ide_name=$2

    print_header "Running $ide_name Plugin with Latest SDK"

    # First build everything
    build_plugin_for_ide "$ide_type" "$ide_name"

    # Find plugin directory (same logic as above)
    local plugin_dir="$(cd "$SCRIPT_DIR/../../../examples/intellij-plugin-demo/plugin" 2>/dev/null && pwd)"

    if [[ -z "$plugin_dir" ]] || [[ ! -d "$plugin_dir" ]]; then
        local git_root="$(git rev-parse --show-toplevel 2>/dev/null)"
        if [[ -n "$git_root" ]]; then
            plugin_dir="$git_root/examples/intellij-plugin-demo/plugin"
        fi
    fi

    if [[ ! -d "$plugin_dir" ]]; then
        print_error "Could not find plugin directory"
        exit 1
    fi

    # Run the plugin
    print_step "Starting IntelliJ with plugin..."
    cd "$plugin_dir"

    if [[ -f "./gradlew" ]]; then
        ./gradlew runIde
    elif command -v gradle &> /dev/null; then
        gradle runIde
    else
        print_error "Neither gradlew nor gradle found"
        exit 1
    fi
}

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

        # Plugin commands
        plugin)         cmd_plugin ;;
        plugin-as)      cmd_plugin_as ;;
        run-plugin)     cmd_run_plugin ;;
        run-plugin-as)  cmd_run_plugin_as ;;

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

        # Configuration
        config-dev)     cmd_config_dev ;;
        config-staging) cmd_config_staging ;;
        config-prod)    cmd_config_prod ;;
        config-show)    cmd_config_show ;;
        config-validate) cmd_config_validate ;;

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
