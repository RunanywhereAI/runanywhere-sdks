#!/usr/bin/env bash
# =============================================================================
# check_engine_prebuilt_pins.sh — assert the private-engine prebuilt boundary is
# whole: the pinned release really has every artifact, the pins really describe
# those bytes, and every consumer that needs a payload really fetches one.
#
# Exists because each of these has already been wrong in a way nothing caught:
#
#   * Android released the non-routable QHexRT shell for months, because
#     build-core-android.sh enables the engine only when a payload is selected
#     and nothing in CI ever fetched one. "Nothing selected" is a legitimate
#     public-build outcome, so it never failed anything.
#   * The Electron win-arm64 lane pinned a hand-staged payload by absolute path
#     and drifted from the published one.
#   * NeuRT's pins had to be refreshed by hand after every rebuild; a stale one
#     fails at download time, deep in a native job.
#
# Read-only and offline by default. With a token it also verifies the pins
# against the real release; without one it checks everything local and says
# which parts it skipped.
#
# Usage: check_engine_prebuilt_pins.sh [--offline]
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
OFFLINE=0
[[ "${1:-}" == "--offline" ]] && OFFLINE=1

fail=0
note() { printf '  %s\n' "$*"; }
bad()  { printf '  [FAIL] %s\n' "$*" >&2; fail=1; }
ok()   { printf '  [OK] %s\n' "$*"; }

# shellcheck source=/dev/null
source "${REPO_ROOT}/core/scripts/load-versions.sh"

# The engines, their ABIs/slices, and the asset basename each publishes.
NEURT_SLICES=(macos-arm64 ios-arm64 ios-arm64-simulator)
QHEXRT_ABIS=(arm64-v8a win-arm64)

echo "== engine prebuilt pins =="

# ---- 1. every pin is present and well-formed --------------------------------
check_sha_var() {
    local name="$1" value="${!1:-}"
    if [[ -z "$value" ]]; then bad "$name is not set in core/VERSIONS"; return; fi
    if [[ ! "$value" =~ ^[0-9a-f]{64}$ ]]; then bad "$name is not a sha256: '$value'"; return; fi
}
for s in "${NEURT_SLICES[@]}"; do
    check_sha_var "NEURT_$(echo "$s" | tr 'a-z-' 'A-Z_')_SHA256"
done
for a in "${QHEXRT_ABIS[@]}"; do
    u="$(echo "$a" | tr 'a-z-' 'A-Z_')"
    check_sha_var "QHEXRT_${u}_SHA256"
    check_sha_var "QHEXRT_${u}_RECEIPT"
done
[[ -n "${NEURT_RELEASE_TAG:-}"  ]] || bad "NEURT_RELEASE_TAG is not set"
[[ -n "${QHEXRT_RELEASE_TAG:-}" ]] || bad "QHEXRT_RELEASE_TAG is not set"
[[ $fail -eq 0 ]] && ok "all pins present and well-formed"

# ---- 2. the ABI pin matches the header it must match ------------------------
# A drifted NEURT_RAC_ABI_VERSION makes the downloader refuse, but only once a
# native job gets that far. Catch it here instead.
hdr="${REPO_ROOT}/core/include/rac/plugin/rac_plugin_entry.h"
local_abi="$(awk '$1=="#define" && $2=="RAC_PLUGIN_API_VERSION" {gsub(/[^0-9]/,"",$3); print $3; exit}' "$hdr")"
if [[ -z "$local_abi" ]]; then
    bad "could not read RAC_PLUGIN_API_VERSION from $hdr"
elif [[ "${NEURT_RAC_ABI_VERSION:-}" != "$local_abi" ]]; then
    bad "NEURT_RAC_ABI_VERSION=${NEURT_RAC_ABI_VERSION:-<unset>} but the header says $local_abi"
else
    ok "NEURT_RAC_ABI_VERSION matches RAC_PLUGIN_API_VERSION ($local_abi)"
fi

# ---- 3. every consumer that needs a payload actually fetches one ------------
# This is the check that would have caught Android shipping the shell. A build
# that silently degrades to "no engine" is the failure mode with no symptom, so
# assert the fetch exists rather than trusting the build to complain.
echo "== consumers fetch what they need =="
expect_fetch() {
    local what="$1" file="$2" pattern="$3"
    if [[ ! -f "${REPO_ROOT}/${file}" ]]; then bad "$file is missing"; return; fi
    if grep -q -- "$pattern" "${REPO_ROOT}/${file}"; then
        ok "$what fetches its payload"
    else
        bad "$what does NOT fetch its payload (expected '$pattern' in $file)"
    fi
}
# Every Apple binding (Swift, Flutter, RN, Electron-macOS, Python) consumes NeuRT
# through the ONE xcframework native_ios builds, so this single fetch covers them.
expect_fetch "native_ios (NeuRT, all Apple bindings)" \
    ".github/workflows/release.yml" "download-neurt.sh --all"
expect_fetch "native_android arm64-v8a (QHexRT)" \
    ".github/workflows/release.yml" "download-qhexrt.sh --abi arm64-v8a"
expect_fetch "electron macOS (NeuRT)" \
    ".github/workflows/electron-native-package.yml" "download-neurt.sh --slice macos-arm64"
expect_fetch "electron win-arm64 (QHexRT)" \
    ".github/workflows/electron-native-package.yml" "download-qhexrt.sh --abi win-arm64"

# No consumer may point at a hand-staged payload by absolute path again.
echo "== no hand-staged payload paths =="
if grep -rnE "QHEXRT_ROOT: *['\"][A-Za-z]:\\\\|NEURT_ROOT: *['\"]?[A-Za-z]:\\\\|qhexrt-prebuilt\\\\versions" \
     "${REPO_ROOT}/.github/workflows/" >/dev/null 2>&1; then
    bad "a workflow pins an engine payload by absolute path; use the downloader"
    grep -rnE "QHEXRT_ROOT: *['\"][A-Za-z]:\\\\|qhexrt-prebuilt\\\\versions" \
        "${REPO_ROOT}/.github/workflows/" | sed 's/^/         /' >&2
else
    ok "no workflow hardcodes an engine payload path"
fi

# ---- 3b. the headers the prebuilt was compiled against have not moved -------
# This REPLACES cloning neurun and recompiling its adapters on every SDK PR.
#
# The receipt records the sdks commit whose headers the published archives were
# compiled against. If the ABI surface has changed since then, those archives may
# no longer match this repo -- and the ABI-version check cannot see it, because a
# widened signature does not necessarily bump RAC_PLUGIN_API_VERSION. Comparing
# the headers is a pure git operation: no private checkout, no compiler.
echo "== ABI headers vs the prebuilt receipt =="
ABI_HEADERS=(
    core/include/rac/plugin/rac_engine_vtable.h
    core/include/rac/plugin/rac_plugin_entry.h
    core/include/rac/features/llm/rac_llm_service.h
    core/include/rac/features/stt/rac_stt_service.h
    core/include/rac/features/diffusion/rac_diffusion_types.h
    core/include/rac/core/rac_error.h
)
receipt=""
for s in "${NEURT_SLICES[@]}"; do
    cand="${REPO_ROOT}/core/third_party/neurt/${s}/RECEIPT.json"
    [[ -f "$cand" ]] && { receipt="$cand"; break; }
done
if [[ -z "$receipt" ]]; then
    note "SKIPPED: no downloaded receipt locally (run download-neurt.sh to enable)."
else
    built_at="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('sdks_commit',''))" "$receipt")"
    if [[ -z "$built_at" || "$built_at" == "unknown" ]]; then
        bad "the receipt records no sdks_commit; re-cut the neurun release"
    elif ! git -C "$REPO_ROOT" cat-file -e "${built_at}^{commit}" 2>/dev/null; then
        # A shallow CI checkout will not have it. Try to fetch just that commit.
        git -C "$REPO_ROOT" fetch -q --depth=1 origin "$built_at" 2>/dev/null || true
        if ! git -C "$REPO_ROOT" cat-file -e "${built_at}^{commit}" 2>/dev/null; then
            note "SKIPPED: commit ${built_at:0:12} not available in this checkout."
        fi
    fi
    if git -C "$REPO_ROOT" cat-file -e "${built_at}^{commit}" 2>/dev/null; then
        drifted="$(git -C "$REPO_ROOT" diff --name-only "$built_at" -- "${ABI_HEADERS[@]}" 2>/dev/null || true)"
        if [[ -n "$drifted" ]]; then
            bad "ABI headers changed since the prebuilt was built (${built_at:0:12}):"
            printf '         %s\n' $drifted >&2
            note "Re-cut a neurun release so its adapters compile against these headers,"
            note "then re-pin. The ABI-version check cannot catch this on its own: a"
            note "widened signature need not bump RAC_PLUGIN_API_VERSION."
        else
            ok "ABI headers unchanged since ${built_at:0:12}"
        fi
    fi
fi

# ---- 4. the pinned release really has all of it -----------------------------
echo "== pinned release contents =="
TOKEN="${NEURUN_TOKEN:-${GH_TOKEN:-}}"
if [[ "$OFFLINE" -eq 1 || -z "$TOKEN" ]]; then
    note "SKIPPED (offline or no NEURUN_TOKEN): cannot verify the release itself."
    note "Local pin checks above still ran."
else
    repo="${NEURT_REPO:-RunanywhereAI/neurun}"
    listing="$(GH_TOKEN="$TOKEN" gh release view "$NEURT_RELEASE_TAG" --repo "$repo" \
                 --json assets --jq '.assets[].name' 2>/dev/null || true)"
    if [[ -z "$listing" ]]; then
        bad "could not read release $NEURT_RELEASE_TAG from $repo"
    else
        v="${NEURT_RELEASE_TAG#v}"
        want=()
        for s in "${NEURT_SLICES[@]}"; do want+=("neurt-${s}-v${v}.tar.gz"); done
        for a in "${QHEXRT_ABIS[@]}"; do want+=("qhexrt-${a}-v${v}.tar.gz"); done
        for w in "${want[@]}"; do
            if ! grep -qx "$w" <<<"$listing"; then bad "release is missing $w"
            elif ! grep -qx "${w}.sha256" <<<"$listing"; then bad "release is missing ${w}.sha256"
            fi
        done
        [[ $fail -eq 0 ]] && ok "release carries all $(( ${#want[@]} * 2 )) expected files"

        # The pin must equal the PUBLISHED checksum. A local rebuild produces
        # different bytes, so a hand-copied pin can describe something that was
        # never released -- exactly the drift this boundary exists to prevent.
        tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
        for s in "${NEURT_SLICES[@]}"; do
            var="NEURT_$(echo "$s" | tr 'a-z-' 'A-Z_')_SHA256"
            GH_TOKEN="$TOKEN" gh release download "$NEURT_RELEASE_TAG" --repo "$repo" \
                --pattern "neurt-${s}-v${v}.tar.gz.sha256" --dir "$tmp" --clobber 2>/dev/null || continue
            pub="$(cat "$tmp/neurt-${s}-v${v}.tar.gz.sha256")"
            [[ "$pub" == "${!var}" ]] && ok "$var matches the published asset" \
                                      || bad "$var=${!var} but the release publishes $pub"
        done
        for a in "${QHEXRT_ABIS[@]}"; do
            var="QHEXRT_$(echo "$a" | tr 'a-z-' 'A-Z_')_SHA256"
            GH_TOKEN="$TOKEN" gh release download "$QHEXRT_RELEASE_TAG" --repo "$repo" \
                --pattern "qhexrt-${a}-v${v}.tar.gz.sha256" --dir "$tmp" --clobber 2>/dev/null || continue
            pub="$(cat "$tmp/qhexrt-${a}-v${v}.tar.gz.sha256")"
            [[ "$pub" == "${!var}" ]] && ok "$var matches the published asset" \
                                      || bad "$var=${!var} but the release publishes $pub"
        done
    fi
fi

echo
if [[ $fail -ne 0 ]]; then
    echo "FAILED: the engine prebuilt boundary is not whole (see [FAIL] above)." >&2
    exit 1
fi
echo "OK: engine prebuilt pins, consumers and release contents all agree."
