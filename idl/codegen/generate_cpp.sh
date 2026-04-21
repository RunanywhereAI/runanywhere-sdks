#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Generate C++ bindings via protoc --cpp_out.
#
# Requirements:
#   brew install protobuf          # includes headers + runtime
#   apt-get install libprotobuf-dev protobuf-compiler   # Ubuntu
#
# Output:
#   sdk/runanywhere-commons/src/generated/proto/
#
# The generated headers live inside sdk/runanywhere-commons so the C ABI shim
# layer can `#include "runanywhere/idl/model_types.pb.h"` for
# proto-encoded wire conversions. CMake's `idl/CMakeLists.txt` generates the
# same files at build time for the `rac_idl` library; this script keeps a
# committed copy for IDE navigation + the CI drift check.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PROTO_DIR="${REPO_ROOT}/idl"
OUT_DIR="${REPO_ROOT}/sdk/runanywhere-commons/src/generated/proto"

mkdir -p "${OUT_DIR}"

if ! command -v protoc >/dev/null 2>&1; then
    echo "error: protoc not found. Run scripts/setup-toolchain.sh." >&2
    exit 127
fi

protoc \
    --proto_path="${PROTO_DIR}" \
    --cpp_out="${OUT_DIR}" \
    model_types.proto voice_events.proto pipeline.proto solutions.proto

echo "✓ C++ proto codegen → ${OUT_DIR}"
ls -1 "${OUT_DIR}"
