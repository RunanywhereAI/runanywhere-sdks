#!/usr/bin/env bash
# Static functional smoke preflight for the React Native sample.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${APP_ROOT}"

echo "==> Checking React Native SDK call coverage"
grep -R -E "RunAnywhere\.(initialize|getAvailableModels|downloadModel|loadModel|generateStream|generate\(|loadSTTModel|transcribeFile|loadTTSModel|synthesize|deleteModel|clearCache|getStorageInfo)" \
    App.tsx src >/dev/null

grep -R -E "VoiceAgentStreamAdapter|initializeVoiceAgentWithLoadedModels|getVoiceAgentHandle" src >/dev/null

echo "==> Checking TypeScript build gate"
yarn typecheck

if [ "${RUN_BUILD_GATES:-0}" = "1" ]; then
    echo "==> Running full React Native verify gates"
    "${SCRIPT_DIR}/verify.sh"
fi

echo "React Native smoke preflight complete"
