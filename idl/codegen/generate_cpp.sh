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
#   core/src/generated/proto/
#
# The generated headers live inside core so the C ABI shim
# layer can `#include "model_types.pb.h"` for proto-encoded wire conversions.
# protoc emits bare filenames directly into OUT_DIR (no runanywhere/idl/
# prefix). This committed copy is the single source the rac_commons build
# compiles (via its own *.pb.cc list in core/CMakeLists.txt);
# it also serves IDE navigation + the CI drift check.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PROTO_DIR="${REPO_ROOT}/idl"
OUT_DIR="${REPO_ROOT}/core/src/generated/proto"

mkdir -p "${OUT_DIR}"

# The pinned protoc, obtained rather than assumed — see bootstrap_protoc.sh.
# generate_all.sh already put it on PATH; this repeats the resolution for a
# standalone invocation (CMake's RAC_REGENERATE_PROTO path calls this script
# directly) and costs nothing when PATH is already correct.
if ! PROTOC_BIN="$("${SCRIPT_DIR}/bootstrap_protoc.sh")"; then
    echo "error: could not obtain the pinned protoc (see above)." >&2
    exit 127
fi
PATH="$(dirname "${PROTOC_BIN}"):${PATH}"
export PATH

# Canonical proto-file list from generate_all.sh, with fallback to
# filesystem discovery when invoked standalone. C++ is the authoritative
# consumer and emits every proto in idl/ except the declaration-only pool.
if [ -z "${RAC_PROTO_FILES:-}" ]; then
    RAC_PROTO_FILES="$(ls "${PROTO_DIR}"/*.proto | LC_ALL=C sort)"
fi

# sdk_defaults.proto carries rac_default annotations and no wire messages.
# commons consumes it as macros via idl/codegen/generate_cpp_defaults.py
# (include/rac/rac_defaults_generated.h), so message classes here would be dead
# weight that also has to be listed in the CMakeLists *.pb.cc set. Mirrors
# DECLARATION_ONLY_FILES in idl/codegen/_convenience_common.py.
RAC_PROTO_EXCLUDES_CPP=(sdk_defaults.proto)

CPP_PROTO_BASENAMES=()
while IFS= read -r proto_path; do
    [ -z "${proto_path}" ] && continue
    proto_base="$(basename "${proto_path}")"
    skip=0
    for excluded in "${RAC_PROTO_EXCLUDES_CPP[@]}"; do
        if [ "${proto_base}" = "${excluded}" ]; then
            skip=1
            break
        fi
    done
    [ "${skip}" -eq 1 ] && continue
    CPP_PROTO_BASENAMES+=("${proto_base}")
done <<< "${RAC_PROTO_FILES}"

# Run from idl/ with RELATIVE paths on both sides.
#
# protoc is a native binary; under Git Bash the shell hands it MSYS-style
# arguments (`--proto_path=/c/Users/...`) and relies on MSYS's argument
# conversion heuristic to rewrite them into `C:/Users/...`. That heuristic is
# not something to bet the Windows build on. Relative paths need no conversion
# at all, and the output is byte-identical: what protoc embeds in the generated
# code is each file's name relative to --proto_path, which is the basename
# either way.
(
    cd "${PROTO_DIR}"
    protoc \
        --proto_path=. \
        --cpp_out=../core/src/generated/proto \
        "${CPP_PROTO_BASENAMES[@]}"
)

echo "✓ C++ proto codegen → ${OUT_DIR}"
ls -1 "${OUT_DIR}"
