#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Generate Dart bindings via dart-lang/protobuf (protoc_plugin).
#
# Requirements:
#   dart pub global activate protoc_plugin 21.1.2
#   export PATH="$PATH:$HOME/.pub-cache/bin"
#
# Output:
#   sdk/runanywhere-flutter/packages/runanywhere/lib/generated/
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PROTO_DIR="${REPO_ROOT}/idl"
OUT_DIR="${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere/lib/generated"

mkdir -p "${OUT_DIR}"

if ! command -v protoc >/dev/null 2>&1; then
    echo "error: protoc not found. Run scripts/setup-toolchain.sh." >&2
    exit 127
fi
if ! command -v protoc-gen-dart >/dev/null 2>&1; then
    echo "error: protoc-gen-dart not found." >&2
    echo "       Install via: dart pub global activate protoc_plugin 21.1.2" >&2
    echo "       and add \$HOME/.pub-cache/bin to your PATH." >&2
    exit 127
fi

# Message types — always emitted.
protoc \
    --proto_path="${PROTO_DIR}" \
    --dart_out="${OUT_DIR}" \
    model_types.proto voice_events.proto pipeline.proto solutions.proto

# GAP 09 service definitions — protoc_plugin emits both message types AND
# `Stream<T>` gRPC client stubs (*.pbgrpc.dart) when --dart_out=grpc:<dir>.
protoc \
    --proto_path="${PROTO_DIR}" \
    --dart_out="grpc:${OUT_DIR}" \
    voice_agent_service.proto llm_service.proto download_service.proto

echo "✓ Dart proto codegen + gRPC stubs → ${OUT_DIR}"
