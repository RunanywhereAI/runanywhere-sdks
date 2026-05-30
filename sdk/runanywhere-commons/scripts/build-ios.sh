#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# build-ios.sh — package-local compatibility wrapper.
#
# The original per-package iOS/macOS build entry
# point was deleted in favour of repo-root scripts/build-core-xcframework.sh,
# but `.github/workflows/release.yml` (native_ios job) and the
# README/CLAUDE.md docs continue to invoke this path. This shim restores
# the workflow contract by:
#
#   1. Forwarding the legacy CLI flags (--backend / --release /
#      --include-macos / --package — accepted but currently ignored, since
#      build-core-xcframework.sh always builds the canonical Apple slice
#      set) to the repo-root xcframework build.
#   2. Staging the resulting `.xcframework` bundles into
#      `sdk/runanywhere-commons/dist/packages/*.zip` so the release
#      workflow's checksum + upload steps continue to find their inputs.
#
# This wrapper exists so we can collapse the legacy CLI without forcing a
# release-CI rewrite in the same change. Long-term, callers should migrate
# to invoking scripts/build-core-xcframework.sh directly.
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

XCFRAMEWORK_SCRIPT="${REPO_ROOT}/scripts/build-core-xcframework.sh"
if [ ! -x "${XCFRAMEWORK_SCRIPT}" ]; then
    echo "error: ${XCFRAMEWORK_SCRIPT} not found or not executable" >&2
    exit 1
fi

echo "▶ Delegating iOS/macOS xcframework build to scripts/build-core-xcframework.sh"
echo "  legacy args (forwarded for log fidelity, ignored by repo-root script): ${LEGACY_ARGS[*]:-<none>}"
"${XCFRAMEWORK_SCRIPT}"

# Stage the produced xcframeworks into the legacy dist/packages/*.zip layout
# so release.yml's checksum + upload steps continue to find their inputs.
SRC_DIR="${REPO_ROOT}/sdk/runanywhere-swift/Binaries"
DEST_DIR="${COMMONS_ROOT}/dist/packages"
mkdir -p "${DEST_DIR}"
rm -f "${DEST_DIR}"/*.zip

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
    zip_path="${DEST_DIR}/${fw_name%.xcframework}.zip"
    echo "▶ Packaging ${fw_name} → ${zip_path}"
    (cd "${SRC_DIR}" && zip -ry "${zip_path}" "${fw_name}")
done

echo "✓ build-ios.sh wrapper complete; staged $(ls -1 "${DEST_DIR}" | wc -l | tr -d ' ') artifact(s) under ${DEST_DIR}"
