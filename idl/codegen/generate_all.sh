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

# Deterministic environment. Every generator below must emit the same bytes on
# a developer laptop and on a CI runner, so the few ambient inputs that can
# reorder or reformat output are pinned here rather than inherited:
#   LC_ALL/LANG  — collation for every `sort` in this pipeline (glibc's
#                  en_US.UTF-8 ignores punctuation at the primary level, so
#                  `rac_options.proto` vs `rag.proto` can order differently
#                  than under C).
#   TZ           — any generator that formats a date would otherwise embed the
#                  runner's local time.
#   PYTHONHASHSEED — the convenience generators walk descriptor sets; a stray
#                  set/frozenset iteration would otherwise be seed-dependent.
export LC_ALL=C
export LANG=C
export TZ=UTC
export PYTHONHASHSEED=0

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

# protoc bakes its own major.minor.patch into the C++ headers
# ("#if PROTOBUF_VERSION != 7035001") and into every ts-proto file header
# ("//   protoc               v7.35.1"). A different protoc therefore rewrites
# 144 committed files without a single .proto having changed. Fail closed on
# the exact pin in core/VERSIONS so that shows up as one actionable error here
# rather than as an unexplained diff in the drift gate.
VERSIONS_FILE="${REPO_ROOT}/core/VERSIONS"
if [ -f "${VERSIONS_FILE}" ]; then
    set -a
    eval "$(grep -E '^[A-Z_][A-Z0-9_]*=' "${VERSIONS_FILE}")"
    set +a
fi

PROTOC_ACTUAL="$(protoc --version | awk '{print $2}')"
echo "▶ protoc version: ${PROTOC_ACTUAL} (pinned ${PROTOC_VERSION:-${PROTOC_VERSION_MAJOR:-any}})"
if [ -n "${PROTOC_VERSION:-}" ] && [ "${PROTOC_ACTUAL}" != "${PROTOC_VERSION}" ]; then
    echo "error: protoc ${PROTOC_ACTUAL} does not match the pinned ${PROTOC_VERSION}" >&2
    echo "       (core/VERSIONS::PROTOC_VERSION). Generated C++ and TypeScript" >&2
    echo "       embed the compiler version, so regenerating with a different" >&2
    echo "       protoc rewrites 144 committed files and breaks the drift gate." >&2
    echo "       Install the pinned release, or bump PROTOC_VERSION and" >&2
    echo "       regenerate every binding in the same commit." >&2
    exit 1
fi

# Canonical proto-file list shared with every per-language codegen
# script via the RAC_PROTO_FILES env var (absolute paths, newline-separated,
# sorted). Discovery via `ls` prevents drift when a new .proto is added — the
# full list is derived from the filesystem, and each per-language script
# applies its own documented exclusion filter (RAC_PROTO_EXCLUDES_<lang>)
# rather than duplicating the positive list. Per-language scripts fall back
# to the same `ls "$IDL_DIR"/*.proto` discovery when invoked standalone, so
# behavior is identical whether run via generate_all.sh or individually.
RAC_PROTO_FILES="$(ls "${IDL_DIR}"/*.proto | LC_ALL=C sort)"
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
        # ra_result_codes.dart is codegen output (ErrorCode -> user-facing
        # message table derived from idl/errors.proto), but nothing used to
        # invoke its generator, so the file was committed once and then aged
        # out of the drift gate: an errors.proto edit could not make it stale
        # in CI because CI never regenerated it. Run it here so the one gate
        # that guards generated code actually covers it.
        echo "▶ Dart result-code messages"
        python3 "${SCRIPT_DIR}/generate_dart_result_codes.py"
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
