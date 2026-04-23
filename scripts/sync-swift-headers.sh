#!/usr/bin/env bash
# =============================================================================
# sync-swift-headers.sh
# =============================================================================
# Sync the vendored Swift CRACommons header tree from the canonical commons
# header tree. The Swift package consumes commons via a `CRACommons` system-
# module target that expects a FLAT include directory (all headers at the same
# level, side-by-side), while the canonical commons tree is organised
# hierarchically under `rac/<subdir>/`.
#
# What this script does:
#   1. Walks every *.h file under the vendored directory.
#   2. Finds the canonical counterpart by basename under the commons tree.
#      (Ambiguous basenames are disambiguated by picking the candidate whose
#      byte size is closest to the currently vendored file.)
#   3. Copies canonical -> vendored, flattening any hierarchical include paths
#      of the form  `#include "rac/<subdir>/<name>.h"` to `#include "<name>.h"`
#      so the flat vendored layout still compiles under Clang.
#   4. Leaves Swift-only files (`CRACommons.h`, `module.modulemap`) untouched.
#
# Idempotent: running twice is a no-op.
#
# Usage:
#   scripts/sync-swift-headers.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CANONICAL_DIR="$REPO_ROOT/sdk/runanywhere-commons/include/rac"
VENDORED_DIR="$REPO_ROOT/sdk/runanywhere-swift/Sources/RunAnywhere/CRACommons/include"

if [[ ! -d "$CANONICAL_DIR" ]]; then
  echo "error: canonical header tree not found: $CANONICAL_DIR" >&2
  exit 1
fi
if [[ ! -d "$VENDORED_DIR" ]]; then
  echo "error: vendored header tree not found: $VENDORED_DIR" >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

total=0
updated=0
skipped=0

# Pick the canonical candidate whose byte size is closest to the vendored file.
# Keeps the sync deterministic when multiple headers share a basename
# (e.g. rac_events.h lives in both core/ and infrastructure/events/).
pick_canonical() {
  local vendored_file="$1"; shift
  local -a candidates=("$@")

  if [[ ${#candidates[@]} -eq 1 ]]; then
    printf '%s\n' "${candidates[0]}"
    return
  fi

  local vendored_size
  vendored_size=$(wc -c < "$vendored_file" | tr -d ' ')

  local best="" best_delta=-1
  local c c_size delta
  for c in "${candidates[@]}"; do
    c_size=$(wc -c < "$c" | tr -d ' ')
    delta=$(( c_size > vendored_size ? c_size - vendored_size : vendored_size - c_size ))
    if [[ $best_delta -lt 0 || $delta -lt $best_delta ]]; then
      best_delta=$delta
      best="$c"
    fi
  done
  printf '%s\n' "$best"
}

for vendored_file in "$VENDORED_DIR"/*.h; do
  [[ -e "$vendored_file" ]] || continue
  base="$(basename "$vendored_file")"

  # Swift-only umbrella and modulemap are not mirrored from commons.
  if [[ "$base" == "CRACommons.h" ]]; then
    continue
  fi

  # Find all canonical candidates by basename.
  # (Use a while-read loop for bash 3.2 compatibility on macOS.)
  candidates=()
  while IFS= read -r line; do
    candidates+=("$line")
  done < <(find "$CANONICAL_DIR" -type f -name "$base" | sort)

  if [[ ${#candidates[@]} -eq 0 ]]; then
    echo "  skip  $base (no canonical counterpart)"
    skipped=$((skipped + 1))
    continue
  fi

  canonical="$(pick_canonical "$vendored_file" "${candidates[@]}")"

  # Flatten hierarchical includes so the flat Swift tree resolves.
  staged="$tmp_dir/$base"
  sed -E 's|#include[[:space:]]+"rac/[^"]*/([^/"]+\.h)"|#include "\1"|g' \
      "$canonical" > "$staged"

  total=$((total + 1))
  if ! cmp -s "$staged" "$vendored_file"; then
    cp "$staged" "$vendored_file"
    updated=$((updated + 1))
  fi
done

echo "✓ headers synced ($updated updated, $((total - updated)) unchanged, $skipped skipped of $total vendored)"
