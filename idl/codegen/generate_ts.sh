#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Generate TypeScript bindings via ts-proto for React Native AND Web targets.
#
# Requirements:
#   npm install -g ts-proto@1.181.1 protobufjs
#
# Output:
#   sdk/runanywhere-react-native/packages/core/src/generated/
#   sdk/runanywhere-web/packages/core/src/generated/
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PROTO_DIR="${REPO_ROOT}/idl"
RN_OUT_DIR="${REPO_ROOT}/sdk/runanywhere-react-native/packages/core/src/generated"
WEB_OUT_DIR="${REPO_ROOT}/sdk/runanywhere-web/packages/core/src/generated"

mkdir -p "${RN_OUT_DIR}" "${WEB_OUT_DIR}"

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

# RN target: env=node works for both RN and the metro packager's Node parser.
protoc \
    --plugin=protoc-gen-ts_proto="${TS_PROTO_PLUGIN}" \
    --proto_path="${PROTO_DIR}" \
    --ts_proto_out="${RN_OUT_DIR}" \
    --ts_proto_opt=esModuleInterop=true,outputServices=false,env=node,useOptionals=messages \
    model_types.proto voice_events.proto pipeline.proto solutions.proto

echo "✓ TS (RN) proto codegen → ${RN_OUT_DIR}"

# Web target: env=browser enables different Buffer/Uint8Array handling.
protoc \
    --plugin=protoc-gen-ts_proto="${TS_PROTO_PLUGIN}" \
    --proto_path="${PROTO_DIR}" \
    --ts_proto_out="${WEB_OUT_DIR}" \
    --ts_proto_opt=esModuleInterop=true,outputServices=false,env=browser,useOptionals=messages \
    model_types.proto voice_events.proto pipeline.proto solutions.proto

echo "✓ TS (Web) proto codegen → ${WEB_OUT_DIR}"
