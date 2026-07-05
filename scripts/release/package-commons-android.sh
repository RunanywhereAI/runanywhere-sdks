#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

usage() {
    cat <<'EOF'
Usage: scripts/release/package-commons-android.sh <abi>

Stages the per-ABI Android .so set produced by scripts/build/android.sh
(commons + llamacpp + onnx backends, sourced from the Kotlin SDK jniLibs
trees) into the versioned release archive
sdk/runanywhere-commons/dist/RACommons-android-<abi>-v<version>.zip (+ .sha256).

Run scripts/build/android.sh <abi> first.

Arguments:
  abi           arm64-v8a | armeabi-v7a | x86_64

Environment:
  RAC_RELEASE_VERSION   Version tag override (default: PROJECT_VERSION from VERSIONS)
EOF
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
esac

ABI="${1:-}"
if [[ ! "${ABI}" =~ ^(arm64-v8a|armeabi-v7a|x86_64)$ ]]; then
    usage >&2
    die "unsupported ABI '${ABI}' (expected arm64-v8a, armeabi-v7a, or x86_64)"
fi

COMMONS_ROOT="${RAC_ROOT}/sdk/runanywhere-commons"
source "${RAC_ROOT}/scripts/lib/load-versions.sh" >/dev/null
VERSION="${RAC_RELEASE_VERSION:-${PROJECT_VERSION}}"

KOTLIN_BASE="${RAC_ROOT}/sdk/runanywhere-kotlin"
DIST="${COMMONS_ROOT}/dist"
STAGING="${DIST}/android-staging/${ABI}"
rm -rf "${STAGING}"
mkdir -p "${STAGING}"

stage_backend() {
    local sub="$1" src="$2"
    if [ -d "${src}" ]; then
        mkdir -p "${STAGING}/${sub}"
        cp -R "${src}/." "${STAGING}/${sub}/"
    fi
}
stage_backend jni      "${KOTLIN_BASE}/src/main/jniLibs/${ABI}"
stage_backend llamacpp "${KOTLIN_BASE}/modules/runanywhere-core-llamacpp/src/main/jniLibs/${ABI}"
stage_backend onnx     "${KOTLIN_BASE}/modules/runanywhere-core-onnx/src/main/jniLibs/${ABI}"
# Flat unified/ convenience copy: every .so for this ABI in one place.
mkdir -p "${STAGING}/unified"
find "${STAGING}" -maxdepth 2 -name "*.so" -exec cp {} "${STAGING}/unified/" \; 2>/dev/null || true

ZIP="RACommons-android-${ABI}-v${VERSION}.zip"
rm -f "${DIST}/${ZIP}" "${DIST}/${ZIP}.sha256"
(cd "${DIST}/android-staging" && run_cmd zip -r "../${ZIP}" "${ABI}")
(cd "${DIST}" && shasum -a 256 "${ZIP}" > "${ZIP}.sha256")

ok "staged ABI '${ABI}' → ${DIST}/${ZIP}"
