#!/bin/sh
# =============================================================================
# RunAnywhere rcli installer
#
#   curl -fsSL https://raw.githubusercontent.com/RunanywhereAI/runanywhere-sdks/main/sdk/runanywhere-cli/scripts/install.sh | sh
#
# Downloads the rcli release tarball for this platform, verifies its sha256,
# installs to ~/.local/share/rcli/<version> and symlinks ~/.local/bin/rcli.
#
# Environment:
#   RCLI_VERSION       Pin a version (default: latest GitHub release)
#   RCLI_INSTALL_DIR   Install root   (default: ~/.local/share/rcli)
#   RCLI_BIN_DIR       Symlink dir    (default: ~/.local/bin)
# =============================================================================

set -eu

REPO="RunanywhereAI/runanywhere-sdks"
INSTALL_DIR="${RCLI_INSTALL_DIR:-${HOME}/.local/share/rcli}"
BIN_DIR="${RCLI_BIN_DIR:-${HOME}/.local/bin}"

error() { printf 'install.sh: %s\n' "$1" >&2; exit 1; }

# --- platform detection ------------------------------------------------------
OS="$(uname -s)"
ARCH="$(uname -m)"
case "${OS}-${ARCH}" in
    Darwin-arm64)  PLATFORM="macos-arm64" ;;
    Linux-x86_64)  PLATFORM="linux-x86_64" ;;
    Darwin-x86_64) error "Intel macOS builds are not published yet (Apple Silicon only). Build from source: see sdk/runanywhere-cli/README.md" ;;
    *)             error "unsupported platform ${OS}/${ARCH}. Build from source: see sdk/runanywhere-cli/README.md" ;;
esac

command -v curl >/dev/null 2>&1 || error "curl is required"
command -v tar  >/dev/null 2>&1 || error "tar is required"

# --- resolve version ---------------------------------------------------------
VERSION="${RCLI_VERSION:-}"
if [ -z "${VERSION}" ]; then
    VERSION="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
               | grep '"tag_name"' | head -1 | sed -E 's/.*"v?([^"]+)".*/\1/')"
    [ -n "${VERSION}" ] || error "could not resolve the latest release (set RCLI_VERSION=x.y.z)"
fi
VERSION="${VERSION#v}"

TARBALL="rcli-${PLATFORM}-v${VERSION}.tar.gz"
URL="https://github.com/${REPO}/releases/download/v${VERSION}/${TARBALL}"

printf 'Installing rcli %s (%s)\n' "${VERSION}" "${PLATFORM}"

# --- download + verify -------------------------------------------------------
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

curl -fL --progress-bar -o "${TMP}/${TARBALL}" "${URL}" \
    || error "download failed: ${URL}"
curl -fsSL -o "${TMP}/${TARBALL}.sha256" "${URL}.sha256" \
    || error "checksum download failed: ${URL}.sha256"

(
    cd "${TMP}"
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 -c "${TARBALL}.sha256" >/dev/null
    else
        sha256sum -c "${TARBALL}.sha256" >/dev/null
    fi
) || error "sha256 verification failed"

# --- install -----------------------------------------------------------------
DEST="${INSTALL_DIR}/${VERSION}"
rm -rf "${DEST}"
mkdir -p "${DEST}" "${BIN_DIR}"
tar -xzf "${TMP}/${TARBALL}" -C "${DEST}" --strip-components 1

ln -sf "${DEST}/bin/rcli" "${BIN_DIR}/rcli"

printf 'Installed: %s/rcli -> %s/bin/rcli\n' "${BIN_DIR}" "${DEST}"
case ":${PATH}:" in
    *":${BIN_DIR}:"*) ;;
    *) printf 'NOTE: add %s to your PATH (e.g. export PATH="%s:$PATH")\n' "${BIN_DIR}" "${BIN_DIR}" ;;
esac
printf 'Try: rcli list --all && rcli run qwen3\n'
