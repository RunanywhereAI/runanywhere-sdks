#!/usr/bin/env bash
# Clean-clone verification for the Web sample.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${APP_ROOT}/../../.." && pwd)"
WASM_DIR="${REPO_ROOT}/sdk/runanywhere-web/packages/llamacpp/wasm"
WASM_JS="${WASM_DIR}/racommons-llamacpp.js"
WASM_BIN="${WASM_DIR}/racommons-llamacpp.wasm"

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

if [ "${REFRESH_WASM:-0}" = "1" ]; then
    require_command cmake
    log "Refreshing WASM artifact"
    "${REPO_ROOT}/scripts/build-core-wasm.sh"
fi

if [ ! -f "${WASM_JS}" ] || [ ! -f "${WASM_BIN}" ]; then
    if [ "${REQUIRE_WASM:-0}" = "1" ]; then
        echo "error: WASM artifacts are missing. Run REFRESH_WASM=1 bash scripts/verify.sh." >&2
        exit 1
    fi
    echo "warning: WASM artifacts not found; Vite build may only validate demo-mode paths." >&2
fi

require_command npm

if [ -f package-lock.json ]; then
    log "Installing dependencies with npm ci"
    npm ci
else
    log "Installing dependencies with npm install"
    npm install
fi

log "Building Web sample"
npm run build

log "Web verification complete"
