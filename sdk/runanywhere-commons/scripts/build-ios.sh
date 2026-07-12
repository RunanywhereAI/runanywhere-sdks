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

shopt -s nullglob
xcframeworks=("${SRC_DIR}"/*.xcframework)
if [ "${#xcframeworks[@]}" -eq 0 ]; then
    echo "error: no .xcframework bundles produced under ${SRC_DIR}" >&2
    exit 1
fi

for fw in "${xcframeworks[@]}"; do
    fw_name="$(basename "${fw}")"
    zip_path="${DEST_DIR}/${fw_name%.xcframework}-ios-v${VERSION}.zip"
    echo "▶ Packaging ${fw_name} → ${zip_path}"
    "${REPO_ROOT}/sdk/runanywhere-swift/scripts/create-reproducible-xcframework-zip.sh" \
        "${fw}" "${zip_path}"
done
(cd "${DEST_DIR}" && for f in *.zip; do shasum -a 256 "$f" > "$f.sha256"; done)

echo "✓ build-ios.sh complete; staged ${#xcframeworks[@]} versioned archive(s) under ${DEST_DIR}"
