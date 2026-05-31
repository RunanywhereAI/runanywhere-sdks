#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# check_flutter_centralization.sh
#
# Tier 4 / PR #494 T4.4 — Flutter dependency centralization linter.
#
# Reads the `dependencies:` / `dev_dependencies:` blocks of
# sdk/runanywhere-flutter/packages/runanywhere/pubspec.yaml (the workspace
# source of truth for shared third-party deps — see pass2-syn-121) and
# warns when any other pubspec.yaml in the repo hardcodes a `^x.y.z` (or
# `x.y.z`) version that differs from the source-of-truth value for the
# same dependency name.
#
# Backwards-compat fallback: if the workspace pubspec ever reintroduces a
# `melos.dependencies:` block, parse_registry() will pick it up first.
#
# This is a CONVENTION LINTER. It is intentionally a warning-only / soft
# failure tool by default: per-package pinning may be legitimate (e.g. for
# the example app which is outside the pub workspace and cannot use `any`
# to defer to workspace resolution). The validator only fails when a
# version DIFFERS from the central registry, not when it merely duplicates
# the same string.
#
# Usage:
#   scripts/validation/gates/check_flutter_centralization.sh                # warn
#   FLUTTER_CENTRALIZATION_STRICT=1 ... check_flutter_centralization.sh  # fail on warn
#
# Scope:
#   - Walks sdk/runanywhere-flutter/**/pubspec.yaml and
#     examples/flutter/**/pubspec.yaml
#   - Skips the workspace root pubspec itself (that IS the source of truth)
#   - Ignores SDK-bundled deps (`sdk: flutter`) and path/git deps

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
WORKSPACE_ROOT_PUBSPEC="${REPO_ROOT}/sdk/runanywhere-flutter/pubspec.yaml"
# Source-of-truth package (per pass2-syn-121: melos.dependencies block was
# removed because Pub does not read it; the `packages/runanywhere` pubspec
# is now the authoritative pin set for shared third-party deps).
SOURCE_OF_TRUTH_PUBSPEC="${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere/pubspec.yaml"

if [[ ! -f "${WORKSPACE_ROOT_PUBSPEC}" ]]; then
  echo "error: workspace root pubspec not found at ${WORKSPACE_ROOT_PUBSPEC}" >&2
  exit 2
fi

STRICT="${FLUTTER_CENTRALIZATION_STRICT:-0}"
WARN_COUNT=0
DRIFT_COUNT=0

# --- Parse workspace registry (melos.dependencies block, then fallback) ---
# Extract the registry into a `name => version` map serialized as `name<TAB>version`
# lines, e.g.:
#   ffi    ^2.1.0
#   protoc_plugin    25.0.0
#
# AWK state machine — locked to the YAML indentation that pubspec.yaml uses.
parse_registry() {
  awk '
    BEGIN { in_melos = 0; in_deps = 0 }
    # Top-level `melos:` key — must start at column 0 (no leading whitespace).
    /^melos:[[:space:]]*$/ { in_melos = 1; in_deps = 0; next }
    # Any other top-level key ends the melos block.
    /^[a-zA-Z_]/ { in_melos = 0; in_deps = 0; next }
    # `  dependencies:` (exactly 2 spaces) inside the melos block.
    in_melos && /^  dependencies:[[:space:]]*$/ { in_deps = 1; next }
    # Any other `  <key>:` (2-space indent) inside melos ends the deps block.
    in_melos && /^  [a-zA-Z_]/ { in_deps = 0 }
    # Match `    name: version` lines (4-space indent) inside deps block.
    in_deps && /^    [a-zA-Z_][a-zA-Z0-9_]*:[[:space:]]*[^[:space:]#]/ {
      line = $0
      # Strip leading 4 spaces.
      sub(/^    /, "", line)
      # Split on the first colon.
      colon = index(line, ":")
      if (colon == 0) next
      name = substr(line, 1, colon - 1)
      version = substr(line, colon + 1)
      # Trim whitespace.
      sub(/^[[:space:]]+/, "", version)
      sub(/[[:space:]]+$/, "", version)
      # Strip trailing inline comment.
      sub(/[[:space:]]*#.*$/, "", version)
      # Skip empty values (a block-style sub-map would land here).
      if (version == "") next
      printf "%s\t%s\n", name, version
    }
  ' "$1"
}

# Extract `^x.y.z` / `x.y.z` pins from a package pubspec's top-level
# `dependencies:` / `dev_dependencies:` blocks. Returns `name<TAB>version`.
# Used as the source-of-truth registry when the (deprecated)
# `melos.dependencies:` block is absent — see pass2-syn-121.
parse_package_registry() {
  awk '
    BEGIN { in_deps = 0 }
    /^dependencies:[[:space:]]*$/ { in_deps = 1; next }
    /^dev_dependencies:[[:space:]]*$/ { in_deps = 1; next }
    /^[a-zA-Z_]/ { in_deps = 0; next }
    in_deps && /^  [a-zA-Z_][a-zA-Z0-9_]*:[[:space:]]*\^?[0-9]+\.[0-9]+\.[0-9]+/ {
      line = $0
      sub(/^  /, "", line)
      colon = index(line, ":")
      if (colon == 0) next
      name = substr(line, 1, colon - 1)
      version = substr(line, colon + 1)
      sub(/^[[:space:]]+/, "", version)
      sub(/[[:space:]]+$/, "", version)
      sub(/[[:space:]]*#.*$/, "", version)
      if (version == "") next
      printf "%s\t%s\n", name, version
    }
  ' "$1"
}

REGISTRY_TSV="$(parse_registry "${WORKSPACE_ROOT_PUBSPEC}")"
REGISTRY_SOURCE="workspace-root melos.dependencies"
if [[ -z "${REGISTRY_TSV}" ]]; then
  # pass2-syn-121: the workspace `melos.dependencies` block was removed
  # because Pub does not consume it. Fall back to the
  # packages/runanywhere pubspec as the source of truth.
  if [[ ! -f "${SOURCE_OF_TRUTH_PUBSPEC}" ]]; then
    echo "error: no centralized dependencies parsed from melos.dependencies block in" >&2
    echo "       ${WORKSPACE_ROOT_PUBSPEC}" >&2
    echo "       and source-of-truth package pubspec not found at" >&2
    echo "       ${SOURCE_OF_TRUTH_PUBSPEC}" >&2
    exit 2
  fi
  REGISTRY_TSV="$(parse_package_registry "${SOURCE_OF_TRUTH_PUBSPEC}")"
  REGISTRY_SOURCE="packages/runanywhere/pubspec.yaml"
fi

if [[ -z "${REGISTRY_TSV}" ]]; then
  echo "error: source-of-truth pubspec parsed empty registry:" >&2
  echo "       ${SOURCE_OF_TRUTH_PUBSPEC}" >&2
  exit 2
fi

REGISTRY_COUNT="$(printf "%s\n" "${REGISTRY_TSV}" | wc -l | tr -d ' ')"
printf "✓ Loaded %s centralized dependency entries from %s.\n" "${REGISTRY_COUNT}" "${REGISTRY_SOURCE}"

# Build a lookup function over REGISTRY_TSV.
registry_version_for() {
  local dep_name="$1"
  printf "%s\n" "${REGISTRY_TSV}" | awk -F '\t' -v n="${dep_name}" '$1 == n { print $2; exit }'
}

# --- Walk target pubspec files ---------------------------------------------
PUBSPEC_TARGETS=()
while IFS= read -r -d '' f; do
  PUBSPEC_TARGETS+=("$f")
done < <(find \
  "${REPO_ROOT}/sdk/runanywhere-flutter" \
  "${REPO_ROOT}/examples/flutter" \
  -type f -name pubspec.yaml -print0 2>/dev/null)

if [[ "${#PUBSPEC_TARGETS[@]}" -eq 0 ]]; then
  echo "warning: no pubspec.yaml files found under sdk/runanywhere-flutter/ or examples/flutter/" >&2
fi

# Extract `^x.y.z` / `x.y.z` pins from a package pubspec, restricted to
# dependencies: / dev_dependencies: blocks. Returns lines of
# `name<TAB>version<TAB>line_no`.
scan_package_pins() {
  awk '
    BEGIN { in_deps = 0 }
    # Top-level deps blocks.
    /^dependencies:[[:space:]]*$/ { in_deps = 1; next }
    /^dev_dependencies:[[:space:]]*$/ { in_deps = 1; next }
    # Any other top-level key ends the block.
    /^[a-zA-Z_]/ { in_deps = 0; next }
    # Match `  name: ^x.y.z` or `  name: x.y.z` (exact 2-space indent).
    in_deps && /^  [a-zA-Z_][a-zA-Z0-9_]*:[[:space:]]*\^?[0-9]+\.[0-9]+\.[0-9]+/ {
      line = $0
      sub(/^  /, "", line)
      colon = index(line, ":")
      if (colon == 0) next
      name = substr(line, 1, colon - 1)
      version = substr(line, colon + 1)
      sub(/^[[:space:]]+/, "", version)
      sub(/[[:space:]]+$/, "", version)
      sub(/[[:space:]]*#.*$/, "", version)
      printf "%s\t%s\t%s\n", name, version, NR
    }
  ' "$1"
}

for pubspec in "${PUBSPEC_TARGETS[@]}"; do
  rel="${pubspec#${REPO_ROOT}/}"

  # Skip the source of truth itself (both the workspace root and the
  # packages/runanywhere pubspec when the latter acts as the registry).
  if [[ "${pubspec}" == "${WORKSPACE_ROOT_PUBSPEC}" ]]; then
    continue
  fi
  if [[ "${REGISTRY_SOURCE}" == "packages/runanywhere/pubspec.yaml" \
        && "${pubspec}" == "${SOURCE_OF_TRUTH_PUBSPEC}" ]]; then
    continue
  fi

  pins="$(scan_package_pins "${pubspec}")"
  [[ -z "${pins}" ]] && continue

  while IFS=$'\t' read -r dep_name dep_version line_no; do
    [[ -z "${dep_name}" ]] && continue

    central="$(registry_version_for "${dep_name}")"
    if [[ -z "${central}" ]]; then
      # Not in the registry — out of scope, ignore.
      continue
    fi

    if [[ "${dep_version}" == "${central}" ]]; then
      # Allowed duplicate (same version as registry). No-op.
      continue
    fi

    # DRIFT: a centrally-registered dep is pinned to a different version.
    printf "::warning file=%s,line=%s::%s pinned to %s but central registry says %s\n" \
      "${rel}" "${line_no}" "${dep_name}" "${dep_version}" "${central}" >&2
    DRIFT_COUNT=$((DRIFT_COUNT + 1))
    WARN_COUNT=$((WARN_COUNT + 1))
  done <<< "${pins}"
done

printf "\n"
printf "Flutter dependency centralization report:\n"
printf "  Central registry entries: %s\n" "${REGISTRY_COUNT}"
printf "  Drift warnings:           %s\n" "${DRIFT_COUNT}"

if [[ "${DRIFT_COUNT}" -eq 0 ]]; then
  printf "✓ All centrally-registered deps match the workspace registry.\n"
  exit 0
fi

if [[ "${STRICT}" == "1" ]]; then
  printf "✗ Drift detected and FLUTTER_CENTRALIZATION_STRICT=1 — failing.\n" >&2
  exit 1
fi

printf "Set FLUTTER_CENTRALIZATION_STRICT=1 to treat drift as a failure.\n"
exit 0
