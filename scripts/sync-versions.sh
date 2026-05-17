#!/usr/bin/env bash
# =============================================================================
# sync-versions.sh
# =============================================================================
# Single-source version bump across the monorepo. Updates every manifest that
# carries a version string so they all match the requested release version.
#
# Usage:
#   scripts/sync-versions.sh <new_version>
#
# Example:
#   scripts/sync-versions.sh 0.20.0
#   scripts/sync-versions.sh v0.20.0      # 'v' prefix is stripped
#
# What it touches:
#   sdk/runanywhere-commons/VERSION                        (single line)
#   sdk/runanywhere-commons/VERSIONS                       (PROJECT_VERSION line)
#   Package.swift                                          (sdkVersion line)
#   sdk/runanywhere-swift/.../SDKConstants.swift           (public `RunAnywhere.version`)
#   sdk/runanywhere-kotlin/gradle.properties               (runanywhere.nativeLibVersion + SDK_VERSION)
#   sdk/runanywhere-kotlin/.../SDKConstants.kt             (Kotlin VERSION constant)
#   sdk/shared/proto-ts/package.json                       (proto-ts package version)
#   sdk/runanywhere-web/package.json                       (root version)
#   sdk/runanywhere-web/packages/*/package.json            (each package version)
#   sdk/runanywhere-web/.../Version.ts                     (web SDK_VERSION constant)
#   sdk/runanywhere-react-native/package.json              (root)
#   sdk/runanywhere-react-native/packages/*/package.json   (each package + proto-ts dep)
#   sdk/runanywhere-react-native/.../SDKConstants.ts       (RN version constant)
#   sdk/runanywhere-flutter/packages/*/pubspec.yaml        (each version: line)
#   sdk/runanywhere-flutter/.../sdk_constants.dart         (Flutter version constant)
#
# Does NOT touch (intentional, documented SoT for distinct domains):
#   - SwiftPM XCFramework checksums — use sync-checksums.sh after release zips exist.
#   - sdk/runanywhere-commons/VERSIONS dep-pin lines (ONNX/Sherpa/llama.cpp) —
#     those track UPSTREAM library versions, not OUR release version.
#   - sdk/runanywhere-flutter/.fvm/fvm_config.json — Flutter TOOLCHAIN pin
#     (drives `flutter pub get` host), not the SDK release version. The
#     toolchain pin is centralized in `sdk/runanywhere-commons/VERSIONS`
#     (`FLUTTER_VERSION`); bumping the toolchain is a separate concern.
#   - dependencies/versions.json — centralized THIRD-PARTY library pins,
#     not the RunAnywhere SDK release version. Edit by hand when bumping
#     a vendored library.
#   - .syncpackrc.json — derived from dependencies/versions.json; mirror by hand.
# =============================================================================

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 <new_version>" >&2
    echo "Example: $0 0.20.0" >&2
    exit 1
fi

# Strip leading 'v' if present
NEW_VERSION="${1#v}"

# Validate semver-ish format
if ! [[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?$ ]]; then
    echo "ERROR: '$NEW_VERSION' does not look like a semver version" >&2
    exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bump_line() {
    # Replaces a line matching $pattern with $replacement, in $file.
    # Cross-platform sed -i (BSD sed on macOS needs '' after -i).
    local file="$1" pattern="$2" replacement="$3"
    if [ ! -f "$file" ]; then
        echo "  skip (not found): $file"
        return 0
    fi
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' -E "s|${pattern}|${replacement}|" "$file"
    else
        sed -i -E "s|${pattern}|${replacement}|" "$file"
    fi
    echo "  bumped: $file"
}

bump_json_version() {
    local file="$1"
    bump_line "$file" '^  "version": "[^"]+"' "  \"version\": \"${NEW_VERSION}\""
}

bump_pubspec_version() {
    local file="$1"
    bump_line "$file" '^version: .+' "version: ${NEW_VERSION}"
}

# Flutter sub-packages (genie/llamacpp/onnx) depend on the core `runanywhere`
# package via a caret constraint like `runanywhere: ^0.19.13`. When we bump
# the suite, that constraint must track the FULL NEW_VERSION (patch included)
# because backend packages ship native binaries that lockstep with the core
# release; resolving an older same-minor core (e.g. 0.19.0) against a newer
# backend (0.19.13) would create a hard-to-debug native ABI mismatch in apps
# outside the monorepo workspace.
bump_pubspec_runanywhere_dep() {
    local file="$1"
    bump_line "$file" '^  runanywhere: \^[0-9]+\.[0-9]+\.[0-9]+' \
        "  runanywhere: ^${NEW_VERSION}"
}

# Update `"@runanywhere/proto-ts": "^x.y.z"` lines (dependencies / peer ranges)
# across npm package.json files. The published proto-ts package versions are
# kept in lockstep with the SDK suite by sync-versions, so all consumers
# advance to `^${NEW_VERSION}` in the same commit.
bump_npm_proto_ts_dep() {
    local file="$1"
    bump_line "$file" \
        '"@runanywhere/proto-ts": "\^[0-9]+\.[0-9]+\.[0-9]+"' \
        "\"@runanywhere/proto-ts\": \"^${NEW_VERSION}\""
}

echo ">> Syncing versions to ${NEW_VERSION}"
echo ">> Repo root: ${REPO_ROOT}"
echo ""

# 1. commons VERSION + VERSIONS
echo ">> commons:"
echo "$NEW_VERSION" > "${REPO_ROOT}/sdk/runanywhere-commons/VERSION"
echo "  bumped: sdk/runanywhere-commons/VERSION"
bump_line "${REPO_ROOT}/sdk/runanywhere-commons/VERSIONS" \
    '^PROJECT_VERSION=.*' "PROJECT_VERSION=${NEW_VERSION}"

# 2. Swift Package.swift (root) + per-SDK VERSION + SDKConstants.version
echo ""
echo ">> Swift SDK:"
bump_line "${REPO_ROOT}/Package.swift" \
    'let sdkVersion = "[^"]+"' "let sdkVersion = \"${NEW_VERSION}\""
# Swift SDK VERSION file (read by release tooling)
SWIFT_VERSION_FILE="${REPO_ROOT}/sdk/runanywhere-swift/VERSION"
if [ -f "$SWIFT_VERSION_FILE" ]; then
    echo "$NEW_VERSION" > "$SWIFT_VERSION_FILE"
    echo "  bumped: sdk/runanywhere-swift/VERSION"
fi
# SDKConstants.swift — public API `RunAnywhere.version` surface
bump_line "${REPO_ROOT}/sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Constants/SDKConstants.swift" \
    'public static let version = "[^"]+"' \
    "public static let version = \"${NEW_VERSION}\""

# 3. Kotlin gradle.properties + SDKConstants.kt
echo ""
echo ">> Kotlin SDK:"
KOTLIN_PROPS="${REPO_ROOT}/sdk/runanywhere-kotlin/gradle.properties"
if [ -f "$KOTLIN_PROPS" ]; then
    if grep -q '^runanywhere\.nativeLibVersion=' "$KOTLIN_PROPS"; then
        bump_line "$KOTLIN_PROPS" \
            '^runanywhere\.nativeLibVersion=.*' "runanywhere.nativeLibVersion=${NEW_VERSION}"
    else
        echo "runanywhere.nativeLibVersion=${NEW_VERSION}" >> "$KOTLIN_PROPS"
        echo "  appended: runanywhere.nativeLibVersion to $KOTLIN_PROPS"
    fi
    if grep -q '^SDK_VERSION=' "$KOTLIN_PROPS"; then
        bump_line "$KOTLIN_PROPS" \
            '^SDK_VERSION=.*' "SDK_VERSION=${NEW_VERSION}"
    fi
fi
# Kotlin public `RunAnywhere.version` surface (mirrors Swift SDKConstants.version).
bump_line "${REPO_ROOT}/sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/foundation/constants/SDKConstants.kt" \
    'const val VERSION = "[^"]+"' \
    "const val VERSION = \"${NEW_VERSION}\""

# 3a. Shared proto-ts package — pinned to suite version so RN/Web @runanywhere/*
# packages can use `^${NEW_VERSION}` as a single moving target.
echo ""
echo ">> Shared proto-ts:"
bump_json_version "${REPO_ROOT}/sdk/shared/proto-ts/package.json"

# 4. Web SDK packages
echo ""
echo ">> Web SDK:"
for pkg in \
    "${REPO_ROOT}/sdk/runanywhere-web/package.json" \
    "${REPO_ROOT}/sdk/runanywhere-web/packages/core/package.json" \
    "${REPO_ROOT}/sdk/runanywhere-web/packages/llamacpp/package.json" \
    "${REPO_ROOT}/sdk/runanywhere-web/packages/onnx/package.json"; do
    bump_json_version "$pkg"
    bump_npm_proto_ts_dep "$pkg"
done
# Web SDK public `RunAnywhere.version` surface — keeps the TS constant in
# sync with the commons VERSION file and the package.json versions above.
bump_line "${REPO_ROOT}/sdk/runanywhere-web/packages/core/src/Foundation/Version.ts" \
    "export const SDK_VERSION = '[^']+'" \
    "export const SDK_VERSION = '${NEW_VERSION}'"

# 5. React Native SDK packages
echo ""
echo ">> React Native SDK:"
for pkg in \
    "${REPO_ROOT}/sdk/runanywhere-react-native/package.json" \
    "${REPO_ROOT}/sdk/runanywhere-react-native/packages/core/package.json" \
    "${REPO_ROOT}/sdk/runanywhere-react-native/packages/llamacpp/package.json" \
    "${REPO_ROOT}/sdk/runanywhere-react-native/packages/onnx/package.json"; do
    bump_json_version "$pkg"
    bump_npm_proto_ts_dep "$pkg"
done
# React Native public `RunAnywhere.version` surface — keeps the TS constant
# (consumed by Public/RunAnywhere.ts during initialize) aligned with commons.
bump_line "${REPO_ROOT}/sdk/runanywhere-react-native/packages/core/src/Foundation/Constants/SDKConstants.ts" \
    "version: '[^']+'" \
    "version: '${NEW_VERSION}'"

# 6. Flutter SDK packages
echo ""
echo ">> Flutter SDK:"
for pkg in \
    "${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere/pubspec.yaml" \
    "${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere_genie/pubspec.yaml" \
    "${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere_llamacpp/pubspec.yaml" \
    "${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere_onnx/pubspec.yaml"; do
    bump_pubspec_version "$pkg"
done

# Sub-packages depend on the core `runanywhere` package; align their
# dependency floor to match the bumped suite version.
for pkg in \
    "${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere_genie/pubspec.yaml" \
    "${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere_llamacpp/pubspec.yaml" \
    "${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere_onnx/pubspec.yaml"; do
    bump_pubspec_runanywhere_dep "$pkg"
done

# Flutter public `RunAnywhere.version` surface — Dart constant consumed by
# `RunAnywhere.version` getter and by the native init payload.
bump_line "${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere/lib/foundation/constants/sdk_constants.dart" \
    "static const String version = '[^']+'" \
    "static const String version = '${NEW_VERSION}'"

echo ""
echo ">> Done. Verify with:"
echo "    git diff -- sdk/ Package.swift"
echo ""
echo ">> Then commit, tag, and push:"
echo "    git add -u"
echo "    git commit -m \"chore: release ${NEW_VERSION}\""
echo "    git tag v${NEW_VERSION}"
echo "    git push origin main v${NEW_VERSION}"
