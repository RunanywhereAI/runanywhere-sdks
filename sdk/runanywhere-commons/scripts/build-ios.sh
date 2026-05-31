#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# build-ios.sh — package-local compatibility wrapper.
#
# The original per-package iOS/macOS build entry
# point was deleted in favour of repo-root sdk/runanywhere-swift/scripts/build-core-xcframework.sh,
# but `.github/workflows/release.yml` (native_ios job) and the
# README/CLAUDE.md docs continue to invoke this path. This shim restores
# the workflow contract by:
#
#   1. Forwarding the legacy CLI flags (--backend / --release /
#      --include-macos / --package — accepted but currently ignored, since
#      build-core-xcframework.sh always builds the canonical Apple slice
#      set) to the repo-root xcframework build.
#   2. Packaging the resulting `.xcframework` bundles into the versioned
#      `sdk/runanywhere-commons/dist/packages/<Framework>-ios-v<version>.zip`
#      (+ .sha256) that release.yml uploads and `publish` asserts on.
#
# This wrapper exists so we can collapse the legacy CLI without forcing a
# release-CI rewrite in the same change. Long-term, callers should migrate
# to invoking sdk/runanywhere-swift/scripts/build-core-xcframework.sh directly.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMONS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${COMMONS_ROOT}/../.." && pwd)"

if [ "$(uname -s)" != "Darwin" ]; then
    echo "error: build-ios.sh only runs on macOS" >&2
    exit 1
fi

# Forward (and discard) the legacy flag surface — build-core-xcframework.sh
# does not parse them today but we accept them so the workflow command
# remains byte-identical.
LEGACY_ARGS=("$@")

XCFRAMEWORK_SCRIPT="${REPO_ROOT}/sdk/runanywhere-swift/scripts/build-core-xcframework.sh"
if [ ! -x "${XCFRAMEWORK_SCRIPT}" ]; then
    echo "error: ${XCFRAMEWORK_SCRIPT} not found or not executable" >&2
    exit 1
fi

echo "▶ Delegating iOS/macOS xcframework build to sdk/runanywhere-swift/scripts/build-core-xcframework.sh"
echo "  legacy args (forwarded for log fidelity, ignored by repo-root script): ${LEGACY_ARGS[*]:-<none>}"
"${XCFRAMEWORK_SCRIPT}"

# Stage the produced xcframeworks into dist/packages/ as the versioned release
# archives (<Framework>-ios-v<version>.zip + .sha256) that release.yml's upload
# step, sync-checksums.sh, and the Package.swift binary targets all expect.
# Version: RAC_RELEASE_VERSION (the release tag, passed by release.yml) or the
# canonical PROJECT_VERSION from VERSIONS for standalone/local runs.
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
    (cd "${SRC_DIR}" && zip -ry "${zip_path}" "${fw_name}")
done
(cd "${DEST_DIR}" && for f in *.zip; do shasum -a 256 "$f" > "$f.sha256"; done)

echo "✓ build-ios.sh complete; staged $(ls -1 "${DEST_DIR}"/*.zip 2>/dev/null | wc -l | tr -d ' ') versioned archive(s) under ${DEST_DIR}"
