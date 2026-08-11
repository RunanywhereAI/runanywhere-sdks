#!/usr/bin/env bash
# Clean-clone verification for the native Android sample.
#
# The RunAnywhere SDK and its backend engines are resolved from Maven Central,
# so this gate needs nothing but the Android SDK and network access.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

log() {
    printf '\n==> %s\n' "$*"
}

cd "${APP_ROOT}"

if [ -z "${ANDROID_HOME:-}" ] && [ ! -f local.properties ]; then
    echo "error: set ANDROID_HOME or create local.properties with sdk.dir=/path/to/Android/sdk" >&2
    exit 1
fi

log "Building Android debug APK"
./gradlew --dependency-verification strict :app:assembleDebug

log "Android verification complete"
