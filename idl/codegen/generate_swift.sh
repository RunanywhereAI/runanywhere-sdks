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
    # Wave 3 Step 3.1 (RC-8) — hardware profile types for hardware namespace.
    "${PROTO_DIR}/hardware_profile.proto"
    # CPP-02 — model lifecycle service stub mirroring rac_model_lifecycle.h.
    "${PROTO_DIR}/lifecycle_service.proto"
    # Wave H-2 / IDL-02 — canonical ThinkingTagPattern shared by llm_options and model_types.
    "${PROTO_DIR}/thinking_tag_pattern.proto"
)

protoc \
    --proto_path="${PROTO_DIR}" \
    --swift_out="Visibility=Public:${OUT_DIR}" \
    "${MESSAGE_PROTOS[@]}"

echo "✓ Swift proto codegen → ${OUT_DIR}"

# SWF-grpc delete (Wave H-2): the three `*.grpc.swift` stubs (voice_agent_service,
# llm_service, download_service) require GRPCCore / GRPCProtobuf and therefore
# macOS 15 / iOS 18 — above our supported minimums (macOS 14 / iOS 17). Swift
# consumes the same services through hand-written AsyncStream adapters
# (VoiceAgentStreamAdapter, LLMStreamAdapter) wired to the in-process C
# callback, so the gRPC stubs would only be dead code. We skip emitting them.
#
# Belt-and-braces: if an older toolchain or a developer invocation emits
# the stubs anyway, strip them here so CI remains byte-deterministic.
rm -f "${OUT_DIR}/voice_agent_service.grpc.swift" \
      "${OUT_DIR}/llm_service.grpc.swift" \
      "${OUT_DIR}/download_service.grpc.swift"

ls -1 "${OUT_DIR}"
