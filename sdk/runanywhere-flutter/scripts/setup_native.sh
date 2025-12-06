#!/bin/bash

# =============================================================================
# RunAnywhere Flutter SDK - Native Library Setup
#
# This is a wrapper script that calls the main setup script in runanywhere-core.
#
# Usage:
#   ./scripts/setup_native.sh [options]
#
# Options:
#   --mode <remote|local>   Set mode (default: remote)
#   --version <version>     Binary version to download (default: latest)
#   --platform <platform>   Platform: ios, android, macos, all (default: all)
#   --backend <backend>     Backend: onnx, llamacpp, all (default: onnx)
#   --core-path <path>      Path to runanywhere-core (auto-detected)
#   --help                  Show help
#
# Examples:
#   ./scripts/setup_native.sh                           # Remote, latest
#   ./scripts/setup_native.sh --mode local              # Build from source
#   ./scripts/setup_native.sh --version 0.0.1-dev.2230b4e
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLUTTER_SDK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Parse --core-path if provided, otherwise auto-detect
CORE_PATH=""
PASSTHROUGH_ARGS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --core-path)
            CORE_PATH="$2"
            shift 2
            ;;
        --help|-h)
            head -25 "$0" | tail -23 | sed 's/^# //' | sed 's/^#//'
            exit 0
            ;;
        *)
            PASSTHROUGH_ARGS+=("$1")
            shift
            ;;
    esac
done

# Auto-detect runanywhere-core location
if [ -z "$CORE_PATH" ]; then
    # Try common relative paths
    POSSIBLE_PATHS=(
        "${FLUTTER_SDK_DIR}/../../../../runanywhere-core"
        "${FLUTTER_SDK_DIR}/../../../runanywhere-core"
        "${FLUTTER_SDK_DIR}/../../runanywhere-core"
        "${FLUTTER_SDK_DIR}/../runanywhere-core"
    )

    for path in "${POSSIBLE_PATHS[@]}"; do
        if [ -d "$path" ] && [ -f "$path/scripts/flutter/setup.sh" ]; then
            CORE_PATH="$(cd "$path" && pwd)"
            break
        fi
    done
fi

# Validate core path
if [ -z "$CORE_PATH" ] || [ ! -f "$CORE_PATH/scripts/flutter/setup.sh" ]; then
    echo -e "${RED}Error: Could not find runanywhere-core${NC}"
    echo ""
    echo "Please specify the path using --core-path:"
    echo "  $0 --core-path /path/to/runanywhere-core"
    echo ""
    echo "Or set up the following directory structure:"
    echo "  project/"
    echo "    runanywhere-core/"
    echo "    sdks/"
    echo "      runanywhere-flutter/  <- you are here"
    exit 1
fi

echo -e "${GREEN}Using runanywhere-core at: ${CORE_PATH}${NC}"
echo ""

# Run the main setup script
exec "${CORE_PATH}/scripts/flutter/setup.sh" "${PASSTHROUGH_ARGS[@]}" "${FLUTTER_SDK_DIR}"
