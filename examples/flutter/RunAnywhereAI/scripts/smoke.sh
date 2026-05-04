#!/usr/bin/env bash
# Static functional smoke preflight for the Flutter sample.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${APP_ROOT}"

echo "==> Checking Flutter SDK call coverage"
grep -R -E "RunAnywhere|RunAnywhereSDK|generateStream|generate\(|downloadModel|loadLLMModel|loadSTTModel|transcribe|loadTTSVoice|synthesize|deleteStoredModel|getStorageInfo|startVoiceSession|voice\.initializeWithLoadedModels" \
    lib >/dev/null

grep -R -E "RAG|rag|file_picker|syncfusion_flutter_pdf" lib pubspec.yaml >/dev/null

echo "==> Running Flutter analyzer"
flutter analyze

if [ "${RUN_BUILD_GATES:-0}" = "1" ]; then
    echo "==> Running full Flutter verify gates"
    "${SCRIPT_DIR}/verify.sh"
fi

echo "Flutter smoke preflight complete"
