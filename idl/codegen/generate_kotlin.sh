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
    wire-compiler \
        --proto_path="${PROTO_DIR}" \
        --kotlin_out="${OUT_DIR}" \
        model_types.proto voice_events.proto pipeline.proto solutions.proto
    echo "✓ Kotlin proto codegen → ${OUT_DIR}"
else
    echo "warning: wire-compiler not on PATH." >&2
    echo "         The Gradle Wire plugin in sdk/runanywhere-kotlin/build.gradle.kts" >&2
    echo "         will regenerate at build time. For one-off CLI runs, install via" >&2
    echo "         'brew install wire' (macOS) or download from" >&2
    echo "         https://github.com/square/wire/releases" >&2
fi
