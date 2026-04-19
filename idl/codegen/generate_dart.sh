#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Generate Dart bindings via protobuf.dart.
#
# Requirements:
#   dart pub global activate protoc_plugin
#   export PATH="$PATH:$HOME/.pub-cache/bin"
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PROTO_DIR="${REPO_ROOT}/idl"
OUT_DIR="${REPO_ROOT}/frontends/dart/lib/generated"

mkdir -p "${OUT_DIR}"

if ! command -v protoc >/dev/null 2>&1; then
    echo "error: protoc not found" >&2
    exit 127
fi
if ! command -v protoc-gen-dart >/dev/null 2>&1; then
    echo "error: protoc-gen-dart not found;" >&2
    echo "       install via 'dart pub global activate protoc_plugin'" >&2
    exit 127
fi

protoc \
    --proto_path="${PROTO_DIR}" \
    --dart_out="${OUT_DIR}" \
    voice_events.proto pipeline.proto solutions.proto

echo "✓ Dart proto codegen → ${OUT_DIR}"
