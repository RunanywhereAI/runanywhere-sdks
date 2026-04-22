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
# Tools installed:
#   protoc                 25.x     (shared, all languages)
#   protoc-gen-swift       1.27.x   (swift-protobuf)
#   wire-compiler          4.9.x    (Kotlin via Square Wire)
#   protoc_plugin          21.1.2   (Dart — emits *.pb.dart and *.pbgrpc.dart)
#   ts-proto               1.181.x  (TypeScript message types)
#   google-protobuf Python 4.25.x   (Python message types)
#
# GAP 09 streaming services (server-streaming gRPC client stubs):
#   protoc-gen-grpc-swift  1.21.x   (Swift AsyncStream client wrappers)
#   grpcio-tools           1.65.x   (Python AsyncIterator client wrappers)
#   protoc-gen-grpckt      NOT installed by default — see generate_kotlin.sh
#                                    note about KMP commonMain incompatibility.
#
# Usage:
#   ./scripts/setup-toolchain.sh          # install / upgrade
#   ./scripts/setup-toolchain.sh --check  # verify present + versions; no install

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

PROTOC_EXPECTED_MAJOR="25"
SWIFT_PROTOBUF_EXPECTED="1.27"
WIRE_EXPECTED="4.9"
PROTOC_PLUGIN_DART_EXPECTED="21.1.2"
TS_PROTO_EXPECTED="1.181"
PYTHON_PROTOBUF_EXPECTED="4.25"
# GAP 09 streaming additions:
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
    if have protoc-gen-dart; then
        echo "• protoc-gen-dart already present."
        return 0
    fi
    if ! have dart; then
        echo "warning: dart not on PATH — install via flutter or dart.dev, then re-run." >&2
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
            "grpcio-tools>=${GRPCIO_TOOLS_EXPECTED}"   # GAP 09: AsyncIterator client stubs
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
        echo "warning: GAP 09 Swift streaming codegen needs protoc-gen-grpc-swift on Linux/Win." >&2
        echo "         Build from https://github.com/grpc/grpc-swift (release/1.x) and put on PATH." >&2
    fi
}

check_versions() {
    local rc=0
    if have protoc; then
        echo "protoc:            $(protoc --version)"
    else
        echo "protoc:            MISSING" >&2
        rc=1
    fi
    if have protoc-gen-swift; then
        echo "protoc-gen-swift:  $(protoc-gen-swift --version 2>/dev/null || echo 'present')"
    else
        echo "protoc-gen-swift:  MISSING (Swift codegen will fail)" >&2
    fi
    if have wire-compiler; then
        echo "wire-compiler:     $(wire-compiler --version 2>/dev/null || echo 'present')"
    else
        echo "wire-compiler:     not on PATH (Gradle Wire plugin handles this)"
    fi
    if have protoc-gen-dart; then
        echo "protoc-gen-dart:   present"
    else
        echo "protoc-gen-dart:   MISSING (Dart codegen will fail)" >&2
    fi
    if have npm && [ -x "$(npm root -g 2>/dev/null)/ts-proto/protoc-gen-ts_proto" ]; then
        echo "ts-proto:          present"
    else
        echo "ts-proto:          MISSING (TS codegen will fail)" >&2
    fi
    if have python3 && python3 -c "import google.protobuf" >/dev/null 2>&1; then
        echo "python-protobuf:   present"
    else
        echo "python-protobuf:   MISSING (Python codegen will fail)" >&2
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
install_grpc_swift   # GAP 09 streaming codegen for Swift (Apple-only Homebrew bottle).

echo ""
echo "▶ Verifying installed versions:"
check_versions || true

echo ""
echo "✓ Toolchain setup complete (warnings above for plugins not auto-installable)."
