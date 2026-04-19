#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Generate Kotlin bindings from v2 proto3 schemas via Wire (Square).
#
# Requirements:
#   brew install wire           # wire-compiler binary
# OR via gradle: see frontends/kotlin/build.gradle.kts (wire plugin).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PROTO_DIR="${REPO_ROOT}/idl"
OUT_DIR="${REPO_ROOT}/frontends/kotlin/src/main/kotlin/com/runanywhere/generated"

mkdir -p "${OUT_DIR}"

if command -v wire-compiler >/dev/null 2>&1; then
    wire-compiler \
        --proto_path="${PROTO_DIR}" \
        --kotlin_out="${OUT_DIR}" \
        voice_events.proto pipeline.proto solutions.proto
    echo "✓ Kotlin proto codegen → ${OUT_DIR}"
else
    echo "warning: wire-compiler not on PATH; the Gradle Wire plugin will" >&2
    echo "         generate these at build time instead." >&2
fi
