#!/usr/bin/env bash
# Functional smoke preflight for the Web sample.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${APP_ROOT}"

echo "==> Checking Web SDK call coverage"
# After the V2 cleanup the legacy ModelManager / TextGeneration / VLMWorkerBridge
# facades were deleted. The example app currently exercises the canonical Phase
# 1 init + persistent-storage chooser flow (`RunAnywhere.initialize`,
# `RunAnywhere.restoreLocalStorage`, `RunAnywhere.chooseLocalStorageDirectory`)
# while the proto-byte backend bridges are wired up in a follow-up.
grep -R -E "RunAnywhere\.(initialize|restoreLocalStorage|chooseLocalStorageDirectory|requestLocalStorageAccess)|RunAnywhere\.solutions\.run|RAG\.(query|ingest|getStatistics)" \
    src >/dev/null

echo "==> Building Web sample"
npm run build

test -f dist/index.html

echo "Web smoke preflight complete"
