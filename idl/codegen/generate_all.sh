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
    echo "       Run scripts/setup-toolchain.sh first, or install manually:" >&2
    echo "         brew install protobuf            # macOS" >&2
    echo "         apt-get install protobuf-compiler   # Ubuntu" >&2
    exit 127
fi

echo "▶ protoc version: $(protoc --version)"

# IDL-19c: canonical proto-file list shared with every per-language codegen
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

if [ "${SKIP_DART}" -eq 1 ]; then
    echo "▶ Dart proto codegen (skipped via --skip-dart)"
else
    echo "▶ Dart proto codegen"
    "${SCRIPT_DIR}/generate_dart.sh"
fi

echo "▶ TypeScript proto codegen (RN + Web)"
"${SCRIPT_DIR}/generate_ts.sh"

echo "▶ C++ proto codegen"
"${SCRIPT_DIR}/generate_cpp.sh"

# GAP 09 Phase 14: AsyncIterable<T> stream wrappers for RN + Web. The
# template-based renderer is intentionally separate from generate_ts.sh
# (which uses ts-proto for messages) — different tools, different outputs.
echo "▶ RN AsyncIterable streams (GAP 09)"
"${SCRIPT_DIR}/generate_rn_streams.sh"

echo "▶ Web AsyncIterable streams (GAP 09)"
"${SCRIPT_DIR}/generate_web_streams.sh"

echo "✓ All proto codegen complete."
