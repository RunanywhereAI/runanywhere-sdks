#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Generate Kotlin bindings via Square Wire.
#
# Requirements (one of):
#   brew install wire                                 # wire-compiler binary
#   (or) Gradle's com.squareup.wire:wire-gradle-plugin:4.9.9 in
#        sdk/runanywhere-kotlin/build.gradle.kts
#
# Output:
#   sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/generated/
#
# Wire emits pure Kotlin data classes with no Java protobuf dependency, which
# keeps KMP's commonMain source set portable.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PROTO_DIR="${REPO_ROOT}/idl"
OUT_DIR="${REPO_ROOT}/sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/generated"

mkdir -p "${OUT_DIR}"

if command -v wire-compiler >/dev/null 2>&1; then
    # Wire emits pure Kotlin data classes for messages. GAP 09 service
    # definitions are passed too — Wire treats `service { rpc ... }` blocks
    # as informational and emits the message types only. The streaming
    # client wrapper is hand-written in
    # sdk/runanywhere-kotlin/src/jvmAndroidMain/kotlin/.../adapters/
    # using kotlinx.coroutines Flow + the Wire-generated message types.
    wire-compiler \
        --proto_path="${PROTO_DIR}" \
        --kotlin_out="${OUT_DIR}" \
        model_types.proto voice_events.proto pipeline.proto solutions.proto \
        voice_agent_service.proto llm_service.proto download_service.proto \
        llm_options.proto chat.proto tool_calling.proto \
        diffusion_options.proto embeddings_options.proto errors.proto \
        lora_options.proto rag.proto sdk_events.proto storage_types.proto \
        structured_output.proto stt_options.proto tts_options.proto \
        vad_options.proto vlm_options.proto \
        hardware_profile.proto

    # v2 close-out: Wire 4.x emits gRPC service interfaces (`<Service>Client.kt`)
    # AND their Grpc client implementations (`Grpc<Service>Client.kt`). Both
    # depend on com.squareup.wire:wire-grpc-client which we don't carry in KMP
    # commonMain (JVM-only grpc runtime). The hand-written
    # VoiceAgentStreamAdapter / DownloadStreamAdapter under jvmAndroidMain
    # consume the message types directly via rac_*_set_proto_callback, so the
    # generated client stubs are dead weight. Strip them so regen stays green.
    for svc in Download LLM VoiceAgent; do
        rm -f "${OUT_DIR}/ai/runanywhere/proto/v1/${svc}Client.kt"
        rm -f "${OUT_DIR}/ai/runanywhere/proto/v1/Grpc${svc}Client.kt"
    done

    echo "✓ Kotlin proto codegen → ${OUT_DIR} (gRPC client stubs stripped)"

    # Note: protoc-gen-grpckt (grpc-kotlin official plugin) emits
    # com.google.protobuf-style Java messages + Flow client stubs. We do
    # NOT use it here because it would force a Java protobuf runtime
    # dependency in commonMain (breaks KMP). The hand-written ~150 LOC
    # adapter (Wave C Phase 17) is the bridge.
else
    echo "warning: wire-compiler not on PATH." >&2
    echo "         The Gradle Wire plugin in sdk/runanywhere-kotlin/build.gradle.kts" >&2
    echo "         will regenerate at build time. For one-off CLI runs, install via" >&2
    echo "         'brew install wire' (macOS) or download from" >&2
    echo "         https://github.com/square/wire/releases" >&2
fi
