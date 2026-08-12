#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Run every codegen for every language. Called from CI (idl-drift-check.yml)
# and from local workflows after edits to any *.proto file under idl/.
#
# Flags:
#   --skip-dart   Skip Dart codegen (use when Dart 3.0+ is unavailable
#                 locally; CI regenerates Dart bindings on the pinned toolchain).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
IDL_DIR="${REPO_ROOT}/idl"

SKIP_DART=0
for arg in "$@"; do
    case "$arg" in
        --skip-dart) SKIP_DART=1 ;;
        -h|--help)
            sed -n '1,15p' "$0" | sed 's/^#//'
            exit 0
            ;;
    esac
done

# Fail fast on missing toolchain rather than running 80% and breaking late.
# Each language script does its own lookup; this is just the base gate.
if ! command -v protoc >/dev/null 2>&1; then
    echo "error: protoc not on PATH." >&2
    echo "       Run scripts/setup/setup-toolchain.sh first, or install manually:" >&2
    echo "         brew install protobuf            # macOS" >&2
    echo "         apt-get install protobuf-compiler   # Ubuntu" >&2
    exit 127
fi

echo "▶ protoc version: $(protoc --version)"

# Canonical proto-file list shared with every per-language codegen
# script via the RAC_PROTO_FILES env var (absolute paths, newline-separated,
# sorted). Discovery via `ls` prevents drift when a new .proto is added — the
# full list is derived from the filesystem, and each per-language script
# applies its own documented exclusion filter (RAC_PROTO_EXCLUDES_<lang>)
# rather than duplicating the positive list. Per-language scripts fall back
# to the same `ls "$IDL_DIR"/*.proto` discovery when invoked standalone, so
# behavior is identical whether run via generate_all.sh or individually.
RAC_PROTO_FILES="$(ls "${IDL_DIR}"/*.proto | sort)"
export RAC_PROTO_FILES
echo "▶ canonical proto file list:"
echo "${RAC_PROTO_FILES}" | sed 's|^.*/|    - |'

echo "▶ Swift proto codegen"
"${SCRIPT_DIR}/generate_swift.sh"

echo "▶ Kotlin proto codegen"
"${SCRIPT_DIR}/generate_kotlin.sh"

# Emit RAConvenience.kt from rac_options.proto annotations on top of the
# Wire-generated message/enum types. Must run AFTER generate_kotlin.sh so the
# referenced types (ai.runanywhere.proto.v1.*) exist on disk; Wire emits a
# `companion object` on every message/enum, which the convenience extensions
# bind to. The post-processor exits 0 (warning) when python3 is unavailable so
# Kotlin-only developer workflows that omit Python remain unblocked.
if command -v python3 >/dev/null 2>&1; then
    python3 "${SCRIPT_DIR}/generate_kotlin_convenience.py"
else
    echo "warning: python3 not found — skipping RAConvenience.kt codegen." >&2
fi

if [ "${SKIP_DART}" -eq 1 ]; then
    echo "▶ Dart proto codegen (skipped via --skip-dart)"
else
    echo "▶ Dart proto codegen"
    "${SCRIPT_DIR}/generate_dart.sh"
    # Convenience post-processor (rac_* annotations -> defaults() / validate()
    # / wireString helpers). Tolerant of a python3-less environment: skip
    # with a warning rather than fail the upstream codegen.
    if command -v python3 >/dev/null 2>&1; then
        echo "▶ Dart convenience post-processor"
        python3 "${SCRIPT_DIR}/generate_dart_convenience.py"
    else
        echo "warning: python3 not on PATH; skipping Dart convenience post-processor." >&2
    fi
fi

echo "▶ TypeScript proto codegen (RN + Web)"
"${SCRIPT_DIR}/generate_ts.sh"
# TypeScript convenience helpers (defaults / validate /
# wireString) derived from rac_* annotations. Skips silently when python3
# is absent, so a TS-only developer environment without Python still
# completes the upstream codegen successfully.
if command -v python3 >/dev/null 2>&1; then
    python3 "${SCRIPT_DIR}/generate_ts_convenience.py"
else
    echo "warning: python3 not on PATH; skipping generate_ts_convenience.py" >&2
fi

echo "▶ C++ proto codegen"
"${SCRIPT_DIR}/generate_cpp.sh"

# C macros for every rac_default annotation. commons composes its default
# structs (RAC_LLM_OPTIONS_DEFAULT and friends) from these, so the C layer that
# actually runs inference reads the same annotations the SDKs generate against.
# Unlike the four convenience post-processors this emits a plain header and
# needs no language toolchain beyond protoc + the python protobuf runtime.
echo "▶ C defaults header"
if python3 -c 'import google.protobuf' >/dev/null 2>&1; then
    python3 "${SCRIPT_DIR}/generate_cpp_defaults.py"
else
    echo "warning: python protobuf runtime not installed; skipping generate_cpp_defaults.py" >&2
fi

# Swift / Kotlin / Dart / TypeScript constants for the central default pool.
# sdk_defaults.proto is excluded from the four message generators above, so its
# values reach the SDKs as plain constants rather than as a generated message
# type nobody puts on a wire.
echo "▶ Default pool constants (Swift/Kotlin/Dart/TS)"
if python3 -c 'import google.protobuf' >/dev/null 2>&1; then
    python3 "${SCRIPT_DIR}/generate_defaults_pool.py"
else
    echo "warning: python protobuf runtime not installed; skipping generate_defaults_pool.py" >&2
fi

# AsyncIterable<T> stream wrappers for RN + Web. The
# template-based renderer is intentionally separate from generate_ts.sh
# (which uses ts-proto for messages) — different tools, different outputs.
#
# A single shared script renders the streams once into
# bindings/proto-ts/src/streams. Both RN and Web consume the result via
# @runanywhere/proto-ts; the previous generate_rn_streams.sh /
# generate_web_streams.sh pair was byte-identical and overwrote each
# other's output, masking unilateral edits.
echo "▶ Shared TS AsyncIterable streams"
"${SCRIPT_DIR}/generate_streams.sh"

# Python protobuf for the RAG surface (optional — needs grpcio-tools). Soft-skip
# when the package is missing so a non-Python developer environment still
# completes the upstream codegen; CI installs grpcio-tools and fails on drift.
echo "▶ Python proto codegen (RAG)"
if python3 -c 'import grpc_tools.protoc' >/dev/null 2>&1; then
    "${SCRIPT_DIR}/generate_python.sh"
else
    echo "warning: grpcio-tools not installed; skipping generate_python.sh" >&2
fi

# Python's ErrorCode / ErrorCategory. The Python SDK has no convenience
# post-processor because it reaches the C ABI directly for everything but RAG,
# so these 139 enum members were transcribed by hand under a "keep in sync"
# docstring. Only protoc + the python protobuf runtime are needed here, not
# grpcio-tools.
echo "▶ Python error enums"
if python3 -c 'import google.protobuf' >/dev/null 2>&1; then
    python3 "${SCRIPT_DIR}/generate_python_errors.py"
else
    echo "warning: python protobuf runtime not installed; skipping generate_python_errors.py" >&2
fi

echo "✓ All proto codegen complete."
