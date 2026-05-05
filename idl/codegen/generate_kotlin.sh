#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Generate Kotlin bindings via Square Wire.
#
# Requirements (one of):
#   brew install wire                                 # wire-compiler binary
#   (or) Gradle's com.squareup.wire:wire-gradle-plugin:4.9.9 in
#        sdk/runanywhere-kotlin/build.gradle.kts
#
# Output:
#   sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/generated/
#
# Wire emits pure Kotlin data classes with no Java protobuf dependency, which
# keeps KMP's commonMain source set portable.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PROTO_DIR="${REPO_ROOT}/idl"
OUT_DIR="${REPO_ROOT}/sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/generated"

mkdir -p "${OUT_DIR}"

if command -v wire-compiler >/dev/null 2>&1; then
    # Wire emits pure Kotlin data classes for messages. GAP 09 service
    # definitions are passed too — Wire treats `service { rpc ... }` blocks
    # as informational and emits the message types only. The streaming
    # client wrapper is hand-written in
    # sdk/runanywhere-kotlin/src/jvmAndroidMain/kotlin/.../adapters/
    # using kotlinx.coroutines Flow + the Wire-generated message types.
    #
    # IDL-19c: canonical proto-file list from generate_all.sh, with fallback
    # to filesystem discovery when invoked standalone.
    # Kotlin excludes component_types.proto — Wire auto-emits its message
    # types (ComponentLifecycleState, EventCategory) transitively via
    # `import "component_types.proto"` in dependent protos, so passing it
    # explicitly would be a no-op. The exclusion keeps the positive list
    # minimal and matches historical behaviour.
    if [ -z "${RAC_PROTO_FILES:-}" ]; then
        RAC_PROTO_FILES="$(ls "${PROTO_DIR}"/*.proto | sort)"
    fi

    RAC_PROTO_EXCLUDES_KOTLIN=(
        "component_types.proto"
    )

    KOTLIN_PROTO_BASENAMES=()
    while IFS= read -r proto_path; do
        [ -z "${proto_path}" ] && continue
        proto_base="$(basename "${proto_path}")"
        skip=0
        for excluded in "${RAC_PROTO_EXCLUDES_KOTLIN[@]}"; do
            if [ "${proto_base}" = "${excluded}" ]; then
                skip=1
                break
            fi
        done
        [ "${skip}" -eq 1 ] && continue
        KOTLIN_PROTO_BASENAMES+=("${proto_base}")
    done <<< "${RAC_PROTO_FILES}"

    wire-compiler \
        --proto_path="${PROTO_DIR}" \
        --kotlin_out="${OUT_DIR}" \
        "${KOTLIN_PROTO_BASENAMES[@]}"

    # v2 close-out: Wire 4.x emits gRPC service interfaces (`<Service>Client.kt`)
    # AND their Grpc client implementations (`Grpc<Service>Client.kt`). Both
    # depend on com.squareup.wire:wire-grpc-client which we don't carry in KMP
    # commonMain (JVM-only grpc runtime). The hand-written
    # VoiceAgentStreamAdapter / DownloadStreamAdapter under jvmAndroidMain
    # consume the message types directly via rac_*_set_proto_callback, so the
    # generated client stubs are dead weight. Strip them so regen stays green.
    find "${OUT_DIR}/ai/runanywhere/proto/v1/" -name "*Client.kt" -delete
    find "${OUT_DIR}/ai/runanywhere/proto/v1/" -name "Grpc*Client.kt" -delete

    echo "✓ Kotlin proto codegen → ${OUT_DIR} (gRPC client stubs stripped)"

    # Note: protoc-gen-grpckt (grpc-kotlin official plugin) emits
    # com.google.protobuf-style Java messages + Flow client stubs. We do
    # NOT use it here because it would force a Java protobuf runtime
    # dependency in commonMain (breaks KMP). The hand-written ~150 LOC
    # adapter (Wave C Phase 17) is the bridge.
else
    echo "warning: wire-compiler not on PATH." >&2
    echo "         The Gradle Wire plugin in sdk/runanywhere-kotlin/build.gradle.kts" >&2
    echo "         will regenerate at build time. For one-off CLI runs, install via" >&2
    echo "         'brew install wire' (macOS) or download from" >&2
    echo "         https://github.com/square/wire/releases" >&2
fi
