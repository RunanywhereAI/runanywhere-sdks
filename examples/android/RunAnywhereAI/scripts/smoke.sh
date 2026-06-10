#!/usr/bin/env bash
# Static functional smoke preflight for the native Android sample.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${APP_ROOT}"

echo "==> Checking Kotlin SDK call coverage"
grep -R -E "RunAnywhere\.(initialize|registerModel|downloadModel|loadLLMModel|generateStream|generate\(|loadSTTModel|transcribe|loadTTSVoice|synthesize|deleteModel|clearCache|storageInfo|startVoiceSession|processVoice)" \
    app/src/main >/dev/null

grep -R -E "RAG|rag|cancelGeneration|stopSynthesis|VoiceAssistant" app/src/main >/dev/null

if [ "${RUN_BUILD_GATES:-0}" = "1" ]; then
    echo "==> Running full Android verify gates"
    "${SCRIPT_DIR}/verify.sh"
fi

echo "Android smoke preflight complete"
