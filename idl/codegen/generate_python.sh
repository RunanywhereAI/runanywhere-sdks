#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Generate Python bindings via the official google/protobuf plugin.
#
# Requirements:
#   python3 -m pip install protobuf==4.25.1
#
# Output:
#   sdk/runanywhere-python/src/runanywhere/generated/
#
# Note: sdk/runanywhere-python/ does not exist yet. This script creates the
# target directory so a future Python SDK can consume the same schemas; CI
# does NOT require Python SDK sources to compile.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PROTO_DIR="${REPO_ROOT}/idl"
OUT_DIR="${REPO_ROOT}/sdk/runanywhere-python/src/runanywhere/generated"

mkdir -p "${OUT_DIR}"

if ! command -v protoc >/dev/null 2>&1; then
    echo "error: protoc not found. Run scripts/setup-toolchain.sh." >&2
    exit 127
fi

protoc \
    --proto_path="${PROTO_DIR}" \
    --python_out="${OUT_DIR}" \
    --pyi_out="${OUT_DIR}" \
    model_types.proto voice_events.proto pipeline.proto solutions.proto

# Ensure the package is importable.
touch "${OUT_DIR}/__init__.py"

echo "✓ Python proto codegen → ${OUT_DIR}"
