#!/usr/bin/env bash
# Clean-clone verification for the Flutter sample.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${APP_ROOT}/../../.." && pwd)"

RUN_ANDROID="${RUN_ANDROID:-1}"
RUN_IOS="${RUN_IOS:-0}"
ANDROID_ABI="${ANDROID_ABI:-arm64-v8a}"

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

if [ "${REFRESH_ANDROID_NATIVE:-0}" = "1" ]; then
    require_command cmake
    log "Refreshing Android native artifacts (${ANDROID_ABI})"
    "${REPO_ROOT}/scripts/build-core-android.sh" "${ANDROID_ABI}"
fi

if [ "${REFRESH_IOS_NATIVE:-0}" = "1" ]; then
    require_command xcodebuild
    log "Refreshing iOS XCFramework artifacts"
    "${REPO_ROOT}/scripts/build-core-xcframework.sh"
fi

require_command flutter

log "Resolving Flutter dependencies"
flutter pub get

log "Analyzing Flutter sample"
flutter analyze

if [ "${RUN_ANDROID}" = "1" ]; then
    log "Building debug APK"
    flutter build apk --debug
fi

if [ "${RUN_IOS}" = "1" ]; then
    require_command xcodebuild
    log "Building iOS simulator app"
    flutter build ios --simulator --debug
fi

log "Flutter verification complete"
