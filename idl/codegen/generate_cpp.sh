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
# layer can `#include "model_types.pb.h"` for proto-encoded wire conversions.
# protoc emits bare filenames directly into OUT_DIR (no runanywhere/idl/
# prefix). CMake's `idl/CMakeLists.txt` generates the same files at build
# time for the `rac_idl` library and adds the generated directory to the
# include path; this script keeps a committed copy for IDE navigation + the
# CI drift check.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PROTO_DIR="${REPO_ROOT}/idl"
OUT_DIR="${REPO_ROOT}/sdk/runanywhere-commons/src/generated/proto"

mkdir -p "${OUT_DIR}"

if ! command -v protoc >/dev/null 2>&1; then
    echo "error: protoc not found. Run scripts/setup/setup-toolchain.sh." >&2
    exit 127
fi

# Canonical proto-file list from generate_all.sh, with fallback to
# filesystem discovery when invoked standalone. C++ is the authoritative
# consumer and emits every proto in idl/ — no exclusions.
if [ -z "${RAC_PROTO_FILES:-}" ]; then
    RAC_PROTO_FILES="$(ls "${PROTO_DIR}"/*.proto | sort)"
fi

CPP_PROTO_BASENAMES=()
while IFS= read -r proto_path; do
    [ -z "${proto_path}" ] && continue
    CPP_PROTO_BASENAMES+=("$(basename "${proto_path}")")
done <<< "${RAC_PROTO_FILES}"

protoc \
    --proto_path="${PROTO_DIR}" \
    --cpp_out="${OUT_DIR}" \
    "${CPP_PROTO_BASENAMES[@]}"

echo "✓ C++ proto codegen → ${OUT_DIR}"
ls -1 "${OUT_DIR}"
