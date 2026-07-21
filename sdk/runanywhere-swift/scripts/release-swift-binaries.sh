#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# release-swift-binaries.sh — builds + zips + checksums all seven Apple
# XCFrameworks (RACommons / RABackendLLAMACPP / RABackendONNX /
# RABackendSherpa / RABackendMLX / RunAnywhereMLXRuntime /
# RunAnywhereMLXMetal), packages the separate MLX resource payload, and
# patches the root/Flutter manifests and Flutter MLX podspec checksums to match.
#
# Pre-requisites (manual, one-time on the release machine):
#   1. Xcode 15+ with iOS SDK installed.
#   2. sdk/runanywhere-commons/third_party/onnxruntime-ios/onnxruntime.xcframework
#      present. Run:
#        ./sdk/runanywhere-commons/scripts/ios/download-onnx.sh
#      (or set RAC_BACKEND_ONNX=OFF to skip the ONNX backend.)
#   3. Pinned iOS Sherpa and macOS static Sherpa/ONNX inventories present. Run:
#        ./sdk/runanywhere-commons/scripts/ios/download-sherpa-onnx.sh
#        ./sdk/runanywhere-commons/scripts/macos/download-sherpa-onnx.sh
#
# Usage:
#   sdk/runanywhere-swift/scripts/release-swift-binaries.sh <version>          # builds + checksums
#   sdk/runanywhere-swift/scripts/release-swift-binaries.sh 0.20.0
#
# Dry-run (no cmake/xcodebuild actually invoked, zips are generated from
# placeholders — only used to validate the pipeline end-to-end in CI):
#   DRY_RUN=1 sdk/runanywhere-swift/scripts/release-swift-binaries.sh 0.20.0
#
# Outputs:
#   release-artifacts/native-ios-macos/RACommons-ios-v${VERSION}.zip
#   release-artifacts/native-ios-macos/RABackendLLAMACPP-ios-v${VERSION}.zip
#   release-artifacts/native-ios-macos/RABackendONNX-ios-v${VERSION}.zip    (if ONNX enabled)
#   release-artifacts/native-ios-macos/RABackendSherpa-ios-v${VERSION}.zip (if ONNX enabled)
#   release-artifacts/native-ios-macos/RABackendMLX-ios-v${VERSION}.zip     (if MLX enabled)
#   release-artifacts/native-ios-macos/RunAnywhereMLXRuntime-ios-v${VERSION}.zip (if MLX enabled)
#   release-artifacts/native-ios-macos/RunAnywhereMLXMetal-ios-v${VERSION}.zip   (if MLX enabled)
#   release-artifacts/native-ios-macos/RunAnywhereMLXResources-ios-v${VERSION}.zip (if MLX enabled)
#
# Tagging and publication stay outside this build helper. The Release workflow
# rebuilds and verifies these archives from the pushed tag before publishing.

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "usage: $0 <version>   (e.g. 0.20.0)" >&2
    exit 1
fi
VERSION="$1"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DEST="${REPO_ROOT}/release-artifacts/native-ios-macos"

MANIFEST_VERSION="$(sed -nE 's/^let sdkVersion = "([^"]+)"$/\1/p' "${REPO_ROOT}/Package.swift")"
if [ -z "${MANIFEST_VERSION}" ]; then
    echo "error: could not read sdkVersion from Package.swift" >&2
    exit 1
fi
if [ "${VERSION}" != "${MANIFEST_VERSION}" ]; then
    echo "error: requested version ${VERSION} does not match Package.swift sdkVersion ${MANIFEST_VERSION}" >&2
    exit 1
fi

DRY_RUN="${DRY_RUN:-0}"
RAC_BACKEND_ONNX="${RAC_BACKEND_ONNX:-ON}"
RAC_BACKEND_MLX="${RAC_BACKEND_MLX:-ON}"
export DRY_RUN RAC_BACKEND_ONNX RAC_BACKEND_MLX

if [ "${RAC_BACKEND_ONNX}" != "ON" ] || [ "${RAC_BACKEND_MLX}" != "ON" ]; then
    echo "error: a Swift release requires every Apple binary/resource payload (ONNX and MLX must be ON)" >&2
    exit 1
fi

if [ "$(uname -s)" != "Darwin" ]; then
    echo "error: $0 only runs on macOS" >&2
    exit 1
fi

# Archive hashes are committed before tagging and rebuilt in release CI, so a
# merely compatible Xcode is insufficient: the exact canonical build must match.
VERSIONS_FILE="${REPO_ROOT}/sdk/runanywhere-commons/VERSIONS"
XCODE_VERSION="$(sed -nE 's/^XCODE_VERSION=(.+)$/\1/p' "${VERSIONS_FILE}")"
XCODE_BUILD="$(sed -nE 's/^XCODE_BUILD=(.+)$/\1/p' "${VERSIONS_FILE}")"
if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "error: xcodebuild is required" >&2
    exit 1
fi
xcode_version_output="$(xcodebuild -version)"
actual_xcode_version="$(awk '/^Xcode / { print $2 }' <<< "${xcode_version_output}")"
actual_xcode_build="$(awk '/^Build version / { print $3 }' <<< "${xcode_version_output}")"
if [ "${actual_xcode_version}" != "${XCODE_VERSION}" ] || [ "${actual_xcode_build}" != "${XCODE_BUILD}" ]; then
    echo "error: expected Xcode ${XCODE_VERSION} (${XCODE_BUILD}), found ${actual_xcode_version} (${actual_xcode_build})" >&2
    exit 1
fi

# ONNX prereq check. The actual path lives inside the commons submodule,
# not at the repo root — kept consistent with sdk/runanywhere-commons/
# scripts/ios/download-onnx.sh and the FetchONNXRuntime.cmake module.
IOS_ONNXRT="${REPO_ROOT}/sdk/runanywhere-commons/third_party/onnxruntime-ios/onnxruntime.xcframework"
if [ "${RAC_BACKEND_ONNX}" = "ON" ] && [ ! -d "${IOS_ONNXRT}" ] && [ "${DRY_RUN}" != "1" ]; then
    cat >&2 <<EOF
error: ONNX Runtime iOS xcframework not found at
  ${IOS_ONNXRT}

Run this first (one-time, per checkout):
  ./sdk/runanywhere-commons/scripts/ios/download-onnx.sh

Or re-run with RAC_BACKEND_ONNX=OFF to skip the ONNX backend in this build.
EOF
    exit 1
fi

mkdir -p "${DEST}"

# ────────────────────────────────────────────────────────────────────────────
# 1. Build all seven xcframeworks plus the Swift MLX resource payload.
# ────────────────────────────────────────────────────────────────────────────
echo "▶ [1/3] Building iOS xcframeworks (DRY_RUN=${DRY_RUN}, RAC_BACKEND_ONNX=${RAC_BACKEND_ONNX}, RAC_BACKEND_MLX=${RAC_BACKEND_MLX})"
export ZERO_AR_DATE=1
"${REPO_ROOT}/sdk/runanywhere-swift/scripts/build-core-xcframework.sh"

# ────────────────────────────────────────────────────────────────────────────
# 2. Zip each xcframework. Filenames match what sync-checksums.sh + the
#    binaryTarget URL convention in Package.swift expect:
#
#      ${DEST}/RACommons-ios-v${VERSION}.zip
#      ${DEST}/RABackendLLAMACPP-ios-v${VERSION}.zip
#      ${DEST}/RABackendONNX-ios-v${VERSION}.zip
#      ${DEST}/RABackendSherpa-ios-v${VERSION}.zip
#      ${DEST}/RABackendMLX-ios-v${VERSION}.zip
#      ${DEST}/RunAnywhereMLXRuntime-ios-v${VERSION}.zip
#      ${DEST}/RunAnywhereMLXMetal-ios-v${VERSION}.zip
#      ${DEST}/RunAnywhereMLXResources-ios-v${VERSION}.zip
# ────────────────────────────────────────────────────────────────────────────
echo "▶ [2/3] Zipping XCFramework/resource payloads"

BINARIES_DIR="${REPO_ROOT}/sdk/runanywhere-swift/Binaries"

zip_target() {
    local xcf_name="$1"     # e.g. RACommons.xcframework
    local zip_prefix="$2"   # e.g. RACommons-ios
    local xcf="${BINARIES_DIR}/${xcf_name}"
    local zip="${DEST}/${zip_prefix}-v${VERSION}.zip"

    if [ "${DRY_RUN}" = "1" ]; then
        # DRY_RUN: xcframework doesn't actually exist. Create an empty
        # placeholder zip so downstream checksum + Package.swift-patch
        # logic still completes end-to-end.
        : > "${DEST}/.dryrun_placeholder_${xcf_name}"
        (cd "${DEST}" && zip -qry "${zip}" ".dryrun_placeholder_${xcf_name}")
        rm -f "${DEST}/.dryrun_placeholder_${xcf_name}"
        echo "[DRY RUN] (placeholder) Zipped ${zip}"
        return
    fi

    if [ ! -d "${xcf}" ]; then
        echo "error: xcframework not found: ${xcf}" >&2
        echo "       build-core-xcframework.sh should have produced it." >&2
        exit 1
    fi
    echo "  ▶ ${zip}"
    "${REPO_ROOT}/sdk/runanywhere-swift/scripts/create-reproducible-xcframework-zip.sh" \
        "${xcf}" "${zip}"
}

zip_resources() {
    local resources_name="$1"
    local zip_prefix="$2"
    local resources="${BINARIES_DIR}/${resources_name}"
    local zip="${DEST}/${zip_prefix}-v${VERSION}.zip"

    if [ "${DRY_RUN}" = "1" ]; then
        : > "${DEST}/.dryrun_placeholder_${resources_name}"
        (cd "${DEST}" && zip -qry "${zip}" ".dryrun_placeholder_${resources_name}")
        rm -f "${DEST}/.dryrun_placeholder_${resources_name}"
        echo "[DRY RUN] (placeholder) Zipped ${zip}"
        return
    fi
    if [ ! -d "${resources}" ]; then
        echo "error: runtime resources not found: ${resources}" >&2
        exit 1
    fi
    echo "  ▶ ${zip}"
    "${REPO_ROOT}/sdk/runanywhere-swift/scripts/create-reproducible-directory-zip.sh" \
        "${resources}" "${zip}"
}

zip_target "RACommons.xcframework"          "RACommons-ios"
zip_target "RABackendLLAMACPP.xcframework"  "RABackendLLAMACPP-ios"
# CoreML Stable-Diffusion engine — Apple-only, always produced by
# build-core-xcframework.sh. The Swift ONNXRuntime target declares an
# unconditional dependency on RABackendCoreMLBinary, so external SPM consumers
# need this zip + the matching `.binaryTarget(name: "RABackendCoreMLBinary", …)`
# entry in the root Package.swift to resolve the manifest.
zip_target "RABackendCoreML.xcframework"    "RABackendCoreML-ios"
if [ "${RAC_BACKEND_ONNX}" = "ON" ]; then
    zip_target "RABackendONNX.xcframework"  "RABackendONNX-ios"
    # Sherpa-ONNX ships as a peer xcframework alongside RABackendONNX. The
    # Swift ONNXBackend / ONNXRuntime targets in Package.swift declare an
    # unconditional dependency on RABackendSherpaBinary, so external SPM
    # consumers cannot resolve the manifest unless we publish this zip and
    # populate the matching `.binaryTarget(name: "RABackendSherpaBinary", …)`
    # entry. Skipping it when the xcframework is absent would only mask the
    # gap until the first `swift package resolve`.
    zip_target "RABackendSherpa.xcframework" "RABackendSherpa-ios"
else
    echo "  ▶ Skipping RABackendONNX zip (RAC_BACKEND_ONNX=OFF)"
fi
if [ "${RAC_BACKEND_MLX}" = "ON" ]; then
    zip_target "RABackendMLX.xcframework" "RABackendMLX-ios"
    zip_target "RunAnywhereMLXRuntime.xcframework" "RunAnywhereMLXRuntime-ios"
    zip_target "RunAnywhereMLXMetal.xcframework" "RunAnywhereMLXMetal-ios"
    zip_resources "RunAnywhereMLXRuntimeResources" "RunAnywhereMLXResources-ios"
else
    echo "  ▶ Skipping all MLX binary/resource zips (RAC_BACKEND_MLX=OFF)"
fi

# ────────────────────────────────────────────────────────────────────────────
# 3. Patch package-contract checksums.
# ────────────────────────────────────────────────────────────────────────────
echo "▶ [3/3] Patching Apple package checksums via sync-checksums.sh"
"${REPO_ROOT}/sdk/runanywhere-swift/scripts/sync-checksums.sh" "${DEST}"

# ────────────────────────────────────────────────────────────────────────────
# 4. Operator handoff. We INTENTIONALLY do not run `gh release upload`;
#    see the docstring at the top of this file.
# ────────────────────────────────────────────────────────────────────────────
echo ""
echo "✓ Release artifacts ready in: ${DEST}"
ls -la "${DEST}" || true
echo ""
echo "Next steps (operator):"
echo "  1. Review package checksum diffs:"
echo "       git diff Package.swift sdk/runanywhere-flutter/packages/runanywhere_mlx/ios/runanywhere_mlx.podspec"
echo "  2. Verify checksums and the local-native Swift build:"
echo "       sdk/runanywhere-swift/scripts/sync-checksums.sh --check ${DEST}"
echo "       RUNANYWHERE_USE_LOCAL_NATIVES=1 swift package resolve && RUNANYWHERE_USE_LOCAL_NATIVES=1 swift build -c release"
echo "  3. Commit and push the checksum manifest before creating the tag:"
echo "       git add Package.swift sdk/runanywhere-flutter/packages/runanywhere_mlx/ios/runanywhere_mlx.podspec && \\"
echo "           git commit -m 'release: bump xcframework checksums for v${VERSION}' && \\"
echo "           git push origin HEAD"
echo "  4. Tag that exact commit and push the tag; the Release workflow rebuilds,"
echo "     verifies these deterministic checksums, validates consumers, and publishes:"
echo "       git tag v${VERSION} && git push origin v${VERSION}"
echo ""
if [ "${DRY_RUN}" = "1" ]; then
    echo "NOTE: DRY_RUN=1 was set. Package contract checksums now correspond"
    echo "      to placeholder zips — do NOT commit these checksum diffs."
    echo "      Re-run without DRY_RUN to produce real artifacts."
fi
