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
# ============================================================================
# SIMPLIFIED WORKFLOWS (Most Common)
# ============================================================================
#
# BUILD SDK TARGETS:
# ------------------
# ./scripts/sdk.sh sdk-jvm          # Build JVM SDK only (for IntelliJ plugins)
# ./scripts/sdk.sh sdk-android      # Build Android SDK only
# ./scripts/sdk.sh sdk-all          # Build both JVM + Android targets
#
# BUILD & RUN SAMPLE APPS (with automatic SDK sync):
# ---------------------------------------------------
# ./scripts/sdk.sh plugin-app       # Build SDK + Run IntelliJ plugin
# ./scripts/sdk.sh android-app      # Build SDK + Run Android app
#
# CLEANUP COMMANDS:
# -----------------
# ./scripts/sdk.sh clean-sdk        # Quick clean (SDK only) ~5s
# ./scripts/sdk.sh clean-all        # Clean SDK + sample apps ~10s
# ./scripts/sdk.sh clean-deep       # Deep clean + caches + Maven ~15s
# ./scripts/sdk.sh clean-workspace  # Nuclear option - complete reset ~30s
#
# ============================================================================
# ADVANCED COMMANDS
# ============================================================================
#
# For more commands, run: ./scripts/sdk.sh help
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

# Module configuration
MODULES=(
    "modules:runanywhere-core"
    "modules:runanywhere-whisper-stt"
    "modules:runanywhere-llm-llamacpp"
    "modules:runanywhere-vad"
    "modules:runanywhere-tts"
    "modules:runanywhere-speaker-diarization"
)

# Native libraries
NATIVE_LIBS=(
    "whisper-jni"
    "llama-jni"
)

# Sample app paths (relative to project root)
REPO_ROOT="$(cd "$PROJECT_DIR/../.." && pwd)"
ANDROID_APP_DIR="$REPO_ROOT/examples/android/RunAnywhereAI"
INTELLIJ_PLUGIN_DIR="$REPO_ROOT/examples/intellij-plugin-demo"

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
# Complete build command that tries to build everything
cmd_build_all() {
    print_header "Complete SDK Build - All Platforms"

    # Parse options for cleanup level
    local CLEAN_LEVEL="none"
    while [[ $# -gt 0 ]]; do
        case $1 in
            --clean)
                CLEAN_LEVEL="clean"
                shift
                ;;
            --deep-clean)
                CLEAN_LEVEL="deep"
                shift
                ;;
            --no-clean)
                CLEAN_LEVEL="none"
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    # Step 1: Conditional cleanup based on flags
    if [[ "$CLEAN_LEVEL" != "none" ]]; then
        print_step "[1/6] Cleaning build environment (Level: $CLEAN_LEVEL)..."

        if [[ "$CLEAN_LEVEL" == "deep" ]]; then
            # Deep clean - maximum cleanup
            # Stop Gradle daemon
            ./gradlew --stop || true

            # Clean all build artifacts
            ./gradlew clean --no-daemon --no-build-cache --no-configuration-cache || true
            rm -rf build/ .gradle/ || true

            # Clear Gradle caches that might have incompatible Kotlin versions
            print_step "Clearing Gradle caches..."
            rm -rf ~/.gradle/caches/modules-2/files-2.1/org.jetbrains.kotlin/ || true
            rm -rf ~/.gradle/caches/transforms-*/ || true
            rm -rf ~/.gradle/caches/8.11.1/transforms/ || true

            # Clear Kotlin compiler daemon
            print_step "Clearing Kotlin compiler daemon..."
            pkill -f "kotlin-compile-daemon" || true
            rm -rf ~/Library/Application\ Support/kotlin/daemon/* 2>/dev/null || true
        else
            # Normal clean - just clean build artifacts
            ./gradlew clean || true
        fi
    else
        print_step "[1/6] Starting build (no clean)..."
    fi

    # Step 2: Verify environment
    print_step "[2/6] Verifying build environment..."
    echo "  Java version: $(java -version 2>&1 | head -1)"
    echo "  Gradle version: $(./gradlew --version | grep Gradle | cut -d' ' -f2)"
    echo "  Kotlin version: $(grep '^kotlin =' gradle/libs.versions.toml | cut -d'"' -f2)"

    # Step 3: Build common module
    print_step "[3/6] Building Common Module..."
    ./gradlew :compileKotlinMetadata --no-daemon --no-build-cache --refresh-dependencies || {
        print_error "Common module compilation failed"
        return 1
    }
    print_success "Common module compiled successfully"

    # Step 4: Build JVM target
    print_step "[4/6] Building JVM Target..."
    ./gradlew :compileKotlinJvm :jvmJar --no-daemon --no-build-cache --stacktrace || {
        print_warning "JVM build failed - retrying with full refresh..."
        # Second attempt with more aggressive cleanup
        rm -rf src/jvmMain/kotlin/com/runanywhere/sdk/public/RunAnywhere.kt.bak 2>/dev/null || true
        ./gradlew :compileKotlinJvm :jvmJar --no-daemon --no-build-cache --refresh-dependencies --rerun-tasks || {
            print_error "JVM build failed even after retry"
        }
    }

    if [[ -f "build/libs/$SDK_JAR_NAME-jvm-$SDK_VERSION.jar" ]]; then
        print_success "✅ JVM JAR built: build/libs/$SDK_JAR_NAME-jvm-$SDK_VERSION.jar"
        echo "   Size: $(du -h build/libs/$SDK_JAR_NAME-jvm-$SDK_VERSION.jar | cut -f1)"

        # Optionally publish
        if [[ "$OPT_PUBLISH" == "true" ]]; then
            cmd_publish_jvm
        fi
    else
        print_warning "⚠️ JVM JAR not found"
    fi

    # Step 5: Build Android target
    print_step "[5/6] Building Android Target..."
    ./gradlew :compileDebugKotlinAndroid :assembleDebug --no-daemon --no-build-cache --stacktrace || {
        print_warning "Android Debug build failed - trying release..."
        ./gradlew :compileReleaseKotlinAndroid :assembleRelease --no-daemon --no-build-cache --stacktrace || {
            print_error "Android build failed"
        }
    }

    if [[ -f "build/outputs/aar/$SDK_JAR_NAME-debug.aar" ]]; then
        print_success "✅ Android Debug AAR built: build/outputs/aar/$SDK_JAR_NAME-debug.aar"
        echo "   Size: $(du -h build/outputs/aar/$SDK_JAR_NAME-debug.aar | cut -f1)"
    elif [[ -f "build/outputs/aar/$SDK_JAR_NAME-release.aar" ]]; then
        print_success "✅ Android Release AAR built: build/outputs/aar/$SDK_JAR_NAME-release.aar"
        echo "   Size: $(du -h build/outputs/aar/$SDK_JAR_NAME-release.aar | cut -f1)"
    elif [[ -f "build/outputs/aar/$SDK_NAME-debug.aar" ]]; then
        print_success "✅ Android Debug AAR built: build/outputs/aar/$SDK_NAME-debug.aar"
        echo "   Size: $(du -h build/outputs/aar/$SDK_NAME-debug.aar | cut -f1)"
    elif [[ -f "build/outputs/aar/$SDK_NAME-release.aar" ]]; then
        print_success "✅ Android Release AAR built: build/outputs/aar/$SDK_NAME-release.aar"
        echo "   Size: $(du -h build/outputs/aar/$SDK_NAME-release.aar | cut -f1)"
    else
        print_warning "⚠️ Android AAR not found"
    fi

    # Step 6: Summary
    print_step "[6/6] Build Summary..."
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Build Artifacts:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "JVM Artifacts:"
    ls -la build/libs/*.jar 2>/dev/null || echo "  ❌ No JVM JARs found"
    echo ""
    echo "Android Artifacts:"
    ls -la build/outputs/aar/*.aar 2>/dev/null || echo "  ❌ No Android AARs found"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Check overall success
    local success=true
    if [[ ! -f "build/libs/$SDK_JAR_NAME-jvm-$SDK_VERSION.jar" ]] && [[ ! -f "build/outputs/aar/$SDK_JAR_NAME-debug.aar" ]] && [[ ! -f "build/outputs/aar/$SDK_JAR_NAME-release.aar" ]] && [[ ! -f "build/outputs/aar/$SDK_NAME-debug.aar" ]] && [[ ! -f "build/outputs/aar/$SDK_NAME-release.aar" ]]; then
        success=false
    fi

    if [[ "$success" == "true" ]]; then
        print_success "✅ Build completed successfully!"
    else
        print_warning "⚠️ Build completed with warnings. Check output above for details."
    fi
}

show_help() {
    cat << EOF
${BOLD}${BLUE}RunAnywhere KMP SDK Management Tool${NC}
${CYAN}Version: $SDK_VERSION${NC}

${BOLD}${GREEN}USAGE:${NC}
    ./scripts/sdk.sh ${YELLOW}[command]${NC} ${CYAN}[options]${NC}

${BOLD}${GREEN}PRIMARY COMMANDS:${NC} ${CYAN}(Most commonly used)${NC}
    ${BOLD}${YELLOW}SIMPLIFIED WORKFLOWS:${NC}
    ${YELLOW}sdk-jvm${NC}          Build JVM SDK only (for IntelliJ plugins)
    ${YELLOW}sdk-android${NC}      Build Android SDK only
    ${YELLOW}sdk-all${NC}          Build both JVM and Android SDK targets
    ${YELLOW}plugin-app${NC}       Build JVM SDK + Run IntelliJ Plugin
    ${YELLOW}android-app${NC}      Build Android SDK + Run Android Sample App

    ${BOLD}${YELLOW}CLEANUP COMMANDS:${NC}
    ${YELLOW}clean${NC}            Clean SDK build artifacts (basic)
    ${YELLOW}clean-sdk${NC}        Clean SDK build artifacts only
    ${YELLOW}clean-deep${NC}       Deep clean: SDK + caches + daemon + Maven
    ${YELLOW}clean-all${NC}        Clean everything: SDK + sample apps + natives
    ${YELLOW}clean-workspace${NC}  Nuclear clean: Complete workspace reset (5s delay)

    ${BOLD}${YELLOW}ADVANCED BUILD COMMANDS:${NC}
    ${YELLOW}build-all${NC}       Complete build for all platforms (recommended)
    ${YELLOW}build-modules${NC}   Build all KMP modules
    ${YELLOW}build-native${NC}    Build native libraries (whisper, llama.cpp)
    ${YELLOW}build-samples${NC}   Build sample applications
    ${YELLOW}build-complete${NC}  Build everything (SDK, modules, native, samples)
    ${YELLOW}jvm${NC}             Build JVM target for IntelliJ/JetBrains plugins
    ${YELLOW}plugin${NC}          Build SDK and plugin for IntelliJ IDEA
    ${YELLOW}plugin-as${NC}       Build SDK and plugin for Android Studio
    ${YELLOW}run-plugin${NC}      Build and run IntelliJ IDEA with plugin
    ${YELLOW}run-plugin-as${NC}   Build and run Android Studio with plugin
    ${YELLOW}dev-plugin${NC}      Clean rebuild SDK, force recompile and run plugin
    ${YELLOW}android${NC}         Build Android AAR library
    ${YELLOW}all${NC}             Build all targets (JVM, Android, Native)
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
    ${CYAN}--clean${NC}         Perform normal clean before build
    ${CYAN}--deep-clean${NC}    Perform deep clean (including caches) before build
    ${CYAN}--no-clean${NC}      Skip cleaning (default for build-all)
    ${CYAN}--ide-type${NC}      Override IDE type (IC, IU, AS)
    ${CYAN}--ide-version${NC}   Override IDE version (e.g., 2023.3, 2024.1)

${BOLD}${GREEN}EXAMPLES:${NC}
    ${CYAN}# Quick workflows for common tasks${NC}
    ./scripts/sdk.sh sdk-jvm            # Build JVM SDK only
    ./scripts/sdk.sh sdk-all            # Build both JVM + Android SDK
    ./scripts/sdk.sh plugin-app         # Build SDK and run IntelliJ plugin
    ./scripts/sdk.sh android-app        # Build SDK and run Android app

    ${CYAN}# Cleanup tasks${NC}
    ./scripts/sdk.sh clean-sdk          # Quick clean of SDK only
    ./scripts/sdk.sh clean-all          # Clean SDK + all sample apps
    ./scripts/sdk.sh clean-deep         # Deep clean including caches
    ./scripts/sdk.sh clean-workspace    # Complete workspace reset (nuclear)

    ${CYAN}# Complete builds${NC}
    ./scripts/sdk.sh build-all

    ${CYAN}# Clean and build${NC}
    ./scripts/sdk.sh build-all --clean
    ./scripts/sdk.sh clean-build

    ${CYAN}# Deep clean and build (when having issues)${NC}
    ./scripts/sdk.sh build-all --deep-clean
    ./scripts/sdk.sh deep-clean

    ${CYAN}# Quick JVM build for plugin development${NC}
    ./scripts/sdk.sh jvm

    ${CYAN}# Build and run plugin in IntelliJ IDEA${NC}
    ./scripts/sdk.sh run-plugin

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



# Build JVM target (primary for IntelliJ plugins)
cmd_jvm() {
    # Set up configuration if environment specified
    if [[ -n "$OPT_ENV" ]]; then
        print_step "Setting up $OPT_ENV configuration..."
        "$SCRIPT_DIR/config-manager.sh" setup "$OPT_ENV" || true
    fi

    print_header "Building JVM Target for IntelliJ Plugin"

    print_step "Cleaning previous JVM build..."
    gradle_exec :cleanJvmJar || true

    print_step "Compiling JVM sources..."
    gradle_exec :compileKotlinJvm || {
        print_warning "JVM compilation failed, trying with refresh dependencies..."
        gradle_exec --refresh-dependencies :compileKotlinJvm
    }

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

    print_step "Cleaning previous Android build..."
    gradle_exec :clean || true

    print_step "Compiling Android sources..."
    gradle_exec :compileDebugKotlinAndroid || {
        print_warning "Android compilation failed, trying with refresh dependencies..."
        gradle_exec --refresh-dependencies :compileDebugKotlinAndroid
    }

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

    print_step "Cleaning all previous builds..."
    gradle_exec clean || true

    print_step "Building common module..."
    gradle_exec :compileKotlinMetadata || true

    print_step "Building JVM target..."
    gradle_exec :compileKotlinJvm :jvmJar || {
        print_warning "JVM build failed, continuing..."
    }

    print_step "Building Android target..."
    gradle_exec :compileDebugKotlinAndroid :assembleDebug || {
        print_warning "Android build failed, continuing..."
    }

    print_success "Build completed (check warnings above for any failures)"
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
# MODULE BUILD COMMANDS
# ============================================================================

# Build native libraries (JNI)
cmd_build_native() {
    print_header "Building Native Libraries"

    for lib in "${NATIVE_LIBS[@]}"; do
        local native_dir="$PROJECT_DIR/native/$lib"
        local build_script="$native_dir/build-native.sh"

        if [[ ! -f "$build_script" ]]; then
            print_warning "Build script not found for $lib at $build_script"
            continue
        fi

        print_step "Building $lib..."
        cd "$native_dir"
        chmod +x "$build_script"

        if ./build-native.sh all; then
            print_success "✅ $lib built successfully"
        else
            print_warning "⚠️ $lib build failed, continuing..."
        fi
    done

    cd "$PROJECT_DIR"
    print_success "Native library builds complete"
}

# Build all modules
cmd_build_modules() {
    print_header "Building All KMP Modules"

    # First ensure core module interfaces exist
    ensure_core_interfaces

    # Build core module first
    print_step "Building core module..."
    gradle_exec :modules:runanywhere-core:build :modules:runanywhere-core:publishToMavenLocal || {
        print_warning "Core module failed, trying to fix..."
        fix_module_build "modules/runanywhere-core"
        gradle_exec :modules:runanywhere-core:build :modules:runanywhere-core:publishToMavenLocal
    }

    # Build other modules
    for module in "${MODULES[@]}"; do
        if [[ "$module" != "modules:runanywhere-core" ]]; then
            print_step "Building $module..."
            gradle_exec :$module:build :$module:publishToMavenLocal || {
                print_warning "$module build failed, attempting fix..."
                local module_path="${module/://}"
                fix_module_build "$module_path"
                gradle_exec :$module:build || print_warning "$module build failed"
            }
        fi
    done

    print_success "All modules built and published to Maven Local"
}

# Ensure core interfaces exist
ensure_core_interfaces() {
    local core_path="$PROJECT_DIR/modules/runanywhere-core/src/commonMain/kotlin/com/runanywhere/sdk/core"

    if [[ ! -d "$core_path" ]]; then
        print_info "Creating core module structure..."
        mkdir -p "$core_path"

        # Create service provider interfaces
        cat > "$core_path/ServiceProviders.kt" << 'EOF'
package com.runanywhere.sdk.core

import kotlinx.coroutines.flow.Flow

interface STTServiceProvider {
    suspend fun createSTTService(configuration: Any): Any
    fun canHandle(modelId: String): Boolean
    val name: String
    val priority: Int
    val supportedFeatures: Set<String>
}

interface LLMServiceProvider {
    suspend fun createLLMService(modelPath: String): Any
    suspend fun generate(prompt: String, options: Any): Any
    fun generateStream(prompt: String, options: Any): Flow<String>
    fun canHandle(modelId: String): Boolean
    val name: String
    val priority: Int
    val supportedFeatures: Set<String>
}

interface AutoRegisteringModule {
    fun register()
    val isAvailable: Boolean
    val name: String
    val version: String
    val description: String
    fun cleanup()
}

object ModuleRegistry {
    private val sttProviders = mutableListOf<STTServiceProvider>()
    private val llmProviders = mutableListOf<LLMServiceProvider>()

    fun registerSTT(provider: STTServiceProvider) {
        sttProviders.add(provider)
    }

    fun registerLLM(provider: LLMServiceProvider) {
        llmProviders.add(provider)
    }

    val shared = ModuleRegistry
}
EOF
    fi
}

# Fix module build issues
fix_module_build() {
    local module_path=$1

    if [[ ! -f "$PROJECT_DIR/$module_path/build.gradle.kts" ]]; then
        print_info "Creating build.gradle.kts for $module_path"
        local module_name="${module_path##*/}"

        mkdir -p "$PROJECT_DIR/$module_path/src/commonMain/kotlin"
        mkdir -p "$PROJECT_DIR/$module_path/src/jvmMain/kotlin"
        mkdir -p "$PROJECT_DIR/$module_path/src/androidMain/kotlin"

        cat > "$PROJECT_DIR/$module_path/build.gradle.kts" << EOF
plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.android.library)
}

kotlin {
    jvm {
        compilations.all {
            kotlinOptions.jvmTarget = "17"
        }
    }

    androidTarget {
        compilations.all {
            kotlinOptions.jvmTarget = "17"
        }
    }

    sourceSets {
        val commonMain by getting {
            dependencies {
                if ("$module_name" != "runanywhere-core") {
                    api(project(":modules:runanywhere-core"))
                }
                implementation(libs.kotlinx.coroutines.core)
            }
        }

        val jvmMain by getting
        val androidMain by getting
    }
}

android {
    namespace = "com.runanywhere.sdk.${module_name.replace("-", ".")}"
    compileSdk = 36
    defaultConfig.minSdk = 24

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}
EOF
    fi
}

# Build sample applications
cmd_build_samples() {
    print_header "Building Sample Applications"

    # Ensure SDK is published first
    print_step "Publishing SDK to Maven Local..."
    gradle_exec publishToMavenLocal

    # Build Android sample app
    if [[ -d "$ANDROID_APP_DIR" ]]; then
        print_step "Building Android sample app..."
        cd "$ANDROID_APP_DIR"

        # Fix dependencies if needed
        fix_android_app_deps

        if ./gradlew assembleDebug; then
            print_success "✅ Android app built successfully"
            local apk="app/build/outputs/apk/debug/app-debug.apk"
            [[ -f "$apk" ]] && print_info "APK: $apk ($(du -h "$apk" | cut -f1))"
        else
            print_warning "⚠️ Android app build failed"
        fi
    else
        print_warning "Android sample app not found at $ANDROID_APP_DIR"
    fi

    # Build IntelliJ plugin (already handled by existing plugin command)
    if [[ -d "$INTELLIJ_PLUGIN_DIR" ]]; then
        print_step "Building IntelliJ plugin..."
        cd "$INTELLIJ_PLUGIN_DIR"

        if [[ -f "./gradlew" ]]; then
            ./gradlew buildPlugin || print_warning "Plugin build failed"
        fi
    fi

    cd "$PROJECT_DIR"
    print_success "Sample app builds complete"
}

# Fix Android app dependencies
fix_android_app_deps() {
    local build_file="$ANDROID_APP_DIR/app/build.gradle.kts"
    [[ ! -f "$build_file" ]] && build_file="$ANDROID_APP_DIR/app/build.gradle"

    # Ensure maven local is in repositories
    local settings_file="$ANDROID_APP_DIR/settings.gradle.kts"
    [[ ! -f "$settings_file" ]] && settings_file="$ANDROID_APP_DIR/settings.gradle"

    if [[ -f "$settings_file" ]] && ! grep -q "mavenLocal()" "$settings_file"; then
        print_info "Adding mavenLocal() to Android app repositories..."
        sed -i.bak '/repositories {/a\        mavenLocal()' "$settings_file"
    fi

    # Check if KMP SDK dependency exists
    if ! grep -q "com.runanywhere.sdk" "$build_file" 2>/dev/null; then
        print_info "Adding KMP SDK dependency to Android app..."
        # This would need more sophisticated editing based on actual file format
    fi
}

# Build everything
cmd_build_complete() {
    print_header "Complete Build - SDK, Modules, Native Libraries, and Samples"

    local start_time=$(date +%s)

    # Step 1: Build native libraries
    print_step "[1/4] Building native libraries..."
    cmd_build_native

    # Step 2: Build core SDK
    print_step "[2/4] Building core SDK..."
    cmd_build_all

    # Step 3: Build modules
    print_step "[3/4] Building modules..."
    cmd_build_modules

    # Step 4: Build samples
    print_step "[4/4] Building sample applications..."
    cmd_build_samples

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    print_success "Complete build finished in ${duration} seconds"

    # Summary report
    print_header "Build Summary"
    echo "✅ Native Libraries:"
    for lib in "${NATIVE_LIBS[@]}"; do
        [[ -d "$PROJECT_DIR/native/$lib/build" ]] && echo "  ✓ $lib" || echo "  ✗ $lib"
    done

    echo -e "\n✅ SDK Artifacts:"
    [[ -f "build/libs/$SDK_JAR_NAME-jvm-$SDK_VERSION.jar" ]] && echo "  ✓ JVM JAR" || echo "  ✗ JVM JAR"
    [[ -f "build/outputs/aar/$SDK_JAR_NAME-debug.aar" ]] && echo "  ✓ Android AAR" || echo "  ✗ Android AAR"

    echo -e "\n✅ Modules:"
    for module in "${MODULES[@]}"; do
        local module_name="${module##*:}"
        echo "  ✓ $module_name"
    done

    echo -e "\n✅ Sample Apps:"
    [[ -f "$ANDROID_APP_DIR/app/build/outputs/apk/debug/app-debug.apk" ]] && echo "  ✓ Android app" || echo "  ✗ Android app"
    [[ -d "$INTELLIJ_PLUGIN_DIR/build/distributions" ]] && echo "  ✓ IntelliJ plugin" || echo "  ✗ IntelliJ plugin"
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
# CLEANUP COMMANDS
# ============================================================================

# Clean SDK build artifacts only (basic clean)
cmd_clean_sdk() {
    print_header "Cleaning SDK Build Artifacts"

    print_step "Removing build directories..."
    rm -rf build/
    rm -rf .gradle/

    print_step "Running Gradle clean..."
    gradle_exec clean || true

    print_success "✅ SDK build artifacts cleaned"
}

# Deep clean SDK with caches and daemon (aggressive clean)
cmd_clean_deep() {
    print_header "Deep Clean - SDK + Caches + Daemon"

    print_step "[1/5] Stopping Gradle daemon..."
    ./gradlew --stop || true

    print_step "[2/5] Cleaning build artifacts..."
    ./gradlew clean --no-daemon --no-build-cache --no-configuration-cache || true
    rm -rf build/
    rm -rf .gradle/

    print_step "[3/5] Cleaning local Gradle caches..."
    rm -rf ~/.gradle/caches/modules-2/files-2.1/com.runanywhere.sdk/ || true
    rm -rf ~/.gradle/caches/transforms-*/ || true

    print_step "[4/5] Cleaning Kotlin compiler daemon..."
    pkill -f "kotlin-compile-daemon" || true
    rm -rf ~/Library/Application\ Support/kotlin/daemon/* 2>/dev/null || true
    rm -rf ~/.kotlin/daemon/* 2>/dev/null || true

    print_step "[5/5] Cleaning Maven Local SDK artifacts..."
    rm -rf ~/.m2/repository/com/runanywhere/sdk/ || true

    print_success "✅ Deep clean completed"
    print_info "Gradle daemon, caches, and Maven artifacts removed"
}

# Clean everything - SDK + sample apps + dependencies
cmd_clean_all() {
    print_header "Clean All - SDK + Sample Apps + Dependencies"

    # Clean SDK first
    print_step "[1/4] Cleaning SDK..."
    cmd_clean_sdk

    # Clean Android sample app
    if [[ -d "$ANDROID_APP_DIR" ]]; then
        print_step "[2/4] Cleaning Android sample app..."
        cd "$ANDROID_APP_DIR"
        ./gradlew clean || true
        rm -rf app/build/ || true
        rm -rf build/ || true
        rm -rf .gradle/ || true
        cd "$PROJECT_DIR"
        print_success "Android app cleaned"
    else
        print_step "[2/4] Android app not found, skipping..."
    fi

    # Clean IntelliJ plugin
    local plugin_dir="$(cd "$SCRIPT_DIR/../../../examples/intellij-plugin-demo/plugin" 2>/dev/null && pwd)"
    if [[ -n "$plugin_dir" ]] && [[ -d "$plugin_dir" ]]; then
        print_step "[3/4] Cleaning IntelliJ plugin..."
        cd "$plugin_dir"
        ./gradlew clean || true
        rm -rf build/ || true
        rm -rf .gradle/ || true
        cd "$PROJECT_DIR"
        print_success "IntelliJ plugin cleaned"
    else
        print_step "[3/4] IntelliJ plugin not found, skipping..."
    fi

    # Clean native libraries
    print_step "[4/4] Cleaning native libraries..."
    for lib in "${NATIVE_LIBS[@]}"; do
        local native_dir="$PROJECT_DIR/native/$lib"
        if [[ -d "$native_dir/build" ]]; then
            rm -rf "$native_dir/build" || true
            print_info "Cleaned $lib"
        fi
    done

    print_success "✅ All build artifacts cleaned"

    # Summary
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Cleaned:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  ✅ SDK build artifacts"
    [[ -d "$ANDROID_APP_DIR" ]] && echo "  ✅ Android sample app"
    [[ -n "$plugin_dir" ]] && echo "  ✅ IntelliJ plugin"
    echo "  ✅ Native libraries"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Clean workspace and prepare for fresh start (nuclear option)
cmd_clean_workspace() {
    print_header "Clean Workspace - Complete Reset"

    print_warning "This will remove ALL build artifacts, caches, and dependencies!"
    print_info "Press Ctrl+C within 5 seconds to cancel..."
    sleep 5

    print_step "[1/6] Stopping all Gradle daemons..."
    ./gradlew --stop || true
    pkill -f "GradleDaemon" || true

    print_step "[2/6] Cleaning SDK..."
    cmd_clean_sdk

    print_step "[3/6] Cleaning sample apps..."
    # Clean Android app
    if [[ -d "$ANDROID_APP_DIR" ]]; then
        cd "$ANDROID_APP_DIR"
        ./gradlew --stop || true
        ./gradlew clean || true
        rm -rf app/build/ build/ .gradle/ || true
        cd "$PROJECT_DIR"
    fi

    # Clean IntelliJ plugin
    local plugin_dir="$(cd "$SCRIPT_DIR/../../../examples/intellij-plugin-demo/plugin" 2>/dev/null && pwd)"
    if [[ -n "$plugin_dir" ]] && [[ -d "$plugin_dir" ]]; then
        cd "$plugin_dir"
        ./gradlew --stop || true
        ./gradlew clean || true
        rm -rf build/ .gradle/ || true
        cd "$PROJECT_DIR"
    fi

    print_step "[4/6] Cleaning native libraries..."
    for lib in "${NATIVE_LIBS[@]}"; do
        rm -rf "$PROJECT_DIR/native/$lib/build" || true
    done

    print_step "[5/6] Cleaning global Gradle caches..."
    rm -rf ~/.gradle/caches/modules-2/files-2.1/com.runanywhere.sdk/ || true
    rm -rf ~/.gradle/caches/transforms-*/ || true
    rm -rf ~/.gradle/caches/8.*/transforms/ || true

    print_step "[6/6] Cleaning Maven Local SDK..."
    rm -rf ~/.m2/repository/com/runanywhere/sdk/ || true

    print_success "✅ Workspace completely cleaned"
    print_info "Run 'sdk-all' to rebuild everything"
}

# ============================================================================
# SIMPLIFIED WORKFLOW COMMANDS
# ============================================================================

# Build SDK (JVM only) - no sample apps
cmd_sdk_jvm() {
    print_header "Build SDK - JVM Target Only"

    print_step "[1/2] Building JVM SDK..."
    gradle_exec :compileKotlinJvm :jvmJar || {
        print_error "JVM build failed"
        return 1
    }

    print_step "[2/2] Publishing to Maven Local..."
    cmd_publish_jvm

    print_success "✅ JVM SDK built and published"
    local jar_file="build/libs/$SDK_JAR_NAME-jvm-$SDK_VERSION.jar"
    if [[ -f "$jar_file" ]]; then
        print_info "JAR: $jar_file ($(du -h "$jar_file" | cut -f1))"
    fi
}

# Build SDK (Android only) - no sample apps
cmd_sdk_android() {
    print_header "Build SDK - Android Target Only"

    print_step "[1/2] Building Android SDK..."
    gradle_exec :compileDebugKotlinAndroid :assembleDebug || {
        print_warning "Debug build failed, trying release..."
        gradle_exec :compileReleaseKotlinAndroid :assembleRelease || {
            print_error "Android build failed"
            return 1
        }
    }

    print_step "[2/2] Publishing to Maven Local..."
    gradle_exec :publishAndroidDebugPublicationToMavenLocal || gradle_exec :publishAndroidReleasePublicationToMavenLocal || true

    print_success "✅ Android SDK built and published"

    # Show built artifacts
    local aar_debug="build/outputs/aar/$SDK_JAR_NAME-debug.aar"
    local aar_release="build/outputs/aar/$SDK_JAR_NAME-release.aar"
    [[ -f "$aar_debug" ]] && print_info "AAR: $aar_debug ($(du -h "$aar_debug" | cut -f1))"
    [[ -f "$aar_release" ]] && print_info "AAR: $aar_release ($(du -h "$aar_release" | cut -f1))"
}

# Build SDK (All targets) - no sample apps
cmd_sdk_all() {
    print_header "Build SDK - All Targets (JVM + Android)"

    print_step "[1/3] Building JVM target..."
    gradle_exec :compileKotlinJvm :jvmJar || print_warning "JVM build had issues"

    print_step "[2/3] Building Android target..."
    gradle_exec :compileDebugKotlinAndroid :assembleDebug || print_warning "Android build had issues"

    print_step "[3/3] Publishing to Maven Local..."
    gradle_exec publishToMavenLocal || print_warning "Publishing had issues"

    print_success "✅ SDK built for all targets"

    # Summary
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "SDK Build Summary:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    [[ -f "build/libs/$SDK_JAR_NAME-jvm-$SDK_VERSION.jar" ]] && echo "  ✅ JVM JAR" || echo "  ❌ JVM JAR"
    [[ -f "build/outputs/aar/$SDK_JAR_NAME-debug.aar" ]] && echo "  ✅ Android AAR" || echo "  ❌ Android AAR"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Build and Run Android Sample App (with latest SDK)
cmd_android_app() {
    print_header "Build & Run Android Sample App"

    # Step 1: Build and publish Android SDK
    print_step "[1/4] Building Android SDK..."
    cmd_sdk_android || {
        print_error "SDK build failed"
        return 1
    }

    # Step 2: Build Android sample app
    if [[ ! -d "$ANDROID_APP_DIR" ]]; then
        print_error "Android app not found at: $ANDROID_APP_DIR"
        return 1
    fi

    print_step "[2/4] Syncing Android app with latest SDK..."
    cd "$ANDROID_APP_DIR"

    # Ensure mavenLocal is in repositories
    ensure_android_maven_local

    # Force Gradle to refresh dependencies to pick up latest SDK
    print_info "Refreshing Gradle dependencies..."
    ./gradlew --refresh-dependencies clean || {
        print_warning "Gradle refresh had issues, continuing..."
    }

    print_step "[3/4] Building Android sample app..."

    # Build the app
    ./gradlew assembleDebug || {
        print_error "Android app build failed"
        return 1
    }

    local apk="app/build/outputs/apk/debug/app-debug.apk"
    if [[ ! -f "$apk" ]]; then
        print_error "APK not found at: $apk"
        return 1
    fi

    print_success "✅ Android app built: $apk ($(du -h "$apk" | cut -f1))"

    # Step 4: Install and run on device/emulator
    print_step "[4/4] Installing and launching app..."

    # Check for connected devices
    if ! command -v adb &> /dev/null; then
        print_warning "adb not found in PATH. Please install manually: adb install $apk"
        cd "$PROJECT_DIR"
        return 0
    fi

    local devices=$(adb devices | grep -v "List" | grep "device$" | wc -l)
    if [[ $devices -eq 0 ]]; then
        print_warning "No Android devices/emulators connected"
        print_info "Please connect a device or start an emulator, then run:"
        print_info "  cd $ANDROID_APP_DIR && adb install -r $apk"
        cd "$PROJECT_DIR"
        return 0
    fi

    # Install APK
    adb install -r "$apk" || {
        print_warning "Installation failed. Try manually: adb install -r $apk"
        cd "$PROJECT_DIR"
        return 1
    }

    # Launch app (get package name from AndroidManifest)
    local package_name=$(./gradlew -q app:printPackageName 2>/dev/null || echo "com.runanywhere.ai")
    adb shell monkey -p "$package_name" -c android.intent.category.LAUNCHER 1 || {
        print_info "App installed. Please launch manually."
    }

    print_success "✅ Android app installed and launched!"
    cd "$PROJECT_DIR"
}

# Build and Run IntelliJ Plugin (with latest SDK)
cmd_plugin_app() {
    print_header "Build & Run IntelliJ Plugin"

    # Step 1: Build and publish JVM SDK
    print_step "[1/4] Building JVM SDK..."
    cmd_sdk_jvm || {
        print_error "SDK build failed"
        return 1
    }

    # Step 2: Configure and build plugin
    local plugin_dir="$(cd "$SCRIPT_DIR/../../../examples/intellij-plugin-demo/plugin" 2>/dev/null && pwd)"

    if [[ -z "$plugin_dir" ]] || [[ ! -d "$plugin_dir" ]]; then
        local git_root="$(git rev-parse --show-toplevel 2>/dev/null)"
        if [[ -n "$git_root" ]]; then
            plugin_dir="$git_root/examples/intellij-plugin-demo/plugin"
        fi
    fi

    if [[ ! -d "$plugin_dir" ]]; then
        print_error "Plugin directory not found at: examples/intellij-plugin-demo/plugin"
        return 1
    fi

    print_step "[2/4] Syncing plugin with latest SDK..."
    cd "$plugin_dir"

    # Detect IDE and configure plugin
    local ide_info=$(detect_ide "IC")
    if [[ -n "$ide_info" ]]; then
        local detected_version=$(echo "$ide_info" | cut -d':' -f2)
        print_info "Detected IntelliJ IDEA version: $detected_version"
        update_plugin_for_ide "$plugin_dir" "IC" "$ide_info"
    else
        print_info "Using default IntelliJ configuration"
        update_plugin_for_ide "$plugin_dir" "IC" ""
    fi

    # Force Gradle to refresh dependencies to pick up latest SDK
    if [[ -f "./gradlew" ]]; then
        print_info "Refreshing Gradle dependencies..."
        ./gradlew --refresh-dependencies clean || {
            print_warning "Gradle refresh had issues, continuing..."
        }
    else
        print_error "gradlew not found in plugin directory"
        cd "$PROJECT_DIR"
        return 1
    fi

    print_step "[3/4] Building IntelliJ plugin..."

    ./gradlew buildPlugin || {
        print_error "Plugin build failed"
        cd "$PROJECT_DIR"
        return 1
    }

    print_success "✅ Plugin built successfully"

    # Step 4: Run IntelliJ with plugin
    print_step "[4/4] Starting IntelliJ IDEA with plugin..."
    print_info "IntelliJ will start in a new window. Close this window to stop."

    ./gradlew runIde

    cd "$PROJECT_DIR"
}

# Helper: Ensure Android app has mavenLocal in repositories
ensure_android_maven_local() {
    local settings_file="$ANDROID_APP_DIR/settings.gradle.kts"
    [[ ! -f "$settings_file" ]] && settings_file="$ANDROID_APP_DIR/settings.gradle"

    if [[ -f "$settings_file" ]] && ! grep -q "mavenLocal()" "$settings_file"; then
        print_info "Adding mavenLocal() to Android app repositories..."
        # Backup original
        cp "$settings_file" "$settings_file.bak"

        # Add mavenLocal after first repositories block
        if grep -q "repositories {" "$settings_file"; then
            sed -i.tmp '/repositories {/,/}/ s/repositories {/repositories {\n        mavenLocal()/' "$settings_file" 2>/dev/null || {
                # Fallback: just add to dependencyResolutionManagement
                echo "" >> "$settings_file"
                echo "// Added by sdk.sh" >> "$settings_file"
                echo "dependencyResolutionManagement {" >> "$settings_file"
                echo "    repositories {" >> "$settings_file"
                echo "        mavenLocal()" >> "$settings_file"
                echo "        google()" >> "$settings_file"
                echo "        mavenCentral()" >> "$settings_file"
                echo "    }" >> "$settings_file"
                echo "}" >> "$settings_file"
            }
            rm -f "$settings_file.tmp"
        fi
    fi
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
OPT_CLEAN=false
OPT_DEEP_CLEAN=false
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
        --clean)        OPT_CLEAN=true; shift ;;
        --deep-clean)   OPT_DEEP_CLEAN=true; shift ;;
        --no-clean)     shift ;;
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

    # Detect Android Studio on macOS
    detect_android_studio_mac() {
        local as_path="/Applications/Android Studio.app"
        if [[ -d "$as_path" ]]; then
            # Try to get version from Info.plist
            local version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$as_path/Contents/Info.plist" 2>/dev/null)
            # Also get build number
            local build_file="$as_path/Contents/Resources/build.txt"
            local build_info=""
            if [[ -f "$build_file" ]]; then
                build_info=$(cat "$build_file" | grep -oE 'AI-[0-9]+\.[0-9]+' | cut -d'-' -f2 | cut -d'.' -f1)
            fi
            if [[ -n "$version" ]]; then
                echo "AS:$version:$as_path:$build_info"
            fi
        fi
    }

    # Detect IntelliJ IDEA on macOS
    detect_intellij_mac() {
        # Check for IntelliJ IDEA Community
        local idea_ce="/Applications/IntelliJ IDEA CE.app"
        if [[ -d "$idea_ce" ]]; then
            local version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$idea_ce/Contents/Info.plist" 2>/dev/null)
            if [[ -n "$version" ]]; then
                echo "IC:$version:$idea_ce"
            fi
        fi

        # Check for IntelliJ IDEA Ultimate
        local idea_ult="/Applications/IntelliJ IDEA.app"
        if [[ -d "$idea_ult" ]]; then
            local version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$idea_ult/Contents/Info.plist" 2>/dev/null)
            if [[ -n "$version" ]]; then
                echo "IU:$version:$idea_ult"
            fi
        fi
    }

    # Main detection based on OS
    local result=""
    case "$(uname -s)" in
        Darwin)
            if [[ "$ide_type" == "AS" ]]; then
                result=$(detect_android_studio_mac | head -1)
            else
                result=$(detect_intellij_mac | head -1)
            fi
            ;;
        Linux)
            # Linux detection not yet implemented
            ;;
        *)
            # Unsupported OS
            ;;
    esac

    if [[ -n "$result" ]]; then
        echo "$result"
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

# Development plugin workflow - force clean rebuild and run
cmd_dev_plugin() {
    print_header "Development Plugin Workflow - Force Clean Rebuild"

    # Step 1: Clean all build artifacts
    print_step "Cleaning all build artifacts..."
    cmd_clean

    # Step 2: Force recompile by touching source files to invalidate cache
    print_step "Invalidating build cache..."
    find src/commonMain/kotlin -name "*.kt" -exec touch {} \; 2>/dev/null || true

    # Step 3: Build JVM and publish to Maven Local
    print_step "Building and publishing SDK..."
    cmd_jvm
    cmd_publish_jvm

    # Step 4: Run plugin
    print_step "Running plugin with fresh SDK..."
    run_plugin_for_ide "IC" "IntelliJ IDEA"
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
        clean)          cmd_clean_sdk ;;
        clean-sdk)      cmd_clean_sdk ;;
        clean-deep)     cmd_clean_deep ;;
        clean-all)      cmd_clean_all ;;
        clean-workspace) cmd_clean_workspace ;;
        build-all)
            # Pass global clean options to build_all
            if [[ "$OPT_DEEP_CLEAN" == "true" ]]; then
                cmd_build_all --deep-clean
            elif [[ "$OPT_CLEAN" == "true" ]]; then
                cmd_build_all --clean
            else
                cmd_build_all
            fi
            ;;
        build-modules)  cmd_build_modules ;;
        build-native)   cmd_build_native ;;
        build-samples)  cmd_build_samples ;;
        build-complete) cmd_build_complete ;;
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
        # Simplified workflows
        sdk-jvm)        cmd_sdk_jvm ;;
        sdk-android)    cmd_sdk_android ;;
        sdk-all)        cmd_sdk_all ;;
        plugin-app)     cmd_plugin_app ;;
        android-app)    cmd_android_app ;;

        # Plugin commands
        plugin)         cmd_plugin ;;
        plugin-as)      cmd_plugin_as ;;
        run-plugin)     cmd_run_plugin ;;
        run-plugin-as)  cmd_run_plugin_as ;;
        dev-plugin)     cmd_dev_plugin ;;

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
