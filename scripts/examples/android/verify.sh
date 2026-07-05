#!/usr/bin/env bash
# Clean-clone verification for the native Android sample.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
REPO_ROOT="${RAC_ROOT}"
APP_ROOT="${REPO_ROOT}/examples/android/RunAnywhereAI"
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

if [ -z "${ANDROID_HOME:-}" ] && [ ! -f local.properties ]; then
    echo "error: set ANDROID_HOME or create local.properties with sdk.dir=/path/to/Android/sdk" >&2
    exit 1
fi

if [ "${REFRESH_NATIVE:-0}" = "1" ]; then
    require_command cmake
    log "Refreshing Android native artifacts (${ANDROID_ABI})"
    "${REPO_ROOT}/scripts/build/android.sh" "${ANDROID_ABI}"
fi

log "Building Android debug APK"
./gradlew :app:assembleDebug

log "Android verification complete"
