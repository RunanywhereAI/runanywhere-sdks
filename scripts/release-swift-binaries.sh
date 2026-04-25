#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# release-swift-binaries.sh — builds + zips + checksums all Swift binary
# target xcframeworks (RACommons / RABackendLLAMACPP / RABackendONNX) for
# iOS (device + simulator) and patches Package.swift checksums to match.
#
# Pre-requisites (manual, one-time on the release machine):
#   1. Xcode 15+ with iOS SDK installed.
#   2. sdk/runanywhere-commons/third_party/onnxruntime-ios/onnxruntime.xcframework
#      present. Run:
#        ./sdk/runanywhere-commons/scripts/ios/download-onnx.sh
#      (or set RAC_BACKEND_ONNX=OFF to skip the ONNX backend.)
#   3. `gh` CLI authenticated (only needed for the actual upload, which
#      this script does NOT perform — see "Next steps" at the end).
#
# Usage:
#   scripts/release-swift-binaries.sh <version>          # builds + checksums
#   scripts/release-swift-binaries.sh 0.20.0
#
# Dry-run (no cmake/xcodebuild actually invoked, zips are generated from
# placeholders — only used to validate the pipeline end-to-end in CI):
#   DRY_RUN=1 scripts/release-swift-binaries.sh 0.20.0
#
# Skip ONNX (for dev iteration when onnxruntime-ios isn't extracted):
#   RAC_BACKEND_ONNX=OFF scripts/release-swift-binaries.sh 0.20.0
#
# Outputs:
#   release-artifacts/native-ios-macos/RACommons-ios-v${VERSION}.zip
#   release-artifacts/native-ios-macos/RABackendLLAMACPP-ios-v${VERSION}.zip
#   release-artifacts/native-ios-macos/RABackendONNX-ios-v${VERSION}.zip    (if ONNX enabled)
#
# Why this isn't fully automated (no `gh release upload` here):
#   - Publishing requires `gh auth` on a release machine with the proper
#     repo permissions; we intentionally keep the upload step operator-gated.
#   - Same reason the tag/push steps happen outside this script.

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "usage: $0 <version>   (e.g. 0.20.0)" >&2
    exit 1
fi
VERSION="$1"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${REPO_ROOT}/release-artifacts/native-ios-macos"

DRY_RUN="${DRY_RUN:-0}"
RAC_BACKEND_ONNX="${RAC_BACKEND_ONNX:-ON}"
export DRY_RUN RAC_BACKEND_ONNX

if [ "$(uname -s)" != "Darwin" ]; then
    echo "error: $0 only runs on macOS" >&2
    exit 1
fi

# Xcode version sanity: 15.0 minimum. Anything older lacks the
# `-create-xcframework` flags we use below.
if command -v xcodebuild >/dev/null 2>&1; then
    xcver="$(xcodebuild -version 2>/dev/null | awk '/^Xcode /{print $2; exit}')"
    xcmajor="${xcver%%.*}"
    if [ -n "${xcmajor}" ] && [ "${xcmajor}" -lt 15 ]; then
        echo "error: Xcode ${xcver} is too old; need Xcode 15.0 or newer" >&2
        exit 1
    fi
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
# 1. Build all three xcframeworks (RACommons + per-backend).
# ────────────────────────────────────────────────────────────────────────────
echo "▶ [1/3] Building iOS xcframeworks (DRY_RUN=${DRY_RUN}, RAC_BACKEND_ONNX=${RAC_BACKEND_ONNX})"
"${REPO_ROOT}/scripts/build-core-xcframework.sh"

# ────────────────────────────────────────────────────────────────────────────
# 2. Zip each xcframework. Filenames match what sync-checksums.sh + the
#    binaryTarget URL convention in Package.swift expect:
#
#      ${DEST}/RACommons-ios-v${VERSION}.zip
#      ${DEST}/RABackendLLAMACPP-ios-v${VERSION}.zip
#      ${DEST}/RABackendONNX-ios-v${VERSION}.zip
# ────────────────────────────────────────────────────────────────────────────
echo "▶ [2/3] Zipping xcframeworks"

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
    (cd "$(dirname "${xcf}")" && zip -qry "${zip}" "$(basename "${xcf}")")
}

zip_target "RACommons.xcframework"          "RACommons-ios"
zip_target "RABackendLLAMACPP.xcframework"  "RABackendLLAMACPP-ios"
if [ "${RAC_BACKEND_ONNX}" = "ON" ]; then
    zip_target "RABackendONNX.xcframework"  "RABackendONNX-ios"
else
    echo "  ▶ Skipping RABackendONNX zip (RAC_BACKEND_ONNX=OFF)"
fi

# ────────────────────────────────────────────────────────────────────────────
# 3. Patch Package.swift checksums.
# ────────────────────────────────────────────────────────────────────────────
echo "▶ [3/3] Patching Package.swift checksums via sync-checksums.sh"
"${REPO_ROOT}/scripts/sync-checksums.sh" "${DEST}"

# ────────────────────────────────────────────────────────────────────────────
# 4. Operator handoff. We INTENTIONALLY do not run `gh release upload`;
#    see the docstring at the top of this file.
# ────────────────────────────────────────────────────────────────────────────
echo ""
echo "✓ Release artifacts ready in: ${DEST}"
ls -la "${DEST}" || true
echo ""
echo "Next steps (operator):"
echo "  1. Review Package.swift diff:"
echo "       git diff Package.swift"
echo "  2. Verify swift build is green:"
echo "       swift package resolve && swift build -c release"
echo "  3. Create the GitHub release (and upload zips in the same call):"
echo "       gh release create v${VERSION} ${DEST}/*.zip \\"
echo "           --title 'v${VERSION}' --generate-notes"
echo "  4. Commit the checksum bump + push:"
echo "       git add Package.swift && \\"
echo "           git commit -m 'release: bump xcframework checksums for v${VERSION}' && \\"
echo "           git push origin HEAD"
echo ""
if [ "${DRY_RUN}" = "1" ]; then
    echo "NOTE: DRY_RUN=1 was set. Checksums in Package.swift now correspond"
    echo "      to placeholder zips — do NOT commit this Package.swift diff."
    echo "      Re-run without DRY_RUN to produce real artifacts."
fi
