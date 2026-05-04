#!/usr/bin/env bash
# Functional smoke preflight for the Web sample.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${APP_ROOT}"

echo "==> Checking Web SDK call coverage"
grep -R -E "RunAnywhere\.(initialize|registerModels|restoreLocalStorage|chooseLocalStorageDirectory|importModelFromPicker|importModelFromFile)|ModelManager\.(downloadModel|loadModel|deleteModel|clearAll|getStorageInfo)|TextGeneration\.generateStream|ToolCalling\.generateWithTools|VLMWorkerBridge|transcribe|synthesize|voice" \
    src >/dev/null

echo "==> Building Web sample"
npm run build

test -f dist/index.html

echo "Web smoke preflight complete"
