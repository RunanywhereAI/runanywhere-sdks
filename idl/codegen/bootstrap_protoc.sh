#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# bootstrap_protoc.sh — put the EXACT pinned protoc on this machine
# =============================================================================
# THE PROBLEM
#   protoc stamps its own major.minor.patch into everything it emits:
#   `#if PROTOBUF_VERSION != 7035001` in every generated C++ header, and a
#   `//   protoc               v7.35.1` banner in every ts-proto file. So the
#   generated code is a function of the compiler *patch* version, not just of
#   the schemas — and generate_all.sh fails closed on anything but
#   core/VERSIONS::PROTOC_VERSION.
#
#   Package managers cannot satisfy that. `brew install protobuf` gives
#   whatever is current, `apt-get install protobuf-compiler` gives whatever the
#   distro froze, and neither offers a patch-level pin. That is the whole reason
#   the generated C/C++ tree used to be committed.
#
# THE FIX
#   protobuf publishes prebuilt, immutable, per-platform archives on every
#   release, so the pin is obtainable everywhere — it just has to be downloaded
#   rather than asked for:
#
#     protoc-<v>-osx-aarch_64.zip      protoc-<v>-osx-x86_64.zip
#     protoc-<v>-osx-universal_binary.zip
#     protoc-<v>-linux-x86_64.zip      protoc-<v>-linux-aarch_64.zip
#     protoc-<v>-win64.zip             protoc-<v>-win32.zip
#
#   (note the macOS arm64 asset is `osx-aarch_64`, with an underscore.)
#
#   This script resolves the pin in four steps, cheapest first:
#     1. $RAC_PROTOC, if it reports the pinned version
#     2. `protoc` already on PATH, if it reports the pinned version
#     3. a previous download in the cache, if it reports the pinned version
#     4. download the pinned asset, verify its sha256 against
#        idl/codegen/protoc.sha256, unpack it atomically, and re-verify by
#        running `protoc --version`
#
#   Nothing is ever installed without a checksum match, and nothing is ever
#   returned without `protoc --version` agreeing with the pin. An unrecognised
#   asset (i.e. a PROTOC_VERSION bump that did not update protoc.sha256) is a
#   hard error, not a silently unverified download.
#
# OUTPUT CONTRACT
#   stdout is ONE line: the absolute path of the protoc executable.
#   Everything else — progress, warnings — goes to stderr, so callers can do
#       PROTOC="$(idl/codegen/bootstrap_protoc.sh)"
#   and CMake can do the same with execute_process(OUTPUT_VARIABLE ...).
#
# USAGE
#   idl/codegen/bootstrap_protoc.sh              # path to protoc  (may download)
#   idl/codegen/bootstrap_protoc.sh --print-dir  # its bin directory
#   idl/codegen/bootstrap_protoc.sh --check      # resolve without downloading
#
# ENVIRONMENT
#   RAC_PROTOC             explicit protoc to use (still version-checked)
#   RAC_PROTOC_CACHE       cache root; default
#                          ${XDG_CACHE_HOME:-$HOME/.cache}/runanywhere/protoc
#   RAC_PROTOC_NO_DOWNLOAD=1  never download; fail if the pin is not already
#                          present. For air-gapped hosts and for CI jobs that
#                          want the install to be an explicit, cached step.
#   RAC_PROTOC_ASSET       override the auto-detected asset name (e.g. force
#                          osx-universal_binary on a macOS CI runner)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CHECKSUMS="${SCRIPT_DIR}/protoc.sha256"

MODE="path"
NO_DOWNLOAD="${RAC_PROTOC_NO_DOWNLOAD:-0}"
while [ $# -gt 0 ]; do
    case "$1" in
        --print-dir) MODE="dir"; shift ;;
        --print-path) MODE="path"; shift ;;
        --check)     NO_DOWNLOAD=1; shift ;;
        -h|--help)   sed -n '2,70p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "bootstrap_protoc.sh: unknown flag: $1" >&2; exit 2 ;;
    esac
done

log() { echo "bootstrap_protoc: $*" >&2; }
die() { echo "bootstrap_protoc: error: $*" >&2; exit 1; }

# --- the pin -----------------------------------------------------------------
VERSIONS_FILE="${REPO_ROOT}/core/VERSIONS"
[ -f "${VERSIONS_FILE}" ] || die "core/VERSIONS not found at ${VERSIONS_FILE}"
PIN="$(grep -E '^PROTOC_VERSION=' "${VERSIONS_FILE}" | head -1 | cut -d= -f2 | tr -d '[:space:]')"
[ -n "${PIN}" ] || die "core/VERSIONS does not define PROTOC_VERSION"

# `protoc --version` prints "libprotoc 35.1".
protoc_version_of() {
    "$1" --version 2>/dev/null | awk '{print $2}'
}
is_pinned() {
    [ -n "${1:-}" ] && [ -x "$1" ] && [ "$(protoc_version_of "$1")" = "${PIN}" ]
}

emit() {
    case "${MODE}" in
        dir)  dirname "$1" ;;
        path) printf '%s\n' "$1" ;;
    esac
    exit 0
}

# --- 1. explicit override ----------------------------------------------------
if [ -n "${RAC_PROTOC:-}" ]; then
    if is_pinned "${RAC_PROTOC}"; then
        emit "${RAC_PROTOC}"
    fi
    die "RAC_PROTOC=${RAC_PROTOC} reports '$(protoc_version_of "${RAC_PROTOC}" || true)', pinned is ${PIN}"
fi

# --- 2. already on PATH ------------------------------------------------------
if command -v protoc >/dev/null 2>&1; then
    ON_PATH="$(command -v protoc)"
    if is_pinned "${ON_PATH}"; then
        emit "${ON_PATH}"
    fi
    log "protoc on PATH is $(protoc_version_of "${ON_PATH}"), need ${PIN} — resolving the pinned build"
fi

# --- 3. the cache ------------------------------------------------------------
CACHE_ROOT="${RAC_PROTOC_CACHE:-${XDG_CACHE_HOME:-${HOME}/.cache}/runanywhere/protoc}"
INSTALL_DIR="${CACHE_ROOT}/${PIN}"
# The Windows archives carry protoc.exe; every other asset carries plain protoc.
for candidate in "${INSTALL_DIR}/bin/protoc" "${INSTALL_DIR}/bin/protoc.exe"; do
    if is_pinned "${candidate}"; then
        emit "${candidate}"
    fi
done

if [ "${NO_DOWNLOAD}" = "1" ]; then
    die "protoc ${PIN} is not installed and downloading is disabled (RAC_PROTOC_NO_DOWNLOAD/--check).
       Expected it at ${INSTALL_DIR}/bin/protoc, on PATH, or via \$RAC_PROTOC.
       Run: ${SCRIPT_DIR#"${REPO_ROOT}/"}/bootstrap_protoc.sh"
fi

# --- 4. download -------------------------------------------------------------
# The asset name is a function of (kernel, machine). uname -m reports the
# hardware, which on Apple silicon under Rosetta is still arm64, and on 64-bit
# Windows Git Bash is x86_64.
if [ -n "${RAC_PROTOC_ASSET:-}" ]; then
    ASSET="${RAC_PROTOC_ASSET}"
else
    case "$(uname -s)" in
        Darwin)
            case "$(uname -m)" in
                arm64|aarch64) ASSET="osx-aarch_64" ;;
                x86_64)        ASSET="osx-x86_64" ;;
                *) die "no protoc asset for Darwin/$(uname -m)" ;;
            esac
            ;;
        Linux)
            case "$(uname -m)" in
                x86_64|amd64)  ASSET="linux-x86_64" ;;
                aarch64|arm64) ASSET="linux-aarch_64" ;;
                *) die "no protoc asset for Linux/$(uname -m)" ;;
            esac
            ;;
        MINGW*|MSYS*|CYGWIN*|Windows_NT)
            case "$(uname -m)" in
                x86_64|amd64) ASSET="win64" ;;
                i686|i386)    ASSET="win32" ;;
                *) die "no protoc asset for Windows/$(uname -m)" ;;
            esac
            ;;
        *) die "no protoc asset for $(uname -s)/$(uname -m)" ;;
    esac
fi

ZIP_NAME="protoc-${PIN}-${ASSET}.zip"
URL="https://github.com/protocolbuffers/protobuf/releases/download/v${PIN}/${ZIP_NAME}"

[ -f "${CHECKSUMS}" ] || die "missing ${CHECKSUMS}"
EXPECTED="$(awk -v f="${ZIP_NAME}" '$2 == f {print $1}' "${CHECKSUMS}" | head -1)"
if [ -z "${EXPECTED}" ]; then
    die "no sha256 recorded for ${ZIP_NAME} in ${CHECKSUMS#"${REPO_ROOT}/"}.
       PROTOC_VERSION was bumped to ${PIN} without refreshing the checksums;
       see the header of that file for how to regenerate them. Refusing to
       install an unverified compiler."
fi

# sha256 without assuming any one tool: macOS has shasum, Linux sha256sum, Git
# Bash both — but a stripped container may have neither and still have python3.
sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 "$1" | awk '{print $NF}'
    else
        for py in python3 python; do
            if command -v "${py}" >/dev/null 2>&1; then
                "${py}" -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"
                return 0
            fi
        done
        return 1
    fi
}

# Likewise for unzip. Git Bash ships no `unzip` at all, which is exactly the
# host that most needs this to work, so try every extractor that a machine
# capable of building this repo plausibly has.
unzip_to() {
    local zip="$1" dest="$2"
    if command -v unzip >/dev/null 2>&1; then
        unzip -q -o "${zip}" -d "${dest}" && return 0
    fi
    for py in python3 python; do
        if command -v "${py}" >/dev/null 2>&1; then
            "${py}" -c 'import sys,zipfile;zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "${zip}" "${dest}" && return 0
        fi
    done
    if command -v cmake >/dev/null 2>&1; then
        (cd "${dest}" && cmake -E tar xf "${zip}") && return 0
    fi
    if command -v 7z >/dev/null 2>&1; then
        7z x -y -o"${dest}" "${zip}" >/dev/null && return 0
    fi
    return 1
}

# Stage inside the cache root, NOT $TMPDIR. Publishing below is a directory
# rename, and on Git Bash for Windows $TMPDIR and $HOME routinely sit on
# different volumes (D:\a\_temp vs C:\Users\...). MSYS's rename() reports
# EACCES — "Permission denied" — rather than EXDEV for a cross-volume directory
# move, so GNU mv never reaches its copy fallback and the install fails with an
# error that reads like a permissions problem and is not one. Everything under
# CACHE_ROOT is one filesystem by construction.
mkdir -p "${CACHE_ROOT}"
TMP="$(mktemp -d "${CACHE_ROOT}/.tmp-XXXXXX")"
cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT

log "downloading ${URL}"
# Every fetch is bounded. Without --max-time / --timeout a stalled connection
# (a proxy that accepts and never speaks, a hung CDN edge) blocks the whole
# build forever instead of failing — and this runs inside CMake configures and
# Gradle tasks where nobody is watching a terminal.
if command -v curl >/dev/null 2>&1; then
    curl --fail --silent --show-error --location \
        --connect-timeout 20 --max-time 300 --speed-time 60 --speed-limit 1024 \
        --retry 5 --retry-all-errors --retry-delay 2 --retry-max-time 600 \
        -o "${TMP}/${ZIP_NAME}" "${URL}" \
        || die "download failed or timed out: ${URL}"
elif command -v wget >/dev/null 2>&1; then
    wget --quiet --tries=5 --timeout=60 --waitretry=2 \
        -O "${TMP}/${ZIP_NAME}" "${URL}" \
        || die "download failed or timed out: ${URL}"
else
    die "neither curl nor wget is available to fetch ${URL}"
fi

ACTUAL="$(sha256_of "${TMP}/${ZIP_NAME}")" || die "no sha256 tool available (sha256sum/shasum/openssl/python3)"
if [ "${ACTUAL}" != "${EXPECTED}" ]; then
    die "checksum mismatch for ${ZIP_NAME}
       expected ${EXPECTED}
       actual   ${ACTUAL}
       Refusing to install. Either the download was corrupted or the pinned
       asset changed upstream."
fi
log "sha256 ok (${EXPECTED})"

mkdir -p "${TMP}/unpack"
unzip_to "${TMP}/${ZIP_NAME}" "${TMP}/unpack" \
    || die "no unzip tool available (unzip/python3/cmake)"
chmod +x "${TMP}/unpack/bin/protoc" "${TMP}/unpack/bin/protoc.exe" 2>/dev/null || true

# Publish atomically: unpack to a scratch dir, then rename into place, so a
# killed download can never leave a half-populated cache that the next run
# happily treats as installed. A concurrent bootstrap that wins the race is
# fine — the losing rename is discarded and both see the same verified bits.
# ${TMP} is already inside ${CACHE_ROOT}, so this is a same-filesystem rename
# on every host including Git Bash (see the staging note above).
if [ ! -d "${INSTALL_DIR}" ]; then
    mv "${TMP}/unpack" "${INSTALL_DIR}" 2>/dev/null || true
fi

for candidate in "${INSTALL_DIR}/bin/protoc" "${INSTALL_DIR}/bin/protoc.exe"; do
    if is_pinned "${candidate}"; then
        log "installed protoc ${PIN} -> ${candidate}"
        emit "${candidate}"
    fi
done

die "unpacked ${ZIP_NAME} but ${INSTALL_DIR}/bin/protoc does not report ${PIN}"
