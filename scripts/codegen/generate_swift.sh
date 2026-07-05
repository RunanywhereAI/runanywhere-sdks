#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

usage() {
    cat <<EOF
Usage: scripts/codegen/generate_swift.sh

Generate Swift bindings via apple/swift-protobuf.

Requires: brew install protobuf swift-protobuf

Output: sdk/runanywhere-swift/Sources/RunAnywhere/Generated/
EOF
}

for arg in "$@"; do
    case "$arg" in
        -h|--help) usage; exit 0 ;;
        *) usage >&2; die "unknown argument: $arg" ;;
    esac
done

PROTO_DIR="${RAC_ROOT}/idl"
OUT_DIR="${RAC_ROOT}/sdk/runanywhere-swift/Sources/RunAnywhere/Generated"

mkdir -p "${OUT_DIR}"

if ! command -v protoc >/dev/null 2>&1; then
    error "protoc not found. Run scripts/setup/toolchain.sh."
    exit 127
fi
if ! command -v protoc-gen-swift >/dev/null 2>&1; then
    error "protoc-gen-swift not found."
    log "  Install via 'brew install swift-protobuf' or build from source."
    exit 127
fi

# Canonical proto-file list from generate_all.sh, with fallback to filesystem
# discovery when invoked standalone.
if [ -z "${RAC_PROTO_FILES:-}" ]; then
    RAC_PROTO_FILES="$(ls "${PROTO_DIR}"/*.proto | sort)"
fi

# Language-specific exclusions (basenames). Empty today — every schema in
# idl/ is emitted for Swift.
RAC_PROTO_EXCLUDES_SWIFT=()

MESSAGE_PROTOS=()
while IFS= read -r proto_path; do
    [ -z "${proto_path}" ] && continue
    proto_base="$(basename "${proto_path}")"
    skip=0
    if [ "${#RAC_PROTO_EXCLUDES_SWIFT[@]}" -gt 0 ]; then
        for excluded in "${RAC_PROTO_EXCLUDES_SWIFT[@]}"; do
            if [ "${proto_base}" = "${excluded}" ]; then
                skip=1
                break
            fi
        done
    fi
    [ "${skip}" -eq 1 ] && continue
    MESSAGE_PROTOS+=("${proto_path}")
done <<< "${RAC_PROTO_FILES}"

protoc \
    --proto_path="${PROTO_DIR}" \
    --swift_out="Visibility=Public:${OUT_DIR}" \
    "${MESSAGE_PROTOS[@]}"

ok "Swift proto codegen → ${OUT_DIR}"

# *.grpc.swift stubs require GRPCCore/GRPCProtobuf (macOS 15 / iOS 18, above
# our minimums). Streaming goes through hand-written AsyncStream adapters, so
# strip any stubs an older toolchain may emit to keep CI byte-deterministic.
rm -f "${OUT_DIR}"/*.grpc.swift

# RAConvenience.swift from rac_options.proto annotations, plus
# ModalityProtoABI+Generated.swift from swift-modality-abi.yaml.
if command -v python3 >/dev/null 2>&1; then
    python3 "${SCRIPT_DIR}/generate_swift_convenience.py"
    python3 "${SCRIPT_DIR}/generate_swift_modality_abi.py"
else
    warn "python3 not found — skipping RAConvenience.swift + ModalityProtoABI codegen."
fi

ls -1 "${OUT_DIR}"
