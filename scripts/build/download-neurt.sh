#!/usr/bin/env bash
# =============================================================================
# download-neurt.sh — fetch the prebuilt NeuRT archives for one Apple slice.
#
# NeuRT (the Apple Neural Engine engine) is built and published by the PRIVATE
# `neurun` repo. This script is the CONSUMER half of that boundary; the producer
# half is `NeuRT/tools/scripts/package-rac-dist.sh` over there.
#
# This repo used to compile neurun's source: engines/neurt/CMakeLists.txt resolved
# a NEURT_ROOT checkout and regex-parsed neurun's root CMakeLists.txt for a source
# list. Consequences: only someone holding that private repo could build this
# repo's Apple release, and a stray `)` inside a comment over there silently
# dropped a source file here. Now we link published bytes, pinned by tag + SHA-256
# in core/VERSIONS exactly like sherpa-onnx.
#
# Usage:
#   download-neurt.sh --slice <macos-arm64|ios-arm64|ios-arm64-simulator> [--force]
#   download-neurt.sh --all [--force]
#
# Auth: a GitHub token with read access to the private neurun repo, via
# $NEURUN_TOKEN or $GH_TOKEN. Without one this exits 3 (NOT 1) — the same
# "no prebuilt selected" convention validate-qhexrt-prebuilt.py uses, so a public
# build can fall back to the non-routable shell instead of failing the build.
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# core/third_party/ is already gitignored and is where every other vendored
# download lands (sherpa-onnx, onnxruntime). Using it means no new ignore rule
# that a future download script could forget to mirror.
DEST_ROOT="${REPO_ROOT}/core/third_party/neurt"

ALL_SLICES=(macos-arm64 ios-arm64 ios-arm64-simulator)
SLICES=()
FORCE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --slice) SLICES+=("$2"); shift 2 ;;
        --all)   SLICES=("${ALL_SLICES[@]}"); shift ;;
        --force) FORCE=1; shift ;;
        -h|--help) sed -n '2,25p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "[ERROR] unknown argument: $1" >&2; exit 2 ;;
    esac
done
[[ ${#SLICES[@]} -gt 0 ]] || { echo "[ERROR] pass --slice <name> or --all" >&2; exit 2; }

# ---- pins -------------------------------------------------------------------
# core/VERSIONS is the single source of truth. Do NOT add fallback defaults here:
# a hardcoded default silently drifts from the pin and then requests a release
# asset that does not exist, which surfaces as a 404 rather than a version error.
# shellcheck source=/dev/null
source "${REPO_ROOT}/core/scripts/load-versions.sh"

for required in NEURT_REPO NEURT_RELEASE_TAG NEURT_RAC_ABI_VERSION; do
    if [[ -z "${!required:-}" ]]; then
        echo "[ERROR] ${required} not set in core/VERSIONS" >&2
        exit 1
    fi
done

# The ABI version the archives must have been built against — read from the header
# rather than trusted from VERSIONS, so the pin cannot drift from the real ABI.
ABI_HEADER="${REPO_ROOT}/core/include/rac/plugin/rac_plugin_entry.h"
LOCAL_ABI="$(awk '$1=="#define" && $2=="RAC_PLUGIN_API_VERSION" {gsub(/[^0-9]/,"",$3); print $3; exit}' "$ABI_HEADER")"
if [[ -z "$LOCAL_ABI" ]]; then
    echo "[ERROR] could not parse RAC_PLUGIN_API_VERSION from ${ABI_HEADER}" >&2
    exit 1
fi
if [[ "$LOCAL_ABI" != "$NEURT_RAC_ABI_VERSION" ]]; then
    echo "[ERROR] core/VERSIONS says NEURT_RAC_ABI_VERSION=${NEURT_RAC_ABI_VERSION}," >&2
    echo "        but ${ABI_HEADER} defines RAC_PLUGIN_API_VERSION=${LOCAL_ABI}." >&2
    echo "        The plugin ABI changed: cut a new neurun release and re-pin." >&2
    exit 1
fi

TOKEN="${NEURUN_TOKEN:-${GH_TOKEN:-}}"
if [[ -z "$TOKEN" ]]; then
    echo "[SKIP] No NEURUN_TOKEN/GH_TOKEN — NeuRT prebuilts are private."
    echo "       The neurt engine will build as its non-routable shell."
    exit 3
fi

sha256_of() { shasum -a 256 "$1" | awk '{print $1}'; }

fetch_slice() {
    local slice="$1"
    local key="NEURT_$(echo "$slice" | tr 'a-z-' 'A-Z_')_SHA256"
    local expected="${!key:-}"
    if [[ -z "$expected" ]]; then
        echo "[ERROR] ${key} not set in core/VERSIONS" >&2
        return 1
    fi

    local version="${NEURT_RELEASE_TAG#v}"
    local asset="neurt-${slice}-v${version}.tar.gz"
    local dest="${DEST_ROOT}/${slice}"
    local stamp="${dest}/.pinned"

    # Cache on the exact pin, not merely on "a directory exists". A stale tree from
    # a previous tag is the failure mode that makes a re-pin look like a no-op.
    if [[ "$FORCE" -eq 0 && -f "$stamp" && "$(cat "$stamp")" == "${NEURT_RELEASE_TAG}:${expected}" ]]; then
        echo "[OK] ${slice}: already at ${NEURT_RELEASE_TAG}"
        return 0
    fi

    echo "[DOWNLOAD] ${slice} <- ${NEURT_REPO} ${NEURT_RELEASE_TAG}"
    local tmp; tmp="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp'" RETURN

    if ! GH_TOKEN="$TOKEN" gh release download "$NEURT_RELEASE_TAG" \
            --repo "$NEURT_REPO" --pattern "$asset" --dir "$tmp" 2>"${tmp}/err"; then
        echo "[ERROR] could not download ${asset} from ${NEURT_REPO}@${NEURT_RELEASE_TAG}" >&2
        sed 's/^/        /' "${tmp}/err" >&2 || true
        return 1
    fi

    local got; got="$(sha256_of "${tmp}/${asset}")"
    if [[ "$got" != "$expected" ]]; then
        echo "[ERROR] ${asset} SHA-256 mismatch" >&2
        echo "        expected ${expected}" >&2
        echo "        got      ${got}" >&2
        return 1
    fi
    echo "[OK] verified SHA-256 ${got}"

    rm -rf "$dest"; mkdir -p "$dest"
    tar -xzf "${tmp}/${asset}" -C "$dest" --strip-components=1

    # ---- the ABI receipt ----------------------------------------------------
    # This is why the boundary is safe. A vtable-layout change would relink these
    # archives cleanly and corrupt dispatch at runtime; a static archive resolves
    # no symbols, so no link error would ever appear.
    local receipt="${dest}/RECEIPT.json"
    [[ -f "$receipt" ]] || { echo "[ERROR] ${slice}: RECEIPT.json missing from the archive" >&2; return 1; }
    local got_abi; got_abi="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['rac_plugin_api_version'])" "$receipt")"
    if [[ "$got_abi" != "$LOCAL_ABI" ]]; then
        echo "[ERROR] ${slice}: built against RAC_PLUGIN_API_VERSION=${got_abi}," >&2
        echo "        but this repo is at ${LOCAL_ABI}. Cut a new neurun release." >&2
        return 1
    fi
    local got_slice; got_slice="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['slice'])" "$receipt")"
    if [[ "$got_slice" != "$slice" ]]; then
        echo "[ERROR] ${slice}: receipt claims slice '${got_slice}' — mismatched asset." >&2
        return 1
    fi

    # Fail closed on the archive set. A partial extract links to a confusing
    # "undefined symbol neurt::Generator::load" much later.
    local missing=0
    for lib in libneurt_core.a libneurt_rac_llm_ops.a libneurt_rac_stt_ops.a libneurt_rac_diffusion.a; do
        [[ -f "${dest}/lib/${lib}" ]] || { echo "[ERROR] ${slice}: missing ${lib}" >&2; missing=1; }
    done
    [[ -f "${dest}/include/rac_diffusion_coreml.h" ]] \
        || { echo "[ERROR] ${slice}: missing include/rac_diffusion_coreml.h" >&2; missing=1; }
    [[ $missing -eq 0 ]] || return 1

    echo "${NEURT_RELEASE_TAG}:${expected}" > "$stamp"
    echo "[OK] ${slice} -> ${dest}  (ABI ${got_abi})"
}

rc=0
for slice in "${SLICES[@]}"; do
    fetch_slice "$slice" || rc=1
done
exit "$rc"
