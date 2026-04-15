#!/usr/bin/env bash
# =============================================================================
# sdk/runanywhere-web/scripts/package-sdk.sh
# =============================================================================
# Unified SDK packaging contract for the Web SDK. Consumes pre-built WASM
# modules and produces npm tarballs (one per workspace) with checksums.
#
# USAGE:
#   package-sdk.sh [--mode local|ci] [--natives-from PATH]
#
# OPTIONS:
#   --mode local|ci      Build mode (default: auto-detect from $CI)
#   --natives-from PATH  Directory with WASM files. Expected layout either:
#                        - PATH/{core,llamacpp,onnx}/wasm/...  (same as in-tree)
#                        - PATH/*.tar.gz that expands to the above
#                        Default: in-place (assumes WASM already built)
#
# OUTPUTS:
#   dist/sdk-web/*.tgz     + .sha256     (one per npm workspace)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
WEB_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${REPO_ROOT}/scripts/detect-mode.sh"

NATIVES_FROM=""

while [ $# -gt 0 ]; do
    case "$1" in
        --mode) RAC_BUILD_MODE="$2"; shift 2 ;;
        --natives-from) NATIVES_FROM="$2"; shift 2 ;;
        --help|-h) head -20 "$0" | tail -16; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 1 ;;
    esac
done

echo ">> Web SDK packaging (mode=${RAC_BUILD_MODE})"

if [ -n "$NATIVES_FROM" ]; then
    [ -d "$NATIVES_FROM" ] || { echo "ERROR: --natives-from not found: $NATIVES_FROM" >&2; exit 1; }
    echo ">> Staging WASM from $NATIVES_FROM"
    # If native-web tarball, extract into packages/
    for tar in "$NATIVES_FROM"/RACommons-web-*.tar.gz; do
        [ -f "$tar" ] || continue
        tar xzf "$tar" -C "$WEB_ROOT/packages/"
    done
    # If loose {core,llamacpp,onnx}/wasm subdirs, copy them
    for pkg in core llamacpp onnx; do
        if [ -d "$NATIVES_FROM/$pkg/wasm" ]; then
            mkdir -p "$WEB_ROOT/packages/$pkg/wasm"
            cp -R "$NATIVES_FROM/$pkg/wasm/." "$WEB_ROOT/packages/$pkg/wasm/"
        fi
    done
fi

cd "$WEB_ROOT"

echo ">> npm install"
npm install

echo ">> npm run build:ts"
npm run build:ts

echo ">> npm run typecheck"
npm run typecheck

DIST_DIR="${WEB_ROOT}/dist/sdk-web"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

for pkg in core llamacpp onnx; do
    echo ">> npm pack packages/$pkg"
    (cd "packages/$pkg" && npm pack --pack-destination "$DIST_DIR" >/dev/null)
done

echo ""
echo ">> Artifacts in $DIST_DIR:"
for f in "$DIST_DIR"/*.tgz; do
    [ -f "$f" ] || continue
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$f" > "$f.sha256"
    else
        sha256sum "$f" > "$f.sha256"
    fi
    echo "  $(basename "$f")"
done

if [ -x "${REPO_ROOT}/scripts/validate-artifact.sh" ]; then
    echo ""
    "${REPO_ROOT}/scripts/validate-artifact.sh" "$DIST_DIR"/*.tgz 2>/dev/null || true
fi
