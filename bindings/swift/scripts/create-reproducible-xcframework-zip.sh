#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Creates a byte-stable XCFramework archive. ZIP records filesystem mtimes and
# traverses directories in filesystem order by default, so archiving the same
# bundle twice can otherwise produce different SwiftPM checksums.

set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "usage: $0 XCFRAMEWORK_DIR OUTPUT_ZIP" >&2
    exit 1
fi

SOURCE="$1"
OUTPUT="$2"

if [ ! -d "${SOURCE}" ] || [[ "${SOURCE}" != *.xcframework ]]; then
    echo "error: expected an .xcframework directory: ${SOURCE}" >&2
    exit 1
fi

OUTPUT_DIR="$(cd "$(dirname "${OUTPUT}")" && pwd -P)"
OUTPUT="${OUTPUT_DIR}/$(basename "${OUTPUT}")"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/rac-xcframework-zip.XXXXXX")"

cleanup() {
    rm -rf "${STAGING}"
}
trap cleanup EXIT

SOURCE_NAME="$(basename "${SOURCE}")"
COPYFILE_DISABLE=1 cp -R "${SOURCE}" "${STAGING}/${SOURCE_NAME}"

# ZIP's earliest portable timestamp is 1980-01-01. Normalize every entry and
# omit host-specific UID/GID and extended timestamp fields (`-X`). Explicitly
# feed a sorted file list so archive member ordering is stable as well.
find "${STAGING}/${SOURCE_NAME}" -exec touch -h -t 198001010000 {} +
rm -f "${OUTPUT}"
(
    cd "${STAGING}"
    LC_ALL=C find "${SOURCE_NAME}" -print \
        | LC_ALL=C sort \
        | zip -qXy "${OUTPUT}" -@
)

echo "  reproducible archive: ${OUTPUT}"
