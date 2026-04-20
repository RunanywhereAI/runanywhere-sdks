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
#   sdk/runanywhere-kotlin/gradle.properties               (runanywhere.nativeLibVersion)
#   sdk/runanywhere-web/package.json                       (root version)
#   sdk/runanywhere-web/packages/*/package.json            (each package version)
#   sdk/runanywhere-react-native/package.json              (root)
#   sdk/runanywhere-react-native/packages/*/package.json   (each package)
#   sdk/runanywhere-flutter/packages/*/pubspec.yaml        (each version: line)
#
# Does NOT touch (intentional):
#   - SwiftPM XCFramework checksums (use sync-checksums.sh after release artifacts exist)
#   - VERSIONS file dependency versions (those track upstream library versions, not our release)
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
# package via a caret constraint like `runanywhere: ^0.19.0`. When we bump
# the suite, that constraint must track the NEW_VERSION's MAJOR.MINOR floor
# so the sub-packages pull a matching core, not an older published one.
bump_pubspec_runanywhere_dep() {
    local file="$1"
    # Caret floor = current MAJOR.MINOR.0 (e.g. 0.19.12 → 0.19.0)
    local major_minor
    major_minor="$(echo "${NEW_VERSION}" | awk -F. '{print $1"."$2".0"}')"
    bump_line "$file" '^  runanywhere: \^[0-9]+\.[0-9]+\.[0-9]+' \
        "  runanywhere: ^${major_minor}"
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

# 2. Swift Package.swift (root)
echo ""
echo ">> Swift SDK:"
bump_line "${REPO_ROOT}/Package.swift" \
    'let sdkVersion = "[^"]+"' "let sdkVersion = \"${NEW_VERSION}\""

# 3. Kotlin gradle.properties
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

# 4. Web SDK packages
echo ""
echo ">> Web SDK:"
for pkg in \
    "${REPO_ROOT}/sdk/runanywhere-web/package.json" \
    "${REPO_ROOT}/sdk/runanywhere-web/packages/core/package.json" \
    "${REPO_ROOT}/sdk/runanywhere-web/packages/llamacpp/package.json" \
    "${REPO_ROOT}/sdk/runanywhere-web/packages/onnx/package.json"; do
    bump_json_version "$pkg"
done

# 5. React Native SDK packages
echo ""
echo ">> React Native SDK:"
for pkg in \
    "${REPO_ROOT}/sdk/runanywhere-react-native/package.json" \
    "${REPO_ROOT}/sdk/runanywhere-react-native/packages/core/package.json" \
    "${REPO_ROOT}/sdk/runanywhere-react-native/packages/llamacpp/package.json" \
    "${REPO_ROOT}/sdk/runanywhere-react-native/packages/onnx/package.json"; do
    bump_json_version "$pkg"
done

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

echo ""
echo ">> Done. Verify with:"
echo "    git diff -- sdk/ Package.swift"
echo ""
echo ">> Then commit, tag, and push:"
echo "    git add -u"
echo "    git commit -m \"chore: release ${NEW_VERSION}\""
echo "    git tag v${NEW_VERSION}"
echo "    git push origin main v${NEW_VERSION}"
