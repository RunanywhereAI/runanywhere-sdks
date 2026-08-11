#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Creates a byte-stable ZIP containing exactly one named directory. This is
# used for resource-only release payloads that are not SwiftPM binary targets.

set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "usage: $0 SOURCE_DIR OUTPUT_ZIP" >&2
    exit 1
fi

SOURCE="$1"
OUTPUT="$2"

if [ ! -d "${SOURCE}" ]; then
    echo "error: source directory not found: ${SOURCE}" >&2
    exit 1
fi

OUTPUT_DIR="$(cd "$(dirname "${OUTPUT}")" && pwd -P)"
OUTPUT="${OUTPUT_DIR}/$(basename "${OUTPUT}")"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/rac-directory-zip.XXXXXX")"

cleanup() {
    rm -rf "${STAGING}"
}
trap cleanup EXIT

SOURCE_NAME="$(basename "${SOURCE}")"
COPYFILE_DISABLE=1 cp -R "${SOURCE}" "${STAGING}/${SOURCE_NAME}"
find "${STAGING}/${SOURCE_NAME}" -exec touch -h -t 198001010000 {} +
rm -f "${OUTPUT}"
(
    cd "${STAGING}"
    LC_ALL=C find "${SOURCE_NAME}" -print \
        | LC_ALL=C sort \
        | zip -qXy "${OUTPUT}" -@
)

echo "  reproducible resource archive: ${OUTPUT}"
