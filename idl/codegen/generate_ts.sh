#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Generate TypeScript bindings via ts-proto.
#
# Requirements:
#   npm install -g ts-proto protobufjs
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PROTO_DIR="${REPO_ROOT}/idl"
TS_OUT_DIR="${REPO_ROOT}/frontends/ts/src/generated"
WEB_OUT_DIR="${REPO_ROOT}/frontends/web/src/generated"

mkdir -p "${TS_OUT_DIR}" "${WEB_OUT_DIR}"

if ! command -v protoc >/dev/null 2>&1; then
    echo "error: protoc not found" >&2
    exit 127
fi

# Resolve the ts-proto plugin that `npm install -g ts-proto` provides.
TS_PROTO_PLUGIN="$(npm root -g 2>/dev/null)/ts-proto/protoc-gen-ts_proto"
if [ ! -x "${TS_PROTO_PLUGIN}" ]; then
    echo "error: ts-proto plugin not found at ${TS_PROTO_PLUGIN}" >&2
    echo "       install via 'npm install -g ts-proto'" >&2
    exit 127
fi

for OUT in "${TS_OUT_DIR}" "${WEB_OUT_DIR}"; do
    protoc \
        --plugin=protoc-gen-ts_proto="${TS_PROTO_PLUGIN}" \
        --proto_path="${PROTO_DIR}" \
        --ts_proto_out="${OUT}" \
        --ts_proto_opt=esModuleInterop=true,outputServices=false,env=browser \
        voice_events.proto pipeline.proto solutions.proto
    echo "✓ TS proto codegen → ${OUT}"
done
