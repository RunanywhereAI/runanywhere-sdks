#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Generate Swift bindings via apple/swift-protobuf + grpc-swift.
#
# Requirements:
#   brew install protobuf swift-protobuf
#   Streaming services additionally need:
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
    echo "error: protoc not found. Run scripts/setup/setup-toolchain.sh." >&2
    exit 127
fi
if ! command -v protoc-gen-swift >/dev/null 2>&1; then
    echo "error: protoc-gen-swift not found." >&2
    echo "       Install via 'brew install swift-protobuf' or build from source." >&2
    exit 127
fi

# Canonical proto-file list from generate_all.sh, with fallback to
# filesystem discovery when invoked standalone.
# router.proto is now included (empty exclusion list) so Swift has
# future-proof parity with Kotlin / C++; no active Swift consumer today, but
# generated RAFrameworksForCapabilityRequest/Response exist for symmetry with
# Kotlin's positive-list semantic (prior commit 769ceccff).
if [ -z "${RAC_PROTO_FILES:-}" ]; then
    RAC_PROTO_FILES="$(ls "${PROTO_DIR}"/*.proto | sort)"
fi

# Language-specific exclusions (basenames of .proto files to skip).
# Empty today — every schema in idl/ is emitted for Swift.
RAC_PROTO_EXCLUDES_SWIFT=()

MESSAGE_PROTOS=()
while IFS= read -r proto_path; do
    [ -z "${proto_path}" ] && continue
    proto_base="$(basename "${proto_path}")"
    skip=0
    if [ "${#RAC_PROTO_EXCLUDES_SWIFT[@]}" -gt 0 ]; then
        for excluded in "${RAC_PROTO_EXCLUDES_SWIFT[@]}"; do
            if [ "${proto_base}" = "${excluded}" ]; then
                skip=1
                break
            fi
        done
    fi
    [ "${skip}" -eq 1 ] && continue
    MESSAGE_PROTOS+=("${proto_path}")
done <<< "${RAC_PROTO_FILES}"

protoc \
    --proto_path="${PROTO_DIR}" \
    --swift_out="Visibility=Public:${OUT_DIR}" \
    "${MESSAGE_PROTOS[@]}"

echo "✓ Swift proto codegen → ${OUT_DIR}"

# The `*.grpc.swift` stubs require GRPCCore /
# GRPCProtobuf and therefore macOS 15 / iOS 18 — above our supported
# minimums (macOS 14 / iOS 17). Swift consumes streaming services through
# hand-written AsyncStream adapters (VoiceAgentStreamAdapter,
# LLMStreamAdapter, etc.) wired to the in-process C callback, so the gRPC
# stubs would only be dead code. We skip emitting them.
#
# Belt-and-braces: if an older toolchain or a developer invocation emits
# the stubs anyway, strip them here so CI remains byte-deterministic.
# Wildcard intentionally covers ALL service protos (21 today: Chat,
# Diffusion, Download, Embeddings, Hardware, Lifecycle, LLM, LoRA,
# ModelRegistry, Pipeline, RAG, SDKEvents, Solutions, Storage,
# StructuredOutput, STT, ToolCalling, TTS, VAD, VLM, VoiceAgent) plus
# any future ones, so this gate stays correct without per-service updates.
rm -f "${OUT_DIR}"/*.grpc.swift

# Emit RAConvenience.swift from rac_options.proto annotations
# (rac_display_name / rac_analytics_key / rac_wire_string + future rac_default /
# rac_required / rac_min / rac_max). The post-processor reads idl/*.proto via
# protoc --descriptor_set_out and writes hand-friendly accessor extensions onto
# the RA* swift-protobuf types in the same module.
if command -v python3 >/dev/null 2>&1; then
    python3 "${SCRIPT_DIR}/generate_swift_convenience.py"
    # Generate `ModalityProtoABI+Generated.swift` from the
    # manifest at swift-modality-abi.yaml. Owns the dlsym table for the 7
    # fully-equivalent modality-ABI methods.
    python3 "${SCRIPT_DIR}/generate_swift_modality_abi.py"
else
    echo "warning: python3 not found — skipping RAConvenience.swift + ModalityProtoABI codegen." >&2
    echo "         Install python3 (https://www.python.org) to enable annotations." >&2
fi

ls -1 "${OUT_DIR}"
