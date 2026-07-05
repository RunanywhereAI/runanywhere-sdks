#!/usr/bin/env bash
#
# check_typescript_centralization.sh
#
# Fails CI when any TypeScript/Web/RN package.json drifts from the centralized
# version pins declared in scripts/lib/versions.json (enforced via scripts/lib/syncpack.json).
#
# Usage:
#   scripts/validation/gates/check_typescript_centralization.sh
#
# Environment:
#   SYNCPACK_VERSION   syncpack version to invoke via npx (default: 13.0.4).
#                      Pinned to keep CI deterministic; bump intentionally.
#   CI                 Treated as truthy when set to a non-empty, non-"0", non-"false"
#                      value. Suppresses interactive progress output from npx.
#
# Exit codes:
#   0  All pinned dependencies match scripts/lib/versions.json.
#   1  At least one mismatch detected.
#   2  Tooling unavailable (npx missing) or config files missing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

SYNCPACK_VERSION="${SYNCPACK_VERSION:-13.0.4}"
SYNCPACKRC="${REPO_ROOT}/scripts/lib/syncpack.json"
VERSIONS_JSON="${REPO_ROOT}/scripts/lib/versions.json"

if [[ ! -f "${SYNCPACKRC}" ]]; then
  printf "::error::Missing syncpack config (%s)\n" "${SYNCPACKRC}" >&2
  exit 2
fi

if [[ ! -f "${VERSIONS_JSON}" ]]; then
  printf "::error::Missing scripts/lib/versions.json (%s)\n" "${VERSIONS_JSON}" >&2
  exit 2
fi

if ! command -v npx >/dev/null 2>&1; then
  printf "::error::npx not found on PATH. Install Node.js >= 18 to run this check.\n" >&2
  exit 2
fi

cd "${REPO_ROOT}"

npx_flags=("--yes")
case "${CI:-}" in
  ""|0|false)
    ;;
  *)
    npx_flags+=("--no-progress")
    ;;
esac

printf "Checking TypeScript/Web/RN version centralization...\n"
printf "  syncpack:           %s\n" "${SYNCPACK_VERSION}"
printf "  config:             scripts/lib/syncpack.json\n"
printf "  centralized pins:   scripts/lib/versions.json\n\n"

set +e
npx "${npx_flags[@]}" "syncpack@${SYNCPACK_VERSION}" list-mismatches --config "${SYNCPACKRC}"
status=$?
set -e

if [[ "${status}" -ne 0 ]]; then
  printf "\n" >&2
  printf "::error::syncpack detected version mismatches against scripts/lib/versions.json.\n" >&2
  printf "Fix locally with:\n" >&2
  printf "  npx syncpack@%s fix-mismatches --config %s\n" "${SYNCPACK_VERSION}" "${SYNCPACKRC}" >&2
  printf "Then commit the updated package.json files.\n" >&2
  exit 1
fi

printf "\nAll pinned dependencies are aligned with scripts/lib/versions.json.\n"
