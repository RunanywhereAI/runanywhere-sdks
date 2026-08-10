#!/usr/bin/env bash
# Launch the RunAnywhere Electron demo on Linux (mirrors run-demo.cmd).
# Paths are relative to this file, so it works wherever the repo lives.
set -euo pipefail

# If set, Electron runs as plain Node (no window).
unset ELECTRON_RUN_AS_NODE

# This file lives in examples/electron/RunAnywhereAI/; repo root is 3 up.
REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
export RUNANYWHERE_NATIVE_PATH="$REPO/sdk/runanywhere-electron/prebuilds/linux-x64/runanywhere_native.node"

# Electron ships as a devDependency of the SDK; use its binary directly so no
# node_modules is needed at the repo root or in this example.
ELECTRON="$REPO/sdk/runanywhere-electron/node_modules/.bin/electron"
if [ ! -x "$ELECTRON" ]; then
  echo "electron not found at $ELECTRON — run 'npm install' in sdk/runanywhere-electron first" >&2
  exit 1
fi

cd "$REPO"
echo "Launching RunAnywhere demo...  (close the window to quit the app)"
exec "$ELECTRON" examples/electron/RunAnywhereAI "$@"
