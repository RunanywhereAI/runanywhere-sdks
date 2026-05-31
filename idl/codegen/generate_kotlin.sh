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
#   sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/generated/
#
# Wire emits pure Kotlin data classes with no Java protobuf dependency.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PROTO_DIR="${REPO_ROOT}/idl"
OUT_DIR="${REPO_ROOT}/sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/generated"

mkdir -p "${OUT_DIR}"

if command -v wire-compiler >/dev/null 2>&1; then
    # Wire emits pure Kotlin data classes for messages. Service
    # definitions are passed too — Wire treats `service { rpc ... }` blocks
    # as informational and emits the message types only. The streaming
    # client wrapper is hand-written in
    # sdk/runanywhere-kotlin/src/main/kotlin/.../adapters/
    # using kotlinx.coroutines Flow + the Wire-generated message types.
    #
    # Canonical proto-file list from generate_all.sh, with fallback
    # to filesystem discovery when invoked standalone.
    # component_types.proto is included in the Kotlin
    # positive list. Wire does NOT transitively emit enum-only dependencies
    # (ComponentLifecycleState, EventCategory) when the defining proto is
    # excluded — a prior assumption that it did was incorrect and left
    # consumer code (VoiceAgentTypes.kt, EventBus.kt, SDKEvent.kt) depending
    # on files that regen would delete. No exclusions today.
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

    # Pre-clean the Wire output namespace so that types removed or renamed in
    # the IDL (e.g. AcceleratorPreference → AccelerationPreference) cannot
    # linger as committed orphans. wire-compiler writes files but never
    # deletes; without this `rm -rf` step a previous codegen output for a
    # type that no longer exists in any .proto stays committed in the
    # generated directory, ends up on developers' classpath, and silently
    # competes with the canonical type at autocomplete time. Constrain the
    # delete to the Wire-owned subtree (`ai/runanywhere/proto/v1/`) so
    # hand-written code under the same `generated/` root is preserved.
    if [ -d "${OUT_DIR}/ai/runanywhere/proto/v1" ]; then
        find "${OUT_DIR}/ai/runanywhere/proto/v1" -name "*.kt" -delete
    fi

    wire-compiler \
        --proto_path="${PROTO_DIR}" \
        --kotlin_out="${OUT_DIR}" \
        "${KOTLIN_PROTO_BASENAMES[@]}"

    # Wire 4.x emits gRPC service interfaces (`<Service>Client.kt`) AND their
    # Grpc client implementations (`Grpc<Service>Client.kt`). Both depend on
    # com.squareup.wire:wire-grpc-client which the SDK does not carry. The
    # hand-written VoiceAgentStreamAdapter / DownloadStreamAdapter consume the
    # message types directly via rac_*_set_proto_callback, so the generated
    # client stubs are dead weight. Strip them so regen stays green.
    find "${OUT_DIR}/ai/runanywhere/proto/v1/" -name "*Client.kt" -delete
    find "${OUT_DIR}/ai/runanywhere/proto/v1/" -name "Grpc*Client.kt" -delete

    echo "✓ Kotlin proto codegen → ${OUT_DIR} (gRPC client stubs stripped)"

    # Note: protoc-gen-grpckt (grpc-kotlin official plugin) emits
    # com.google.protobuf-style Java messages + Flow client stubs. We do
    # NOT use it here because it would force a Java protobuf runtime
    # dependency. The hand-written ~150 LOC adapter is the bridge.
else
    echo "warning: wire-compiler not on PATH." >&2
    echo "         The Gradle Wire plugin in sdk/runanywhere-kotlin/build.gradle.kts" >&2
    echo "         will regenerate at build time. For one-off CLI runs, install via" >&2
    echo "         'brew install wire' (macOS) or download from" >&2
    echo "         https://github.com/square/wire/releases" >&2
fi
