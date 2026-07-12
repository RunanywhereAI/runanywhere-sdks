#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ORT_SCRIPT="${REPO_ROOT}/sdk/runanywhere-web/wasm/scripts/vendor-onnxruntime-wasm.sh"
SHERPA_SCRIPT="${REPO_ROOT}/sdk/runanywhere-web/wasm/scripts/vendor-sherpa-onnx-wasm.sh"

fail() {
  echo "[FAIL] WASM provenance contract: $*" >&2
  exit 1
}

read_assignment() {
  local file="$1"
  local name="$2"
  sed -nE "s/^${name}=\"([0-9]+)\"$/\\1/p" "${file}"
}

ORT_SCRIPT_SCHEMA="$(read_assignment "${ORT_SCRIPT}" RECIPE_SCHEMA)"
SHERPA_EXPECTED_ORT_SCHEMA="$(read_assignment "${SHERPA_SCRIPT}" ORT_RECIPE_SCHEMA)"
SHERPA_SCRIPT_SCHEMA="$(read_assignment "${SHERPA_SCRIPT}" SHERPA_RECIPE_SCHEMA)"

[[ "${ORT_SCRIPT_SCHEMA}" =~ ^[0-9]+$ ]] || fail "ORT RECIPE_SCHEMA must be numeric"
[[ "${SHERPA_EXPECTED_ORT_SCHEMA}" =~ ^[0-9]+$ ]] || fail "Sherpa ORT_RECIPE_SCHEMA must be numeric"
[[ "${SHERPA_SCRIPT_SCHEMA}" =~ ^[0-9]+$ ]] || fail "SHERPA_RECIPE_SCHEMA must be numeric"
[ "${ORT_SCRIPT_SCHEMA}" = "${SHERPA_EXPECTED_ORT_SCHEMA}" ] ||
  fail "Sherpa expects ORT schema ${SHERPA_EXPECTED_ORT_SCHEMA}, but ORT writes ${ORT_SCRIPT_SCHEMA}"
[ "${SHERPA_EXPECTED_ORT_SCHEMA}" != "${SHERPA_SCRIPT_SCHEMA}" ] ||
  fail "ORT and Sherpa recipe schemas must remain component-specific"

bash -n "${ORT_SCRIPT}" "${SHERPA_SCRIPT}"

# These checks intentionally match the literal variable references in the
# generated provenance metadata written by the vendor scripts.
# shellcheck disable=SC2016
grep -Fq 'recipe_schema=${RECIPE_SCHEMA}' "${ORT_SCRIPT}" ||
  fail "ORT vendor script does not validate/write its RECIPE_SCHEMA"
# shellcheck disable=SC2016
grep -Fq 'recipe_schema=${ORT_RECIPE_SCHEMA}' "${SHERPA_SCRIPT}" ||
  fail "Sherpa vendor script does not validate ORT with ORT_RECIPE_SCHEMA"
# shellcheck disable=SC2016
grep -Fq 'recipe_schema=${SHERPA_RECIPE_SCHEMA}' "${SHERPA_SCRIPT}" ||
  fail "Sherpa vendor script does not validate/write SHERPA_RECIPE_SCHEMA"

if grep -Eq '^RECIPE_SCHEMA=' "${SHERPA_SCRIPT}"; then
  fail "ambiguous RECIPE_SCHEMA assignment reintroduced in a vendor script"
fi

echo "[OK] WASM provenance schemas: ORT=${ORT_SCRIPT_SCHEMA}, Sherpa=${SHERPA_SCRIPT_SCHEMA}"
