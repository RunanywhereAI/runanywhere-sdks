#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Run every codegen for every language. Called from CI and from the local
# `./scripts/sync-versions.sh` wrapper.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "▶ Generating Swift protos..."
"${SCRIPT_DIR}/generate_swift.sh"

echo "▶ Generating Kotlin protos..."
"${SCRIPT_DIR}/generate_kotlin.sh"

echo "▶ Generating Dart protos..."
"${SCRIPT_DIR}/generate_dart.sh"

echo "▶ Generating TS/JS protos..."
"${SCRIPT_DIR}/generate_ts.sh"

echo "▶ Generating Python protos..."
"${SCRIPT_DIR}/generate_python.sh"

echo "✓ All proto codegen complete."
