# Brewfile — companion to Mintfile for non-Swift Homebrew-only tooling.
#
# Mintfile (Swift) pins SwiftLint / Periphery / swift-format / swift-protobuf.
# This file declares the rest of the Homebrew-installed tooling that the IDL
# codegen and CI workflows depend on.
#
# === HOW THIS FILE IS CONSUMED (as of 2026-05) ===
#
# This Brewfile is the *declarative SoT* for which Homebrew formulas the
# toolchain expects. It is NOT (yet) consumed automatically by any CI workflow
# or setup script: pr-build.yml and idl-drift-check.yml still call
# `brew install <formula>` directly for the same formulas listed below.
# That divergence is intentional but documented here so future readers know:
#
#   - Local contributors can run `brew bundle --file Brewfile` from the repo
#     root to install (or `brew bundle check --file Brewfile` to verify drift)
#     and stay in sync with what CI ad-hoc installs.
#   - When you add a formula to a CI workflow, also add it here so future
#     formula renames (e.g. the grpc-swift split that motivated pass-2) have a
#     single text file to grep against.
#   - Migrating CI to consume this file directly (`brew bundle --file Brewfile`
#     replacing the ad-hoc `brew install` lines in .github/workflows/*.yml) is
#     tracked as a follow-up; until then this file documents intent and lets
#     local checkouts stay aligned.
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
