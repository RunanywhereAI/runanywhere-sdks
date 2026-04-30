#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Generate shared TypeScript bindings via ts-proto for React Native and Web.
#
# Requirements:
#   npm install -g ts-proto@1.181.1 protobufjs
#
# Output:
#   sdk/runanywhere-proto-ts/src/
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PROTO_DIR="${REPO_ROOT}/idl"
TS_OUT_DIR="${REPO_ROOT}/sdk/runanywhere-proto-ts/src"

mkdir -p "${TS_OUT_DIR}"

if ! command -v protoc >/dev/null 2>&1; then
    echo "error: protoc not found. Run scripts/setup-toolchain.sh." >&2
    exit 127
fi

# Resolve the ts-proto plugin that `npm install -g ts-proto` provides. On some
# systems (nvm, asdf) `npm root -g` points at a user-local path — both work.
TS_PROTO_PLUGIN="$(npm root -g 2>/dev/null)/ts-proto/protoc-gen-ts_proto"
if [ ! -x "${TS_PROTO_PLUGIN}" ]; then
    echo "error: ts-proto plugin not found at ${TS_PROTO_PLUGIN}" >&2
    echo "       Install via: npm install -g ts-proto@1.181.1" >&2
    exit 127
fi

# Shared target: env=browser keeps bytes as Uint8Array, which works in Web and
# React Native without coupling generated code to global Buffer.
protoc \
    --plugin=protoc-gen-ts_proto="${TS_PROTO_PLUGIN}" \
    --proto_path="${PROTO_DIR}" \
    --ts_proto_out="${TS_OUT_DIR}" \
    --ts_proto_opt=esModuleInterop=true,outputServices=false,env=browser,useOptionals=messages \
    model_types.proto voice_events.proto pipeline.proto solutions.proto voice_agent_service.proto llm_service.proto download_service.proto \
    llm_options.proto chat.proto tool_calling.proto \
    diffusion_options.proto embeddings_options.proto errors.proto \
    lora_options.proto rag.proto sdk_events.proto storage_types.proto \
    structured_output.proto stt_options.proto tts_options.proto \
    vad_options.proto vlm_options.proto \
    hardware_profile.proto

echo "✓ TS proto codegen → ${TS_OUT_DIR}"
