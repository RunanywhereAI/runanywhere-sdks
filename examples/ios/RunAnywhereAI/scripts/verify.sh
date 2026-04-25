#!/usr/bin/env bash
# Clean-clone verification for the native iOS sample.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${APP_ROOT}/../../.." && pwd)"
DESTINATION="${IOS_DESTINATION:-generic/platform=iOS Simulator}"

log() {
    printf '\n==> %s\n' "$*"
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "error: required command not found: $1" >&2
        exit 1
    fi
}

check_xcframeworks() {
    local missing=0
    for framework in \
        RACommons.xcframework \
        RABackendLLAMACPP.xcframework \
        RABackendONNX.xcframework \
        RABackendSherpa.xcframework
    do
        if [ ! -d "${REPO_ROOT}/sdk/runanywhere-swift/Binaries/${framework}" ]; then
            echo "missing: sdk/runanywhere-swift/Binaries/${framework}" >&2
            missing=1
        fi
    done

    if [ "${missing}" -ne 0 ] && [ "${ALLOW_MISSING_NATIVE_ARTIFACTS:-0}" != "1" ]; then
        echo "error: local XCFrameworks are missing. Run REFRESH_NATIVE=1 bash scripts/verify.sh to build them." >&2
        exit 1
    fi
}

cd "${APP_ROOT}"

require_command swift
require_command xcodebuild

if [ "${REFRESH_NATIVE:-0}" = "1" ]; then
    log "Refreshing iOS XCFramework artifacts"
    "${REPO_ROOT}/scripts/build-core-xcframework.sh"
fi

log "Checking local XCFramework artifacts"
check_xcframeworks

log "Resolving Swift package dependencies"
swift package resolve
xcodebuild \
    -project RunAnywhereAI.xcodeproj \
    -scheme RunAnywhereAI \
    -resolvePackageDependencies

log "Building iOS simulator app"
xcodebuild \
    -project RunAnywhereAI.xcodeproj \
    -scheme RunAnywhereAI \
    -configuration Debug \
    -sdk iphonesimulator \
    -destination "${DESTINATION}" \
    build

log "iOS verification complete"
