#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Generate Swift bindings via apple/swift-protobuf + (GAP 09) grpc-swift.
#
# Requirements:
#   brew install protobuf swift-protobuf
#   GAP 09 streaming services additionally need:
#     brew install grpc-swift   # provides protoc-gen-grpc-swift
#
# Output:
#   sdk/runanywhere-swift/Sources/RunAnywhere/Generated/
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PROTO_DIR="${REPO_ROOT}/idl"
OUT_DIR="${REPO_ROOT}/sdk/runanywhere-swift/Sources/RunAnywhere/Generated"

mkdir -p "${OUT_DIR}"

if ! command -v protoc >/dev/null 2>&1; then
    echo "error: protoc not found. Run scripts/setup-toolchain.sh." >&2
    exit 127
fi
if ! command -v protoc-gen-swift >/dev/null 2>&1; then
    echo "error: protoc-gen-swift not found." >&2
    echo "       Install via 'brew install swift-protobuf' or build from source." >&2
    exit 127
fi

# Message types — always generated.
MESSAGE_PROTOS=(
    "${PROTO_DIR}/model_types.proto"
    "${PROTO_DIR}/voice_events.proto"
    "${PROTO_DIR}/pipeline.proto"
    "${PROTO_DIR}/solutions.proto"
    # GAP 09 service definitions ALSO emit message types (Request types).
    "${PROTO_DIR}/voice_agent_service.proto"
    "${PROTO_DIR}/llm_service.proto"
    "${PROTO_DIR}/download_service.proto"
    # Phase 3 IDL exhaustiveness — duplicated data shapes across SDKs.
    "${PROTO_DIR}/llm_options.proto"
    "${PROTO_DIR}/chat.proto"
    "${PROTO_DIR}/tool_calling.proto"
    # Phase B — additional duplicated data shapes (per-modality options + shared types).
    "${PROTO_DIR}/diffusion_options.proto"
    "${PROTO_DIR}/embeddings_options.proto"
    "${PROTO_DIR}/errors.proto"
    "${PROTO_DIR}/lora_options.proto"
    "${PROTO_DIR}/rag.proto"
    "${PROTO_DIR}/sdk_events.proto"
    "${PROTO_DIR}/storage_types.proto"
    "${PROTO_DIR}/structured_output.proto"
    "${PROTO_DIR}/stt_options.proto"
    "${PROTO_DIR}/tts_options.proto"
    "${PROTO_DIR}/vad_options.proto"
    "${PROTO_DIR}/vlm_options.proto"
)

protoc \
    --proto_path="${PROTO_DIR}" \
    --swift_out="Visibility=Public:${OUT_DIR}" \
    "${MESSAGE_PROTOS[@]}"

echo "✓ Swift proto codegen → ${OUT_DIR}"

# GAP 09: server-streaming gRPC stubs (AsyncStream<T>). Optional — produces
# *.grpc.swift files only when the grpc-swift plugin is installed; we don't
# error out because the message-only path above is sufficient for non-streaming
# consumers.
if command -v protoc-gen-grpc-swift >/dev/null 2>&1; then
    # grpc-swift 2.x dropped the v1 Server/Client/TestClient flags — it
    # always emits both client + server. We just pass Visibility for the
    # generated Swift access modifier so frontends can `import` the types.
    protoc \
        --proto_path="${PROTO_DIR}" \
        --grpc-swift_out="Visibility=Public:${OUT_DIR}" \
        "${PROTO_DIR}/voice_agent_service.proto" \
        "${PROTO_DIR}/llm_service.proto" \
        "${PROTO_DIR}/download_service.proto"
    echo "✓ Swift gRPC stubs → ${OUT_DIR}/*.grpc.swift"
else
    echo "note: protoc-gen-grpc-swift not installed; skipping streaming stubs."
    echo "      Install via 'brew install grpc-swift' to generate AsyncStream client wrappers."
fi

ls -1 "${OUT_DIR}"
