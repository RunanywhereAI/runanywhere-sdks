#!/bin/bash
#
# package-release.sh - Package XCFrameworks for release
#
# Usage: ./scripts/package-release.sh [version]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
DIST_DIR="${ROOT_DIR}/dist"
VERSION="${1:-$(cat "${ROOT_DIR}/VERSION")}"

echo "=== Packaging RunAnywhere Commons ${VERSION} ==="

# Create distribution directory
mkdir -p "${DIST_DIR}"

# XCFrameworks to package
XCFRAMEWORKS=(
    "RACommons"
    "RABackendLlamaCPP"
    "RABackendONNX"
    "RABackendWhisperCPP"
)

# Package each XCFramework
for FRAMEWORK in "${XCFRAMEWORKS[@]}"; do
    XCFRAMEWORK_PATH="${DIST_DIR}/${FRAMEWORK}.xcframework"
    ZIP_NAME="${FRAMEWORK}-${VERSION}.zip"
    ZIP_PATH="${DIST_DIR}/${ZIP_NAME}"

    if [ ! -d "${XCFRAMEWORK_PATH}" ]; then
        echo "Warning: ${XCFRAMEWORK_PATH} not found, skipping..."
        continue
    fi

    echo "Packaging ${FRAMEWORK}..."

    # Create ZIP
    cd "${DIST_DIR}"
    rm -f "${ZIP_NAME}"
    zip -r -q "${ZIP_NAME}" "${FRAMEWORK}.xcframework"

    # Calculate checksum
    CHECKSUM=$(shasum -a 256 "${ZIP_NAME}" | awk '{ print $1 }')
    echo "${CHECKSUM}  ${ZIP_NAME}" > "${ZIP_NAME}.sha256"

    echo "  Created: ${ZIP_NAME}"
    echo "  SHA256: ${CHECKSUM}"

    cd "${ROOT_DIR}"
done

# Create combined package
COMBINED_ZIP="RunAnywhereCommons-${VERSION}.zip"
COMBINED_PATH="${DIST_DIR}/${COMBINED_ZIP}"

echo ""
echo "Creating combined package..."

cd "${DIST_DIR}"
rm -f "${COMBINED_ZIP}"
zip -r -q "${COMBINED_ZIP}" *.xcframework

CHECKSUM=$(shasum -a 256 "${COMBINED_ZIP}" | awk '{ print $1 }')
echo "${CHECKSUM}  ${COMBINED_ZIP}" > "${COMBINED_ZIP}.sha256"

echo "  Created: ${COMBINED_ZIP}"
echo "  SHA256: ${CHECKSUM}"

# Generate manifest
MANIFEST="${DIST_DIR}/MANIFEST.md"
cat > "${MANIFEST}" << EOF
# RunAnywhere Commons v${VERSION}

## Checksums (SHA256)

EOF

for FRAMEWORK in "${XCFRAMEWORKS[@]}"; do
    ZIP_NAME="${FRAMEWORK}-${VERSION}.zip"
    if [ -f "${DIST_DIR}/${ZIP_NAME}.sha256" ]; then
        cat "${DIST_DIR}/${ZIP_NAME}.sha256" >> "${MANIFEST}"
    fi
done

echo "" >> "${MANIFEST}"
echo "Combined package:" >> "${MANIFEST}"
cat "${COMBINED_ZIP}.sha256" >> "${MANIFEST}"

echo ""
echo "=== Packaging Complete ==="
echo "Output: ${DIST_DIR}"
ls -la "${DIST_DIR}"
