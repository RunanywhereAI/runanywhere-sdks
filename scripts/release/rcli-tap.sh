#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"

usage() {
    cat <<'EOF'
Usage: scripts/release/rcli-tap.sh <version>

Renders sdk/runanywhere-cli/packaging/homebrew/rcli.rb.in against a PUBLISHED
GitHub release (downloads the .sha256 sidecars) and pushes Formula/rcli.rb to
the Homebrew tap repository.

Run manually after the release workflow's draft Release is published:
  ./scripts/release/rcli-tap.sh 0.20.0

Environment:
  RCLI_TAP_REPO   Tap git remote (default git@github.com:RunanywhereAI/homebrew-tap.git)
  RCLI_TAP_DIR    Existing tap checkout to reuse (default: fresh temp clone)
  DRY_RUN=1       Render + print, do not commit/push
EOF
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
esac

VERSION="${1:?usage: rcli-tap.sh <version>}"
VERSION="${VERSION#v}"

CLI_ROOT="${RAC_ROOT}/sdk/runanywhere-cli"
TEMPLATE="${CLI_ROOT}/packaging/homebrew/rcli.rb.in"
RELEASE_BASE="https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v${VERSION}"
TAP_REPO="${RCLI_TAP_REPO:-git@github.com:RunanywhereAI/homebrew-tap.git}"

fetch_sha() {
    local asset="$1"
    local line
    line="$(curl -fsSL "${RELEASE_BASE}/${asset}.sha256")" ||
        die "missing release asset ${asset}.sha256 — is v${VERSION} published?"
    echo "${line}" | awk '{print $1}'
}

info "Fetching release checksums for v${VERSION}..."
SHA_MAC_ARM="$(fetch_sha "rcli-macos-arm64-v${VERSION}.tar.gz")"
SHA_LINUX_X64="$(fetch_sha "rcli-linux-x86_64-v${VERSION}.tar.gz")"

RENDERED="$(mktemp)"
sed -e "s/@VERSION@/${VERSION}/g" \
    -e "s/@SHA256_MACOS_ARM64@/${SHA_MAC_ARM}/g" \
    -e "s/@SHA256_LINUX_X86_64@/${SHA_LINUX_X64}/g" \
    "${TEMPLATE}" > "${RENDERED}"

log "Rendered formula:"
log "----------------------------------------"
cat "${RENDERED}"
log "----------------------------------------"

if [[ "${DRY_RUN:-0}" == "1" ]]; then
    info "DRY_RUN=1 — not pushing to the tap."
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

ok "Tap updated: brew install runanywhere-ai/tap/rcli"
