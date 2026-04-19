#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Generate Python bindings via the official protobuf plugin.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PROTO_DIR="${REPO_ROOT}/idl"
OUT_DIR="${REPO_ROOT}/frontends/python/runanywhere/generated"

mkdir -p "${OUT_DIR}"

if ! command -v protoc >/dev/null 2>&1; then
    echo "error: protoc not found" >&2
    exit 127
fi

protoc \
    --proto_path="${PROTO_DIR}" \
    --python_out="${OUT_DIR}" \
    --pyi_out="${OUT_DIR}" \
    voice_events.proto pipeline.proto solutions.proto

# Ensure the package is importable.
touch "${OUT_DIR}/__init__.py"

echo "✓ Python proto codegen → ${OUT_DIR}"
