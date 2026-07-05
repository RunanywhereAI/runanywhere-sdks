#!/usr/bin/env bash
# Static functional smoke preflight for the React Native sample.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"
APP_ROOT="${RAC_ROOT}/examples/react-native/RunAnywhereAI"

cd "${APP_ROOT}"

echo "==> Checking React Native SDK call coverage"
grep -R -E "RunAnywhere\.(initialize|listModels|downloadedModels|downloadModel|importModel|loadModel|currentModel|generateStream|generate\(|transcribe\(|synthesize|deleteStorage|cleanTempFiles|getStorageInfo)" \
    App.tsx src >/dev/null

grep -R -E "initializeVoiceAgentWithLoadedModels|streamVoiceAgent" src >/dev/null

echo "==> Checking TypeScript build gate"
yarn typecheck

if [ "${RUN_BUILD_GATES:-0}" = "1" ]; then
    echo "==> Running full React Native verify gates"
    "${SCRIPT_DIR}/verify.sh"
fi

echo "React Native smoke preflight complete"
