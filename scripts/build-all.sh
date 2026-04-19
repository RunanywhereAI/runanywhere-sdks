#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# scripts/build-all.sh
#
# Top-level convenience entry: builds every v2 artifact from a clean
# clone. Each section is guarded by availability of the corresponding
# toolchain so a missing dep skips cleanly instead of failing the whole
# build.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

echo "=== ra_core + engines + solutions (CMake) ================================"
cmake --preset macos-debug
cmake --build --preset macos-debug
ctest --preset macos-debug

echo
echo "=== frontend: Swift ======================================================"
if command -v swift >/dev/null 2>&1; then
    ( cd frontends/swift && swift build && swift test )
else
    echo "WARN  swift not found on host — skipping Swift frontend"
fi

echo
echo "=== frontend: Kotlin ====================================================="
if command -v gradle >/dev/null 2>&1; then
    ( cd frontends/kotlin && gradle build --no-daemon )
else
    echo "WARN  gradle not found on host — skipping Kotlin frontend"
fi

echo
echo "=== frontend: Flutter (Dart) ============================================="
if command -v flutter >/dev/null 2>&1; then
    ( cd frontends/dart && flutter pub get && flutter analyze && flutter test )
elif command -v dart >/dev/null 2>&1; then
    ( cd frontends/dart && dart pub get && dart analyze && dart test )
else
    echo "WARN  flutter/dart not found on host — skipping Flutter frontend"
fi

echo
echo "=== frontend: React Native (TS) =========================================="
if command -v npm >/dev/null 2>&1; then
    ( cd frontends/ts && npm install --no-audit --no-fund && npm run typecheck && npm test )
else
    echo "WARN  npm not found on host — skipping RN frontend"
fi

echo
echo "=== frontend: Web ========================================================"
if command -v npm >/dev/null 2>&1; then
    ( cd frontends/web && npm install --no-audit --no-fund && npm run typecheck && npm test )
else
    echo "WARN  npm not found on host — skipping Web frontend"
fi

echo
echo "=== verify versions ======================================================"
"${ROOT}/scripts/verify-versions.sh"

echo
echo "✓ build-all complete"
