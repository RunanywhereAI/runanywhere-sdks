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

source "${REPO_ROOT}/scripts/setup/detect-mode.sh"

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

echo ">> npm ci"
npm ci

# proto-ts is a SIBLING workspace member (../shared/proto-ts), so npm's hoisting
# from $WEB_ROOT places @bufbuild/protobuf into $WEB_ROOT/node_modules only —
# unreachable when tsc compiles proto-ts from its own sibling dir (TS2307 on
# '@bufbuild/protobuf/wire' in a clean CI checkout; only passes locally via a
# stray repo-root install). Install proto-ts standalone from its committed
# lockfile first, mirroring the RN SDK's package-sdk.sh. --workspaces=false stops
# npm from detecting the monorepo root and failing on the `workspace:*` protocol.
echo ">> npm ci proto-ts (standalone, so tsc can resolve @bufbuild/protobuf)"
(cd "$REPO_ROOT/sdk/shared/proto-ts" && npm ci --workspaces=false --no-audit --no-fund)

echo ">> npm run build:ts"
npm run build:ts

# Packaging emits the npm tarballs only. Typecheck is pr-build.yml's gate —
# running it here is redundant and not part of producing the artifact.

DIST_DIR="${WEB_ROOT}/dist/sdk-web"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

PACKAGE_VERSION="$(node -p "require('./package.json').version")"
[ -n "$PACKAGE_VERSION" ] || { echo "ERROR: Web package version is empty" >&2; exit 1; }

# proto-ts is still emitted as a first-class Web release asset, but the Web
# core and LlamaCPP entry tarballs also vendor this exact payload. Installing
# either entry package from GitHub Releases therefore never asks npm for an
# unpublished proto-ts version.
echo ">> npm pack ../shared/proto-ts"
(cd ../shared/proto-ts && npm pack --silent --pack-destination "$DIST_DIR" >/dev/null)
PROTO_ARCHIVE="$DIST_DIR/runanywhere-proto-ts-$PACKAGE_VERSION.tgz"
[ -f "$PROTO_ARCHIVE" ] || { echo "ERROR: npm pack did not produce $PROTO_ARCHIVE" >&2; exit 1; }
python3 "$REPO_ROOT/scripts/release/rewrite_npm_package.py" \
    --archive "$PROTO_ARCHIVE" \
    --exact-version "$PACKAGE_VERSION"

for pkg in core llamacpp onnx; do
    pkg_dir="$WEB_ROOT/packages/$pkg"
    echo ">> npm pack packages/$pkg"
    (cd "$pkg_dir" && npm pack --silent --pack-destination "$DIST_DIR" >/dev/null)
    case "$pkg" in
        core) artifact="$DIST_DIR/runanywhere-web-$PACKAGE_VERSION.tgz" ;;
        llamacpp) artifact="$DIST_DIR/runanywhere-web-llamacpp-$PACKAGE_VERSION.tgz" ;;
        onnx) artifact="$DIST_DIR/runanywhere-web-onnx-$PACKAGE_VERSION.tgz" ;;
    esac
    [ -f "$artifact" ] || { echo "ERROR: npm pack did not produce $artifact" >&2; exit 1; }
    rewrite_args=(
        --archive "$artifact"
        --exact-version "$PACKAGE_VERSION"
    )
    if [ "$pkg" != "onnx" ]; then
        rewrite_args+=(--bundle "@runanywhere/proto-ts=$PROTO_ARCHIVE")
    fi
    python3 "$REPO_ROOT/scripts/release/rewrite_npm_package.py" "${rewrite_args[@]}"
done

python3 "$SCRIPT_DIR/validate_public_packages.py" \
    --dist "$DIST_DIR" \
    --expected-version "$PACKAGE_VERSION"

echo ""
echo ">> Artifacts in $DIST_DIR:"
for f in "$DIST_DIR"/*.tgz; do
    [ -f "$f" ] || continue
    artifact_dir="$(dirname "$f")"
    artifact_name="$(basename "$f")"
    if command -v shasum >/dev/null 2>&1; then
        (cd "$artifact_dir" && shasum -a 256 "$artifact_name" > "$artifact_name.sha256")
        (cd "$artifact_dir" && shasum -a 256 --check "$artifact_name.sha256")
    else
        (cd "$artifact_dir" && sha256sum "$artifact_name" > "$artifact_name.sha256")
        (cd "$artifact_dir" && sha256sum --check "$artifact_name.sha256")
    fi
    echo "  $(basename "$f")"
done

# Exercise the same entry-package transactions documented for users. The
# standalone proto tarball is intentionally omitted: these installs succeed
# only when the advertised entry package carries its own exact proto payload.
INSTALL_SMOKE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/runanywhere-web-install.XXXXXX")"
trap 'rm -rf "$INSTALL_SMOKE_ROOT"' EXIT
verify_candidate_install() {
    local label="$1"
    local entry_package="$2"
    local proto_owner="$3"
    shift 3
    local install_root="$INSTALL_SMOKE_ROOT/$label"
    mkdir -p "$install_root"
    (
        cd "$install_root"
        npm init --yes >/dev/null
        npm install \
            --ignore-scripts \
            --no-audit \
            --no-fund \
            --package-lock=false \
            "$@" >/dev/null
        ENTRY_PACKAGE="$entry_package" \
        PROTO_OWNER="$proto_owner" \
        EXPECTED_VERSION="$PACKAGE_VERSION" \
        node - <<'NODE'
const fs = require('fs');
const path = require('path');
const { createRequire } = require('module');

const packageRoot = (name) => path.join(process.cwd(), 'node_modules', ...name.split('/'));
const entryManifest = JSON.parse(
  fs.readFileSync(path.join(packageRoot(process.env.ENTRY_PACKAGE), 'package.json'), 'utf8')
);
if (entryManifest.version !== process.env.EXPECTED_VERSION) {
  throw new Error(`${entryManifest.name} resolved ${entryManifest.version}`);
}
const ownerRoot = packageRoot(process.env.PROTO_OWNER);
const ownerRequire = createRequire(path.join(ownerRoot, 'package.json'));
const protoManifestPath = ownerRequire.resolve('@runanywhere/proto-ts/package.json');
const protoManifest = JSON.parse(fs.readFileSync(protoManifestPath, 'utf8'));
if (protoManifest.version !== process.env.EXPECTED_VERSION) {
  throw new Error(`proto-ts resolved ${protoManifest.version}`);
}
ownerRequire.resolve('@bufbuild/protobuf/wire');
console.log(`verified ${entryManifest.name}@${entryManifest.version} with bundled proto-ts@${protoManifest.version}`);
NODE
    )
}

verify_candidate_install \
    core \
    @runanywhere/web \
    @runanywhere/web \
    "$DIST_DIR/runanywhere-web-$PACKAGE_VERSION.tgz"
verify_candidate_install \
    llamacpp \
    @runanywhere/web-llamacpp \
    @runanywhere/web-llamacpp \
    "$DIST_DIR/runanywhere-web-$PACKAGE_VERSION.tgz" \
    "$DIST_DIR/runanywhere-web-llamacpp-$PACKAGE_VERSION.tgz"
verify_candidate_install \
    onnx \
    @runanywhere/web-onnx \
    @runanywhere/web \
    "$DIST_DIR/runanywhere-web-$PACKAGE_VERSION.tgz" \
    "$DIST_DIR/runanywhere-web-onnx-$PACKAGE_VERSION.tgz"

if [ -x "${REPO_ROOT}/scripts/release/validate-artifact.sh" ]; then
    echo ""
    "${REPO_ROOT}/scripts/release/validate-artifact.sh" "$DIST_DIR"/*.tgz
fi
