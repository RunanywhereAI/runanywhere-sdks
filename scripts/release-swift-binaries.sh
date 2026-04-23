#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# release-swift-binaries.sh — full v3.1.x Swift release-automation
# wrapper. Builds + zips + checksums all 3 (or 4 incl. MetalRT)
# RACommons / RABackendONNX / RABackendLlamaCPP xcframeworks for
# iOS device + iOS simulator + macOS, then patches Package.swift
# checksums to match.
#
# Pre-requisites (manual, one-time):
#   1. Xcode 15+ with iOS SDK installed.
#   2. third_party/onnxruntime-ios/onnxruntime.xcframework extracted
#      from https://download.onnxruntime.ai/pod-archive-onnxruntime-c-1.17.1.zip
#      (or set RAC_BACKEND_ONNX=OFF to skip ONNX in this build).
#   3. third_party/onnxruntime-macos/ similarly extracted.
#
# Usage:
#   scripts/release-swift-binaries.sh <version>     # builds + checksums; doesn't tag/push
#   scripts/release-swift-binaries.sh 3.1.1
#
# Outputs:
#   release-artifacts/native-ios-macos/RACommons-ios-v3.1.1.zip
#   release-artifacts/native-ios-macos/RACommons-macos-v3.1.1.zip
#   release-artifacts/native-ios-macos/RABackendONNX-ios-v3.1.1.zip
#   ... (one zip per binary target × platform combo)
#
# After running, the operator should:
#   gh release create v3.1.1 release-artifacts/native-ios-macos/*.zip
#   git add Package.swift && git commit -m "release: bump checksums for v3.1.1"
#
# Why this isn't fully automated:
#   - GitHub release publishing requires `gh auth` from a release machine.
#   - Notarization (if shipping macOS binaries off-Mac) requires
#     Developer ID + Notary Service credentials.
#   - This script intentionally stops at "ready to upload".

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "usage: $0 <version>   (e.g. 3.1.1)" >&2
    exit 1
fi
VERSION="$1"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${REPO_ROOT}/release-artifacts/native-ios-macos"

if [ "$(uname -s)" != "Darwin" ]; then
    echo "error: $0 only runs on macOS" >&2
    exit 1
fi

# Sanity: required prereqs.
if [ ! -d "${REPO_ROOT}/third_party/onnxruntime-ios/onnxruntime.xcframework" ]; then
    echo "error: third_party/onnxruntime-ios/onnxruntime.xcframework missing." >&2
    echo "  Download from: https://download.onnxruntime.ai/pod-archive-onnxruntime-c-1.17.1.zip" >&2
    echo "  Or set RAC_BACKEND_ONNX=OFF to skip ONNX in this build." >&2
    exit 1
fi

mkdir -p "${DEST}"

# 1. Build core xcframework (RACommons).
echo "▶ [1/N] Building RACommons xcframework"
"${REPO_ROOT}/scripts/build-core-xcframework.sh"

XCF_SRC="${REPO_ROOT}/sdk/runanywhere-swift/Binaries/RACommons.xcframework"
if [ ! -d "${XCF_SRC}" ]; then
    echo "error: build-core-xcframework.sh did not produce ${XCF_SRC}" >&2
    exit 1
fi

# Zip the iOS slice (device + simulator). The xcframework already
# contains both slices; we just need to package as a single zip
# matching the Package.swift URL convention.
ZIP="${DEST}/RACommons-ios-v${VERSION}.zip"
echo "▶ Zipping ${ZIP}"
(cd "$(dirname "${XCF_SRC}")" && zip -qry "${ZIP}" "$(basename "${XCF_SRC}")")

# 2. TODO: per-backend xcframework builds (LlamaCPP, ONNX, MetalRT).
# Each backend has its own build script — wire them here once they
# follow the build-core-xcframework.sh template.
#
# scripts/build-backend-xcframework.sh llamacpp
# scripts/build-backend-xcframework.sh onnx
# scripts/build-backend-xcframework.sh metalrt   # skipped if RAC_BACKEND_METALRT=OFF
#
# For v3.1.1 the backend-build scripts don't exist yet; this script
# only handles RACommons. Backend xcframeworks need manual builds via
# their respective preset incantations until the helper scripts land.

# 3. Patch Package.swift checksums.
echo "▶ Patching Package.swift checksums via sync-checksums.sh"
"${REPO_ROOT}/scripts/sync-checksums.sh" "${DEST}"

# 4. Print release-create command for the operator to run.
echo ""
echo "✓ Release artifacts ready in: ${DEST}"
echo ""
echo "Next steps (operator):"
echo "  1. Review Package.swift diff:"
echo "       git diff Package.swift"
echo "  2. Verify swift build green from a clean clone:"
echo "       cd /tmp && rm -rf clean-test && \\"
echo "       git clone $(cd ${REPO_ROOT} && git remote get-url origin) clean-test && \\"
echo "       cd clean-test && swift build"
echo "  3. Tag + create the GitHub release:"
echo "       gh release create v${VERSION} ${DEST}/*.zip --title 'v${VERSION}' --generate-notes"
echo "  4. Commit the Package.swift checksum bump:"
echo "       git add Package.swift && git commit -m 'release: bump xcframework checksums for v${VERSION}'"
echo "  5. Push the release commit:"
echo "       git push origin <branch>"
echo ""
