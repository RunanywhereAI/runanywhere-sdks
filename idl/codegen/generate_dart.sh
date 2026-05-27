#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Generate Dart bindings via dart-lang/protobuf (protoc_plugin).
#
# Requirements:
#   dart pub global activate protoc_plugin ${PROTOC_GEN_DART_VERSION}
#   export PATH="$PATH:$HOME/.pub-cache/bin"
#
# Output:
#   sdk/runanywhere-flutter/packages/runanywhere/lib/generated/
#
# Supports flags:
#   --skip-dart   Explicit opt-out (honoured from generate_all.sh).
set -euo pipefail

for arg in "$@"; do
    case "$arg" in
        --skip-dart)
            echo "note: --skip-dart requested; skipping Dart codegen."
            exit 0
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PROTO_DIR="${REPO_ROOT}/idl"
OUT_DIR="${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere/lib/generated"

# Load PROTOC_GEN_DART_VERSION from the centralized VERSIONS file so the
# install hint below matches what setup-toolchain.sh actually installs.
VERSIONS_FILE="${REPO_ROOT}/sdk/runanywhere-commons/VERSIONS"
if [ -f "${VERSIONS_FILE}" ]; then
    set -a
    eval "$(grep -E '^[A-Z_][A-Z0-9_]*=' "${VERSIONS_FILE}")"
    set +a
fi
PROTOC_GEN_DART_VERSION="${PROTOC_GEN_DART_VERSION:-25.0.0}"

# IDL-16 / CPP-10: pin Dart + protoc_plugin versions so local + CI runs
# produce byte-identical output. Older Dart / protoc_plugin combos emit
# subtly different code (e.g. accidental .pbgrpc.dart) that trips the
# idl-drift-check CI gate on unrelated PRs.
if command -v dart >/dev/null 2>&1; then
    DART_VERSION="$(dart --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    if [ -n "${DART_VERSION}" ]; then
        DART_MAJOR="$(echo "${DART_VERSION}" | cut -d. -f1)"
        if [ "${DART_MAJOR}" -lt 3 ]; then
            echo "warning: Dart ${DART_VERSION} < 3.0 detected; skipping Dart codegen." >&2
            echo "         Upgrade Dart to 3.0+ or use CI to generate the bindings." >&2
            exit 0
        fi
    fi
else
    echo "warning: 'dart' binary not on PATH; proceeding but will fail on missing plugin." >&2
fi

mkdir -p "${OUT_DIR}"

if ! command -v protoc >/dev/null 2>&1; then
    echo "error: protoc not found. Run scripts/setup-toolchain.sh." >&2
    exit 127
fi
if ! command -v protoc-gen-dart >/dev/null 2>&1; then
    echo "error: protoc-gen-dart not found." >&2
    echo "       Install via: dart pub global activate protoc_plugin ${PROTOC_GEN_DART_VERSION}" >&2
    echo "       and add \$HOME/.pub-cache/bin to your PATH." >&2
    exit 127
fi

# IDL-16 / CPP-10: verify protoc_plugin is pinned at PROTOC_GEN_DART_VERSION
# (loaded from VERSIONS). The plugin does not expose --version in older
# releases; fall back to a best-effort check.
#
# IMPORTANT: stdin must be redirected from /dev/null. protoc plugins (including
# protoc_plugin) implement the CodeGeneratorRequest/Response protocol over
# stdin/stdout — if stdin is left attached to a terminal or a parent's stdin,
# the plugin blocks indefinitely waiting for a request, even when --version is
# passed. Without `</dev/null` this hangs generate_dart.sh forever when run
# from generate_all.sh.
if PLUGIN_VERSION_OUT="$(protoc-gen-dart --version </dev/null 2>&1)"; then
    if ! echo "${PLUGIN_VERSION_OUT}" | grep -q "${PROTOC_GEN_DART_VERSION}"; then
        echo "warning: protoc_plugin version could not be verified as ${PROTOC_GEN_DART_VERSION}." >&2
        echo "         Got: ${PLUGIN_VERSION_OUT}" >&2
        echo "         Re-pin via: dart pub global activate protoc_plugin ${PROTOC_GEN_DART_VERSION}" >&2
    fi
fi

# IDL-19c: canonical proto-file list from generate_all.sh, with fallback to
# filesystem discovery when invoked standalone.
# IDL-19b: router.proto is now included (empty exclusion list) so Flutter has
# future-proof parity with Kotlin / C++; no active Dart consumer today, but
# generated router.pb.dart exists for symmetry.
#
# Using `--dart_out=<dir>` (no `grpc:` prefix) skips the gRPC client stubs
# for services (voice_agent_service, llm_service, download_service). The
# dart-lang plugin still emits descriptor JSON and server stubs
# (`*.pbjson.dart` / `*.pbserver.dart`), so this script strips them below.
# Flutter keeps only the runtime message/enum files (`*.pb.dart` and
# `*.pbenum.dart`). Streaming flows through the
# hand-written VoiceAgentStreamAdapter / LLMStreamAdapter over
# rac_*_set_proto_callback instead.
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

# Belt-and-braces: strip stubs/descriptors that are not runtime SDK surface.
# (The convenience subtree under ${OUT_DIR}/convenience/ is owned by
# generate_dart_convenience.py and intentionally NOT stripped here.)
rm -f \
    "${OUT_DIR}"/*.pbgrpc.dart \
    "${OUT_DIR}"/*.pbserver.dart \
    "${OUT_DIR}"/*.pbjson.dart

echo "✓ Dart proto codegen → ${OUT_DIR} (message/enum bindings; stubs/descriptors stripped)"
