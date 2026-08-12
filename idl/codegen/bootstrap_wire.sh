#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# bootstrap_wire.sh — put the EXACT pinned Square Wire compiler on this machine
# =============================================================================
# WHY
#   The Kotlin bindings are wire-compiler output, and Wire's emitted filenames
#   and formatting move between releases (5.x renamed `LoRAState.kt` to
#   `LoraState.kt`, which is the whole reason check_generated_filenames.sh
#   exists). So the Kotlin tree is a function of WIRE_VERSION, and the version
#   has to be obtainable on every host that builds the AAR — including JitPack,
#   which runs Gradle on a machine we do not provision.
#
#   There is no package manager route at all here: `brew install wire` installs
#   the Wire *messaging app*, not Square's protobuf compiler. The only real
#   distribution is the fat JAR on Maven Central.
#
# WHAT IT DOES
#   Resolves the pinned wire-compiler cheapest-first — an existing
#   `wire-compiler` on PATH, then the cache, then a checksum-verified download —
#   and prints the path of a `wire-compiler` shell wrapper that runs it. The
#   wrapper exists so generate_kotlin.sh can keep invoking a plain command name.
#
#   A `wire-compiler` already on PATH is accepted as-is: Wire has no --version
#   flag (5.5.1 exits 1 with "Nothing to do! Specify --java_out=..." and no
#   version string anywhere), so there is nothing to verify it against. That is
#   a deliberate trust-the-operator escape hatch; the default path — cache or
#   download — is exact, because the JAR is pinned by name AND by sha256.
#
# OUTPUT CONTRACT
#   stdout is ONE line: the absolute path of a runnable `wire-compiler`.
#   Diagnostics go to stderr.
#
# USAGE
#   idl/codegen/bootstrap_wire.sh              # path to wire-compiler
#   idl/codegen/bootstrap_wire.sh --print-dir  # its directory (for PATH)
#   idl/codegen/bootstrap_wire.sh --check      # resolve without downloading
#
# ENVIRONMENT
#   RAC_WIRE_COMPILER      explicit wire-compiler executable to use
#   RAC_WIRE_CACHE         cache root; default
#                          ${XDG_CACHE_HOME:-$HOME/.cache}/runanywhere/wire
#   RAC_WIRE_NO_DOWNLOAD=1 never download
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CHECKSUMS="${SCRIPT_DIR}/wire.sha256"

MODE="path"
NO_DOWNLOAD="${RAC_WIRE_NO_DOWNLOAD:-0}"
while [ $# -gt 0 ]; do
    case "$1" in
        --print-dir) MODE="dir"; shift ;;
        --print-path) MODE="path"; shift ;;
        --check)     NO_DOWNLOAD=1; shift ;;
        -h|--help)   sed -n '2,46p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "bootstrap_wire.sh: unknown flag: $1" >&2; exit 2 ;;
    esac
done

log() { echo "bootstrap_wire: $*" >&2; }
die() { echo "bootstrap_wire: error: $*" >&2; exit 1; }

emit() {
    case "${MODE}" in
        dir)  dirname "$1" ;;
        path) printf '%s\n' "$1" ;;
    esac
    exit 0
}

VERSIONS_FILE="${REPO_ROOT}/core/VERSIONS"
[ -f "${VERSIONS_FILE}" ] || die "core/VERSIONS not found at ${VERSIONS_FILE}"
PIN="$(grep -E '^WIRE_VERSION=' "${VERSIONS_FILE}" | head -1 | cut -d= -f2 | tr -d '[:space:]')"
[ -n "${PIN}" ] || die "core/VERSIONS does not define WIRE_VERSION"

# --- 1. explicit override / already on PATH ---------------------------------
if [ -n "${RAC_WIRE_COMPILER:-}" ]; then
    [ -x "${RAC_WIRE_COMPILER}" ] || die "RAC_WIRE_COMPILER=${RAC_WIRE_COMPILER} is not executable"
    emit "${RAC_WIRE_COMPILER}"
fi
if command -v wire-compiler >/dev/null 2>&1; then
    emit "$(command -v wire-compiler)"
fi

# --- 2. the cache ------------------------------------------------------------
CACHE_ROOT="${RAC_WIRE_CACHE:-${XDG_CACHE_HOME:-${HOME}/.cache}/runanywhere/wire}"
INSTALL_DIR="${CACHE_ROOT}/${PIN}"
JAR="${INSTALL_DIR}/wire-compiler.jar"
SHIM="${INSTALL_DIR}/bin/wire-compiler"
if [ -f "${JAR}" ] && [ -x "${SHIM}" ]; then
    emit "${SHIM}"
fi

if [ "${NO_DOWNLOAD}" = "1" ]; then
    die "wire-compiler ${PIN} is not installed and downloading is disabled.
       Expected ${SHIM}, a wire-compiler on PATH, or \$RAC_WIRE_COMPILER."
fi

command -v java >/dev/null 2>&1 || die "java is required to run wire-compiler (install a JDK ${JAVA_VERSION:-17}+)"

# --- 3. download -------------------------------------------------------------
JAR_NAME="wire-compiler-${PIN}-jar-with-dependencies.jar"
URL="https://repo1.maven.org/maven2/com/squareup/wire/wire-compiler/${PIN}/${JAR_NAME}"

[ -f "${CHECKSUMS}" ] || die "missing ${CHECKSUMS}"
EXPECTED="$(awk -v f="${JAR_NAME}" '$2 == f {print $1}' "${CHECKSUMS}" | head -1)"
if [ -z "${EXPECTED}" ]; then
    die "no sha256 recorded for ${JAR_NAME} in ${CHECKSUMS#"${REPO_ROOT}/"}.
       WIRE_VERSION was bumped to ${PIN} without refreshing the checksum; see
       the header of that file. Refusing to install an unverified compiler."
fi

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then openssl dgst -sha256 "$1" | awk '{print $NF}'
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"
    else return 1
    fi
}

# Staged inside the cache root, not $TMPDIR: publishing is a rename, and on Git
# Bash for Windows $TMPDIR and $HOME are routinely different volumes, where
# MSYS's rename() answers EACCES instead of EXDEV and coreutils `mv` therefore
# never falls back to a copy. Same filesystem, always.
mkdir -p "${CACHE_ROOT}"
TMP="$(mktemp -d "${CACHE_ROOT}/.tmp-XXXXXX")"
trap 'rm -rf "${TMP}"' EXIT

log "downloading ${URL}"
# Bounded: this runs inside Gradle builds and CMake configures where a stalled
# connection would otherwise hang the build with no output at all. The fat JAR
# is ~30 MB, so the ceiling is higher than protoc's.
if command -v curl >/dev/null 2>&1; then
    curl --fail --silent --show-error --location \
        --connect-timeout 20 --max-time 600 --speed-time 60 --speed-limit 1024 \
        --retry 5 --retry-all-errors --retry-delay 2 --retry-max-time 900 \
        -o "${TMP}/${JAR_NAME}" "${URL}" || die "download failed or timed out: ${URL}"
elif command -v wget >/dev/null 2>&1; then
    wget --quiet --tries=5 --timeout=60 --waitretry=2 \
        -O "${TMP}/${JAR_NAME}" "${URL}" || die "download failed or timed out: ${URL}"
else
    die "neither curl nor wget is available to fetch ${URL}"
fi

ACTUAL="$(sha256_of "${TMP}/${JAR_NAME}")" || die "no sha256 tool available"
if [ "${ACTUAL}" != "${EXPECTED}" ]; then
    die "checksum mismatch for ${JAR_NAME}
       expected ${EXPECTED}
       actual   ${ACTUAL}"
fi
log "sha256 ok (${EXPECTED})"

mkdir -p "${INSTALL_DIR}/bin"
mv "${TMP}/${JAR_NAME}" "${JAR}.tmp"
mv "${JAR}.tmp" "${JAR}"
# The wrapper resolves the JAR next to itself, so a moved cache still works.
# shellcheck disable=SC2016
printf '#!/usr/bin/env bash\nexec java -jar "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/wire-compiler.jar" "$@"\n' > "${SHIM}"
chmod +x "${SHIM}"

log "installed wire-compiler ${PIN} -> ${SHIM}"
emit "${SHIM}"
