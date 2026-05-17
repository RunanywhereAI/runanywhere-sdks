#!/usr/bin/env bash
#
# sync_rac_api_exports.sh
#
# Companion to check_rac_api_exports.sh. Regenerates the symbols
# section of sdk/runanywhere-commons/exports/RACommons.exports by
# parsing every RAC_API-decorated declaration under
# sdk/runanywhere-commons/include/rac/**/*.h and appending any newly
# discovered symbols to the curated exports list.
#
# Existing content (comment headers + previously-listed symbols) is
# preserved verbatim. Only NET-NEW symbols are appended under a new
# "AUTO-SYNC" section. The script never rewrites or reorders existing
# entries — running it multiple times is idempotent.
#
# Symbols that are deliberately excluded (backend-conditional entry
# points and stale decls) are listed in the EXCLUDE set below and are
# never appended. To exclude additional symbols, add them to that set.
#
# Usage:
#   scripts/validation/sync_rac_api_exports.sh           # append new symbols
#   scripts/validation/sync_rac_api_exports.sh --check   # alias for
#                                                       # check_rac_api_exports.sh --strict
#
# After running, re-run check_rac_api_exports.sh --strict to confirm
# drift is reduced to the deliberately-excluded set.

set -euo pipefail

MODE="sync"
for arg in "$@"; do
    case "$arg" in
        --check) MODE="check" ;;
        -h|--help)
            grep '^# ' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

if [[ "${MODE}" == "check" ]]; then
    exec "${SCRIPT_DIR}/check_rac_api_exports.sh" --strict
fi

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

# pass2-syn-002: collect sibling backend-conditional exports too so
# symbols listed there are not re-appended into the main file.
SIBLING_EXPORTS=()
for sibling in "${EXPORTS_DIR}/RACommons.rag.exports" \
               "${EXPORTS_DIR}/RACommons.onnx_embeddings.exports" \
               "${EXPORTS_DIR}/RACommons.whisperkit_coreml.exports"; do
    if [[ -f "${sibling}" ]]; then
        SIBLING_EXPORTS+=("${sibling}")
    fi
done

python3 - "${COMMONS_INCLUDE}" "${EXPORTS_FILE}" "${SIBLING_EXPORTS[@]}" <<'PYEOF'
import os
import re
import sys
from datetime import datetime, timezone

include_root = sys.argv[1]
exports_path = sys.argv[2]
sibling_paths = sys.argv[3:]

# pass2-syn-002: the stale rac_vad_{start,stop,reset} decls have been
# deleted from the headers, and backend-conditional symbols now live in
# sibling exports files (RACommons.rag.exports etc.) which are read into
# the `exported` set below. The EXCLUDE policy is therefore empty by
# default — every RAC_API decl should either land in RACommons.exports or
# in one of the backend sibling files. Add entries here only if a new
# stale/unimplemented decl needs temporary suppression while it's being
# removed.
EXCLUDE = set()

# Collect currently exported symbols from the main file PLUS every
# sibling backend-conditional file.
exported = set()
for path in (exports_path, *sibling_paths):
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line.startswith('_rac_'):
                exported.add(line[1:])

# Walk headers and collect RAC_API-decorated function decls
decl_names = set()
for root, _, files in os.walk(include_root):
    for fname in files:
        if not (fname.endswith('.h') or fname.endswith('.hpp')):
            continue
        path = os.path.join(root, fname)
        with open(path, errors='replace') as fh:
            content = fh.read()
        content = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)
        content = re.sub(r'//.*$', '', content, flags=re.MULTILINE)
        for chunk in content.split('RAC_API')[1:]:
            m = re.search(r'([a-zA-Z_][a-zA-Z0-9_]*)\s*\(', chunk)
            if not m:
                continue
            name = m.group(1)
            if name.startswith('rac_'):
                decl_names.add(name)

new_symbols = sorted((decl_names - exported) - EXCLUDE)

if not new_symbols:
    print(f"OK: no new RAC_API symbols to add ({len(decl_names)} decls, "
          f"{len(exported)} exported, {len(EXCLUDE)} excluded by policy).")
    sys.exit(0)

ts = datetime.now(timezone.utc).strftime('%Y-%m-%d')
header = [
    "",
    "# ============================================================================",
    f"# AUTO-SYNC ({ts}): symbols appended by sync_rac_api_exports.sh.",
    "# Net-new RAC_API-decorated decls discovered in the commons headers and",
    "# not already covered by an earlier curated section. Excluded set lives",
    f"# in scripts/validation/sync_rac_api_exports.sh (EXCLUDE).",
    f"# Added {len(new_symbols)} symbols, sorted alphabetically.",
    "# ============================================================================",
]

with open(exports_path, 'a') as f:
    for line in header:
        f.write(line + "\n")
    for name in new_symbols:
        f.write(f"_{name}\n")

print(f"Appended {len(new_symbols)} symbol(s) to {exports_path}")
for name in new_symbols:
    print(f"  + _{name}")
PYEOF
