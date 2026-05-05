#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Generate shared TypeScript bindings via ts-proto for React Native and Web.
#
# Requirements:
#   npm install -g ts-proto@1.181.1 protobufjs
#
# Output:
#   sdk/runanywhere-proto-ts/src/
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PROTO_DIR="${REPO_ROOT}/idl"
TS_OUT_DIR="${REPO_ROOT}/sdk/runanywhere-proto-ts/src"

mkdir -p "${TS_OUT_DIR}"

if ! command -v protoc >/dev/null 2>&1; then
    echo "error: protoc not found. Run scripts/setup-toolchain.sh." >&2
    exit 127
fi

# Resolve the ts-proto plugin that `npm install -g ts-proto` provides. On some
# systems (nvm, asdf) `npm root -g` points at a user-local path — both work.
TS_PROTO_PLUGIN="$(npm root -g 2>/dev/null)/ts-proto/protoc-gen-ts_proto"
if [ ! -x "${TS_PROTO_PLUGIN}" ]; then
    echo "error: ts-proto plugin not found at ${TS_PROTO_PLUGIN}" >&2
    echo "       Install via: npm install -g ts-proto@1.181.1" >&2
    exit 127
fi

# IDL-19c: canonical proto-file list from generate_all.sh, with fallback to
# filesystem discovery when invoked standalone. TS excludes:
#   - component_types.proto — ts-proto auto-emits its message types
#     transitively via dependent protos' imports, so passing it explicitly
#     is redundant. Exclusion keeps the positive list minimal.
#   - router.proto — engine-router capability-query types are consumed only
#     by C++/Kotlin; RN/Web call commons through NitroModules/WASM bindings
#     without needing generated router.ts.
if [ -z "${RAC_PROTO_FILES:-}" ]; then
    RAC_PROTO_FILES="$(ls "${PROTO_DIR}"/*.proto | sort)"
fi

RAC_PROTO_EXCLUDES_TS=(
    "component_types.proto"
    "router.proto"
)

TS_PROTO_BASENAMES=()
while IFS= read -r proto_path; do
    [ -z "${proto_path}" ] && continue
    proto_base="$(basename "${proto_path}")"
    skip=0
    for excluded in "${RAC_PROTO_EXCLUDES_TS[@]}"; do
        if [ "${proto_base}" = "${excluded}" ]; then
            skip=1
            break
        fi
    done
    [ "${skip}" -eq 1 ] && continue
    TS_PROTO_BASENAMES+=("${proto_base}")
done <<< "${RAC_PROTO_FILES}"

# Shared target: env=browser keeps bytes as Uint8Array, which works in Web and
# React Native without coupling generated code to global Buffer.
protoc \
    --plugin=protoc-gen-ts_proto="${TS_PROTO_PLUGIN}" \
    --proto_path="${PROTO_DIR}" \
    --ts_proto_out="${TS_OUT_DIR}" \
    --ts_proto_opt=esModuleInterop=true,outputServices=false,env=browser,useOptionals=messages \
    "${TS_PROTO_BASENAMES[@]}"

echo "✓ TS proto codegen → ${TS_OUT_DIR}"
