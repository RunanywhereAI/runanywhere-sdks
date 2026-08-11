#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Emscripten SDK Setup Script
# =============================================================================
#
# Installs and activates the Emscripten SDK (emsdk) for building
# RACommons to WebAssembly.
#
# The exact version is sourced from core/VERSIONS.
# Emscripten 5+ is required for the current WebGPU/Asyncify toolchain;
# using the canonical pin keeps generated glue and vendored archive provenance
# in lockstep.
#
# Usage:
#   ./scripts/setup-emsdk.sh              # Install to ./emsdk/
#   ./scripts/setup-emsdk.sh /opt/emsdk   # Install to custom path
#
# After running, activate in your shell:
#   source <emsdk-path>/emsdk_env.sh
#
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WASM_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${WASM_DIR}/../../.." && pwd)"

# shellcheck disable=SC1091
source "${REPO_ROOT}/core/scripts/load-versions.sh"
: "${EMSCRIPTEN_VERSION:?EMSCRIPTEN_VERSION is missing from the canonical VERSIONS file}"

EMSDK_VERSION="${EMSCRIPTEN_VERSION}"
INSTALL_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/emsdk}"

# `emsdk install` unpacks Emscripten but never installs its own npm
# dependencies, and the emsdk tree is gitignored, so a fresh clone has an
# `upstream/emscripten/node_modules` that does not exist at all.
#
# Nothing notices until link time: the C++ compiles to 98%, then emcc runs its
# JS post-processing and `tools/acorn-optimizer.mjs` imports `acorn-import-phases`
# — a declared dependency — and every WASM target dies with ERR_MODULE_NOT_FOUND.
# The failure reads like a compiler bug hours into a build rather than a missing
# `npm install`, so install the dependencies as part of setup.
ensure_emscripten_node_modules() {
    local emscripten_dir="$1/upstream/emscripten"
    if [ ! -f "${emscripten_dir}/package.json" ]; then
        return 0
    fi
    if [ -d "${emscripten_dir}/node_modules/acorn-import-phases" ]; then
        echo "Emscripten npm dependencies already installed."
        return 0
    fi
    if ! command -v npm >/dev/null 2>&1; then
        echo "ERROR: npm is required to install Emscripten's own JS tool dependencies." >&2
        echo "       Without them every WASM link fails in acorn-optimizer.mjs." >&2
        return 1
    fi
    echo "Installing Emscripten's npm dependencies (required by its JS optimizer)..."
    ( cd "${emscripten_dir}" && npm install --no-audit --no-fund )
}

echo "======================================"
echo " Emscripten SDK Setup"
echo "======================================"
echo " Version:     ${EMSDK_VERSION}"
echo " Install dir: ${INSTALL_DIR}"
echo "======================================"

# Check if already installed
if [ -d "${INSTALL_DIR}" ] && [ -f "${INSTALL_DIR}/emsdk" ]; then
    echo "emsdk already installed at ${INSTALL_DIR}"
    echo "Updating and activating version ${EMSDK_VERSION}..."
    cd "${INSTALL_DIR}"
    git pull 2>/dev/null || true
    ./emsdk install "${EMSDK_VERSION}"
    ./emsdk activate "${EMSDK_VERSION}"
    ensure_emscripten_node_modules "${INSTALL_DIR}"
    echo ""
    echo "Activate in your shell:"
    echo "  source ${INSTALL_DIR}/emsdk_env.sh"
    exit 0
fi

# Clone emsdk
echo "Cloning emsdk..."
git clone https://github.com/emscripten-core/emsdk.git "${INSTALL_DIR}"
cd "${INSTALL_DIR}"

# Install and activate
echo "Installing Emscripten ${EMSDK_VERSION}..."
./emsdk install "${EMSDK_VERSION}"
./emsdk activate "${EMSDK_VERSION}"
ensure_emscripten_node_modules "${INSTALL_DIR}"

echo ""
echo "======================================"
echo " Emscripten SDK installed successfully"
echo "======================================"
echo ""
echo "Activate in your shell before building:"
echo "  source ${INSTALL_DIR}/emsdk_env.sh"
echo ""
echo "Then build the WASM module:"
echo "  cd bindings/web/wasm"
echo "  ./scripts/build.sh"
