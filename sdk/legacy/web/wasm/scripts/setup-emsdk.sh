#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Emscripten SDK Setup Script
# =============================================================================
#
# Installs and activates the Emscripten SDK (emsdk) for building
# RACommons to WebAssembly.
#
# Minimum version: 5.0.0
#   - Required for WebGPU + JSPI support (-sJSPI / ASYNCIFY=2).
#   - Older versions (e.g. 3.1.51) lack JSPI and ship a broken
#     wgpuInstanceWaitAny stub that crashes WebGPU inference.
#
# Usage:
#   ./scripts/setup-emsdk.sh              # Install to ./emsdk/
#   ./scripts/setup-emsdk.sh /opt/emsdk   # Install to custom path
#
# After running, activate in your shell:
#   source <emsdk-path>/emsdk_env.sh
#
# =============================================================================

EMSDK_VERSION="5.0.0"
INSTALL_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/emsdk}"

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

echo ""
echo "======================================"
echo " Emscripten SDK installed successfully"
echo "======================================"
echo ""
echo "Activate in your shell before building:"
echo "  source ${INSTALL_DIR}/emsdk_env.sh"
echo ""
echo "Then build the WASM module:"
echo "  cd sdk/runanywhere-web/wasm"
echo "  ./scripts/build.sh"
