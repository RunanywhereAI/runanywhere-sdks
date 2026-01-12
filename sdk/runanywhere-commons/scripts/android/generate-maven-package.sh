#!/bin/bash

# =============================================================================
# generate-maven-package.sh
# Generates versions.json manifest for Android distribution
#
# Usage: ./generate-maven-package.sh <version> <artifacts-dir>
#
# This script reads the checksums from the built artifacts and generates:
#   1. versions.json - Version manifest with URLs and SHA256 checksums
#
# This provides parity with iOS generate-spm-package.sh which generates
# Package.swift and *.podspec files with checksums.
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="${1:-0.0.0}"
ARTIFACTS_DIR="${2:-.}"
OUTPUT_DIR="${ARTIFACTS_DIR}"

# Configuration - Update these for your organization
GITHUB_ORG="${PUBLIC_REPO_OWNER:-RunanywhereAI}"
REPO_NAME="${PUBLIC_REPO_NAME:-runanywhere-binaries}"
BASE_URL="https://github.com/${GITHUB_ORG}/${REPO_NAME}/releases/download/v${VERSION}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Generating Android versions.json manifest${NC}"
echo "Version: ${VERSION}"
echo "Artifacts dir: ${ARTIFACTS_DIR}"
echo "Base URL: ${BASE_URL}"
echo ""

# =============================================================================
# Read checksums from .sha256 files
# =============================================================================

get_checksum() {
    local artifact_name="$1"
    local sha_file="${ARTIFACTS_DIR}/${artifact_name}-android.zip.sha256"

    if [ -f "$sha_file" ]; then
        # SHA256 file format: <hash>  <filename> or <hash> <filename>
        awk '{print $1}' "$sha_file"
    else
        echo "CHECKSUM_NOT_FOUND"
    fi
}

get_file_size() {
    local artifact_name="$1"
    local zip_file="${ARTIFACTS_DIR}/${artifact_name}-android.zip"

    if [ -f "$zip_file" ]; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            stat -f%z "$zip_file"
        else
            stat -c%s "$zip_file"
        fi
    else
        echo "0"
    fi
}

# Detect available backends
JNI_CHECKSUM=$(get_checksum "RunAnywhereJNI")
ONNX_CHECKSUM=$(get_checksum "RunAnywhereONNX")
LLAMACPP_CHECKSUM=$(get_checksum "RunAnywhereLlamaCPP")
TFLITE_CHECKSUM=$(get_checksum "RunAnywhereTFLite")

# Get file sizes
JNI_SIZE=$(get_file_size "RunAnywhereJNI")
ONNX_SIZE=$(get_file_size "RunAnywhereONNX")
LLAMACPP_SIZE=$(get_file_size "RunAnywhereLlamaCPP")
TFLITE_SIZE=$(get_file_size "RunAnywhereTFLite")

echo "Detected checksums:"
[ "$JNI_CHECKSUM" != "CHECKSUM_NOT_FOUND" ] && echo "  JNI: ${JNI_CHECKSUM:0:16}..." || echo "  JNI: not found"
[ "$ONNX_CHECKSUM" != "CHECKSUM_NOT_FOUND" ] && echo "  ONNX: ${ONNX_CHECKSUM:0:16}..." || echo "  ONNX: not found"
[ "$LLAMACPP_CHECKSUM" != "CHECKSUM_NOT_FOUND" ] && echo "  LlamaCPP: ${LLAMACPP_CHECKSUM:0:16}..." || echo "  LlamaCPP: not found"
[ "$TFLITE_CHECKSUM" != "CHECKSUM_NOT_FOUND" ] && echo "  TFLite: ${TFLITE_CHECKSUM:0:16}..." || echo "  TFLite: not found"
echo ""

# Count available backends
BACKEND_COUNT=0
[ "$JNI_CHECKSUM" != "CHECKSUM_NOT_FOUND" ] && BACKEND_COUNT=$((BACKEND_COUNT + 1)) || true
[ "$ONNX_CHECKSUM" != "CHECKSUM_NOT_FOUND" ] && BACKEND_COUNT=$((BACKEND_COUNT + 1)) || true
[ "$LLAMACPP_CHECKSUM" != "CHECKSUM_NOT_FOUND" ] && BACKEND_COUNT=$((BACKEND_COUNT + 1)) || true
[ "$TFLITE_CHECKSUM" != "CHECKSUM_NOT_FOUND" ] && BACKEND_COUNT=$((BACKEND_COUNT + 1)) || true

if [ "$BACKEND_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}Warning: No Android artifacts found. Skipping versions.json generation.${NC}"
    exit 0
fi

# =============================================================================
# Generate versions.json
# =============================================================================

# Start JSON
cat > "${OUTPUT_DIR}/versions.json" << EOF
{
  "version": "${VERSION}",
  "platform": "android",
  "generated": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "artifacts": {
EOF

# Track if we need a comma
FIRST_ARTIFACT=true

add_artifact() {
    local name="$1"
    local checksum="$2"
    local size="$3"

    if [ "$checksum" != "CHECKSUM_NOT_FOUND" ]; then
        if [ "$FIRST_ARTIFACT" = false ]; then
            echo "," >> "${OUTPUT_DIR}/versions.json"
        fi
        FIRST_ARTIFACT=false

        cat >> "${OUTPUT_DIR}/versions.json" << EOF
    "${name}": {
      "url": "${BASE_URL}/${name}-android.zip",
      "sha256": "${checksum}",
      "size": ${size}
    }
EOF
    fi
}

# Add artifacts (without trailing commas - handled by add_artifact)
add_artifact "RunAnywhereJNI" "$JNI_CHECKSUM" "$JNI_SIZE"
add_artifact "RunAnywhereONNX" "$ONNX_CHECKSUM" "$ONNX_SIZE"
add_artifact "RunAnywhereLlamaCPP" "$LLAMACPP_CHECKSUM" "$LLAMACPP_SIZE"
add_artifact "RunAnywhereTFLite" "$TFLITE_CHECKSUM" "$TFLITE_SIZE"

# Close JSON
cat >> "${OUTPUT_DIR}/versions.json" << 'EOF'

  }
}
EOF

echo -e "${GREEN}Generated: ${OUTPUT_DIR}/versions.json${NC}"

# =============================================================================
# Generate checksums.txt (simple format for quick reference)
# =============================================================================

cat > "${OUTPUT_DIR}/checksums-android.txt" << EOF
# RunAnywhere Android Checksums
# Version: ${VERSION}
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
#
# Format: <sha256>  <filename>
EOF

[ "$JNI_CHECKSUM" != "CHECKSUM_NOT_FOUND" ] && echo "${JNI_CHECKSUM}  RunAnywhereJNI-android.zip" >> "${OUTPUT_DIR}/checksums-android.txt"
[ "$ONNX_CHECKSUM" != "CHECKSUM_NOT_FOUND" ] && echo "${ONNX_CHECKSUM}  RunAnywhereONNX-android.zip" >> "${OUTPUT_DIR}/checksums-android.txt"
[ "$LLAMACPP_CHECKSUM" != "CHECKSUM_NOT_FOUND" ] && echo "${LLAMACPP_CHECKSUM}  RunAnywhereLlamaCPP-android.zip" >> "${OUTPUT_DIR}/checksums-android.txt"
[ "$TFLITE_CHECKSUM" != "CHECKSUM_NOT_FOUND" ] && echo "${TFLITE_CHECKSUM}  RunAnywhereTFLite-android.zip" >> "${OUTPUT_DIR}/checksums-android.txt"

echo -e "${GREEN}Generated: ${OUTPUT_DIR}/checksums-android.txt${NC}"

# =============================================================================
# Summary
# =============================================================================

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Generation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Generated files:"
echo "  - versions.json (Android manifest with checksums)"
echo "  - checksums-android.txt (simple checksum file)"
echo ""
echo "Android Backends: ${BACKEND_COUNT}"
[ "$JNI_CHECKSUM" != "CHECKSUM_NOT_FOUND" ] && echo "  - JNI Bridge (Native .so)" || true
[ "$ONNX_CHECKSUM" != "CHECKSUM_NOT_FOUND" ] && echo "  - ONNX Runtime (Native .so)" || true
[ "$LLAMACPP_CHECKSUM" != "CHECKSUM_NOT_FOUND" ] && echo "  - LlamaCPP (Native .so)" || true
[ "$TFLITE_CHECKSUM" != "CHECKSUM_NOT_FOUND" ] && echo "  - TensorFlow Lite (Native .so)" || true
echo ""
echo "Consumer usage:"
echo ""
echo "  Kotlin SDK - Gradle:"
echo "    dependencies {"
echo "        implementation(\"com.runanywhere:runanywhere-core-onnx:${VERSION}\")"
echo "    }"
echo ""
echo "  Direct Download:"
[ "$ONNX_CHECKSUM" != "CHECKSUM_NOT_FOUND" ] && echo "    ${BASE_URL}/RunAnywhereONNX-android.zip" || true
[ "$LLAMACPP_CHECKSUM" != "CHECKSUM_NOT_FOUND" ] && echo "    ${BASE_URL}/RunAnywhereLlamaCPP-android.zip" || true
echo ""
echo "  Checksum Validation (example):"
echo "    curl -sL ${BASE_URL}/versions.json | jq '.artifacts.RunAnywhereONNX.sha256'"
echo ""
