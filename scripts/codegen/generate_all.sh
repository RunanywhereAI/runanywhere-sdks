#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

IDL_DIR="${RAC_ROOT}/idl"

usage() {
    cat <<EOF
Usage: scripts/codegen/generate_all.sh [--skip-dart]

Run proto codegen for every language (Swift, Kotlin, Dart, TypeScript, C++)
plus the convenience post-processors and shared TS stream wrappers.

Options:
  --skip-dart   Skip Dart codegen (use when Dart 3.0+ is unavailable locally;
                CI regenerates Dart bindings on the pinned toolchain).
  -h, --help    Show this help.
EOF
}

SKIP_DART=0
for arg in "$@"; do
    case "$arg" in
        --skip-dart) SKIP_DART=1 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; die "unknown argument: $arg" ;;
    esac
done

# Fail fast on missing toolchain rather than running 80% and breaking late.
if ! command -v protoc >/dev/null 2>&1; then
    error "protoc not on PATH."
    log "  Run scripts/setup/toolchain.sh first, or install manually:"
    log "    brew install protobuf                 # macOS"
    log "    apt-get install protobuf-compiler     # Ubuntu"
    exit 127
fi

info "protoc version: $(protoc --version)"

# Canonical proto-file list shared with every per-language script via
# RAC_PROTO_FILES (absolute paths, newline-separated, sorted). Per-language
# scripts fall back to the same discovery when invoked standalone.
RAC_PROTO_FILES="$(ls "${IDL_DIR}"/*.proto | sort)"
export RAC_PROTO_FILES
info "canonical proto file list:"
echo "${RAC_PROTO_FILES}" | sed 's|^.*/|    - |' >&2

step "Swift proto codegen"
"${SCRIPT_DIR}/generate_swift.sh"

step "Kotlin proto codegen"
"${SCRIPT_DIR}/generate_kotlin.sh"

# RAConvenience.kt is derived from rac_options.proto annotations on top of the
# Wire-generated types, so it must run after generate_kotlin.sh.
if command -v python3 >/dev/null 2>&1; then
    python3 "${SCRIPT_DIR}/generate_kotlin_convenience.py"
else
    warn "python3 not found — skipping RAConvenience.kt codegen."
fi

if [ "${SKIP_DART}" -eq 1 ]; then
    step "Dart proto codegen (skipped via --skip-dart)"
else
    step "Dart proto codegen"
    "${SCRIPT_DIR}/generate_dart.sh"
    if command -v python3 >/dev/null 2>&1; then
        info "Dart convenience post-processor"
        python3 "${SCRIPT_DIR}/generate_dart_convenience.py"
    else
        warn "python3 not on PATH; skipping Dart convenience post-processor."
    fi
fi

step "TypeScript proto codegen (RN + Web)"
"${SCRIPT_DIR}/generate_ts.sh"
if command -v python3 >/dev/null 2>&1; then
    python3 "${SCRIPT_DIR}/generate_ts_convenience.py"
else
    warn "python3 not on PATH; skipping generate_ts_convenience.py"
fi

step "C++ proto codegen"
"${SCRIPT_DIR}/generate_cpp.sh"

# Shared AsyncIterable<T> stream wrappers for RN + Web; separate from
# generate_ts.sh (template renderer vs ts-proto messages).
step "Shared TS AsyncIterable streams"
"${SCRIPT_DIR}/generate_streams.sh"

ok "All proto codegen complete."
