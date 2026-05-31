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
#   scripts/validation/commons/sync_rac_api_exports.sh           # append new symbols
#   scripts/validation/commons/sync_rac_api_exports.sh --check   # alias for
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
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

if [[ "${MODE}" == "check" ]]; then
    exec "${SCRIPT_DIR}/check_rac_api_exports.sh" --strict
fi

COMMONS_INCLUDE="${REPO_ROOT}/sdk/runanywhere-commons/include"
EXPORTS_DIR="${REPO_ROOT}/sdk/runanywhere-commons/exports"
EXPORTS_FILE="${EXPORTS_DIR}/RACommons.exports"
RAG_EXPORTS_FILE="${EXPORTS_DIR}/RACommons.rag.exports"

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
# pass3-syn-080: RACommons.rag.exports is the only remaining sibling
# (RACommons.onnx_embeddings.exports and RACommons.whisperkit_coreml.exports
# were deleted by pass3-syn-002 when their decls were folded into the main
# exports list). The list still iterates so this stays forward-compatible
# if a new sibling file is added.
SIBLING_EXPORTS=()
for sibling in "${RAG_EXPORTS_FILE}"; do
    if [[ -f "${sibling}" ]]; then
        SIBLING_EXPORTS+=("${sibling}")
    fi
done

python3 - "${COMMONS_INCLUDE}" "${EXPORTS_FILE}" "${RAG_EXPORTS_FILE}" "${SIBLING_EXPORTS[@]}" <<'PYEOF'
import os
import re
import sys
from datetime import datetime, timezone

include_root = sys.argv[1]
exports_path = sys.argv[2]
rag_exports_path = sys.argv[3]
sibling_paths = sys.argv[4:]

# pass2-syn-002: the stale rac_vad_{start,stop,reset} decls have been
# deleted from the headers, and backend-conditional symbols now live in
# sibling exports files (RACommons.rag.exports etc.) which are read into
# the `exported` set below. The EXCLUDE policy is therefore empty by
# default — every RAC_API decl should either land in RACommons.exports or
# in one of the backend sibling files. Add entries here only if a new
# stale/unimplemented decl needs temporary suppression while it's being
# removed.
EXCLUDE = set()

# pass3-syn-080: path-aware routing policy. Each RAC_API decl is routed to
# a target exports file based on the header path it was declared in. The
# default route is the main RACommons.exports list (the unconditional
# Apple `-exported_symbols_list`). Backend-conditional headers route to
# their sibling .exports file, which CMake appends only when the matching
# backend flag is ON.
#
# Add a new (path_marker, target_path, label) tuple here when a new
# backend-conditional sibling file is introduced. The first marker that
# is a substring of the header path wins; main is used as the fallback.
ROUTING_RULES = [
    ("/features/rag/", rag_exports_path, "RACommons.rag.exports"),
]

def route_for_path(header_path):
    """Return (target_exports_path, label) for the given header path."""
    norm = header_path.replace(os.sep, "/")
    for marker, target, label in ROUTING_RULES:
        if marker in norm:
            return target, label
    return exports_path, "RACommons.exports"

# Collect currently exported symbols from the main file PLUS every
# sibling backend-conditional file.
exported = set()
for path in (exports_path, *sibling_paths):
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line.startswith('_rac_'):
                exported.add(line[1:])

# Walk headers and collect RAC_API-decorated function decls along with the
# header path they were found in (used by route_for_path to pick a target
# exports file).
decl_to_path = {}
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
                # First declaration wins for routing (headers should not
                # re-declare a RAC_API symbol across paths).
                decl_to_path.setdefault(name, path)

decl_names = set(decl_to_path.keys())
new_symbols_all = sorted((decl_names - exported) - EXCLUDE)

if not new_symbols_all:
    print(f"OK: no new RAC_API symbols to add ({len(decl_names)} decls, "
          f"{len(exported)} exported, {len(EXCLUDE)} excluded by policy).")
    sys.exit(0)

# Partition new symbols by target exports file via route_for_path.
buckets = {}  # target_path -> (label, [names])
for name in new_symbols_all:
    target, label = route_for_path(decl_to_path[name])
    if target not in buckets:
        buckets[target] = (label, [])
    buckets[target][1].append(name)

ts = datetime.now(timezone.utc).strftime('%Y-%m-%d')
total_appended = 0
for target_path, (label, names) in buckets.items():
    if not names:
        continue
    if not os.path.exists(target_path):
        print(f"ERROR: target exports file not found: {target_path}", file=sys.stderr)
        sys.exit(1)
    header = [
        "",
        "# ============================================================================",
        f"# AUTO-SYNC ({ts}): symbols appended by sync_rac_api_exports.sh.",
        "# Net-new RAC_API-decorated decls discovered in the commons headers and",
        "# not already covered by an earlier curated section. Routing rules live",
        f"# in scripts/validation/commons/sync_rac_api_exports.sh (ROUTING_RULES).",
        f"# Added {len(names)} symbols to {label}, sorted alphabetically.",
        "# ============================================================================",
    ]
    with open(target_path, 'a') as f:
        for line in header:
            f.write(line + "\n")
        for name in names:
            f.write(f"_{name}\n")
    print(f"Appended {len(names)} symbol(s) to {target_path}")
    for name in names:
        print(f"  + _{name}  ({label})")
    total_appended += len(names)

print(f"Total: {total_appended} symbol(s) across {len(buckets)} file(s).")
PYEOF
