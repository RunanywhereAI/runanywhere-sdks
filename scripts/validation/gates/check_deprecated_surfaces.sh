#!/usr/bin/env bash
# check_deprecated_surfaces.sh
#
# Scans SDK source directories for patterns that indicate regression toward
# hand-written DTOs, JSON bridges, string-based enums, or deprecated facades.
#
# Exits 0 when all detected violations are present in the allowlist.
# Exits 1 when NEW (non-allowlisted) violations are found.
#
# Can run standalone or as a step within run_global_source_checks.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
ALLOWLIST_FILE="${SCRIPT_DIR}/deprecated_surface_allowlist.txt"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Load the allowlist into a newline-separated string for grep-based lookup.
# Compatible with bash 3.x (no associative arrays).
ALLOWLIST_ENTRIES=""
load_allowlist() {
  if [[ ! -f "${ALLOWLIST_FILE}" ]]; then
    printf "WARNING: allowlist not found at %s -- treating all hits as violations\n" "${ALLOWLIST_FILE}" >&2
    return
  fi
  while IFS= read -r line; do
    # Skip blank lines and comments.
    [[ -z "${line}" || "${line}" == \#* ]] && continue
    # Trim trailing whitespace.
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "${line}" ]] && continue
    if [[ "${line}" != *"|"* ]]; then
      printf "ERROR: allowlist entries must use path|category: %s\n" "${line}" >&2
      return 1
    fi
    if [[ -z "${ALLOWLIST_ENTRIES}" ]]; then
      ALLOWLIST_ENTRIES="${line}"
    else
      ALLOWLIST_ENTRIES="${ALLOWLIST_ENTRIES}
${line}"
    fi
  done < "${ALLOWLIST_FILE}"
}

is_allowed() {
  local path="$1"
  local category="$2"
  if [[ -z "${ALLOWLIST_ENTRIES}" ]]; then
    return 1
  fi
  printf "%s\n" "${ALLOWLIST_ENTRIES}" | grep -qxF "${path}|${category}"
}

# Counters and temp files for collecting results.
VIOLATIONS_FILE="$(mktemp)"
ALLOWLISTED_FILE="$(mktemp)"
trap 'rm -f "${VIOLATIONS_FILE}" "${ALLOWLISTED_FILE}"' EXIT

# Record a hit. $1 = relative path from repo root, $2 = category description.
record_hit() {
  local rel_path="$1"
  local category="$2"
  if is_allowed "${rel_path}" "${category}"; then
    printf "%s  (%s)\n" "${rel_path}" "${category}" >> "${ALLOWLISTED_FILE}"
  else
    printf "%s  (%s)\n" "${rel_path}" "${category}" >> "${VIOLATIONS_FILE}"
  fi
}

# Run a grep pattern across a directory and record hits.
# $1 = directory (relative to REPO_ROOT)
# $2 = grep extended-regex pattern
# $3 = file glob (passed to --include)
# $4 = category label
scan_grep() {
  local dir="$1" pattern="$2" glob="$3" category="$4"

  local search_dir="${REPO_ROOT}/${dir}"
  [[ -d "${search_dir}" ]] || return 0

  local hits
  hits=$(grep -rl --include="${glob}" -E "${pattern}" "${search_dir}" 2>/dev/null || true)
  local f
  for f in ${hits}; do
    local rel="${f#"${REPO_ROOT}/"}"
    record_hit "${rel}" "${category}"
  done
}

# Scan tracked files only. This is used for repo-wide retired names so local
# build trees, dependency caches, and ignored generated artifacts cannot turn a
# source-policy gate into a machine-state-dependent result.
scan_git_grep() {
  local pattern="$1" category="$2"
  shift 2

  local hits
  hits=$(git -C "${REPO_ROOT}" grep -l -I -E "${pattern}" -- "$@" 2>/dev/null || true)
  local rel
  for rel in ${hits}; do
    record_hit "${rel}" "${category}"
  done
}

# Find files by name pattern and record hits.
# $1 = directory (relative to REPO_ROOT)
# $2 = find -name pattern
# $3 = category label
# $4+ = optional extra find predicates (e.g. -not -path '*/build/*')
scan_find() {
  local dir="$1" name_pattern="$2" category="$3"
  shift 3

  local search_dir="${REPO_ROOT}/${dir}"
  [[ -d "${search_dir}" ]] || return 0

  while IFS= read -r f; do
    [[ -z "${f}" ]] && continue
    local rel="${f#"${REPO_ROOT}/"}"
    record_hit "${rel}" "${category}"
  done < <(find "${search_dir}" -name "${name_pattern}" "$@" 2>/dev/null)
}

# ---------------------------------------------------------------------------
# Exclusion filter: post-process grep results to remove unwanted paths.
# Since macOS grep does not support --exclude-dir reliably with -r,
# we use a wrapper that filters output lines.
# ---------------------------------------------------------------------------
scan_grep_filtered() {
  local dir="$1" pattern="$2" glob="$3" category="$4"
  shift 4
  # Remaining args are path-fragment exclusions (e.g. "/test/" "/build/")
  local exclusions=("$@")

  local search_dir="${REPO_ROOT}/${dir}"
  [[ -d "${search_dir}" ]] || return 0

  local hits
  hits=$(grep -rl --include="${glob}" -E "${pattern}" "${search_dir}" 2>/dev/null || true)
  local f
  for f in ${hits}; do
    local skip=0
    local excl
    for excl in "${exclusions[@]}"; do
      if [[ "${f}" == *"${excl}"* ]]; then
        skip=1
        break
      fi
    done
    [[ "${skip}" -eq 1 ]] && continue
    local rel="${f#"${REPO_ROOT}/"}"
    record_hit "${rel}" "${category}"
  done
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

load_allowlist

printf "Scanning for deprecated/DTO/JSON bridge surfaces...\n"

# =========================================================================
# 0. Canonical protobuf IDL
# =========================================================================

# Removed wire fields keep only numeric reservations. Do not reintroduce
# source-level compatibility fields that regenerate deprecated SDK members.
scan_grep "idl" \
  "deprecated[[:space:]]*=[[:space:]]*true" "*.proto" "proto:deprecated-declaration"

# =========================================================================
# 1. Kotlin SDK
# =========================================================================

# 1a. *Dto.kt or *DTO.kt files
scan_find "sdk/runanywhere-kotlin" "*Dto.kt" "kotlin:dto-file" \
  -not -path "*/build/*" -not -path "*/test/*"
scan_find "sdk/runanywhere-kotlin" "*DTO.kt" "kotlin:dto-file" \
  -not -path "*/build/*" -not -path "*/test/*"

# 1b. org.json.JSONObject usage in non-test SDK source
scan_grep_filtered "sdk/runanywhere-kotlin/src" \
  "org\.json\.JSON(Object|Array)" "*.kt" "kotlin:org-json-usage" \
  "/test/" "/tests/" "/__tests__/" "/build/"

# 1c. Hand-written JSON serialisation (toJson/fromJson/JsonObject) outside proto
scan_grep_filtered "sdk/runanywhere-kotlin/src" \
  "(toJson|fromJson|JsonObject)" "*.kt" "kotlin:json-serialisation" \
  "/test/" "/tests/" "/__tests__/" "/proto/" "/generated/" "/build/"

# 1d. First-party deprecated compatibility declarations. Wire-generated
# Message.newBuilder() overrides are tool-owned and intentionally excluded.
scan_grep_filtered "sdk/runanywhere-kotlin/src" \
  "@Deprecated" "*.kt" "kotlin:deprecated-declaration" \
  "/test/" "/tests/" "/generated/" "/build/"

# =========================================================================
# 2. Swift SDK
# =========================================================================

# 2a. Hand-written *Types.swift DTO files
scan_find "sdk/runanywhere-swift/Sources" "*Types.swift" "swift:types-dto-file" \
  -not -path "*/.build/*" -not -path "*/proto/*"

# 2b. JSONDecoder/JSONEncoder/JSONSerialization in bridge code
scan_grep_filtered "sdk/runanywhere-swift/Sources" \
  "(JSONDecoder|JSONEncoder|JSONSerialization)" "*.swift" "swift:json-bridge" \
  "/Tests/" "/.build/"

# 2c. Deprecated Swift compatibility declarations.
scan_grep_filtered "sdk/runanywhere-swift/Sources" \
  "@available\\([^)]*deprecated" "*.swift" "swift:deprecated-declaration" \
  "/Tests/" "/.build/"

# =========================================================================
# 3. Flutter SDK
# =========================================================================

# 3a. Vendored nlohmann/json.hpp
scan_find "sdk/runanywhere-flutter" "json.hpp" "flutter:vendored-nlohmann" \
  -path "*/nlohmann/*" -not -path "*/test/*" -not -path "*/tests/*" \
  -not -path "*/build/*" -not -path "*/.cxx/*"

# 3b. *_bridge.cpp or *_bridge.h files
scan_find "sdk/runanywhere-flutter/packages" "*_bridge.cpp" "flutter:json-bridge-cpp" \
  -not -path "*/test/*" -not -path "*/tests/*" -not -path "*/build/*" \
  -not -path "*/.cxx/*"
scan_find "sdk/runanywhere-flutter/packages" "*_bridge.h" "flutter:json-bridge-header" \
  -not -path "*/test/*" -not -path "*/tests/*" -not -path "*/build/*" \
  -not -path "*/.cxx/*"

# 3c. Deprecated Dart compatibility declarations.
scan_grep_filtered "sdk/runanywhere-flutter/packages" \
  "@Deprecated" "*.dart" "flutter:deprecated-declaration" \
  "/test/" "/tests/" "/build/" "/generated/"

# =========================================================================
# 4. React Native SDK
# =========================================================================

# 4a. Vendored nlohmann/json.hpp
scan_find "sdk/runanywhere-react-native" "json.hpp" "rn:vendored-nlohmann" \
  -path "*/nlohmann/*" -not -path "*/node_modules/*" -not -path "*/.cxx/*" -not -path "*/build/*"

# 4b. C++ bridge files using nlohmann/JSON
scan_grep_filtered "sdk/runanywhere-react-native/packages" \
  "(nlohmann|json\.hpp)" "*.cpp" "rn:cpp-json-bridge" \
  "/test/" "/tests/" "/__tests__/" "/node_modules/" "/.cxx/" "/build/"
scan_grep_filtered "sdk/runanywhere-react-native/packages" \
  "(jsonString|jsonEscape)" "*.cpp" "rn:cpp-json-bridge" \
  "/test/" "/tests/" "/__tests__/" "/node_modules/" "/.cxx/" "/build/"

# 4c. TypeScript files with JSON.parse/JSON.stringify (source only, not build artifacts)
scan_grep_filtered "sdk/runanywhere-react-native/packages" \
  "(JSON\.parse|JSON\.stringify)" "*.ts" "rn:ts-json-serialisation" \
  "/test/" "/tests/" "/__tests__/" "/node_modules/" "/build/" "/lib/" "/.cxx/"

# 4d. *Bridge.ts files that are JSON-based bridges
scan_find "sdk/runanywhere-react-native/packages" "*Bridge.ts" "rn:bridge-ts-file" \
  -not -path "*/test/*" -not -path "*/tests/*" -not -path "*/__tests__/*" \
  -not -path "*/node_modules/*" -not -path "*/build/*" -not -path "*/lib/*"

# 4e. Deprecated TypeScript compatibility declarations.
scan_grep_filtered "sdk/runanywhere-react-native/packages" \
  "@deprecated" "*.ts" "rn:deprecated-declaration" \
  "/test/" "/tests/" "/__tests__/" "/node_modules/" "/build/" "/lib/"

# =========================================================================
# 5. Web SDK
# =========================================================================

# 5a. JSON.parse/JSON.stringify in TypeScript source
scan_grep_filtered "sdk/runanywhere-web/packages" \
  "(JSON\.parse|JSON\.stringify)" "*.ts" "web:ts-json-serialisation" \
  "/test/" "/tests/" "/__tests__/" "/node_modules/" "/dist/" "/build/"

# 5b. Hand-written *Types.ts files (non-proto type definitions)
scan_find "sdk/runanywhere-web/packages" "*Types.ts" "web:hand-written-types-ts" \
  -not -path "*/test/*" -not -path "*/tests/*" -not -path "*/__tests__/*" \
  -not -path "*/node_modules/*" -not -path "*/dist/*" -not -path "*/build/*"

# 5c. Deprecated TypeScript compatibility declarations.
scan_grep_filtered "sdk/runanywhere-web/packages" \
  "@deprecated" "*.ts" "web:deprecated-declaration" \
  "/test/" "/tests/" "/__tests__/" "/node_modules/" "/dist/" "/build/"

# =========================================================================
# 6. C++ Public API (SDK-facing headers)
# =========================================================================

# 6a. Public headers declaring rac_*_json functions
scan_grep "sdk/runanywhere-commons/include" \
  "(RAC_API|RAC_LLAMACPP_API|RAC_ONNX_API).*_json" "*.h" "cpp:public-json-api"

# 6b. Public headers with config_json or out_json parameters (service vtable slots)
scan_grep "sdk/runanywhere-commons/include" \
  "(config_json|out_json|out_stats_json)" "*.h" "cpp:json-param-in-public-api"

# 6c. Deprecated C/C++ public declarations.
scan_grep "sdk/runanywhere-commons/include" \
  "(RAC_DEPRECATED|__attribute__\\(\\(deprecated|\\[\\[deprecated)" "*.h" "cpp:deprecated-declaration"

# 6d. Packaged header mirrors are public API too. A clean canonical header is
# insufficient if SwiftPM or an AAR still advertises a retired declaration.
scan_grep "sdk/runanywhere-swift/Sources/RunAnywhere/CRACommons/include" \
  "(RAC_DEPRECATED|__attribute__\\(\\(deprecated|\\[\\[deprecated)" "*.h" "swift-c:deprecated-declaration"
scan_grep "sdk/runanywhere-react-native/packages/core/android/src/main/jniLibs/include" \
  "(RAC_DEPRECATED|__attribute__\\(\\(deprecated|\\[\\[deprecated)" "*.h" "rn-c:deprecated-declaration"

# 6e. Retired compatibility surfaces that must never reappear under a neutral
# name or in one hand-maintained package mirror.
scan_git_grep \
  "enable_sentry_logging|SentryManager|SentryDestination|sentry_logging" \
  "all:retired-sentry-surface" "idl" "sdk"
scan_git_grep \
  "rac_device_identity_reset_cache_for_testing[[:space:]]*\\(" \
  "all:public-test-hook" "sdk"
scan_git_grep \
  "rac_extract_archive[[:space:]]*\\(" \
  "all:retired-archive-adapter-api" "sdk/runanywhere-commons/include" \
  "sdk/runanywhere-swift/Sources/RunAnywhere/CRACommons/include" \
  "sdk/runanywhere-react-native/packages/core/android/src/main/jniLibs/include"

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

printf "\n"
printf "=== Deprecated Surface Check Results ===\n\n"

ALLOWLISTED_COUNT=0
if [[ -s "${ALLOWLISTED_FILE}" ]]; then
  ALLOWLISTED_COUNT=$(wc -l < "${ALLOWLISTED_FILE}" | tr -d ' ')
  printf "Documented exceptions (%s entries):\n" "${ALLOWLISTED_COUNT}"
  while IFS= read -r entry; do
    printf "  [OK] %s\n" "${entry}"
  done < "${ALLOWLISTED_FILE}"
  printf "\n"
fi

VIOLATION_COUNT=0
if [[ -s "${VIOLATIONS_FILE}" ]]; then
  VIOLATION_COUNT=$(wc -l < "${VIOLATIONS_FILE}" | tr -d ' ')
  printf "NEW VIOLATIONS (%s entries) -- migrate them or document a narrowly scoped exception:\n" "${VIOLATION_COUNT}"
  while IFS= read -r entry; do
    printf "  [FAIL] %s\n" "${entry}"
  done < "${VIOLATIONS_FILE}"
  printf "\n"
  printf "Document unavoidable boundaries as path|category in:\n"
  printf "  %s\n" "${ALLOWLIST_FILE}"
  exit 1
fi

printf "All detected surfaces match documented exceptions. No new regressions.\n"
exit 0
