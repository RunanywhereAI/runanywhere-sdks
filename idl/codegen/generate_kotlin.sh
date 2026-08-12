#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Generate Kotlin bindings via Square Wire.
#
# The compiler is obtained by idl/codegen/bootstrap_wire.sh (pinned to
# core/VERSIONS::WIRE_VERSION, checksum-verified, cached), so there is no
# prerequisite to install by hand. `brew install wire` is NOT it — that formula
# is the Wire messaging app.
#
# Output:
#   bindings/kotlin/src/main/kotlin/com/runanywhere/sdk/generated/
#
# Wire emits pure Kotlin data classes with no Java protobuf dependency.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PROTO_DIR="${REPO_ROOT}/idl"
OUT_DIR="${REPO_ROOT}/bindings/kotlin/src/main/kotlin/com/runanywhere/sdk/generated"

mkdir -p "${OUT_DIR}"

# The pinned wire-compiler, obtained rather than assumed — see bootstrap_wire.sh.
# This used to be `if command -v wire-compiler; then ... else warn and skip`,
# which was survivable only while the Kotlin tree was committed: the tracked
# copy carried the build when the generator did not run. It is not committed any
# more, so a skip means the AAR has no message types at all. Fail here instead.
if ! WIRE_BIN="$("${SCRIPT_DIR}/bootstrap_wire.sh")"; then
    echo "error: could not obtain the pinned wire-compiler (see above)." >&2
    echo "       NOTE: 'brew install wire' is the Wire messaging app, not this." >&2
    exit 127
fi

# Wire emits pure Kotlin data classes for messages. Service
# definitions are passed too — Wire treats `service { rpc ... }` blocks
# as informational and emits the message types only. The streaming
# client wrapper is hand-written in
# bindings/kotlin/src/main/kotlin/.../adapters/
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
    RAC_PROTO_FILES="$(ls "${PROTO_DIR}"/*.proto | LC_ALL=C sort)"
fi

# sdk_defaults.proto is the central default pool: it carries rac_default
# annotations and nothing sends its messages over a wire, so no message types
# are emitted for it. idl/codegen/generate_defaults_pool.py turns it into plain
# per-language constants instead. Mirrors DECLARATION_ONLY_FILES in
# idl/codegen/_convenience_common.py.
RAC_PROTO_EXCLUDES_KOTLIN=(sdk_defaults.proto)

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

"${WIRE_BIN}" \
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

# Wire may emit trailing spaces in multiline EnumAdapter constructor
# arguments. Normalize generated Kotlin so codegen output passes the
# repository's whitespace gate deterministically on macOS and Linux.
#
# Done in Python, not perl. Every other tool this pipeline needs is downloaded
# and version-checked (bootstrap_{protoc,wire,pyproto}.sh); perl was the one
# unchecked, unpinned host dependency, and `sed -i` is not portable between GNU
# and BSD. RA_PYTHON is already resolved by generate_all.sh and bootstrapped
# on demand when this script runs standalone.
STRIP_PY="${RA_PYTHON:-}"
if [ -z "${STRIP_PY}" ]; then
    STRIP_PY="$("${SCRIPT_DIR}/bootstrap_pyproto.sh")" || {
        echo "error: no Python available to normalize generated Kotlin whitespace" >&2
        exit 127
    }
fi
"${STRIP_PY}" - "${OUT_DIR}/ai/runanywhere/proto/v1" <<'PY'
import pathlib
import re
import sys

# Bytes, not text: text mode would translate "\n" to os.linesep on write and
# silently turn every generated Kotlin file into CRLF on Windows. Strip spaces
# and tabs that sit immediately before a line ending or at end of file.
TRAILING = re.compile(rb"[ \t]+(?=\r?\n|\Z)")

root = pathlib.Path(sys.argv[1])
for path in sorted(root.rglob("*.kt")):
    data = path.read_bytes()
    cleaned = TRAILING.sub(b"", data)
    if cleaned != data:
        path.write_bytes(cleaned)
PY

echo "✓ Kotlin proto codegen → ${OUT_DIR} (gRPC client stubs stripped)"

# Note: protoc-gen-grpckt (grpc-kotlin official plugin) emits
# com.google.protobuf-style Java messages + Flow client stubs. We do
# NOT use it here because it would force a Java protobuf runtime
# dependency. The hand-written ~150 LOC adapter is the bridge.
