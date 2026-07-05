#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

usage() {
    cat <<EOF
Usage: scripts/codegen/generate_cpp.sh

Generate C++ bindings via protoc --cpp_out.

Requires protoc (brew install protobuf / apt-get install protobuf-compiler).

Output: sdk/runanywhere-commons/src/generated/proto/
The generated headers live inside sdk/runanywhere-commons so the C ABI shim
layer can #include "model_types.pb.h"; this committed copy is the single
source the rac_commons build compiles and also serves the CI drift check.
EOF
}

for arg in "$@"; do
    case "$arg" in
        -h|--help) usage; exit 0 ;;
        *) usage >&2; die "unknown argument: $arg" ;;
    esac
done

PROTO_DIR="${RAC_ROOT}/idl"
OUT_DIR="${RAC_ROOT}/sdk/runanywhere-commons/src/generated/proto"

mkdir -p "${OUT_DIR}"

if ! command -v protoc >/dev/null 2>&1; then
    error "protoc not found. Run scripts/setup/toolchain.sh."
    exit 127
fi

# Canonical proto-file list from generate_all.sh, with fallback to filesystem
# discovery when invoked standalone. C++ emits every proto — no exclusions.
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

ok "C++ proto codegen → ${OUT_DIR}"
ls -1 "${OUT_DIR}"
