#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

web_sdk_dir="$(cd ../../../sdk/runanywhere-web && pwd)"
emsdk_env="${web_sdk_dir}/emsdk/emsdk_env.sh"
expected_emscripten="$(sed -n 's/^EMSCRIPTEN_VERSION=//p' ../../../sdk/runanywhere-commons/VERSIONS)"

if [[ ! -f "${emsdk_env}" ]]; then
  "${web_sdk_dir}/wasm/scripts/setup-emsdk.sh" "${web_sdk_dir}/emsdk"
fi

export EMSDK_QUIET=1
# shellcheck disable=SC1090
source "${emsdk_env}" >/dev/null
actual_emscripten="$(emcc --version | sed -nE '1s/.*[^0-9]([0-9]+\.[0-9]+\.[0-9]+)(-git)?.*/\1/p')"
if [[ "${actual_emscripten}" != "${expected_emscripten}" ]]; then
  "${web_sdk_dir}/wasm/scripts/setup-emsdk.sh" "${web_sdk_dir}/emsdk"
  # shellcheck disable=SC1090
  source "${emsdk_env}" >/dev/null
  actual_emscripten="$(emcc --version | sed -nE '1s/.*[^0-9]([0-9]+\.[0-9]+\.[0-9]+)(-git)?.*/\1/p')"
fi
if [[ "${actual_emscripten}" != "${expected_emscripten}" ]]; then
  echo "Emscripten ${expected_emscripten} is required (found ${actual_emscripten:-unknown})." >&2
  exit 1
fi

if ! command -v vercel >/dev/null 2>&1; then
  echo "Vercel CLI is required. Install it, then run 'vercel link'." >&2
  exit 1
fi

if [[ ! -f .vercel/project.json ]]; then
  echo "This checkout is not linked to Vercel. Run 'vercel link' first." >&2
  exit 1
fi

npm run release:build
npm run release:stage
vercel build --prod --cwd .vercel-stage
node scripts/verify-release-output.mjs .vercel-stage/.vercel/output/static

if [[ ! -d .vercel-stage/.vercel/output/functions/api/runanywhere.func ]]; then
  echo "The prebuilt output is missing the api/runanywhere relay function." >&2
  exit 1
fi

vercel deploy --prebuilt --prod --cwd .vercel-stage "$@"
