#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Run every codegen for every language. Called from CI (idl-drift-check.yml)
# and from local workflows after edits to any *.proto file under idl/.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Fail fast on missing toolchain rather than running 80% and breaking late.
# Each language script does its own lookup; this is just the base gate.
if ! command -v protoc >/dev/null 2>&1; then
    echo "error: protoc not on PATH." >&2
    echo "       Run scripts/setup-toolchain.sh first, or install manually:" >&2
    echo "         brew install protobuf            # macOS" >&2
    echo "         apt-get install protobuf-compiler   # Ubuntu" >&2
    exit 127
fi

echo "▶ protoc version: $(protoc --version)"

echo "▶ Swift proto codegen"
"${SCRIPT_DIR}/generate_swift.sh"

echo "▶ Kotlin proto codegen"
"${SCRIPT_DIR}/generate_kotlin.sh"

echo "▶ Dart proto codegen"
"${SCRIPT_DIR}/generate_dart.sh"

echo "▶ TypeScript proto codegen (RN + Web)"
"${SCRIPT_DIR}/generate_ts.sh"

echo "▶ Python proto codegen"
"${SCRIPT_DIR}/generate_python.sh"

echo "▶ C++ proto codegen"
"${SCRIPT_DIR}/generate_cpp.sh"

# GAP 09 Phase 14: AsyncIterable<T> stream wrappers for RN + Web. The
# template-based renderer is intentionally separate from generate_ts.sh
# (which uses ts-proto for messages) — different tools, different outputs.
echo "▶ RN AsyncIterable streams (GAP 09)"
"${SCRIPT_DIR}/generate_rn_streams.sh"

echo "▶ Web AsyncIterable streams (GAP 09)"
"${SCRIPT_DIR}/generate_web_streams.sh"

echo "✓ All proto codegen complete."
