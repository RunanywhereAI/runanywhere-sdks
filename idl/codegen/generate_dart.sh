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

# GAP 09 service definitions — emit message types only (NOT the gRPC client
# stubs). The .pbgrpc.dart stubs depend on package:grpc runtime which we
# don't carry in the Flutter SDK (streaming flows via the hand-written
# VoiceAgentStreamAdapter / LLMStreamAdapter over rac_*_set_proto_callback
# instead). Using `--dart_out=<dir>` (no `grpc:` prefix) skips the gRPC
# stubs and emits only the .pb.dart message types.
protoc \
    --proto_path="${PROTO_DIR}" \
    --dart_out="${OUT_DIR}" \
    voice_agent_service.proto llm_service.proto download_service.proto

# Phase 3 IDL exhaustiveness — duplicated data shapes across SDKs.
protoc \
    --proto_path="${PROTO_DIR}" \
    --dart_out="${OUT_DIR}" \
    llm_options.proto chat.proto tool_calling.proto

# Belt-and-braces: strip any accidentally-regenerated .pbgrpc.dart files
# (some older protoc_plugin versions emit them even without the grpc: prefix).
rm -f "${OUT_DIR}"/*.pbgrpc.dart

echo "✓ Dart proto codegen → ${OUT_DIR} (gRPC client stubs stripped)"
