#!/usr/bin/env bash
# Functional smoke preflight for the Web sample.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${APP_ROOT}"

echo "==> Checking Web SDK call coverage"
# The example app should stay on the Swift-shaped root facade for app workflows;
# backend internals live under @runanywhere/web/internal.
grep -R -E "RunAnywhere\.(initialize|downloadModel|loadModel|generateStream|processImage|transcribe|synthesize|detectVoiceActivity|ragIngest|ragQuery|chooseLocalStorageDirectory|requestLocalStorageAccess|solutions\.run)" \
    src >/dev/null

if grep -R -E "ModelManager|TextGeneration|VLMWorkerBridge|visionLanguage\.loadModel" src >/dev/null; then
  echo "Found stale Web SDK API usage in the example app" >&2
  exit 1
fi

echo "==> Building Web sample"
npm run build

test -f dist/index.html

echo "Web smoke preflight complete"
