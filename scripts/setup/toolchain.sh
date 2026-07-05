#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# One-shot installer for every tool the IDL codegen pipeline depends on.
# Pins every version so local + CI runs produce byte-identical output and the
# idl-drift-check CI gate actually catches drift instead of tool-version noise.
#
# Supported hosts:
#   macOS 13+ (Homebrew-driven)
#   Ubuntu 22.04+ (apt + user-local pip/npm)
#
# Tools installed (all pins sourced from sdk/runanywhere-commons/VERSIONS):
#   protoc                 34.x     (shared, all languages)        — PROTOC_VERSION_MAJOR
#   protoc-gen-swift       1.38.x   (swift-protobuf)                — SWIFT_PROTOBUF_VERSION
#   wire-compiler          5.5.x    (Kotlin via Square Wire)        — WIRE_VERSION
#   protoc_plugin          25.0.0   (Dart — emits *.pb.dart)        — PROTOC_GEN_DART_VERSION
#   ts-proto               2.11.x   (TypeScript message types)      — TS_PROTO_VERSION
#   google-protobuf Python 4.25.x   (Python message types)
#
# Streaming services (server-streaming gRPC client stubs):
#   protoc-gen-grpc-swift  1.21.x   (Swift AsyncStream client wrappers)
#   grpcio-tools           1.65.x   (Python AsyncIterator client wrappers)
#   protoc-gen-grpckt      NOT installed by default — see generate_kotlin.sh
#                                    note about KMP commonMain incompatibility.
#
# Usage:
#   ./scripts/setup/toolchain.sh          # install / upgrade
#   ./scripts/setup/toolchain.sh --check  # verify present + versions; no install

set -euo pipefail

MODE="install"
for arg in "$@"; do
    case "$arg" in
        --check) MODE="check" ;;
        -h|--help)
            sed -n '1,30p' "$0" | sed 's/^#//'
            exit 0
            ;;
        *) echo "unknown flag: $arg" >&2; exit 2 ;;
    esac
done

# Single source of truth for codegen toolchain pins lives in
# sdk/runanywhere-commons/VERSIONS so this script, scripts/codegen/generate_*.sh,
# and gradle/libs.versions.toml all agree. Load it here; fall back to
# documented defaults if anything is missing so the script still works on a
# minimal checkout.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VERSIONS_FILE="${REPO_ROOT}/sdk/runanywhere-commons/VERSIONS"
if [ -f "${VERSIONS_FILE}" ]; then
    # shellcheck disable=SC1090
    set -a
    # Strip comments and source KEY=VALUE lines. Avoid sourcing the raw file
    # because YAML-like dep-pin comments may include shell metachars.
    eval "$(grep -E '^[A-Z_][A-Z0-9_]*=' "${VERSIONS_FILE}")"
    set +a
fi

PROTOC_EXPECTED_MAJOR="${PROTOC_VERSION_MAJOR:-34}"
SWIFT_PROTOBUF_EXPECTED="${SWIFT_PROTOBUF_VERSION:-1.38.0}"
WIRE_EXPECTED="${WIRE_VERSION:-5.5.1}"
PROTOC_PLUGIN_DART_EXPECTED="${PROTOC_GEN_DART_VERSION:-25.0.0}"
TS_PROTO_EXPECTED="${TS_PROTO_VERSION:-2.11.8}"
PYTHON_PROTOBUF_EXPECTED="4.25"
# Streaming additions:
GRPC_SWIFT_EXPECTED="1.21"
GRPCIO_TOOLS_EXPECTED="1.65"

have() { command -v "$1" >/dev/null 2>&1; }

os_hint() {
    case "$(uname -s)" in
        Darwin) echo "mac" ;;
        Linux)  echo "linux" ;;
        *)      echo "other" ;;
    esac
}

OS="$(os_hint)"

install_protoc() {
    if have protoc; then
        echo "• protoc already present: $(protoc --version)"
        return 0
    fi
    if [ "${OS}" = "mac" ]; then
        brew install protobuf
    elif [ "${OS}" = "linux" ]; then
        sudo apt-get update -y
        sudo apt-get install -y protobuf-compiler libprotobuf-dev
    else
        echo "error: unsupported OS for auto-install of protoc." >&2
        return 1
    fi
}

install_swift_protobuf() {
    if have protoc-gen-swift; then
        echo "• protoc-gen-swift already present."
        return 0
    fi
    if [ "${OS}" = "mac" ]; then
        brew install swift-protobuf
    else
        echo "warning: auto-install of protoc-gen-swift on Linux is not covered;" >&2
        echo "         build from source: https://github.com/apple/swift-protobuf" >&2
    fi
}

install_wire() {
    if have wire-compiler; then
        echo "• wire-compiler already present."
        return 0
    fi
    if [ "${OS}" = "mac" ]; then
        brew install wire || true   # older Homebrew may not have the bottle
    fi
    if ! have wire-compiler; then
        echo "warning: wire-compiler not installed via brew on this host." >&2
        echo "         The Kotlin Gradle build uses the Wire Gradle plugin;" >&2
        echo "         CLI is only needed for standalone codegen runs." >&2
    fi
}

install_dart_plugin() {
    # Dart codegen requires Dart 3.0+ AND protoc_plugin
    # pinned at PROTOC_PLUGIN_DART_EXPECTED (loaded from VERSIONS). Older
    # Dart / plugin combos emit subtly different code that trips
    # idl-drift-check on unrelated PRs. `generate_dart.sh` enforces both at
    # runtime; this installer documents the intent.
    if have protoc-gen-dart; then
        echo "• protoc-gen-dart already present (required pin: ${PROTOC_PLUGIN_DART_EXPECTED})."
        return 0
    fi
    if ! have dart; then
        echo "warning: dart not on PATH — install Dart 3.0+ via flutter or dart.dev, then re-run." >&2
        return 0
    fi
    # Verify the active Dart is 3.0+ before activating the plugin.
    DART_VERSION=$(dart --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    DART_MAJOR=$(echo "${DART_VERSION:-0.0.0}" | cut -d. -f1)
    if [ "${DART_MAJOR}" -lt 3 ]; then
        echo "warning: Dart ${DART_VERSION} < 3.0 — protoc_plugin ${PROTOC_PLUGIN_DART_EXPECTED} requires Dart 3.0+." >&2
        echo "         Upgrade Dart before running scripts/codegen/generate_dart.sh." >&2
        return 0
    fi
    dart pub global activate protoc_plugin "${PROTOC_PLUGIN_DART_EXPECTED}"
    echo "• add \$HOME/.pub-cache/bin to your PATH so protoc can find protoc-gen-dart."
}

install_ts_proto() {
    if ! have npm; then
        echo "warning: npm not on PATH — install Node 18+ and retry." >&2
        return 0
    fi
    npm install -g "ts-proto@^${TS_PROTO_EXPECTED}" protobufjs
}

install_python_protobuf() {
    if have python3; then
        python3 -m pip install --user --upgrade \
            "protobuf>=${PYTHON_PROTOBUF_EXPECTED},<5" \
            "grpcio-tools>=${GRPCIO_TOOLS_EXPECTED}"   # AsyncIterator client stubs
    else
        echo "warning: python3 not on PATH — skipping pip install." >&2
    fi
}

install_grpc_swift() {
    if have protoc-gen-grpc-swift; then
        echo "• protoc-gen-grpc-swift already present."
        return 0
    fi
    if [ "${OS}" = "mac" ]; then
        # grpc-swift v1 ships protoc-gen-grpc-swift via Homebrew.
        brew install grpc-swift 2>/dev/null || \
            echo "warning: 'brew install grpc-swift' failed — install from https://github.com/grpc/grpc-swift" >&2
    else
        echo "warning: Swift streaming codegen needs protoc-gen-grpc-swift on Linux/Win." >&2
        echo "         Build from https://github.com/grpc/grpc-swift (release/1.x) and put on PATH." >&2
    fi
}

check_versions() {
    local rc=0

    # version_ok <actual> <expected_prefix>
    # Returns 0 if actual starts with expected_prefix, 1 otherwise.
    version_ok() {
        case "$1" in
            "$2"*) return 0 ;;
            *)     return 1 ;;
        esac
    }

    if have protoc; then
        local protoc_ver
        protoc_ver="$(protoc --version | grep -oE '[0-9]+\.[0-9]+' | head -1)"
        local protoc_major
        protoc_major="$(echo "${protoc_ver}" | cut -d. -f1)"
        echo "protoc:            ${protoc_ver} (expected major ${PROTOC_EXPECTED_MAJOR})"
        if [ "${protoc_major:-0}" != "${PROTOC_EXPECTED_MAJOR}" ]; then
            echo "  ✗ version mismatch — got major ${protoc_major}, want ${PROTOC_EXPECTED_MAJOR}" >&2
            rc=1
        fi
    else
        echo "protoc:            MISSING" >&2
        rc=1
    fi

    if have protoc-gen-swift; then
        local swift_pb_ver
        swift_pb_ver="$(protoc-gen-swift --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
        echo "protoc-gen-swift:  ${swift_pb_ver:-present} (expected ${SWIFT_PROTOBUF_EXPECTED})"
        if [ -n "${swift_pb_ver}" ] && ! version_ok "${swift_pb_ver}" "${SWIFT_PROTOBUF_EXPECTED%.*}"; then
            echo "  ✗ version mismatch — got ${swift_pb_ver}, want ${SWIFT_PROTOBUF_EXPECTED}" >&2
            rc=1
        fi
    else
        echo "protoc-gen-swift:  MISSING (Swift codegen will fail)" >&2
        rc=1
    fi

    if have wire-compiler; then
        local wire_ver
        wire_ver="$(wire-compiler --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
        echo "wire-compiler:     ${wire_ver:-present} (expected ${WIRE_EXPECTED})"
        if [ -n "${wire_ver}" ] && ! version_ok "${wire_ver}" "${WIRE_EXPECTED%.*}"; then
            echo "  ✗ version mismatch — got ${wire_ver}, want ${WIRE_EXPECTED}" >&2
            rc=1
        fi
    else
        echo "wire-compiler:     not on PATH (Gradle Wire plugin handles this)"
    fi

    if have protoc-gen-dart; then
        local dart_plugin_ver
        dart_plugin_ver="$(dart pub global list 2>/dev/null | grep 'protoc_plugin' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
        echo "protoc-gen-dart:   ${dart_plugin_ver:-present} (expected ${PROTOC_PLUGIN_DART_EXPECTED})"
        if [ -n "${dart_plugin_ver}" ] && ! version_ok "${dart_plugin_ver}" "${PROTOC_PLUGIN_DART_EXPECTED%.*}"; then
            echo "  ✗ version mismatch — got ${dart_plugin_ver}, want ${PROTOC_PLUGIN_DART_EXPECTED}" >&2
            rc=1
        fi
    else
        echo "protoc-gen-dart:   MISSING (Dart codegen will fail)" >&2
        rc=1
    fi

    if have npm && [ -x "$(npm root -g 2>/dev/null)/ts-proto/protoc-gen-ts_proto" ]; then
        local ts_proto_ver
        ts_proto_ver="$(npm list -g --depth=0 ts-proto 2>/dev/null | grep 'ts-proto' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
        echo "ts-proto:          ${ts_proto_ver:-present} (expected ^${TS_PROTO_EXPECTED})"
        if [ -n "${ts_proto_ver}" ] && ! version_ok "${ts_proto_ver}" "${TS_PROTO_EXPECTED%.*}"; then
            echo "  ✗ version mismatch — got ${ts_proto_ver}, want ^${TS_PROTO_EXPECTED}" >&2
            rc=1
        fi
    else
        echo "ts-proto:          MISSING (TS codegen will fail)" >&2
        rc=1
    fi

    if have python3 && python3 -c "import google.protobuf" >/dev/null 2>&1; then
        local py_pb_ver
        py_pb_ver="$(python3 -c "import google.protobuf; print(google.protobuf.__version__)" 2>/dev/null || true)"
        echo "python-protobuf:   ${py_pb_ver:-present} (expected >=${PYTHON_PROTOBUF_EXPECTED},<5)"
        if [ -n "${py_pb_ver}" ] && ! version_ok "${py_pb_ver}" "${PYTHON_PROTOBUF_EXPECTED}"; then
            echo "  ✗ version mismatch — got ${py_pb_ver}, want >=${PYTHON_PROTOBUF_EXPECTED},<5" >&2
            rc=1
        fi
    else
        echo "python-protobuf:   MISSING (Python codegen will fail)" >&2
        rc=1
    fi

    if have python3 && python3 -c "import grpc_tools" >/dev/null 2>&1; then
        local grpcio_ver
        grpcio_ver="$(python3 -c "import grpc_tools; print(grpc_tools.__version__)" 2>/dev/null || true)"
        echo "grpcio-tools:      ${grpcio_ver:-present} (expected >=${GRPCIO_TOOLS_EXPECTED})"
        if [ -n "${grpcio_ver}" ] && ! version_ok "${grpcio_ver}" "${GRPCIO_TOOLS_EXPECTED%.*}"; then
            echo "  ✗ version mismatch — got ${grpcio_ver}, want >=${GRPCIO_TOOLS_EXPECTED}" >&2
            rc=1
        fi
    else
        echo "grpcio-tools:      not present (Python streaming stubs unavailable)" >&2
    fi

    if have protoc-gen-grpc-swift; then
        echo "protoc-gen-grpc-swift: present (expected >=${GRPC_SWIFT_EXPECTED})"
    else
        echo "protoc-gen-grpc-swift: not present (Swift streaming stubs unavailable)" >&2
    fi

    return $rc
}

if [ "${MODE}" = "check" ]; then
    check_versions
    exit $?
fi

echo "▶ Installing IDL codegen toolchain (protoc + language plugins)..."
install_protoc
install_swift_protobuf
install_wire
install_dart_plugin
install_ts_proto
install_python_protobuf
install_grpc_swift   # Streaming codegen for Swift (Apple-only Homebrew bottle).

echo ""
echo "▶ Verifying installed versions:"
check_versions || true

echo ""
echo "✓ Toolchain setup complete (warnings above for plugins not auto-installable)."
