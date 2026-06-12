#!/usr/bin/env bash
# =============================================================================
# update-tap.sh <version>
#
# Renders packaging/homebrew/rcli.rb.in against a PUBLISHED GitHub release
# (downloads the .sha256 sidecars) and pushes Formula/rcli.rb to the Homebrew
# tap repository.
#
# Run manually after the release workflow's draft Release is published:
#   ./sdk/runanywhere-cli/scripts/update-tap.sh 0.20.0
#
# Environment:
#   RCLI_TAP_REPO   Tap git remote (default git@github.com:RunanywhereAI/homebrew-tap.git)
#   RCLI_TAP_DIR    Existing tap checkout to reuse (default: fresh temp clone)
#   DRY_RUN=1       Render + print, do not commit/push
# =============================================================================

set -euo pipefail

VERSION="${1:?usage: update-tap.sh <version>}"
VERSION="${VERSION#v}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEMPLATE="${CLI_ROOT}/packaging/homebrew/rcli.rb.in"
RELEASE_BASE="https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v${VERSION}"
TAP_REPO="${RCLI_TAP_REPO:-git@github.com:RunanywhereAI/homebrew-tap.git}"

fetch_sha() {
    local asset="$1"
    local line
    line="$(curl -fsSL "${RELEASE_BASE}/${asset}.sha256")" ||
        { echo "ERROR: missing release asset ${asset}.sha256 — is v${VERSION} published?" >&2; exit 1; }
    echo "${line}" | awk '{print $1}'
}

echo "Fetching release checksums for v${VERSION}..."
SHA_MAC_ARM="$(fetch_sha "rcli-macos-arm64-v${VERSION}.tar.gz")"
SHA_LINUX_X64="$(fetch_sha "rcli-linux-x86_64-v${VERSION}.tar.gz")"

RENDERED="$(mktemp)"
sed -e "s/@VERSION@/${VERSION}/g" \
    -e "s/@SHA256_MACOS_ARM64@/${SHA_MAC_ARM}/g" \
    -e "s/@SHA256_LINUX_X86_64@/${SHA_LINUX_X64}/g" \
    "${TEMPLATE}" > "${RENDERED}"

echo "Rendered formula:"
echo "----------------------------------------"
cat "${RENDERED}"
echo "----------------------------------------"

if [[ "${DRY_RUN:-0}" == "1" ]]; then
    echo "DRY_RUN=1 — not pushing to the tap."
    exit 0
fi

TAP_DIR="${RCLI_TAP_DIR:-}"
if [[ -z "${TAP_DIR}" ]]; then
    TAP_DIR="$(mktemp -d)/homebrew-tap"
    git clone --depth 1 "${TAP_REPO}" "${TAP_DIR}"
fi

mkdir -p "${TAP_DIR}/Formula"
cp "${RENDERED}" "${TAP_DIR}/Formula/rcli.rb"
git -C "${TAP_DIR}" add Formula/rcli.rb
git -C "${TAP_DIR}" commit -m "rcli ${VERSION}"
git -C "${TAP_DIR}" push

echo "Tap updated: brew install runanywhere-ai/tap/rcli"
