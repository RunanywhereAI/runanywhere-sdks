# Brewfile — companion to Mintfile for non-Swift Homebrew-only tooling.
#
# Mintfile (Swift) pins SwiftLint / Periphery / swift-format / swift-protobuf.
# This file pins the rest of the Homebrew-installed tooling that the IDL
# codegen and CI workflows depend on. Run `brew bundle` from the repo root to
# install (or `brew bundle check` to verify drift).
#
# Why this is separate from Mintfile:
#   - Mintfile only handles tools published as Swift packages.
#   - grpc-swift v2 ships its protoc plugin as `protoc-gen-grpc-swift-2`,
#     a name Mint cannot auto-discover. The Homebrew formula handles install.
#   - protoc itself is a generic C++/Python prerequisite, not Swift-specific.
#
# Versioning note: Homebrew does not pin formula versions in Brewfile by
# default. Treat the formula names below as the SoT for *what* must be present;
# scripts/setup-toolchain.sh + idl-drift-check.yml enforce the minimum version
# at run time (GRPC_SWIFT_EXPECTED=1.21, etc.). When a major release breaks
# wire-format compatibility, add a `version: "<pinned>"` modifier here and
# bump scripts/setup-toolchain.sh in the same commit.

# Protocol Buffers compiler — required by every idl/codegen/generate_*.sh
# driver. Pinned implicitly by `RAC_PROTOBUF_MIN_VERSION` (see CMake) but
# the brew formula is what setup-toolchain.sh installs.
brew "protobuf"

# Swift gRPC plugin for protoc — drives idl/codegen/generate_swift.sh.
# Not pinnable via Mintfile (see Mintfile comment for details).
brew "protoc-gen-grpc-swift"
