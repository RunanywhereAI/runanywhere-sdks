#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

usage() {
    cat <<'EOF'
Usage: scripts/release/package-commons-ios.sh

Packages the .xcframework bundles under sdk/runanywhere-swift/Binaries/ into
the versioned release archives
sdk/runanywhere-commons/dist/packages/<Framework>-ios-v<version>.zip (+ .sha256)
that release.yml uploads and Package.swift binary targets reference.

Run scripts/build/ios-xcframework.sh first.

Environment:
  RAC_RELEASE_VERSION   Version tag override (default: PROJECT_VERSION from VERSIONS)
EOF
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
esac

[ "$(uname -s)" = "Darwin" ] || die "package-commons-ios.sh only runs on macOS"

COMMONS_ROOT="${RAC_ROOT}/sdk/runanywhere-commons"
source "${RAC_ROOT}/scripts/lib/load-versions.sh" >/dev/null
VERSION="${RAC_RELEASE_VERSION:-${PROJECT_VERSION}}"

SRC_DIR="${RAC_ROOT}/sdk/runanywhere-swift/Binaries"
DEST_DIR="${COMMONS_ROOT}/dist/packages"
mkdir -p "${DEST_DIR}"
rm -f "${DEST_DIR}"/*.zip "${DEST_DIR}"/*.sha256

[ -d "${SRC_DIR}" ] || die "expected xcframework output directory ${SRC_DIR} is missing"

shopt -s nullglob
xcframeworks=("${SRC_DIR}"/*.xcframework)
if [ "${#xcframeworks[@]}" -eq 0 ]; then
    die "no .xcframework bundles found under ${SRC_DIR}"
fi

for fw in "${xcframeworks[@]}"; do
    fw_name="$(basename "${fw}")"
    zip_path="${DEST_DIR}/${fw_name%.xcframework}-ios-v${VERSION}.zip"
    info "Packaging ${fw_name} → ${zip_path}"
    (cd "${SRC_DIR}" && zip -ry "${zip_path}" "${fw_name}")
done
(cd "${DEST_DIR}" && for f in *.zip; do shasum -a 256 "$f" > "$f.sha256"; done)

ok "staged $(ls -1 "${DEST_DIR}"/*.zip 2>/dev/null | wc -l | tr -d ' ') versioned archive(s) under ${DEST_DIR}"
