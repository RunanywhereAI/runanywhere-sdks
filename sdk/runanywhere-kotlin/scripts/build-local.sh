#!/bin/bash
# =============================================================================
# RunAnywhere Kotlin SDK - Local Build Script
# =============================================================================
#
# Builds JNI libraries locally from:
#   - runanywhere-core (llama.cpp, ONNX, Sherpa-ONNX backends)
#   - runanywhere-commons (JNI bridge)
#
# This script mirrors the Swift SDK's testLocal=true mode, building everything
# from source for local development and testing.
#
# USAGE:
#   ./scripts/build-local.sh [options] [backends] [abis]
#
# OPTIONS:
#   --clean         Clean all build artifacts before building
#   --skip-deps     Skip dependency download (assume already downloaded)
#   --skip-core     Skip runanywhere-core build (use existing)
#   --skip-commons  Skip runanywhere-commons build (use existing)
#   --copy-only     Only copy existing built libs to jniLibs/ (no building)
#   --help          Show this help message
#
# BACKENDS:
#   all            Build all backends (default)
#   onnx           Build only ONNX backend (STT/TTS/VAD via Sherpa-ONNX)
#   llamacpp       Build only LlamaCPP backend (LLM)
#
# ABIS:
#   arm64-v8a      64-bit ARM (default, recommended for devices)
#   armeabi-v7a    32-bit ARM
#   x86_64         x86 64-bit (for emulator)
#   all            Build all ABIs
#
# EXAMPLES:
#   ./scripts/build-local.sh                     # Build all backends for arm64-v8a
#   ./scripts/build-local.sh --clean             # Clean build everything
#   ./scripts/build-local.sh onnx arm64-v8a      # Build ONNX for arm64 only
#   ./scripts/build-local.sh llamacpp            # Build LlamaCPP only
#   ./scripts/build-local.sh --copy-only         # Just copy existing builds
#   ./scripts/build-local.sh --skip-deps all     # Skip deps, build all
#
# PREREQUISITES:
#   - Android NDK (set ANDROID_NDK_HOME or install via Android Studio)
#   - CMake 3.14+
#   - Ninja (optional but recommended)
#
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_step() { echo -e "${YELLOW}▶ $1${NC}"; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_info() { echo -e "${CYAN}ℹ️  $1${NC}"; }

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Workspace structure: runanywhere-all/
#   ├── runanywhere-core/
#   └── sdks/sdk/
#       ├── runanywhere-commons/
#       ├── runanywhere-swift/
#       └── runanywhere-kotlin/
WORKSPACE_ROOT="$(cd "${PROJECT_ROOT}/../../.." && pwd)"
CORE_DIR="$WORKSPACE_ROOT/runanywhere-core"
COMMONS_DIR="$PROJECT_ROOT/../runanywhere-commons"

# Output path
JNILIBS_DIR="$PROJECT_ROOT/src/androidMain/jniLibs"

# Default settings
CLEAN_BUILD=false
SKIP_DEPS=false
SKIP_CORE=false
SKIP_COMMONS=false
COPY_ONLY=false
BACKENDS="all"
ABIS="arm64-v8a"

# =============================================================================
# Parse Arguments
# =============================================================================

show_help() {
    head -50 "$0" | tail -45
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --clean)
            CLEAN_BUILD=true
            shift
            ;;
        --skip-deps)
            SKIP_DEPS=true
            shift
            ;;
        --skip-core)
            SKIP_CORE=true
            shift
            ;;
        --skip-commons)
            SKIP_COMMONS=true
            shift
            ;;
        --copy-only)
            COPY_ONLY=true
            shift
            ;;
        --help|-h)
            show_help
            ;;
        -*)
            print_error "Unknown option: $1"
            show_help
            ;;
        *)
            # Positional arguments: backends abis
            if [[ "$BACKENDS" == "all" && "$1" != "all" ]]; then
                BACKENDS="$1"
            else
                ABIS="$1"
            fi
            shift
            ;;
    esac
done

# =============================================================================
# Validation
# =============================================================================

print_header "RunAnywhere Kotlin SDK - Local Build"

echo "Configuration:"
echo "  Workspace:     $WORKSPACE_ROOT"
echo "  Core dir:      $CORE_DIR"
echo "  Commons dir:   $COMMONS_DIR"
echo "  Kotlin SDK:    $PROJECT_ROOT"
echo "  jniLibs dir:   $JNILIBS_DIR"
echo ""
echo "  Backends:      $BACKENDS"
echo "  ABIs:          $ABIS"
echo "  Clean build:   $CLEAN_BUILD"
echo "  Skip deps:     $SKIP_DEPS"
echo "  Skip core:     $SKIP_CORE"
echo "  Skip commons:  $SKIP_COMMONS"
echo "  Copy only:     $COPY_ONLY"
echo ""

# Verify directories exist
if [[ ! -d "$CORE_DIR" ]]; then
    print_error "runanywhere-core not found at: $CORE_DIR"
    print_info "Expected workspace structure:"
    print_info "  runanywhere-all/"
    print_info "  ├── runanywhere-core/"
    print_info "  └── sdks/sdk/runanywhere-kotlin/"
    exit 1
fi

if [[ ! -d "$COMMONS_DIR" ]]; then
    print_error "runanywhere-commons not found at: $COMMONS_DIR"
    exit 1
fi

# =============================================================================
# Clean (if requested)
# =============================================================================

if [[ "$CLEAN_BUILD" == "true" ]]; then
    print_step "Cleaning build artifacts..."

    rm -rf "$JNILIBS_DIR"
    rm -rf "$CORE_DIR/build/android"
    rm -rf "$CORE_DIR/dist/android"
    rm -rf "$COMMONS_DIR/build/android"
    rm -rf "$COMMONS_DIR/dist/android"

    print_success "Build artifacts cleaned"
fi

# =============================================================================
# Copy Only Mode
# =============================================================================

if [[ "$COPY_ONLY" == "true" ]]; then
    print_header "Copy Mode - Using Existing Builds"

    # Skip to copy step
    SKIP_DEPS=true
    SKIP_CORE=true
    SKIP_COMMONS=true
fi

# =============================================================================
# Step 1: Download Dependencies
# =============================================================================

if [[ "$SKIP_DEPS" != "true" ]]; then
    print_header "Step 1: Download Dependencies"

    # Check if Sherpa-ONNX is already downloaded
    SHERPA_DIR="$CORE_DIR/third_party/sherpa-onnx-android"
    if [[ -d "$SHERPA_DIR/jniLibs" ]]; then
        print_success "Sherpa-ONNX already downloaded"
    else
        print_step "Downloading Sherpa-ONNX for Android..."

        if [[ -f "$CORE_DIR/scripts/android/download-sherpa-onnx.sh" ]]; then
            cd "$CORE_DIR"
            ./scripts/android/download-sherpa-onnx.sh
            print_success "Sherpa-ONNX downloaded"
        else
            print_error "download-sherpa-onnx.sh not found"
            print_info "Please manually download Sherpa-ONNX to: $SHERPA_DIR"
            exit 1
        fi
    fi
else
    print_info "Skipping dependency download (--skip-deps)"
fi

# =============================================================================
# Step 2: Build runanywhere-core
# =============================================================================

if [[ "$SKIP_CORE" != "true" ]]; then
    print_header "Step 2: Build runanywhere-core"

    cd "$CORE_DIR"

    if [[ -f "./scripts/android/build.sh" ]]; then
        print_step "Building core backends: $BACKENDS for $ABIS..."
        ./scripts/android/build.sh "$BACKENDS" "$ABIS"
        print_success "runanywhere-core build complete"
    else
        print_warning "runanywhere-core/scripts/android/build.sh not found"
        print_info "Core build may already be complete or handled differently"
    fi
else
    print_info "Skipping runanywhere-core build (--skip-core)"
fi

# =============================================================================
# Step 3: Build runanywhere-commons (JNI)
# =============================================================================

if [[ "$SKIP_COMMONS" != "true" ]]; then
    print_header "Step 3: Build runanywhere-commons (JNI Bridge)"

    cd "$COMMONS_DIR"

    if [[ -f "./scripts/build-android.sh" ]]; then
        print_step "Building commons JNI bridge for $ABIS..."

        # Export environment variables for build
        export BUILD_JNI=ON
        export ABIS="$ABIS"

        ./scripts/build-android.sh "$BACKENDS" "$ABIS"
        print_success "runanywhere-commons JNI build complete"
    else
        print_error "runanywhere-commons/scripts/build-android.sh not found"
        exit 1
    fi
else
    print_info "Skipping runanywhere-commons build (--skip-commons)"
fi

# =============================================================================
# Step 4: Copy JNI Libraries to Kotlin SDK
# =============================================================================

print_header "Step 4: Distribute JNI Libraries to Kotlin SDK"

# Create jniLibs directory structure
mkdir -p "$JNILIBS_DIR"

# Parse ABIs
if [[ "$ABIS" == "all" ]]; then
    ABI_LIST="arm64-v8a armeabi-v7a x86_64"
else
    ABI_LIST="$ABIS"
fi

# Copy libraries for each ABI
for ABI in $ABI_LIST; do
    print_step "Copying libraries for $ABI..."

    mkdir -p "$JNILIBS_DIR/$ABI"

    # Source directories
    CORE_DIST="$CORE_DIR/dist/android"
    COMMONS_DIST="$COMMONS_DIR/dist/android"

    # Track if we copied anything
    COPIED_COUNT=0

    # Copy JNI bridge libraries from commons
    if [[ -d "$COMMONS_DIST/jni/$ABI" ]]; then
        for lib in "$COMMONS_DIST/jni/$ABI"/*.so; do
            if [[ -f "$lib" ]]; then
                cp "$lib" "$JNILIBS_DIR/$ABI/"
                echo "    Copied: $(basename "$lib") (from commons/jni)"
                COPIED_COUNT=$((COPIED_COUNT + 1))
            fi
        done
    fi

    # Copy ONNX backend libraries
    if [[ "$BACKENDS" == "all" || "$BACKENDS" == "onnx" ]]; then
        if [[ -d "$COMMONS_DIST/onnx/$ABI" ]]; then
            for lib in "$COMMONS_DIST/onnx/$ABI"/*.so; do
                if [[ -f "$lib" ]]; then
                    cp "$lib" "$JNILIBS_DIR/$ABI/"
                    echo "    Copied: $(basename "$lib") (from commons/onnx)"
                    COPIED_COUNT=$((COPIED_COUNT + 1))
                fi
            done
        fi

        # Also copy from core's ONNX distribution if available
        if [[ -d "$CORE_DIST/onnx/$ABI" ]]; then
            for lib in "$CORE_DIST/onnx/$ABI"/*.so; do
                if [[ -f "$lib" ]] && [[ ! -f "$JNILIBS_DIR/$ABI/$(basename "$lib")" ]]; then
                    cp "$lib" "$JNILIBS_DIR/$ABI/"
                    echo "    Copied: $(basename "$lib") (from core/onnx)"
                    COPIED_COUNT=$((COPIED_COUNT + 1))
                fi
            done
        fi
    fi

    # Copy LlamaCPP backend libraries
    if [[ "$BACKENDS" == "all" || "$BACKENDS" == "llamacpp" ]]; then
        if [[ -d "$COMMONS_DIST/llamacpp/$ABI" ]]; then
            for lib in "$COMMONS_DIST/llamacpp/$ABI"/*.so; do
                if [[ -f "$lib" ]] && [[ ! -f "$JNILIBS_DIR/$ABI/$(basename "$lib")" ]]; then
                    cp "$lib" "$JNILIBS_DIR/$ABI/"
                    echo "    Copied: $(basename "$lib") (from commons/llamacpp)"
                    COPIED_COUNT=$((COPIED_COUNT + 1))
                fi
            done
        fi

        if [[ -d "$CORE_DIST/llamacpp/$ABI" ]]; then
            for lib in "$CORE_DIST/llamacpp/$ABI"/*.so; do
                if [[ -f "$lib" ]] && [[ ! -f "$JNILIBS_DIR/$ABI/$(basename "$lib")" ]]; then
                    cp "$lib" "$JNILIBS_DIR/$ABI/"
                    echo "    Copied: $(basename "$lib") (from core/llamacpp)"
                    COPIED_COUNT=$((COPIED_COUNT + 1))
                fi
            done
        fi
    fi

    # Copy WhisperCPP backend libraries (if building all)
    if [[ "$BACKENDS" == "all" ]]; then
        if [[ -d "$COMMONS_DIST/whispercpp/$ABI" ]]; then
            for lib in "$COMMONS_DIST/whispercpp/$ABI"/*.so; do
                if [[ -f "$lib" ]] && [[ ! -f "$JNILIBS_DIR/$ABI/$(basename "$lib")" ]]; then
                    cp "$lib" "$JNILIBS_DIR/$ABI/"
                    echo "    Copied: $(basename "$lib") (from commons/whispercpp)"
                    COPIED_COUNT=$((COPIED_COUNT + 1))
                fi
            done
        fi
    fi

    if [[ $COPIED_COUNT -eq 0 ]]; then
        print_warning "No libraries found for $ABI"
    else
        print_success "$ABI: $COPIED_COUNT libraries copied"
    fi
done

# =============================================================================
# Summary
# =============================================================================

print_header "Build Complete!"

echo "JNI Libraries Location: $JNILIBS_DIR"
echo ""

# List what was copied
for ABI in $ABI_LIST; do
    if [[ -d "$JNILIBS_DIR/$ABI" ]]; then
        echo "$ABI:"
        ls -lh "$JNILIBS_DIR/$ABI"/*.so 2>/dev/null | awk '{print "  " $NF ": " $5}' || echo "  (no files)"
        echo ""
    fi
done

# Calculate total size
TOTAL_SIZE=$(du -sh "$JNILIBS_DIR" 2>/dev/null | awk '{print $1}' || echo "0")
echo "Total size: $TOTAL_SIZE"
echo ""

print_success "Local build complete!"
echo ""
echo "Next steps:"
echo "  1. Build Kotlin SDK with local libs:"
echo "     ./gradlew -PtestLocal=true assembleDebug"
echo ""
echo "  2. Or run the full SDK build:"
echo "     ./scripts/sdk.sh sdk-android"
echo ""
