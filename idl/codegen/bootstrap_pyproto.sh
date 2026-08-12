#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# bootstrap_pyproto.sh — a python3 that can `import google.protobuf`
# =============================================================================
# WHY
#   protoc is only half of the codegen toolchain. The other half is a set of
#   Python drivers that read a descriptor set and emit derived code:
#
#     generate_cpp_defaults.py   -> core/include/rac/rac_defaults_generated.h
#     generate_defaults_pool.py  -> the RADefaultsPool constants for 7 targets
#     generate_*_convenience.py  -> the defaults()/validate() helpers
#
#   All of them `import google.protobuf`, which is a pip package, not stdlib.
#   That was tolerable while the C header was committed: the generators
#   soft-skipped with a warning and the tracked copy carried the build. Now that
#   nothing generated is tracked, a soft skip means a missing public header and
#   a build that fails much later with `rac/rac_defaults_generated.h: No such
#   file`. So the runtime has to be obtainable, not merely hoped for.
#
# WHAT IT DOES, cheapest first
#   1. $RAC_PYTHON, if it can import google.protobuf
#   2. python3 (then python) on PATH, if it can
#   3. a cached virtualenv from a previous run, if it can
#   4. create that virtualenv and pip-install the pinned protobuf + pyyaml
#
#   Step 4 is skipped when RAC_PY_NO_INSTALL=1, in which case a host without
#   the runtime is a hard error rather than a silent degradation.
#
#   pyyaml is installed alongside protobuf because the Swift modality-ABI
#   generator parses idl/codegen/swift-modality-abi.yaml; keeping one
#   environment for every driver avoids a second bootstrap for one generator.
#
# OUTPUT CONTRACT
#   stdout is ONE line: the absolute path of the interpreter. Diagnostics go to
#   stderr. Mirrors bootstrap_protoc.sh so callers treat them the same way.
#
# USAGE
#   idl/codegen/bootstrap_pyproto.sh            # path to a usable python
#   idl/codegen/bootstrap_pyproto.sh --check    # resolve without installing
#
# ENVIRONMENT
#   RAC_PYTHON          explicit interpreter (still import-checked)
#   RAC_PYTHON_CACHE    venv root; default
#                       ${XDG_CACHE_HOME:-$HOME/.cache}/runanywhere/pyproto
#   RAC_PY_NO_INSTALL=1 never create a venv or pip-install
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

NO_INSTALL="${RAC_PY_NO_INSTALL:-0}"
while [ $# -gt 0 ]; do
    case "$1" in
        --check)   NO_INSTALL=1; shift ;;
        -h|--help) sed -n '2,46p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "bootstrap_pyproto.sh: unknown flag: $1" >&2; exit 2 ;;
    esac
done

log() { echo "bootstrap_pyproto: $*" >&2; }
die() { echo "bootstrap_pyproto: error: $*" >&2; exit 1; }

VERSIONS_FILE="${REPO_ROOT}/core/VERSIONS"
PIN="$(grep -E '^PYTHON_PROTOBUF_VERSION=' "${VERSIONS_FILE}" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')"
PIN="${PIN:-6.33}"

# Both packages, because a venv that has protobuf but not pyyaml would satisfy
# the C/Kotlin path and then fail the Swift one — one probe, one answer.
usable() {
    [ -n "${1:-}" ] || return 1
    command -v "$1" >/dev/null 2>&1 || [ -x "$1" ] || return 1
    "$1" -c 'import google.protobuf, yaml' >/dev/null 2>&1
}

emit() { printf '%s\n' "$1"; exit 0; }

# --- 1. explicit override ----------------------------------------------------
if [ -n "${RAC_PYTHON:-}" ]; then
    usable "${RAC_PYTHON}" && emit "${RAC_PYTHON}"
    die "RAC_PYTHON=${RAC_PYTHON} cannot import google.protobuf + yaml"
fi

# --- 2. an interpreter already on PATH --------------------------------------
# `python` as well as `python3`: Windows installs and some minimal images ship
# only the unsuffixed name.
for candidate in python3 python; do
    if command -v "${candidate}" >/dev/null 2>&1; then
        RESOLVED="$(command -v "${candidate}")"
        usable "${RESOLVED}" && emit "${RESOLVED}"
    fi
done

# --- 3. the cached venv ------------------------------------------------------
CACHE_ROOT="${RAC_PYTHON_CACHE:-${XDG_CACHE_HOME:-${HOME}/.cache}/runanywhere/pyproto}"
VENV_DIR="${CACHE_ROOT}/${PIN}"
for candidate in "${VENV_DIR}/bin/python" "${VENV_DIR}/Scripts/python.exe"; do
    usable "${candidate}" && emit "${candidate}"
done

if [ "${NO_INSTALL}" = "1" ]; then
    die "no python with google.protobuf is available and installing is disabled
       (RAC_PY_NO_INSTALL/--check). Either pip install 'protobuf>=${PIN},<7' pyyaml
       into the interpreter on PATH, point RAC_PYTHON at one that has them, or
       run ${SCRIPT_DIR#"${REPO_ROOT}/"}/bootstrap_pyproto.sh"
fi

# --- 4. build the venv -------------------------------------------------------
BASE_PY=""
for candidate in python3 python; do
    if command -v "${candidate}" >/dev/null 2>&1; then
        BASE_PY="$(command -v "${candidate}")"
        break
    fi
done
[ -n "${BASE_PY}" ] || die "no python3 interpreter on PATH — IDL codegen requires Python 3"

log "creating ${VENV_DIR} with protobuf>=${PIN},<7 + pyyaml (base: ${BASE_PY})"
mkdir -p "${CACHE_ROOT}"
rm -rf "${VENV_DIR}.tmp"
if ! "${BASE_PY}" -m venv "${VENV_DIR}.tmp" >&2; then
    rm -rf "${VENV_DIR}.tmp"
    die "python3 -m venv failed. On Debian/Ubuntu install python3-venv, or
       pip install 'protobuf>=${PIN},<7' pyyaml into ${BASE_PY} yourself."
fi

VENV_PY=""
for candidate in "${VENV_DIR}.tmp/bin/python" "${VENV_DIR}.tmp/Scripts/python.exe"; do
    [ -x "${candidate}" ] && { VENV_PY="${candidate}"; break; }
done
[ -n "${VENV_PY}" ] || { rm -rf "${VENV_DIR}.tmp"; die "venv created but no interpreter found inside it"; }

if ! "${VENV_PY}" -m pip install --quiet --upgrade "protobuf>=${PIN},<7" pyyaml >&2; then
    rm -rf "${VENV_DIR}.tmp"
    die "pip install of protobuf/pyyaml failed (offline? proxy?). Install them
       into ${BASE_PY} manually, or set RAC_PYTHON to an interpreter that has them."
fi

# Publish atomically so an interrupted pip cannot leave a venv that imports
# python fine and google.protobuf not at all.
rm -rf "${VENV_DIR}"
mv "${VENV_DIR}.tmp" "${VENV_DIR}"

for candidate in "${VENV_DIR}/bin/python" "${VENV_DIR}/Scripts/python.exe"; do
    usable "${candidate}" && { log "ready: ${candidate}"; emit "${candidate}"; }
done

die "created ${VENV_DIR} but it still cannot import google.protobuf + yaml"
