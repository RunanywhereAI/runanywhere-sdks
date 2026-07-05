#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

usage() {
    cat <<EOF
Usage: scripts/codegen/generate_ts.sh

Generate shared TypeScript bindings via ts-proto for React Native and Web.

Requires the pinned ts-proto version from
sdk/runanywhere-commons/VERSIONS::TS_PROTO_VERSION; install via
scripts/setup/toolchain.sh or 'npm install -g ts-proto@<version>'.

Output: sdk/shared/proto-ts/src/
EOF
}

for arg in "$@"; do
    case "$arg" in
        -h|--help) usage; exit 0 ;;
        *) usage >&2; die "unknown argument: $arg" ;;
    esac
done

PROTO_DIR="${RAC_ROOT}/idl"
TS_OUT_DIR="${RAC_ROOT}/sdk/shared/proto-ts/src"

# Load TS_PROTO_VERSION from the centralized VERSIONS file so the install hint
# below matches what toolchain.sh actually installs.
VERSIONS_FILE="${RAC_ROOT}/sdk/runanywhere-commons/VERSIONS"
if [ -f "${VERSIONS_FILE}" ]; then
    set -a
    eval "$(grep -E '^[A-Z_][A-Z0-9_]*=' "${VERSIONS_FILE}")"
    set +a
fi
TS_PROTO_VERSION="${TS_PROTO_VERSION:-1.181.1}"

mkdir -p "${TS_OUT_DIR}"

if ! command -v protoc >/dev/null 2>&1; then
    error "protoc not found. Run scripts/setup/toolchain.sh."
    exit 127
fi

# Resolve the ts-proto plugin that `npm install -g ts-proto` provides. On some
# systems (nvm, asdf) `npm root -g` points at a user-local path — both work.
TS_PROTO_PLUGIN="$(npm root -g 2>/dev/null)/ts-proto/protoc-gen-ts_proto"
if [ ! -x "${TS_PROTO_PLUGIN}" ]; then
    error "ts-proto plugin not found at ${TS_PROTO_PLUGIN}"
    log "  Install via: npm install -g ts-proto@${TS_PROTO_VERSION}"
    exit 127
fi

# Canonical proto-file list from generate_all.sh, with fallback to filesystem
# discovery when invoked standalone. No exclusions today.
if [ -z "${RAC_PROTO_FILES:-}" ]; then
    RAC_PROTO_FILES="$(ls "${PROTO_DIR}"/*.proto | sort)"
fi

RAC_PROTO_EXCLUDES_TS=()

TS_PROTO_BASENAMES=()
while IFS= read -r proto_path; do
    [ -z "${proto_path}" ] && continue
    proto_base="$(basename "${proto_path}")"
    skip=0
    if [ "${#RAC_PROTO_EXCLUDES_TS[@]}" -gt 0 ]; then
        for excluded in "${RAC_PROTO_EXCLUDES_TS[@]}"; do
            if [ "${proto_base}" = "${excluded}" ]; then
                skip=1
                break
            fi
        done
    fi
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

ok "TS proto codegen → ${TS_OUT_DIR}"
