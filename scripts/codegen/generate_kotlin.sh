#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

usage() {
    cat <<EOF
Usage: scripts/codegen/generate_kotlin.sh

Generate Kotlin bindings via Square Wire (pure Kotlin data classes, no Java
protobuf dependency).

Requires: brew install wire (or the Wire Gradle plugin regenerates at build
time in sdk/runanywhere-kotlin/).

Output: sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/generated/
EOF
}

for arg in "$@"; do
    case "$arg" in
        -h|--help) usage; exit 0 ;;
        *) usage >&2; die "unknown argument: $arg" ;;
    esac
done

PROTO_DIR="${RAC_ROOT}/idl"
OUT_DIR="${RAC_ROOT}/sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/generated"

mkdir -p "${OUT_DIR}"

if command -v wire-compiler >/dev/null 2>&1; then
    # Canonical proto-file list from generate_all.sh, with fallback to
    # filesystem discovery when invoked standalone. No exclusions today —
    # Wire does not transitively emit enum-only dependencies, so the full
    # positive list is required.
    if [ -z "${RAC_PROTO_FILES:-}" ]; then
        RAC_PROTO_FILES="$(ls "${PROTO_DIR}"/*.proto | sort)"
    fi

    RAC_PROTO_EXCLUDES_KOTLIN=()

    KOTLIN_PROTO_BASENAMES=()
    while IFS= read -r proto_path; do
        [ -z "${proto_path}" ] && continue
        proto_base="$(basename "${proto_path}")"
        skip=0
        for excluded in "${RAC_PROTO_EXCLUDES_KOTLIN[@]:-}"; do
            if [ "${proto_base}" = "${excluded}" ]; then
                skip=1
                break
            fi
        done
        [ "${skip}" -eq 1 ] && continue
        KOTLIN_PROTO_BASENAMES+=("${proto_base}")
    done <<< "${RAC_PROTO_FILES}"

    # Pre-clean the Wire-owned subtree so types removed or renamed in the IDL
    # cannot linger as committed orphans (wire-compiler writes, never deletes).
    # Hand-written code under the same generated/ root is preserved.
    if [ -d "${OUT_DIR}/ai/runanywhere/proto/v1" ]; then
        find "${OUT_DIR}/ai/runanywhere/proto/v1" -name "*.kt" -delete
    fi

    wire-compiler \
        --proto_path="${PROTO_DIR}" \
        --kotlin_out="${OUT_DIR}" \
        "${KOTLIN_PROTO_BASENAMES[@]}"

    # Wire 4.x emits gRPC client stubs that depend on wire-grpc-client, which
    # the SDK does not carry. The hand-written stream adapters consume the
    # message types directly, so strip the stubs to keep regen green.
    find "${OUT_DIR}/ai/runanywhere/proto/v1/" -name "*Client.kt" -delete
    find "${OUT_DIR}/ai/runanywhere/proto/v1/" -name "Grpc*Client.kt" -delete

    ok "Kotlin proto codegen → ${OUT_DIR} (gRPC client stubs stripped)"
else
    warn "wire-compiler not on PATH."
    log "  The Gradle Wire plugin in sdk/runanywhere-kotlin/build.gradle.kts"
    log "  will regenerate at build time. For one-off CLI runs, install via"
    log "  'brew install wire' (macOS) or download from"
    log "  https://github.com/square/wire/releases"
fi
