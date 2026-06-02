#!/usr/bin/env bash
#
# check_rac_api_exports.sh
#
# Drift gate: parse every RAC_API-decorated declaration under
# sdk/runanywhere-commons/include/rac/**/*.h, parse the curated exports list at
# sdk/runanywhere-commons/exports/RACommons.exports, and report any public
# RAC_API symbol missing from the exports list.
#
# Default behavior: prints a non-zero-exit report listing the drift but is
# advisory-only when invoked without `--strict`. Many of the currently
# "missing" symbols are candidates for RAC_API stripping (internalization)
# rather than additions to the exports list — that cleanup is a follow-up.
# Once internalization is done, the script should be
# wired as `--strict` into `run_commons_proto_checks.sh`.
#
# Usage:
#   check_rac_api_exports.sh           # report only, always exits 0 on drift
#   check_rac_api_exports.sh --strict  # exit 1 on drift (CI gate)
#
# To update: either add the new symbol to exports/RACommons.exports with the
# leading underscore (Apple linker convention) OR strip RAC_API from the
# declaration if the function is meant to be commons-internal.

set -euo pipefail

STRICT=0
for arg in "$@"; do
    case "$arg" in
        --strict) STRICT=1 ;;
        -h|--help)
            grep '^# ' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

COMMONS_INCLUDE="${REPO_ROOT}/sdk/runanywhere-commons/include"
EXPORTS_DIR="${REPO_ROOT}/sdk/runanywhere-commons/exports"
EXPORTS_FILE="${EXPORTS_DIR}/RACommons.exports"

if [[ ! -d "${COMMONS_INCLUDE}" ]]; then
    echo "ERROR: commons include tree not found at ${COMMONS_INCLUDE}" >&2
    exit 1
fi
if [[ ! -f "${EXPORTS_FILE}" ]]; then
    echo "ERROR: exports file not found at ${EXPORTS_FILE}" >&2
    exit 1
fi

# Backend-conditional sibling exports files are appended to
# the main list by CMake at configure time. Treat them as part of the
# canonical export surface for drift accounting so backend-conditional
# RAC_API decls don't show up as missing.
SIBLING_EXPORTS=()
for sibling in "${EXPORTS_DIR}/RACommons.rag.exports" \
               "${EXPORTS_DIR}/RACommons.onnx_embeddings.exports"; do
    if [[ -f "${sibling}" ]]; then
        SIBLING_EXPORTS+=("${sibling}")
    fi
done

set +e
python3 - "${COMMONS_INCLUDE}" "${EXPORTS_FILE}" "${STRICT}" "${SIBLING_EXPORTS[@]}" <<'PYEOF'
import os
import re
import sys

include_root = sys.argv[1]
exports_path = sys.argv[2]
strict = sys.argv[3] == '1'
sibling_paths = sys.argv[4:]

# Collect exported symbols from the main file plus all sibling
# backend-conditional exports files (RAG, ONNX embeddings). The Apple
# linker concatenates these at link time based on
# RAC_BACKEND_* flags; for drift accounting we treat all of them as
# part of the canonical exported surface.
exported = set()
for path in (exports_path, *sibling_paths):
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line.startswith('_rac_'):
                exported.add(line[1:])  # strip the leading underscore

# Walk headers and find RAC_API-decorated function decls
decl_names = set()
for root, _, files in os.walk(include_root):
    for fname in files:
        if not (fname.endswith('.h') or fname.endswith('.hpp')):
            continue
        path = os.path.join(root, fname)
        with open(path, errors='replace') as fh:
            content = fh.read()
        # Strip comments (block and line)
        content = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)
        content = re.sub(r'//.*$', '', content, flags=re.MULTILINE)
        for chunk in content.split('RAC_API')[1:]:
            m = re.search(r'([a-zA-Z_][a-zA-Z0-9_]*)\s*\(', chunk)
            if not m:
                continue
            name = m.group(1)
            if name.startswith('rac_'):
                decl_names.add(name)

missing = sorted(decl_names - exported)

if missing:
    print("RAC_API exports drift detected — the following RAC_API-decorated symbols")
    print(f"are declared in {include_root} but missing from {exports_path}:")
    print()
    for n in missing:
        print(f"  _{n}")
    print()
    print(f"Total: {len(missing)} missing (out of {len(decl_names)} RAC_API decls,")
    print(f"{len(exported)} exported).")
    print()
    print("Fix: either add `_<name>` to exports/RACommons.exports (Apple linker")
    print("convention) OR strip the RAC_API attribute from the declaration if it")
    print("is meant to be commons-internal.")
    if strict:
        sys.exit(1)
    else:
        print()
        print("NOTE: running in advisory mode (no --strict flag); exiting 0.")
        sys.exit(0)

print(f"OK: all {len(decl_names)} RAC_API-decorated decls are present in the")
print(f"exports list ({len(exported)} total exported symbols).")
PYEOF
PY_EXIT=$?
exit "${PY_EXIT}"
