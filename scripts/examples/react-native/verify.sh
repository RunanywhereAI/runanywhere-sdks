#!/usr/bin/env bash
# Clean-clone verification for the React Native sample.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
REPO_ROOT="${RAC_ROOT}"
APP_ROOT="${REPO_ROOT}/examples/react-native/RunAnywhereAI"

RUN_ANDROID="${RUN_ANDROID:-1}"
RUN_IOS="${RUN_IOS:-0}"
RUN_PODS="${RUN_PODS:-1}"
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
    "${REPO_ROOT}/scripts/build/android.sh" "${ANDROID_ABI}"
fi

if [ "${REFRESH_IOS_NATIVE:-0}" = "1" ]; then
    require_command xcodebuild
    log "Refreshing iOS XCFramework artifacts"
    "${REPO_ROOT}/scripts/build/ios-xcframework.sh"
fi

require_command yarn

log "Typechecking React Native sample"
yarn typecheck

if [ "${RUN_ANDROID}" = "1" ]; then
    log "Building Android debug APK"
    (cd android && ./gradlew :app:assembleDebug)
fi

if [ "${RUN_IOS}" = "1" ]; then
    require_command xcodebuild
    if [ "${RUN_PODS}" = "1" ]; then
        require_command bundle
        log "Installing CocoaPods dependencies via locked Bundler graph"
        bash "${SCRIPT_DIR}/pod-install.sh"
    fi

    log "Building iOS simulator app"
    xcodebuild \
        -workspace ios/RunAnywhereAI.xcworkspace \
        -scheme RunAnywhereAI \
        -configuration Debug \
        -sdk iphonesimulator \
        -destination 'generic/platform=iOS Simulator' \
        build
fi

log "React Native verification complete"
