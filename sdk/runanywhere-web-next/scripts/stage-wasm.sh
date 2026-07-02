#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OLD="${ROOT}/../runanywhere-web"

link_pkg() {
  local pkg="$1"
  local src="${OLD}/packages/${pkg}/wasm"
  local dst="${ROOT}/packages/${pkg}/wasm"
  if [ ! -d "${src}" ]; then
    echo "WARN: ${src} not found — build the WASM first (npm run build:wasm from sdk/runanywhere-web-next), then re-run."
    return
  fi
  rm -rf "${dst}"
  ln -sfn "../../../runanywhere-web/packages/${pkg}/wasm" "${dst}"
  echo "staged packages/${pkg}/wasm -> ${src}"
}

link_pkg core
link_pkg llamacpp
link_pkg onnx
