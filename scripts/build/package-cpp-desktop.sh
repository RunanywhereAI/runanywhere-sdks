#!/usr/bin/env bash
# Build and stage the C++ desktop kit (headers + static commons + IDL).
# Does not produce an rcli binary.
#
#   scripts/build/package-cpp-desktop.sh [preset]
#   default preset: cpp-desktop-macos-arm64 on Darwin, cpp-desktop-windows-x64 else
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
PRESET="${1:-}"
if [[ -z "$PRESET" ]]; then
  case "$(uname -s)" in
    Darwin) PRESET=cpp-desktop-macos-arm64 ;;
    Linux)  PRESET=cpp-desktop-macos-arm64; echo "WARN: using macOS preset name; override for linux" >&2 ;;
    *)      PRESET=cpp-desktop-windows-x64 ;;
  esac
fi
cmake --preset "$PRESET"
cmake --build --preset "$PRESET" --target package-cpp-desktop-tarball
echo "Kit under $ROOT/dist/"
ls -la "$ROOT/dist"/RunAnywhere-cpp-desktop-* 2>/dev/null || ls -la "$ROOT/dist"/cpp-desktop-*
