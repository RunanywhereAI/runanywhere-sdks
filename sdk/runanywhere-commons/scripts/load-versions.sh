#!/bin/bash
# =============================================================================
# Load versions from VERSIONS file
# =============================================================================
# Usage: source scripts/load-versions.sh
#
# This script exports all version variables from the VERSIONS file.
# After sourcing, you can use variables like:
#   $ONNX_VERSION_IOS
#   $SHERPA_ONNX_VERSION_IOS
#   etc.
# =============================================================================

# Find the VERSIONS file - look relative to this script's location
# Handle being sourced from any directory
_SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
if [[ "$_SCRIPT_PATH" != /* ]]; then
    # Relative path - make it absolute
    _SCRIPT_PATH="$(pwd)/$_SCRIPT_PATH"
fi
_SCRIPT_DIR="$(cd "$(dirname "$_SCRIPT_PATH")" && pwd)"
_ROOT_DIR="$(cd "$_SCRIPT_DIR/.." && pwd)"
VERSIONS_FILE="$_ROOT_DIR/VERSIONS"

if [ ! -f "${VERSIONS_FILE}" ]; then
    echo "ERROR: VERSIONS file not found at ${VERSIONS_FILE}" >&2
    return 1 2>/dev/null || exit 1
fi

# Read and export all KEY=VALUE pairs (skip comments and empty lines)
while IFS='=' read -r key value; do
    # Skip comments and empty lines
    [[ "$key" =~ ^#.*$ ]] && continue
    [[ -z "$key" ]] && continue

    # Remove leading/trailing whitespace
    key=$(echo "$key" | xargs)
    value=$(echo "$value" | xargs)

    # Skip if key is empty after trimming
    [[ -z "$key" ]] && continue

    # Export the variable
    export "$key"="$value"
done < "${VERSIONS_FILE}"

# Print loaded versions if VERBOSE is set
if [ "${VERBOSE:-}" = "1" ]; then
    echo "Loaded versions from ${VERSIONS_FILE}:"
    echo "  ONNX_VERSION_IOS=${ONNX_VERSION_IOS}"
    echo "  ONNX_VERSION_MACOS=${ONNX_VERSION_MACOS}"
    echo "  SHERPA_ONNX_VERSION_IOS=${SHERPA_ONNX_VERSION_IOS}"
fi

# Clean up temporary variables
unset _SCRIPT_PATH _SCRIPT_DIR _ROOT_DIR
