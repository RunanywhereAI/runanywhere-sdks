#!/usr/bin/env bash
# Clean-clone verification for the native iOS sample.
#
# The RunAnywhere SDK is consumed entirely from its published GitHub release,
# so this gate needs nothing outside this directory: no monorepo checkout, no
# locally staged XCFrameworks. SwiftPM downloads the checksum-verified binary
# artifacts during `swift package resolve`.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
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

cd "${APP_ROOT}"

require_command swift
require_command xcodebuild

log "Resolving Swift package dependencies (remote SDK release)"
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
    -skipPackagePluginValidation \
    -jobs 2 \
    build

log "iOS verification complete"
