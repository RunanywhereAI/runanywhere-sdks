#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# check_generated_filenames.sh — assert no two generated files differ only in
# letter case.
#
# WHAT THIS USED TO BE, AND WHY IT CHANGED
#   It compared `git ls-files` against the filesystem, case-exactly, for the
#   three generated trees that were still committed. The hazard was a stale
#   committed name: wire-compiler 5.x emits `LoraState.kt` while `LoRAState.kt`
#   stayed in the index, and on macOS/Windows (case-insensitive) `git status`
#   reports that tree clean while on Linux the same run reports six deletions
#   plus six untracked files. The IDL gate runs on macOS, so it could not see it.
#
#   No generated file is committed any more, so there is no index side left to
#   compare against and that check can only be vacuous.
#
# WHAT IT CHECKS NOW
#   The other half of the same hazard, which de-committing does NOT remove: two
#   generated files whose names differ only in case, in the same directory. On a
#   case-insensitive filesystem the second write silently clobbers the first, so
#   the tree that compiles on the developer's Mac has one file where Linux CI
#   has two — and the missing one is a type somebody imports. Comparing each
#   directory's names against their lowercase forms catches that without needing
#   git, on every filesystem.
#
# Usage:
#   ./idl/codegen/check_generated_filenames.sh     # run after generate_all.sh
set -euo pipefail

export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
MANIFEST="${SCRIPT_DIR}/generated_trees.txt"
cd "${REPO_ROOT}"

[ -f "${MANIFEST}" ] || { echo "check_generated_filenames.sh: missing ${MANIFEST}" >&2; exit 2; }

# Every declared output directory. `built` (proto-ts/dist) is included when it
# happens to exist — tsc derives its names from src/, so a collision there is a
# collision here too.
TREES=()
while IFS=$'\t' read -r kind lang path minfiles note; do
    case "${kind}" in tree|built) ;; *) continue ;; esac
    [ -n "${path:-}" ] || continue
    [ -d "${path}" ] && TREES+=("${path}")
done < "${MANIFEST}"

if [ "${#TREES[@]}" -eq 0 ]; then
    echo "check_generated_filenames.sh: no generated tree exists yet — run generate_all.sh first" >&2
    exit 1
fi

COLLISIONS="$(
    find "${TREES[@]}" -type f -print \
        | awk -F/ '{
              name = $NF
              dir  = substr($0, 1, length($0) - length(name) - 1)
              lower = tolower(name)
              key = dir "/" lower
              if (key in seen && seen[key] != name) {
                  print dir "/  " seen[key] "  vs  " name
              }
              seen[key] = name
          }' \
        | LC_ALL=C sort -u
)"

if [ -z "${COLLISIONS}" ]; then
    echo "✓ generated filenames are unique case-insensitively (${#TREES[@]} trees)."
    exit 0
fi

echo "::error::Generated filenames collide when compared case-insensitively." >&2
echo "" >&2
printf '%s\n' "${COLLISIONS}" | sed 's/^/  /' >&2
echo "" >&2
echo "On macOS/Windows one of each pair silently overwrites the other, so the" >&2
echo "tree that compiles locally is missing a file that Linux CI will have." >&2
echo "Fix the generator (or the .proto names) so the outputs differ by more" >&2
echo "than letter case." >&2
exit 1
