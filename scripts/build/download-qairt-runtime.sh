#!/usr/bin/env bash
# Fetch the pinned QAIRT/QNN runtime redistributables for one platform.
#
# These are PUBLIC assets -- no token. RunAnywhere is an authorized Qualcomm
# partner and already distributes these exact binaries unauthenticated on npm
# (@runanywhere/electron-qhexrt ships QnnHtp.dll, libQnnHtpV81Skel.so and
# libqnnhtpv81.cat today). Publishing them here as pinned, versioned assets makes
# an existing distribution verifiable rather than implicit, and is what lets a
# hosted runner -- or a fork, or an external contributor -- build a routable
# Hexagon engine without a licensed QAIRT install.
#
# The engine still compiles against QAIRT HEADERS ONLY and dlopens these at
# runtime. Shipping them beside the engine is packaging, not linking.
#
# Extracts to engines/qhexrt/prebuilt/qairt-runtime/<platform>/versions/<sha>/
# with an atomic per-platform `current` pointer.
#
# PER-PLATFORM on purpose: Android and Windows are built by different lanes and a
# single shared `current` would let one platform's download silently deselect the
# other's (it did, exactly once, during development). The `versions/` level is not
# decoration either -- scripts/build/_selection.py's contract is that `current`
# names `versions/<receipt>`, so a flatter layout produces a broken link.
#
# Structurally SEPARATE from the engine payloads under
# engines/qhexrt/prebuilt/versions/, so "the runtime matches the engine's
# expected SDK" stays a comparison between two independent artifacts and can
# never degenerate into hashing a file against a copy of itself.
#
# Usage: download-qairt-runtime.sh --platform <arm64-v8a|win-arm64> [--force]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=core/scripts/load-versions.sh
source "${REPO_ROOT}/core/scripts/load-versions.sh"
# shellcheck source=scripts/build/_release_asset.sh
source "${REPO_ROOT}/scripts/build/_release_asset.sh"

PLATFORM=""
FORCE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --platform|--abi)
            [[ $# -ge 2 ]] || { echo "[ERROR] $1 needs a value" >&2; exit 2; }
            PLATFORM="$2"; shift 2 ;;
        --force) FORCE=1; shift ;;
        -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
        *) echo "[ERROR] unknown argument: $1" >&2; exit 2 ;;
    esac
done
case "$PLATFORM" in arm64-v8a|win-arm64) ;; *)
    echo "[ERROR] --platform must be arm64-v8a or win-arm64" >&2; exit 2 ;;
esac

PY_BIN="${PYTHON_BIN:-python3}"
command -v "$PY_BIN" >/dev/null 2>&1 || PY_BIN=python

VERSION="${QAIRT_RUNTIME_VERSION:-}"
TAG="${QAIRT_RUNTIME_RELEASE_TAG:-}"
case "$PLATFORM" in
    arm64-v8a) EXPECTED_SHA="${QAIRT_RUNTIME_ARM64_V8A_SHA256:-}" ;;
    win-arm64) EXPECTED_SHA="${QAIRT_RUNTIME_WIN_ARM64_SHA256:-}" ;;
esac
for v in VERSION TAG EXPECTED_SHA; do
    [[ -n "${!v}" ]] || { echo "[ERROR] QAIRT_RUNTIME_* pin missing from core/VERSIONS ($v)" >&2; exit 2; }
done

REPO="${QAIRT_RUNTIME_REPO:-RunanywhereAI/runanywhere-sdks}"
ASSET="qairt-runtime-${PLATFORM}-v${VERSION}.tar.gz"
DEST_ROOT="${REPO_ROOT}/engines/qhexrt/prebuilt/qairt-runtime/${PLATFORM}"
DEST="${DEST_ROOT}/versions/${EXPECTED_SHA}"

# A cached tree is re-validated, not trusted because its receipt exists: if a
# library were deleted or edited while qairt-runtime.json survived, this path
# would select it, and the pairing gate only compares the identity hash -- so the
# first symptom would be the engine failing to load on a device.
cached_ok=0
if [[ -f "${DEST}/qairt-runtime.json" && "$FORCE" -eq 0 ]]; then
    if "$PY_BIN" "${REPO_ROOT}/scripts/build/_validate_qairt_runtime.py" \
            "$DEST" "$PLATFORM" "$VERSION" >/dev/null 2>&1; then
        cached_ok=1
        echo "[OK] ${PLATFORM}: QAIRT runtime ${VERSION} already present and valid"
    else
        echo "[WARN] cached QAIRT runtime failed validation; re-downloading" >&2
        rm -rf "$DEST"
    fi
fi
if [[ "$cached_ok" -eq 0 ]]; then
    tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
    echo "[DOWNLOAD] QAIRT runtime ${PLATFORM} <- ${REPO} ${TAG}"
    # No token: these are public assets.
    fetch_release_asset "$REPO" "$TAG" "$ASSET" "$tmp" "" "$PY_BIN"

    actual="$("$PY_BIN" -c "
import hashlib,sys
print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())" "${tmp}/${ASSET}")"
    if [[ "$actual" != "$EXPECTED_SHA" ]]; then
        echo "[ERROR] checksum mismatch for ${ASSET}" >&2
        echo "        expected ${EXPECTED_SHA}" >&2
        echo "        actual   ${actual}" >&2
        exit 1
    fi
    echo "[OK] verified SHA-256 ${actual}"

    inner="${tmp}/x"; mkdir -p "$inner"
    tar -xzf "${tmp}/${ASSET}" -C "$inner"
    [[ -f "${inner}/qairt-runtime.json" ]] || {
        echo "[ERROR] payload has no qairt-runtime.json receipt" >&2; exit 1; }

    # Validate the STAGED tree before touching anything live -- same checker the
    # cached path above runs, so the two can never drift apart.
    "$PY_BIN" "${REPO_ROOT}/scripts/build/_validate_qairt_runtime.py" \
        "$inner" "$PLATFORM" "$VERSION"

    mkdir -p "${DEST_ROOT}/versions"
    rm -rf "${DEST}.incoming" "$DEST"
    cp -R "$inner" "${DEST}.incoming"
    mv "${DEST}.incoming" "$DEST"
fi

# Atomic selection, same mechanism as the engine payload (junction on Windows,
# relative symlink on POSIX) -- see scripts/build/_selection.py.
"$PY_BIN" -c 'import sys; sys.path.insert(0, sys.argv[1]); import _selection;
_selection.create(sys.argv[2], sys.argv[3])' \
    "${REPO_ROOT}/scripts/build" "$DEST_ROOT" "$EXPECTED_SHA"

echo "[OK] ${PLATFORM} QAIRT runtime selected -> ${DEST}"
