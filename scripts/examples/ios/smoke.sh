#!/usr/bin/env bash
# Static functional smoke preflight for the native iOS sample.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
APP_ROOT="${RAC_ROOT}/examples/ios/RunAnywhereAI"

cd "${APP_ROOT}"

echo "==> Checking Swift SDK call coverage"
grep -R -E "RunAnywhere\.(initialize|registerModel|downloadModel|loadModel|generateStream|generate\(|transcribe|speak|processImage|processImageStream|detectVoiceActivity|getStorageInfo|clearCache|cleanTempFiles|cancelGeneration|listModels|initializeVoiceAgent|streamVoiceAgent|ragCreatePipeline|ragIngest|ragQuery)" \
    RunAnywhereAI >/dev/null

grep -R -E "Voice|Pipeline|RAG|rag|cancelGeneration" RunAnywhereAI >/dev/null

if [ "${RUN_BUILD_GATES:-0}" = "1" ]; then
    echo "==> Running full iOS verify gates"
    "${SCRIPT_DIR}/verify.sh"
fi

echo "iOS smoke preflight complete"
