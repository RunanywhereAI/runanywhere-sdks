#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${PROJECT_ROOT}/../../.." && pwd)"
STAGE_ROOT="${PROJECT_ROOT}/.vercel-stage"

cd "${PROJECT_ROOT}"

die() {
  echo "error: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

verify_output() {
  local output_root="${1:-dist}"
  local required_files=(
    index.html
    coi-serviceworker.js
    assets/racommons.js
    assets/racommons.wasm
    assets/racommons-llamacpp.js
    assets/racommons-llamacpp.wasm
    assets/racommons-llamacpp-webgpu.js
    assets/racommons-llamacpp-webgpu.wasm
    assets/racommons-onnx-sherpa.js
    assets/racommons-onnx-sherpa.wasm
  )
  local invalid_files=()
  local relative_path

  for relative_path in "${required_files[@]}"; do
    [[ -s "${output_root}/${relative_path}" ]] || invalid_files+=("${relative_path}")
  done

  if (( ${#invalid_files[@]} > 0 )); then
    echo "error: release output is missing required non-empty files:" >&2
    printf '  - %s\n' "${invalid_files[@]}" >&2
    exit 1
  fi

  echo "Verified ${#required_files[@]} release files in ${output_root}"
}

copy_to_stage() {
  local relative_path="$1"
  local source_path="${PROJECT_ROOT}/${relative_path}"
  local destination_path="${STAGE_ROOT}/${relative_path}"

  [[ -e "${source_path}" ]] || die "required release input is missing: ${relative_path}"
  mkdir -p "$(dirname "${destination_path}")"
  cp -R "${source_path}" "${destination_path}"
}

stage_prebuilt() {
  [[ -f .vercel/project.json ]] || die "this checkout is not linked to Vercel; run 'vercel link' first"

  rm -rf "${STAGE_ROOT}"
  mkdir -p "${STAGE_ROOT}"

  local relative_path
  for relative_path in \
    dist \
    .vercel/project.json; do
    copy_to_stage "${relative_path}"
  done

  node --input-type=module - "${PROJECT_ROOT}/vercel.json" "${STAGE_ROOT}/vercel.json" <<'NODE'
import fs from 'node:fs';

const sourcePath = process.argv[2];
const destinationPath = process.argv[3];
const config = JSON.parse(fs.readFileSync(sourcePath, 'utf8'));
config.installCommand = 'true';
config.buildCommand = 'true';
fs.writeFileSync(destinationPath, `${JSON.stringify(config, null, 2)}\n`);
NODE

  echo "Staged the verified static app in ${STAGE_ROOT}"
}

activate_emscripten() {
  local web_sdk_dir="${REPO_ROOT}/sdk/runanywhere-web"
  local emsdk_env="${web_sdk_dir}/emsdk/emsdk_env.sh"
  local setup_script="${web_sdk_dir}/wasm/scripts/setup-emsdk.sh"
  local expected_emscripten
  local actual_emscripten

  expected_emscripten="$(sed -n 's/^EMSCRIPTEN_VERSION=//p' "${REPO_ROOT}/sdk/runanywhere-commons/VERSIONS")"
  [[ -n "${expected_emscripten}" ]] || die "EMSCRIPTEN_VERSION is missing from sdk/runanywhere-commons/VERSIONS"

  if [[ ! -f "${emsdk_env}" ]]; then
    "${setup_script}" "${web_sdk_dir}/emsdk"
  fi

  export EMSDK_QUIET=1
  # shellcheck disable=SC1090
  source "${emsdk_env}" >/dev/null
  actual_emscripten="$(emcc --version | sed -nE '1s/.*[^0-9]([0-9]+\.[0-9]+\.[0-9]+)(-git)?.*/\1/p')"

  if [[ "${actual_emscripten}" != "${expected_emscripten}" ]]; then
    "${setup_script}" "${web_sdk_dir}/emsdk"
    # shellcheck disable=SC1090
    source "${emsdk_env}" >/dev/null
    actual_emscripten="$(emcc --version | sed -nE '1s/.*[^0-9]([0-9]+\.[0-9]+\.[0-9]+)(-git)?.*/\1/p')"
  fi

  [[ "${actual_emscripten}" == "${expected_emscripten}" ]] \
    || die "Emscripten ${expected_emscripten} is required (found ${actual_emscripten:-unknown})"
}

deploy_prebuilt() {
  activate_emscripten
  require_command vercel
  [[ -f .vercel/project.json ]] || die "this checkout is not linked to Vercel; run 'vercel link' first"

  npm run release:build
  stage_prebuilt
  vercel build --prod --cwd .vercel-stage
  verify_output .vercel-stage/.vercel/output/static

  if [[ -d .vercel-stage/.vercel/output/functions ]] \
    && find .vercel-stage/.vercel/output/functions -mindepth 1 -print -quit | grep -q .; then
    die "static release unexpectedly contains a serverless function"
  fi

  vercel deploy --prebuilt --prod --cwd .vercel-stage "$@"
}

command_name="${1:-}"
if [[ $# -gt 0 ]]; then
  shift
fi

case "${command_name}" in
  verify)
    verify_output "${1:-dist}"
    ;;
  stage)
    stage_prebuilt
    ;;
  deploy)
    deploy_prebuilt "$@"
    ;;
  *)
    die "usage: scripts/release.sh {verify [output-dir]|stage|deploy [vercel-args...]}"
    ;;
esac
