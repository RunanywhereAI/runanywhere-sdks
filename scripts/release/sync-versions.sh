#!/usr/bin/env bash
# =============================================================================
# sync-versions.sh
# =============================================================================
# Single-source version bump across the monorepo. Updates every manifest that
# carries a version string so they all match the requested release version.
#
# Usage:
#   scripts/release/sync-versions.sh <new_version>
#
# Example:
#   scripts/release/sync-versions.sh 0.20.0
#   scripts/release/sync-versions.sh v0.20.0      # 'v' prefix is stripped
#
# What it touches:
#   AGENTS.md                                               (documented current version)
#   sdk/runanywhere-commons/VERSION                        (single line)
#   sdk/runanywhere-commons/VERSIONS                       (PROJECT_VERSION line)
#   Package.swift                                          (sdkVersion line)
#   sdk/runanywhere-swift/.../Generated/Versions.swift     (RAVersions.sdkVersion)
#   sdk/runanywhere-kotlin/gradle.properties               (runanywhere.nativeLibVersion + SDK_VERSION)
#   sdk/runanywhere-kotlin/src/main/.../SDKConstants.kt    (Kotlin VERSION constant)
#   sdk/shared/proto-ts/package.json + package-lock.json   (proto-ts package version)
#   sdk/runanywhere-web/package.json                       (root version)
#   sdk/runanywhere-web/packages/*/package.json            (each package version)
#   sdk/runanywhere-web/.../Version.ts                     (web SDK_VERSION constant)
#   sdk/runanywhere-react-native/package.json              (root)
#   sdk/runanywhere-react-native/packages/*/package.json   (each package + first-party deps)
#   sdk/runanywhere-react-native backend Gradle fallbacks  (native archive version)
#   sdk/runanywhere-react-native/lerna.json                (fixed package train version)
#   sdk/runanywhere-react-native/.../SDKConstants.ts       (RN version constant)
#   sdk/runanywhere-flutter/packages/*/pubspec.yaml        (each version + core dep)
#   sdk/runanywhere-flutter package/plugin/native metadata (Dart, Gradle, Swift, Kotlin)
#   dependencies/versions.json                             (@runanywhere/proto-ts pin — first-party suite version)
#   SDK AGENTS/architecture/install docs                   (release-facing version examples)
#
# Does NOT touch (intentional, documented SoT for distinct domains):
#   - package CHANGELOG prose — release notes require a reviewed, human-written
#     entry. The coherence gate still requires a heading for NEW_VERSION.
#   - sdk/runanywhere-swift/.../SDKConstants.swift — its `version` constant now
#     reads `rac_sdk_get_version()` from commons at runtime (single source of
#     truth = sdk/runanywhere-commons/VERSION above), so it has no literal to
#     bump. See commons-130.
#   - SwiftPM XCFramework checksums — use sync-checksums.sh after release zips exist.
#   - sdk/runanywhere-commons/VERSIONS dep-pin lines (ONNX/Sherpa/llama.cpp) —
#     those track UPSTREAM library versions, not OUR release version.
#   - sdk/runanywhere-flutter/.fvm/fvm_config.json — Flutter TOOLCHAIN pin
#     (drives `flutter pub get` host), not the SDK release version. The
#     toolchain pin is centralized in `sdk/runanywhere-commons/VERSIONS`
#     (`FLUTTER_VERSION`); bumping the toolchain is a separate concern.
#   - dependencies/versions.json third-party pins (long, protobufjs, typescript,
#     eslint, vite, react-native, etc.) — those track upstream library
#     versions, not OUR release version. Only the first-party
#     @runanywhere/proto-ts pin (published from this repo in lockstep with
#     the SDK suite) is bumped by this script.
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

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CURRENT_VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/sdk/runanywhere-commons/VERSION")"
CURRENT_VERSION_REGEX="${CURRENT_VERSION//./\\.}"

bump_line() {
    # Replaces a line matching $pattern with $replacement, in $file.
    # Cross-platform sed -i (BSD sed on macOS needs '' after -i).
    local file="$1" pattern="$2" replacement="$3"
    if [ ! -f "$file" ]; then
        echo "ERROR: target path missing (sync-versions configuration is stale): $file" >&2
        return 1
    fi
    if ! grep -Eq "${pattern}" "$file"; then
        echo "ERROR: version pattern not found (sync-versions configuration is stale): $file" >&2
        echo "       pattern: $pattern" >&2
        return 1
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

bump_npm_lock_root_version() {
    local file="$1"
    if [ ! -f "$file" ]; then
        echo "ERROR: target path missing (sync-versions configuration is stale): $file" >&2
        return 1
    fi
    node - "$file" "$NEW_VERSION" <<'NODE'
const fs = require('node:fs');
const [file, version] = process.argv.slice(2);
const lock = JSON.parse(fs.readFileSync(file, 'utf8'));
if (typeof lock.version !== 'string' || typeof lock.packages?.['']?.version !== 'string') {
  throw new Error(`package-lock root version fields are missing: ${file}`);
}
lock.version = version;
lock.packages[''].version = version;
fs.writeFileSync(file, `${JSON.stringify(lock, null, 2)}\n`);
NODE
    echo "  bumped: $file"
}

bump_pubspec_version() {
    local file="$1"
    bump_line "$file" '^version: .+' "version: ${NEW_VERSION}"
}

# Flutter sub-packages (llamacpp/mlx/onnx/qhexrt) depend on the core `runanywhere`
# package via a caret constraint like `runanywhere: ^0.19.13`. When we bump
# the suite, that constraint must track the FULL NEW_VERSION (patch included)
# because backend packages ship native binaries that lockstep with the core
# release; resolving an older same-minor core (e.g. 0.19.0) against a newer
# backend (0.19.13) would create a hard-to-debug native ABI mismatch in apps
# outside the monorepo workspace.
bump_pubspec_runanywhere_dep() {
    local file="$1"
    # Match the entire value (including any `-test` / `-rc.1` / etc. pre-release
    # suffix) up to end-of-line / inline-comment so the replacement does not
    # accidentally preserve a stale suffix when bumping past a pre-release.
    bump_line "$file" '^  runanywhere: \^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?[[:space:]]*(#.*)?$' \
        "  runanywhere: ^${NEW_VERSION}"
}

# Update `"@runanywhere/proto-ts": "^x.y.z"` lines (dependencies / peer ranges)
# across npm package.json files. The published proto-ts package versions are
# kept in lockstep with the SDK suite by sync-versions, so all consumers
# advance to `^${NEW_VERSION}` in the same commit.
bump_npm_proto_ts_dep() {
    local file="$1"
    grep -Eq '"@runanywhere/proto-ts": "\^[0-9]' "$file" || return 0
    bump_line "$file" \
        '"@runanywhere/proto-ts": "\^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?"' \
        "\"@runanywhere/proto-ts\": \"^${NEW_VERSION}\""
}

# RN backend packages are released in lockstep with @runanywhere/core. Keep
# their peer floor on the same full suite version so a newer native backend
# cannot resolve an older core with a different C ABI.
bump_npm_core_dep() {
    local file="$1"
    grep -Eq '"@runanywhere/core": ">=[0-9]' "$file" || return 0
    bump_line "$file" \
        '"@runanywhere/core": ">=[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?"' \
        "\"@runanywhere/core\": \">=${NEW_VERSION}\""
}

# Web backend packages publish against the same core build. Preserve the open
# upper bound while advancing the minimum to this train's exact version.
bump_npm_web_core_dep() {
    local file="$1"
    grep -Eq '"@runanywhere/web": ">=[0-9]' "$file" || return 0
    bump_line "$file" \
        '"@runanywhere/web": ">=[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)? <1"' \
        "\"@runanywhere/web\": \">=${NEW_VERSION} <1\""
}

# Update the first-party `@runanywhere/proto-ts` pin inside
# `dependencies/versions.json`. While that file is otherwise a third-party
# library registry, `@runanywhere/proto-ts` is published from THIS repo in
# lockstep with the SDK suite — leaving the pin behind ships a stale
# version every release. See pass3-syn-015.
bump_versions_json_proto_ts_pin() {
    local file="$1"
    bump_line "$file" \
        '"@runanywhere/proto-ts": "\^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?"' \
        "\"@runanywhere/proto-ts\": \"^${NEW_VERSION}\""
}

bump_gradle_version() {
    local file="$1"
    bump_line "$file" \
        "^version = '[0-9]+\\.[0-9]+\\.[0-9]+([.-][A-Za-z0-9.-]+)?'" \
        "version = '${NEW_VERSION}'"
}

echo ">> Syncing versions to ${NEW_VERSION}"
echo ">> Repo root: ${REPO_ROOT}"
echo ""

# 1. Contributor guidance + commons VERSION + VERSIONS
# Regex is intentionally literal; capture groups are expanded by sed, not bash.
# shellcheck disable=SC2016
bump_line "${REPO_ROOT}/AGENTS.md" \
    '(\*\*Current version\*\*: `)[^`]+(` \(canonical source: `sdk/runanywhere-commons/VERSION`\))' \
    "\\1${NEW_VERSION}\\2"
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
bump_line "${REPO_ROOT}/Package.swift" \
    '(\.package\(url: "https://github\.com/RunanywhereAI/runanywhere-sdks", from: ")[^"]+("\))' \
    "\\1${NEW_VERSION}\\2"
# Swift SDK VERSION file (read by release tooling)
SWIFT_VERSION_FILE="${REPO_ROOT}/sdk/runanywhere-swift/VERSION"
if [ -f "$SWIFT_VERSION_FILE" ]; then
    echo "$NEW_VERSION" > "$SWIFT_VERSION_FILE"
    echo "  bumped: sdk/runanywhere-swift/VERSION"
fi
# SDKConstants.swift is intentionally NOT bumped here: its `version` constant
# now reads `rac_sdk_get_version()` from commons at runtime (single source of
# truth = sdk/runanywhere-commons/VERSION above), so there is no string literal
# to rewrite. See commons-130.
# Versions.swift — RAVersions.sdkVersion (centralized version constant whose
# file header explicitly states `Do not hand-edit; run scripts/release/sync-versions.sh
# to refresh.`). The other RAVersions literals (swiftToolsVersion, dep floors)
# track Package.swift's `.upToNextMinor(from:)` constraints and are managed
# alongside dep bumps in the same commit — not by this release-version script.
bump_line "${REPO_ROOT}/sdk/runanywhere-swift/Sources/RunAnywhere/Generated/Versions.swift" \
    'public static let sdkVersion = "[^"]+"' \
    "public static let sdkVersion = \"${NEW_VERSION}\""

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
bump_line "${REPO_ROOT}/sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/foundation/constants/SDKConstants.kt" \
    'const val VERSION = "[^"]+"' \
    "const val VERSION = \"${NEW_VERSION}\""

# 3a. Shared proto-ts package — pinned to suite version so RN/Web @runanywhere/*
# packages can use `^${NEW_VERSION}` as a single moving target.
echo ""
echo ">> Shared proto-ts:"
bump_json_version "${REPO_ROOT}/sdk/shared/proto-ts/package.json"
bump_npm_lock_root_version "${REPO_ROOT}/sdk/shared/proto-ts/package-lock.json"
# Also bump the first-party `@runanywhere/proto-ts` pin in
# `dependencies/versions.json` (the central TS-deps registry that
# renovate.json's customManager and syncpack read). The proto-ts package is
# published from this repo in lockstep with the SDK suite, so its pin must
# advance with every release — otherwise downstream consumers (and any tool
# reading versions.json as source-of-truth) resolve to the prior release's
# proto-ts. See pass3-syn-015.
bump_versions_json_proto_ts_pin "${REPO_ROOT}/dependencies/versions.json"

# 4. Web SDK packages
echo ""
echo ">> Web SDK:"
for pkg in \
    "${REPO_ROOT}/sdk/runanywhere-web/package.json" \
    "${REPO_ROOT}/sdk/runanywhere-web/packages/core/package.json" \
    "${REPO_ROOT}/sdk/runanywhere-web/packages/diffusion/package.json" \
    "${REPO_ROOT}/sdk/runanywhere-web/packages/llamacpp/package.json" \
    "${REPO_ROOT}/sdk/runanywhere-web/packages/onnx/package.json"; do
    bump_json_version "$pkg"
    bump_npm_proto_ts_dep "$pkg"
    bump_npm_web_core_dep "$pkg"
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
    "${REPO_ROOT}/sdk/runanywhere-react-native/packages/mlx/package.json" \
    "${REPO_ROOT}/sdk/runanywhere-react-native/packages/onnx/package.json" \
    "${REPO_ROOT}/sdk/runanywhere-react-native/packages/qhexrt/package.json"; do
    bump_json_version "$pkg"
    bump_npm_proto_ts_dep "$pkg"
    bump_npm_core_dep "$pkg"
done
bump_line "${REPO_ROOT}/sdk/runanywhere-react-native/lerna.json" \
    '^  "version": "[^"]+"' \
    "  \"version\": \"${NEW_VERSION}\""
# React Native public `RunAnywhere.version` surface — keeps the TS constant
# (consumed by Public/RunAnywhere.ts during initialize) aligned with commons.
bump_line "${REPO_ROOT}/sdk/runanywhere-react-native/packages/core/src/Foundation/Constants/SDKConstants.ts" \
    "version: '[^']+'" \
    "version: '${NEW_VERSION}'"
bump_line "${REPO_ROOT}/sdk/runanywhere-react-native/packages/qhexrt/src/QHexRTProvider.ts" \
    "static readonly version = '[^']+'" \
    "static readonly version = '${NEW_VERSION}'"
for gradle_file in \
    "${REPO_ROOT}/sdk/runanywhere-react-native/packages/llamacpp/android/build.gradle" \
    "${REPO_ROOT}/sdk/runanywhere-react-native/packages/onnx/android/build.gradle"; do
    bump_line "$gradle_file" \
        'def coreVersion = coreVersionFile\.exists\(\) \? coreVersionFile\.text\.trim\(\) : "[^"]+"' \
        "def coreVersion = coreVersionFile.exists() ? coreVersionFile.text.trim() : \"${NEW_VERSION}\""
done

# 6. Flutter SDK packages
echo ""
echo ">> Flutter SDK:"
for pkg in \
    "${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere/pubspec.yaml" \
    "${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere_llamacpp/pubspec.yaml" \
    "${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere_mlx/pubspec.yaml" \
    "${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere_onnx/pubspec.yaml" \
    "${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere_qhexrt/pubspec.yaml"; do
    bump_pubspec_version "$pkg"
done

# Sub-packages depend on the core `runanywhere` package; align their
# dependency floor to match the bumped suite version.
for pkg in \
    "${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere_llamacpp/pubspec.yaml" \
    "${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere_mlx/pubspec.yaml" \
    "${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere_onnx/pubspec.yaml" \
    "${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere_qhexrt/pubspec.yaml"; do
    bump_pubspec_runanywhere_dep "$pkg"
done

# Flutter public `RunAnywhere.version` surface — Dart constant consumed by
# `RunAnywhere.version` getter and by the native init payload.

# Flutter's SwiftPM-enabled iOS packages construct checksum-pinned release URLs
# for clean pub.dev consumers, so their archive version must remain in lockstep.
# MLX is CocoaPods-only and its version is updated with the podspecs below.
for package_manifest in \
    "${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere/ios/runanywhere/Package.swift" \
    "${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere_llamacpp/ios/runanywhere_llamacpp/Package.swift" \
    "${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere_onnx/ios/runanywhere_onnx/Package.swift"; do
    bump_line "$package_manifest" \
        'let sdkVersion = "[^"]+"' \
        "let sdkVersion = \"${NEW_VERSION}\""
done

# Flutter Gradle package versions follow the package release train.
for gradle_file in \
    "${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere/android/build.gradle" \
    "${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere_llamacpp/android/build.gradle" \
    "${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere_onnx/android/build.gradle" \
    "${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere_qhexrt/android/build.gradle"; do
    bump_gradle_version "$gradle_file"
done
for binary_config in \
    "${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere/android/binary_config.gradle" \
    "${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere_llamacpp/android/binary_config.gradle" \
    "${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere_onnx/android/binary_config.gradle"; do
    bump_line "$binary_config" \
        'fallbackCoreVersion = "[^"]+"' \
        "fallbackCoreVersion = \"${NEW_VERSION}\""
done
bump_line "${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere/android/src/main/kotlin/ai/runanywhere/sdk/RunAnywherePlugin.kt" \
    'private const val SDK_VERSION = "[^"]+"' \
    "private const val SDK_VERSION = \"${NEW_VERSION}\""
bump_line "${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere/android/src/main/kotlin/ai/runanywhere/sdk/RunAnywherePlugin.kt" \
    'private const val COMMONS_VERSION = "[^"]+"' \
    "private const val COMMONS_VERSION = \"${NEW_VERSION}\""
bump_line "${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere/ios/runanywhere/Sources/runanywhere/RunAnywherePlugin.swift" \
    'result\("[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?"\)' \
    "result(\"${NEW_VERSION}\")"

# Flutter QHexRT carries native metadata outside pubspec.yaml.
bump_line "${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere_qhexrt/lib/qhexrt.dart" \
    "static const String version = '[^']+'" \
    "static const String version = '${NEW_VERSION}'"
bump_line "${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere_qhexrt/android/src/main/kotlin/ai/runanywhere/sdk/qhexrt/QhexrtPlugin.kt" \
    'private const val BACKEND_VERSION = "[^"]+"' \
    "private const val BACKEND_VERSION = \"${NEW_VERSION}\""

# Flutter iOS podspecs — must be bumped in lockstep with pubspec.yaml.
# Unlike RN podspecs (which derive s.version from package.json at eval time),
# Flutter podspecs hardcode s.version and require an explicit bump here.
for podspec in \
    "${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere/ios/runanywhere.podspec" \
    "${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere_llamacpp/ios/runanywhere_llamacpp.podspec" \
    "${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere_mlx/ios/runanywhere_mlx.podspec" \
    "${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere_onnx/ios/runanywhere_onnx.podspec"; do
    bump_line "$podspec" \
        "s\.version[[:space:]]*=[[:space:]]*'[^']+'" \
        "s.version          = '${NEW_VERSION}'"
done

# Release-facing current-version statements and installation examples. Replace
# only the previous canonical suite version so unrelated tool/native versions
# and historical changelogs remain untouched.
echo ""
echo ">> Release-facing documentation:"
for release_doc in \
    "${REPO_ROOT}/sdk/runanywhere-react-native/AGENTS.md" \
    "${REPO_ROOT}/sdk/runanywhere-react-native/packages/mlx/README.md" \
    "${REPO_ROOT}/sdk/runanywhere-flutter/AGENTS.md" \
    "${REPO_ROOT}/sdk/runanywhere-flutter/README.md" \
    "${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere/README.md" \
    "${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere_llamacpp/README.md" \
    "${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere_mlx/README.md" \
    "${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere_onnx/README.md" \
    "${REPO_ROOT}/sdk/runanywhere-flutter/docs/ARCHITECTURE.md" \
    "${REPO_ROOT}/sdk/runanywhere-flutter/docs/Documentation.md" \
    "${REPO_ROOT}/sdk/runanywhere-swift/ARCHITECTURE.md" \
    "${REPO_ROOT}/sdk/runanywhere-swift/Sources/LlamaCPPRuntime/README.md" \
    "${REPO_ROOT}/sdk/runanywhere-swift/Sources/ONNXRuntime/README.md" \
    "${REPO_ROOT}/sdk/runanywhere-kotlin/README.md"; do
    bump_line "$release_doc" "$CURRENT_VERSION_REGEX" "$NEW_VERSION"
done

echo ""
echo ">> Done. Verify with:"
echo "    git diff -- sdk/ Package.swift"
echo "    corepack yarn install --mode=skip-build"
echo "    (cd sdk/runanywhere-react-native && corepack yarn install --mode=skip-build)"
echo "    (cd sdk/runanywhere-web && npm install --package-lock-only --ignore-scripts)"
echo "    bash scripts/validation/gates/check_release_version_coherence.sh"
echo ""
echo ">> Then prepare and validate every release artifact before tagging:"
echo "    - build the native archives"
echo "    - verify Package.swift defaults to remote binaries (local use requires RUNANYWHERE_USE_LOCAL_NATIVES=1)"
echo "    - sync and commit the real XCFramework checksums"
echo "    - rerun the release gates"
echo ""
echo ">> Commit the reviewed release-preparation changes:"
echo "    git add -u"
echo "    git commit -m \"chore: release ${NEW_VERSION}\""
