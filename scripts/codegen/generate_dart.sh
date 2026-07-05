#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

usage() {
    cat <<EOF
Usage: scripts/codegen/generate_dart.sh [--skip-dart]

Generate Dart bindings via dart-lang/protobuf (protoc_plugin).

Requires:
  dart pub global activate protoc_plugin <PROTOC_GEN_DART_VERSION>
  export PATH="\$PATH:\$HOME/.pub-cache/bin"

Output: sdk/runanywhere-flutter/packages/runanywhere/lib/generated/

Options:
  --skip-dart   Explicit opt-out (honoured from generate_all.sh).
  -h, --help    Show this help.
EOF
}

for arg in "$@"; do
    case "$arg" in
        --skip-dart)
            info "--skip-dart requested; skipping Dart codegen."
            exit 0
            ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; die "unknown argument: $arg" ;;
    esac
done

PROTO_DIR="${RAC_ROOT}/idl"
OUT_DIR="${RAC_ROOT}/sdk/runanywhere-flutter/packages/runanywhere/lib/generated"

# Load PROTOC_GEN_DART_VERSION from the centralized VERSIONS file so the
# install hint below matches what toolchain.sh actually installs.
VERSIONS_FILE="${RAC_ROOT}/sdk/runanywhere-commons/VERSIONS"
if [ -f "${VERSIONS_FILE}" ]; then
    set -a
    eval "$(grep -E '^[A-Z_][A-Z0-9_]*=' "${VERSIONS_FILE}")"
    set +a
fi
PROTOC_GEN_DART_VERSION="${PROTOC_GEN_DART_VERSION:-25.0.0}"

# Pin Dart 3.0+ so local + CI runs produce byte-identical output; older combos
# emit subtly different code that trips the idl-drift-check CI gate.
if command -v dart >/dev/null 2>&1; then
    DART_VERSION="$(dart --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    if [ -n "${DART_VERSION}" ]; then
        DART_MAJOR="$(echo "${DART_VERSION}" | cut -d. -f1)"
        if [ "${DART_MAJOR}" -lt 3 ]; then
            warn "Dart ${DART_VERSION} < 3.0 detected; skipping Dart codegen."
            log "  Upgrade Dart to 3.0+ or use CI to generate the bindings."
            exit 0
        fi
    fi
else
    warn "'dart' binary not on PATH; proceeding but will fail on missing plugin."
fi

mkdir -p "${OUT_DIR}"

if ! command -v protoc >/dev/null 2>&1; then
    error "protoc not found. Run scripts/setup/toolchain.sh."
    exit 127
fi
if ! command -v protoc-gen-dart >/dev/null 2>&1; then
    error "protoc-gen-dart not found."
    log "  Install via: dart pub global activate protoc_plugin ${PROTOC_GEN_DART_VERSION}"
    log "  and add \$HOME/.pub-cache/bin to your PATH."
    exit 127
fi

# Best-effort version pin check. stdin MUST be /dev/null: protoc plugins speak
# CodeGeneratorRequest/Response over stdin/stdout, and without </dev/null the
# plugin blocks forever waiting for a request even when --version is passed.
if PLUGIN_VERSION_OUT="$(protoc-gen-dart --version </dev/null 2>&1)"; then
    if ! echo "${PLUGIN_VERSION_OUT}" | grep -q "${PROTOC_GEN_DART_VERSION}"; then
        warn "protoc_plugin version could not be verified as ${PROTOC_GEN_DART_VERSION}."
        log "  Got: ${PLUGIN_VERSION_OUT}"
        log "  Re-pin via: dart pub global activate protoc_plugin ${PROTOC_GEN_DART_VERSION}"
    fi
fi

# Canonical proto-file list from generate_all.sh, with fallback to filesystem
# discovery when invoked standalone. --dart_out without a `grpc:` prefix skips
# gRPC client stubs; descriptor JSON and server stubs are stripped below.
if [ -z "${RAC_PROTO_FILES:-}" ]; then
    RAC_PROTO_FILES="$(ls "${PROTO_DIR}"/*.proto | sort)"
fi

RAC_PROTO_EXCLUDES_DART=()

DART_PROTO_BASENAMES=()
while IFS= read -r proto_path; do
    [ -z "${proto_path}" ] && continue
    proto_base="$(basename "${proto_path}")"
    skip=0
    if [ "${#RAC_PROTO_EXCLUDES_DART[@]}" -gt 0 ]; then
        for excluded in "${RAC_PROTO_EXCLUDES_DART[@]}"; do
            if [ "${proto_base}" = "${excluded}" ]; then
                skip=1
                break
            fi
        done
    fi
    [ "${skip}" -eq 1 ] && continue
    DART_PROTO_BASENAMES+=("${proto_base}")
done <<< "${RAC_PROTO_FILES}"

protoc \
    --proto_path="${PROTO_DIR}" \
    --dart_out="${OUT_DIR}" \
    "${DART_PROTO_BASENAMES[@]}"

# Strip stubs/descriptors that are not runtime SDK surface. The convenience/
# subtree is owned by generate_dart_convenience.py and intentionally kept.
rm -f \
    "${OUT_DIR}"/*.pbgrpc.dart \
    "${OUT_DIR}"/*.pbserver.dart \
    "${OUT_DIR}"/*.pbjson.dart

ok "Dart proto codegen → ${OUT_DIR} (message/enum bindings; stubs/descriptors stripped)"
