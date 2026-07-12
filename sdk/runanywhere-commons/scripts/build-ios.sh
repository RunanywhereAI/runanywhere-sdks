#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Canonical Apple release build and packaging entry point.
#
# Builds the canonical Apple slice set through
# sdk/runanywhere-swift/scripts/build-core-xcframework.sh, then packages the
# resulting `.xcframework` bundles into the versioned
#      `sdk/runanywhere-commons/dist/packages/<Framework>-ios-v<version>.zip`
#      (+ .sha256) that release.yml uploads and `publish` asserts on.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMONS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${COMMONS_ROOT}/../.." && pwd)"

if [ "$(uname -s)" != "Darwin" ]; then
    echo "error: build-ios.sh only runs on macOS" >&2
    exit 1
fi
if [ "$#" -ne 0 ]; then
    echo "usage: build-ios.sh" >&2
    exit 2
fi

XCFRAMEWORK_SCRIPT="${REPO_ROOT}/sdk/runanywhere-swift/scripts/build-core-xcframework.sh"
if [ ! -x "${XCFRAMEWORK_SCRIPT}" ]; then
    echo "error: ${XCFRAMEWORK_SCRIPT} not found or not executable" >&2
    exit 1
fi

echo "▶ Delegating iOS/macOS xcframework build to sdk/runanywhere-swift/scripts/build-core-xcframework.sh"
# Keep Apple static archives free of per-build member timestamps.
export ZERO_AR_DATE=1
"${XCFRAMEWORK_SCRIPT}"

# Stage the produced xcframeworks into dist/packages/ as the versioned release
# archives (<Framework>-ios-v<version>.zip + .sha256) that release.yml's upload
# step, sync-checksums.sh, and the Package.swift binary targets all expect.
# Version: RAC_RELEASE_VERSION (the release tag, passed by release.yml) or the
# canonical PROJECT_VERSION from VERSIONS for standalone/local runs.
# The sourced path is resolved from this script at runtime.
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/load-versions.sh" >/dev/null
VERSION="${RAC_RELEASE_VERSION:-${PROJECT_VERSION}}"

SRC_DIR="${REPO_ROOT}/sdk/runanywhere-swift/Binaries"
DEST_DIR="${COMMONS_ROOT}/dist/packages"
mkdir -p "${DEST_DIR}"
rm -f "${DEST_DIR}"/*.zip "${DEST_DIR}"/*.sha256

if [ ! -d "${SRC_DIR}" ]; then
    echo "error: expected xcframework output directory ${SRC_DIR} is missing" >&2
    exit 1
fi

# Keep the public release surface explicit. Globbing this directory could
# accidentally publish a stale or private XCFramework left by a local build.
xcframework_names=(
    RACommons
    RABackendLLAMACPP
    RABackendONNX
    RABackendSherpa
    RABackendMLX
    RunAnywhereMLXRuntime
    RunAnywhereMLXMetal
)

for framework_name in "${xcframework_names[@]}"; do
    fw_name="${framework_name}.xcframework"
    fw="${SRC_DIR}/${fw_name}"
    if [ ! -d "${fw}" ]; then
        echo "error: required public XCFramework not found: ${fw}" >&2
        exit 1
    fi
    zip_path="${DEST_DIR}/${fw_name%.xcframework}-ios-v${VERSION}.zip"
    echo "▶ Packaging ${fw_name} → ${zip_path}"
    "${REPO_ROOT}/sdk/runanywhere-swift/scripts/create-reproducible-xcframework-zip.sh" \
        "${fw}" "${zip_path}"
done

# Hub/Crypto Bundle.module payloads and attribution notices are not a SwiftPM
# binary target. Keep them in their own archive so each binary-target ZIP
# contains exactly one XCFramework and passes SwiftPM artifact validation.
mlx_resources="${SRC_DIR}/RunAnywhereMLXRuntimeResources"
if [ ! -d "${mlx_resources}" ]; then
    echo "error: MLX runtime resource payload not found: ${mlx_resources}" >&2
    exit 1
fi
mlx_resources_zip="${DEST_DIR}/RunAnywhereMLXResources-ios-v${VERSION}.zip"
echo "▶ Packaging MLX resources → ${mlx_resources_zip}"
"${REPO_ROOT}/sdk/runanywhere-swift/scripts/create-reproducible-directory-zip.sh" \
    "${mlx_resources}" "${mlx_resources_zip}"
(cd "${DEST_DIR}" && for f in *.zip; do shasum -a 256 "$f" > "$f.sha256"; done)

archive_count=$((${#xcframework_names[@]} + 1))
echo "✓ build-ios.sh complete; staged ${archive_count} versioned archive(s) under ${DEST_DIR}"
