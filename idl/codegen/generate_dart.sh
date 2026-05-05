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
#
# Supports flags:
#   --skip-dart   Explicit opt-out (honoured from generate_all.sh).
set -euo pipefail

for arg in "$@"; do
    case "$arg" in
        --skip-dart)
            echo "note: --skip-dart requested; skipping Dart codegen."
            exit 0
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PROTO_DIR="${REPO_ROOT}/idl"
OUT_DIR="${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere/lib/generated"

# IDL-16 / CPP-10: pin Dart + protoc_plugin versions so local + CI runs
# produce byte-identical output. Older Dart / protoc_plugin combos emit
# subtly different code (e.g. accidental .pbgrpc.dart) that trips the
# idl-drift-check CI gate on unrelated PRs.
if command -v dart >/dev/null 2>&1; then
    DART_VERSION="$(dart --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    if [ -n "${DART_VERSION}" ]; then
        DART_MAJOR="$(echo "${DART_VERSION}" | cut -d. -f1)"
        if [ "${DART_MAJOR}" -lt 3 ]; then
            echo "warning: Dart ${DART_VERSION} < 3.0 detected; skipping Dart codegen." >&2
            echo "         Upgrade Dart to 3.0+ or use CI to generate the bindings." >&2
            exit 0
        fi
    fi
else
    echo "warning: 'dart' binary not on PATH; proceeding but will fail on missing plugin." >&2
fi

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

# IDL-16 / CPP-10: verify protoc_plugin is pinned at 21.1.2. The plugin does
# not expose --version in older releases; fall back to a best-effort check.
if PLUGIN_VERSION_OUT="$(protoc-gen-dart --version 2>&1)"; then
    if ! echo "${PLUGIN_VERSION_OUT}" | grep -q "21.1.2"; then
        echo "warning: protoc_plugin version could not be verified as 21.1.2." >&2
        echo "         Got: ${PLUGIN_VERSION_OUT}" >&2
        echo "         Re-pin via: dart pub global activate protoc_plugin 21.1.2" >&2
    fi
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

# Phase B — additional duplicated data shapes (per-modality options + shared types).
protoc \
    --proto_path="${PROTO_DIR}" \
    --dart_out="${OUT_DIR}" \
    diffusion_options.proto embeddings_options.proto errors.proto \
    lora_options.proto rag.proto sdk_events.proto storage_types.proto \
    structured_output.proto stt_options.proto tts_options.proto \
    vad_options.proto vlm_options.proto

# Wave 3 Step 3.1 (RC-8) — hardware profile types for hardware namespace.
protoc \
    --proto_path="${PROTO_DIR}" \
    --dart_out="${OUT_DIR}" \
    hardware_profile.proto

# CPP-02 — model lifecycle service stub mirroring rac_model_lifecycle.h.
protoc \
    --proto_path="${PROTO_DIR}" \
    --dart_out="${OUT_DIR}" \
    lifecycle_service.proto

# Wave H-2 / IDL-02 — canonical ThinkingTagPattern shared by llm_options and model_types.
protoc \
    --proto_path="${PROTO_DIR}" \
    --dart_out="${OUT_DIR}" \
    thinking_tag_pattern.proto

# Belt-and-braces: strip any accidentally-regenerated .pbgrpc.dart files
# (some older protoc_plugin versions emit them even without the grpc: prefix).
rm -f "${OUT_DIR}"/*.pbgrpc.dart

echo "✓ Dart proto codegen → ${OUT_DIR} (gRPC client stubs stripped)"
