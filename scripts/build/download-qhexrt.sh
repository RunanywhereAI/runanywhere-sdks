#!/usr/bin/env bash
# =============================================================================
# download-qhexrt.sh — fetch the prebuilt QHexRT payload for one ABI and select
# it atomically.
#
# QHexRT (the Qualcomm Hexagon NPU engine) is built and published by the PRIVATE
# `neurun` repo. This is the consumer half; the producer half is
# `QHexRT/tools/scripts/package-rac-dist.sh` over there.
#
# WHAT THIS REPLACES. The payload used to be HAND-STAGED straight into
# engines/qhexrt/prebuilt/ by whoever held both repos and a QAIRT licence. That
# is how the Electron win-arm64 lane once pinned a receipt staged months earlier
# and silently shipped NPU kernels from an old commit. Now it is pinned by tag +
# SHA-256 in core/VERSIONS like any other dependency.
#
# ONE `current` AT A TIME, ON PURPOSE. Each ABI is its own content-addressed
# payload (`versions/<build-receipt-sha>/`), and `current` selects the one this
# build targets. Both ABIs can sit in `versions/` simultaneously; a build only
# ever consumes one, because a build only ever targets one platform.
#
# Usage:
#   download-qhexrt.sh --abi <arm64-v8a|win-arm64> [--force]
#
# Auth: a token with read access to the private neurun repo, via $NEURUN_TOKEN
# or $GH_TOKEN. Without one this exits 3 (NOT 1) — the same "no prebuilt
# selected" convention validate-qhexrt-prebuilt.py uses, so a public build falls
# back to the non-routable shell instead of failing.
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PREBUILT="${REPO_ROOT}/engines/qhexrt/prebuilt"

ABI=""
FORCE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --abi)   [[ $# -ge 2 ]] || { echo "[ERROR] --abi requires a value" >&2; exit 2; }
                 ABI="$2"; shift 2 ;;
        --force) FORCE=1; shift ;;
        -h|--help) sed -n '2,28p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "[ERROR] unknown argument: $1" >&2; exit 2 ;;
    esac
done
[[ -n "$ABI" ]] || { echo "[ERROR] --abi is required (arm64-v8a | win-arm64)" >&2; exit 2; }
case "$ABI" in arm64-v8a|win-arm64) ;; *) echo "[ERROR] unknown abi '$ABI'" >&2; exit 2 ;; esac

# core/VERSIONS is the single source of truth. No fallback defaults: a hardcoded
# default drifts from the pin and then requests an asset that does not exist,
# which surfaces as a 404 rather than a version error.
# shellcheck source=/dev/null
source "${REPO_ROOT}/core/scripts/load-versions.sh"

KEY_UPPER="$(echo "$ABI" | tr 'a-z-' 'A-Z_')"
SHA_VAR="QHEXRT_${KEY_UPPER}_SHA256"
RECEIPT_VAR="QHEXRT_${KEY_UPPER}_RECEIPT"
EXPECTED_SHA="${!SHA_VAR:-}"
EXPECTED_RECEIPT="${!RECEIPT_VAR:-}"

for pair in "QHEXRT_REPO:${QHEXRT_REPO:-}" "QHEXRT_RELEASE_TAG:${QHEXRT_RELEASE_TAG:-}" \
            "${SHA_VAR}:${EXPECTED_SHA}" "${RECEIPT_VAR}:${EXPECTED_RECEIPT}"; do
    if [[ -z "${pair#*:}" ]]; then
        echo "[ERROR] ${pair%%:*} not set in core/VERSIONS" >&2
        exit 1
    fi
done

TOKEN="${NEURUN_TOKEN:-${GH_TOKEN:-}}"
if [[ -z "$TOKEN" ]]; then
    echo "[SKIP] No NEURUN_TOKEN/GH_TOKEN — the QHexRT payload is private."
    echo "       The qhexrt engine will build as its non-routable shell."
    exit 3
fi

sha256_of() { shasum -a 256 "$1" 2>/dev/null | awk '{print $1}' || sha256sum "$1" | awk '{print $1}'; }

# `python3` does not exist on Windows. `|| true` so a failed lookup cannot abort
# under `set -e` before the message below explains itself.
PY_BIN="$(command -v python3 || command -v python || true)"
if [[ -z "$PY_BIN" ]]; then
    echo "[ERROR] no python3/python on PATH." >&2
    echo "        A self-hosted Windows service account may not see a per-user" >&2
    echo "        install; put its directory on PATH for the job." >&2
    exit 1
fi

VERSION="${QHEXRT_RELEASE_TAG#v}"
ASSET="qhexrt-${ABI}-v${VERSION}.tar.gz"
DEST="${PREBUILT}/versions/${EXPECTED_RECEIPT}"

# Cache on the exact pin. "The directory exists" is not enough — a tree left by a
# previous tag is precisely the stale-payload failure this script exists to end.
if [[ "$FORCE" -eq 0 && -d "$DEST" && -f "${DEST}/qhexrt-prebuilt.json" ]]; then
    echo "[OK] ${ABI}: ${EXPECTED_RECEIPT} already present"
else
    echo "[DOWNLOAD] ${ABI} <- ${QHEXRT_REPO} ${QHEXRT_RELEASE_TAG}"
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp'" EXIT

    if ! GH_TOKEN="$TOKEN" gh release download "$QHEXRT_RELEASE_TAG" \
            --repo "$QHEXRT_REPO" --pattern "$ASSET" --dir "$tmp" 2>"${tmp}/err"; then
        echo "[ERROR] could not download ${ASSET} from ${QHEXRT_REPO}@${QHEXRT_RELEASE_TAG}" >&2
        sed 's/^/        /' "${tmp}/err" >&2 || true
        exit 1
    fi

    got="$(sha256_of "${tmp}/${ASSET}")"
    if [[ "$got" != "$EXPECTED_SHA" ]]; then
        echo "[ERROR] ${ASSET} SHA-256 mismatch" >&2
        echo "        expected ${EXPECTED_SHA}" >&2
        echo "        got      ${got}" >&2
        exit 1
    fi
    echo "[OK] verified SHA-256 ${got}"

    # Extract to a staging dir first. Writing straight into versions/ would leave
    # a half-populated immutable directory behind on any failure, and every reader
    # treats a versions/<sha> dir as complete by construction.
    stage="${tmp}/x"; mkdir -p "$stage"
    tar -xzf "${tmp}/${ASSET}" -C "$stage"

    # The archive's top-level dir is its receipt hash. Check it against the PIN
    # rather than trusting it: this is what makes the pin describe the bytes.
    inner="$(find "$stage" -mindepth 1 -maxdepth 1 -type d | head -1)"
    [[ -n "$inner" ]] || { echo "[ERROR] archive contained no payload directory" >&2; exit 1; }
    if [[ "$(basename "$inner")" != "$EXPECTED_RECEIPT" ]]; then
        echo "[ERROR] payload receipt is $(basename "$inner")," >&2
        echo "        but core/VERSIONS::${RECEIPT_VAR} pins ${EXPECTED_RECEIPT}." >&2
        exit 1
    fi

    # Validate the STAGED tree before anything live is touched. Publishing first
    # and validating after meant a rejected payload could end up selected, and with
    # --force the `rm -rf "$DEST"` could delete the directory `current` still
    # pointed at, leaving readers on a broken link.
    probe="${tmp}/probe"; mkdir -p "${probe}/versions"
    cp -R "$inner" "${probe}/versions/${EXPECTED_RECEIPT}"
    ln -s "versions/${EXPECTED_RECEIPT}" "${probe}/current"
    if ! staged="$("$PY_BIN" "${REPO_ROOT}/scripts/build/validate-qhexrt-prebuilt.py" \
            --prebuilt "$probe" --android-abi "$ABI" 2>&1)"; then
        echo "[ERROR] payload failed the SDK validator; nothing was changed:" >&2
        echo "$staged" | sed 's/^/        /' >&2
        exit 1
    fi

    # Only now publish. The directory is content-addressed, so an identical
    # receipt means identical bytes and replacing it is a no-op.
    mkdir -p "${PREBUILT}/versions"
    rm -rf "${DEST}.incoming"
    cp -R "$inner" "${DEST}.incoming"
    rm -rf "$DEST"
    mv "${DEST}.incoming" "$DEST"
    echo "[OK] staged and validated ${EXPECTED_RECEIPT}"
fi

# ---- select it atomically ----------------------------------------------------
# Readers resolve `current` to one immutable version directory, so the swap must
# be a rename, never a delete-then-create: a reader in the gap would otherwise
# see no engine at all.
if [[ -e "${PREBUILT}/current" && ! -L "${PREBUILT}/current" ]]; then
    echo "[ERROR] ${PREBUILT}/current exists and is not a symlink; refusing to replace it." >&2
    exit 1
fi
# os.replace, not `mv`: `mv tmp current` FOLLOWS an existing symlink-to-directory
# and moves the temp link INSIDE the old target, leaving `current` unchanged. That
# silently kept the previously selected ABI while reporting success. os.replace
# operates on the link itself and is atomic, so a reader never sees no selection.
"$PY_BIN" - "$PREBUILT" "$EXPECTED_RECEIPT" <<'PYSWAP'
import os, sys
prebuilt, receipt = sys.argv[1], sys.argv[2]
tmp = os.path.join(prebuilt, f".current.{os.getpid()}")
if os.path.lexists(tmp):
    os.remove(tmp)
os.symlink(os.path.join("versions", receipt), tmp, target_is_directory=True)
os.replace(tmp, os.path.join(prebuilt, "current"))
PYSWAP

# ---- prove the SDK will accept it -------------------------------------------
# The same validator the build preflight runs. Catching a bad payload here beats
# catching it mid-build, where the error names a CMake target rather than a pin.
if ! resolved="$("$PY_BIN" "${REPO_ROOT}/scripts/build/validate-qhexrt-prebuilt.py" \
        --prebuilt "$PREBUILT" --android-abi "$ABI" 2>&1)"; then
    echo "[ERROR] the downloaded payload failed the SDK's own validator:" >&2
    echo "$resolved" | sed 's/^/        /' >&2
    exit 1
fi
echo "[OK] ${ABI} selected and validated -> ${resolved}"
