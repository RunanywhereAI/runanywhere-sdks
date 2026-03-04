#!/bin/bash
# =============================================================================
# build-sdk.sh — One command to build everything
# =============================================================================
#
# Full pipeline: C++ (runanywhere-commons) → copy .so → Kotlin SDK
#
# USAGE:
#   ./scripts/build-sdk.sh                  # Full build: C++ + copy + Kotlin
#   ./scripts/build-sdk.sh --skip-cpp       # Copy .so + build Kotlin (C++ already built)
#   ./scripts/build-sdk.sh --cpp-only       # Build C++ + copy .so (skip Kotlin)
#   ./scripts/build-sdk.sh --abis=arm64-v8a # Device only (faster)
#   ./scripts/build-sdk.sh --clean          # Clean build everything
#
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defaults
SKIP_CPP=false
CPP_ONLY=false
PASSTHROUGH_ARGS=()

for arg in "$@"; do
    case $arg in
        --skip-cpp)
            SKIP_CPP=true
            ;;
        --cpp-only)
            CPP_ONLY=true
            ;;
        --help|-h)
            head -14 "$0" | tail -11
            exit 0
            ;;
        *)
            PASSTHROUGH_ARGS+=("$arg")
            ;;
    esac
done

if [ "$SKIP_CPP" = true ] && [ "$CPP_ONLY" = true ]; then
    echo "Cannot use --skip-cpp and --cpp-only together"
    exit 1
fi

if [ "$SKIP_CPP" = true ]; then
    # Skip C++ build, just copy .so files and build Kotlin
    exec "${SCRIPT_DIR}/build-kotlin.sh" --local --skip-build "${PASSTHROUGH_ARGS[@]}"
elif [ "$CPP_ONLY" = true ]; then
    # Build C++ + copy, skip Kotlin Gradle build
    exec "${SCRIPT_DIR}/build-kotlin.sh" --local --rebuild-commons --skip-build "${PASSTHROUGH_ARGS[@]}"
else
    # Full pipeline: C++ + copy + Kotlin
    exec "${SCRIPT_DIR}/build-kotlin.sh" --local --rebuild-commons "${PASSTHROUGH_ARGS[@]}"
fi
