#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Generate Swift bindings from the v2 proto3 schemas via swift-protobuf.
#
# Requirements (install once):
#   brew install protobuf swift-protobuf
#   (or) swift build -c release --package-path .../swift-protobuf
# The script will complain loudly if either is missing.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PROTO_DIR="${REPO_ROOT}/idl"
OUT_DIR="${REPO_ROOT}/frontends/swift/Sources/RunAnywhere/Generated"

mkdir -p "${OUT_DIR}"

if ! command -v protoc >/dev/null 2>&1; then
    echo "error: protoc not found; install via 'brew install protobuf'" >&2
    exit 127
fi
if ! command -v protoc-gen-swift >/dev/null 2>&1; then
    echo "error: protoc-gen-swift not found;" >&2
    echo "       install via 'brew install swift-protobuf' or build from source" >&2
    exit 127
fi

protoc \
    --proto_path="${PROTO_DIR}" \
    --swift_out="Visibility=Public:${OUT_DIR}" \
    "${PROTO_DIR}/voice_events.proto" \
    "${PROTO_DIR}/pipeline.proto" \
    "${PROTO_DIR}/solutions.proto"

echo "✓ Swift proto codegen → ${OUT_DIR}"
ls -1 "${OUT_DIR}"
