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

# IDL-19c: canonical proto-file list from generate_all.sh, with fallback to
# filesystem discovery when invoked standalone. Swift excludes router.proto
# (see RAC_PROTO_EXCLUDES_SWIFT below for rationale).
if [ -z "${RAC_PROTO_FILES:-}" ]; then
    RAC_PROTO_FILES="$(ls "${PROTO_DIR}"/*.proto | sort)"
fi

# Language-specific exclusions (basenames of .proto files to skip).
# router.proto — engine-router capability-query types are consumed only by
#   the C++ core and Kotlin adapters; Swift calls commons directly via the
#   C ABI and has no need for the generated Swift message types. Keeping
#   the exclusion means swift codegen doesn't emit dead router.pb.swift.
RAC_PROTO_EXCLUDES_SWIFT=(
    "router.proto"
)

MESSAGE_PROTOS=()
while IFS= read -r proto_path; do
    [ -z "${proto_path}" ] && continue
    proto_base="$(basename "${proto_path}")"
    skip=0
    for excluded in "${RAC_PROTO_EXCLUDES_SWIFT[@]}"; do
        if [ "${proto_base}" = "${excluded}" ]; then
            skip=1
            break
        fi
    done
    [ "${skip}" -eq 1 ] && continue
    MESSAGE_PROTOS+=("${proto_path}")
done <<< "${RAC_PROTO_FILES}"

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
