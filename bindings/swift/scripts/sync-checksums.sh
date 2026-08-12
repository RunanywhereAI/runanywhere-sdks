#!/usr/bin/env bash
# =============================================================================
# sync-checksums.sh
# =============================================================================
# Updates SHA-256 checksum lines in the root Swift manifest, Flutter's nested
# iOS Swift manifests, and the CocoaPods-only Flutter MLX podspec to match
# freshly-built XCFramework/resource zips. Run after the native iOS/macOS
# builds have produced the zips and before a tag.
#
# Usage:
#   bindings/swift/scripts/sync-checksums.sh ZIP_DIR
#   bindings/swift/scripts/sync-checksums.sh --check ZIP_DIR
#
# Example:
#   bindings/swift/scripts/sync-checksums.sh core/dist
#   bindings/swift/scripts/sync-checksums.sh release-artifacts/native-ios-macos
#
# CROSS-REPO: the standalone Swift distribution repo
#   https://github.com/RunanywhereAI/runanywhere-swift is a generated,
#   Swift-only mirror of bindings/swift (Package.swift + Sources/ + LICENSE +
#   README.md) that exists so SPM consumers do not clone this whole monorepo.
#   Its Package.swift carries the SAME six remote binaryTarget checksums as the
#   root manifest, pointing at the SAME release assets on runanywhere-sdks — the
#   XCFrameworks are never re-uploaded.
#
#   Export RUNANYWHERE_SWIFT_DIST_REPO=/path/to/runanywhere-swift to make this
#   script update (or, with --check, verify) that manifest in the same pass, so
#   the two can never drift. Unset, nothing changes and only the monorepo
#   manifests are touched.
#
#   Release order (after the native iOS/macOS zips exist):
#     1. scripts/release/sync-versions.sh <version>   # bumps sdkVersion everywhere
#     2. git clone https://github.com/RunanywhereAI/runanywhere-swift.git /tmp/ra-swift
#     3. Refresh /tmp/ra-swift from this tree:
#          rsync -a --delete bindings/swift/Sources/{RunAnywhere,LlamaCPPRuntime,\
#            ONNXRuntime,NeuRTRuntime,MLXRuntime}/ ... into /tmp/ra-swift/Sources/
#          and set `let sdkVersion` in /tmp/ra-swift/Package.swift to <version>.
#     4. RUNANYWHERE_SWIFT_DIST_REPO=/tmp/ra-swift \
#          bindings/swift/scripts/sync-checksums.sh <zip_dir>
#     5. Commit + push BOTH repos, then tag runanywhere-sdks `v<version>` and
#        runanywhere-swift `<version>` (no `v` prefix on the dist repo).
#     6. Re-run with --check against the published zips to prove both manifests
#        still match the immutable tags.
#
# Looks for files of the form:
#   {name}-v{version}.zip
# where {name} is one of:
#   RACommons, RABackendLLAMACPP, RABackendONNX, RABackendSherpa,
#   RABackendMLX, RunAnywhereMLXRuntime, RunAnywhereMLXMetal,
#   RunAnywhereMLXResources
#
# and updates the corresponding immutable checksum declaration.
# =============================================================================

set -euo pipefail

MODE="update"
if [ "${1:-}" = "--check" ]; then
    MODE="check"
    shift
fi

if [ $# -ne 1 ]; then
    echo "usage: $0 [--check] ZIP_DIR" >&2
    exit 1
fi

ZIP_DIR="$1"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PACKAGE_SWIFT="${REPO_ROOT}/Package.swift"
FLUTTER_CORE_PACKAGE="${REPO_ROOT}/bindings/flutter/packages/runanywhere/ios/runanywhere/Package.swift"
FLUTTER_LLAMA_PACKAGE="${REPO_ROOT}/bindings/flutter/packages/runanywhere_llamacpp/ios/runanywhere_llamacpp/Package.swift"
FLUTTER_ONNX_PACKAGE="${REPO_ROOT}/bindings/flutter/packages/runanywhere_onnx/ios/runanywhere_onnx/Package.swift"
FLUTTER_MLX_PODSPEC="${REPO_ROOT}/bindings/flutter/packages/runanywhere_mlx/ios/runanywhere_mlx.podspec"

# Optional cross-repo target: a checkout of the standalone
# RunanywhereAI/runanywhere-swift distribution repo. Its Package.swift declares
# the same six remote binaryTargets against the same runanywhere-sdks release
# assets, so its checksums must move in lockstep with the root manifest. Unset
# → skipped entirely and this script behaves exactly as before.
DIST_SWIFT_PACKAGE=""
if [ -n "${RUNANYWHERE_SWIFT_DIST_REPO:-}" ]; then
    DIST_SWIFT_PACKAGE="${RUNANYWHERE_SWIFT_DIST_REPO%/}/Package.swift"
    if [ ! -f "$DIST_SWIFT_PACKAGE" ]; then
        echo "ERROR: RUNANYWHERE_SWIFT_DIST_REPO is set but no Package.swift at" >&2
        echo "       $DIST_SWIFT_PACKAGE" >&2
        exit 1
    fi
fi

if [ ! -f "$PACKAGE_SWIFT" ]; then
    echo "ERROR: Package.swift not found at $PACKAGE_SWIFT" >&2
    exit 1
fi

for flutter_manifest in \
    "$FLUTTER_CORE_PACKAGE" \
    "$FLUTTER_LLAMA_PACKAGE" \
    "$FLUTTER_ONNX_PACKAGE"; do
    if [ ! -f "$flutter_manifest" ]; then
        echo "ERROR: Flutter Package.swift not found at $flutter_manifest" >&2
        exit 1
    fi
done

if [ ! -f "$FLUTTER_MLX_PODSPEC" ]; then
    echo "ERROR: Flutter MLX podspec not found at $FLUTTER_MLX_PODSPEC" >&2
    exit 1
fi

if [ ! -d "$ZIP_DIR" ]; then
    echo "ERROR: zip dir not found: $ZIP_DIR" >&2
    exit 1
fi

SDK_VERSION="$(sed -nE 's/^let sdkVersion = "([^"]+)"$/\1/p' "$PACKAGE_SWIFT")"
if [ -z "$SDK_VERSION" ]; then
    echo "ERROR: could not read sdkVersion from Package.swift" >&2
    exit 1
fi

for flutter_manifest in \
    "$FLUTTER_CORE_PACKAGE" \
    "$FLUTTER_LLAMA_PACKAGE" \
    "$FLUTTER_ONNX_PACKAGE"; do
    flutter_version="$(sed -nE 's/^let sdkVersion = "([^"]+)"$/\1/p' "$flutter_manifest")"
    if [ "$flutter_version" != "$SDK_VERSION" ]; then
        echo "ERROR: Flutter manifest version mismatch: $flutter_manifest" >&2
        echo "       expected $SDK_VERSION, found ${flutter_version:-<missing>}" >&2
        exit 1
    fi
done

flutter_mlx_version="$(sed -nE "s/^[[:space:]]*s\.version[[:space:]]*=[[:space:]]*'([^']+)'$/\1/p" "$FLUTTER_MLX_PODSPEC")"
if [ "$flutter_mlx_version" != "$SDK_VERSION" ]; then
    echo "ERROR: Flutter MLX podspec version mismatch: $FLUTTER_MLX_PODSPEC" >&2
    echo "       expected $SDK_VERSION, found ${flutter_mlx_version:-<missing>}" >&2
    exit 1
fi

if [ -n "$DIST_SWIFT_PACKAGE" ]; then
    dist_version="$(sed -nE 's/^let sdkVersion = "([^"]+)"$/\1/p' "$DIST_SWIFT_PACKAGE")"
    if [ "$dist_version" != "$SDK_VERSION" ]; then
        echo "ERROR: runanywhere-swift manifest version mismatch: $DIST_SWIFT_PACKAGE" >&2
        echo "       expected $SDK_VERSION, found ${dist_version:-<missing>}" >&2
        echo "       Bump 'let sdkVersion' in the distribution repo before syncing." >&2
        exit 1
    fi
fi

# swiftpm binary target name → local-filename-prefix pairs. Names match the
# `.binaryTarget(name: "X", ...)` entries in Package.swift.
# Since v0.19.0, iOS xcframework zips are suffixed "-ios-" to disambiguate
# from Android per-ABI zips. ONNX Runtime is now bundled into RABackendONNX
# and no longer distributed as a separate artifact.
declare_mapping() {
    # Printed form: BINARY_NAME|ZIP_PREFIX
    echo "RACommonsBinary|RACommons-ios"
    echo "RABackendLlamaCPPBinary|RABackendLLAMACPP-ios"
    echo "RABackendONNXBinary|RABackendONNX-ios"
    echo "RABackendSherpaBinary|RABackendSherpa-ios"
    echo "RABackendNeuRTBinary|RABackendNeuRT-ios"
    echo "RABackendMLXBinary|RABackendMLX-ios"
}

sha256_of() {
    # macOS: shasum. Linux: sha256sum. Both emit `<hex>  <file>` on stdout.
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        sha256sum "$1" | awk '{print $1}'
    fi
}

process_checksum_line() {
    local binary_name="$1"
    local new_sum="$2"
    local manifest="$3"
    local pattern_kind="$4"
    python3 - "$MODE" "$binary_name" "$new_sum" "$manifest" "$pattern_kind" <<'PY'
import re, sys

mode, binary_name, new_sum, path, pattern_kind = sys.argv[1:]
with open(path) as f:
    src = f.read()

if pattern_kind == "remote-binary-target":
    # Root manifest: require `url:` between name and checksum to avoid the
    # local-mode entry, which uses `path:` and has no checksum.
    pattern = re.compile(
        r'(name:\s*"' + re.escape(binary_name) + r'"\s*,\s*url:\s*"[^"]+"\s*,\s*checksum:\s*")([0-9a-f]{64})(")',
        re.DOTALL,
    )
elif pattern_kind == "flutter-helper":
    # Flutter manifests select a local path when staged frameworks exist and
    # otherwise construct the remote binaryTarget through this helper call.
    pattern = re.compile(
        r'(runAnywhereBinaryTarget\(\s*name:\s*"' + re.escape(binary_name)
        + r'"\s*,\s*checksum:\s*")([0-9a-f]{64})("\s*\))',
        re.DOTALL,
    )
elif pattern_kind == "flutter-podspec":
    pattern = re.compile(
        r"('" + re.escape(binary_name) + r"'\s*=>\s*')([0-9a-f]{64})(')"
    )
else:
    print(f"  error: unknown checksum pattern kind: {pattern_kind}", file=sys.stderr)
    sys.exit(1)

m = pattern.search(src)
if not m:
    print(f"  error: no checksum target named '{binary_name}' found in {path}",
          file=sys.stderr)
    sys.exit(1)

old_sum = m.group(2)
if mode == "check":
    if old_sum != new_sum:
        print(f"  mismatch: {binary_name}", file=sys.stderr)
        print(f"    {path}: {old_sum}", file=sys.stderr)
        print(f"    release zip:   {new_sum}", file=sys.stderr)
        sys.exit(1)
    print(f"  verified:  {binary_name} ({old_sum[:12]}...)")
    sys.exit(0)

if old_sum == new_sum:
    print(f"  unchanged: {binary_name} ({old_sum[:12]}...)")
    sys.exit(0)

src = src[:m.start(2)] + new_sum + src[m.end(2):]
with open(path, "w") as f:
    f.write(src)
print(f"  bumped:    {binary_name} {old_sum[:12]}... → {new_sum[:12]}...")
PY
}

if [ "$MODE" = "check" ]; then
    echo ">> Verifying release ZIP checksums against tagged Apple package contracts"
else
    echo ">> Syncing Apple package checksums from $ZIP_DIR"
fi
echo ">> Swift release version: $SDK_VERSION"

missing=0
processed=0
failed=0

while IFS='|' read -r binary_name zip_prefix; do
    # Match the manifest version exactly. A stale archive from another release
    # must never be allowed to update or validate this tag's checksum.
    zip_file="$ZIP_DIR/${zip_prefix}-v${SDK_VERSION}.zip"
    if [ ! -f "$zip_file" ]; then
        echo "  missing:   ${zip_prefix}-v${SDK_VERSION}.zip in $ZIP_DIR" >&2
        missing=$((missing + 1))
        continue
    fi
    sum=$(sha256_of "$zip_file")
    if ! process_checksum_line \
        "$binary_name" "$sum" "$PACKAGE_SWIFT" remote-binary-target; then
        failed=$((failed + 1))
    fi
    # The standalone distribution repo uses byte-identical binaryTarget names
    # and the same remote `url:` + `checksum:` shape, so the root pattern
    # applies unchanged.
    if [ -n "$DIST_SWIFT_PACKAGE" ]; then
        if ! process_checksum_line \
            "$binary_name" "$sum" "$DIST_SWIFT_PACKAGE" remote-binary-target; then
            failed=$((failed + 1))
        fi
    fi
    case "$binary_name" in
        RACommonsBinary)
            if ! process_checksum_line \
                RACommons "$sum" "$FLUTTER_CORE_PACKAGE" flutter-helper; then
                failed=$((failed + 1))
            fi
            ;;
        RABackendLlamaCPPBinary)
            if ! process_checksum_line \
                RABackendLLAMACPP "$sum" "$FLUTTER_LLAMA_PACKAGE" flutter-helper; then
                failed=$((failed + 1))
            fi
            ;;
        RABackendONNXBinary)
            if ! process_checksum_line \
                RABackendONNX "$sum" "$FLUTTER_ONNX_PACKAGE" flutter-helper; then
                failed=$((failed + 1))
            fi
            ;;
        RABackendSherpaBinary)
            if ! process_checksum_line \
                RABackendSherpa "$sum" "$FLUTTER_ONNX_PACKAGE" flutter-helper; then
                failed=$((failed + 1))
            fi
            ;;
        RABackendNeuRTBinary)
            # runanywhere_onnx vendors RABackendNeuRT alongside ONNX/Sherpa, so
            # its Flutter manifest pins this checksum too.
            if ! process_checksum_line \
                RABackendNeuRT "$sum" "$FLUTTER_ONNX_PACKAGE" flutter-helper; then
                failed=$((failed + 1))
            fi
            ;;
        RABackendMLXBinary)
            if ! process_checksum_line \
                RABackendMLX "$sum" "$FLUTTER_MLX_PODSPEC" flutter-podspec; then
                failed=$((failed + 1))
            fi
            ;;
    esac
    processed=$((processed + 1))
done < <(declare_mapping)

# The Flutter MLX CocoaPods contract distributes the canonical Swift
# runtime, the platform-selected dynamic Metal framework, and Hub/Crypto
# resources as independent archives. They are intentionally absent from the
# root manifest: normal Swift SDK consumers compile the canonical source
# RunAnywhereMLX product instead of these CocoaPods-oriented binaries.
#
# RAC_CHECKSUM_SKIP (space/comma-separated archive names) opts an archive out of
# both update and --check. This exists to ship a release while a specific archive
# is not yet byte-reproducible across CI runs — currently RunAnywhereMLXRuntime,
# whose stripped mach-O still differs ~1.3KB build-to-build (see
# thoughts/shared/issues/sdk-release-bugs.md). The affected package (Flutter
# runanywhere_mlx) MUST NOT be published while its archive is skipped.
rac_should_skip_checksum() {
    local norm=" ${RAC_CHECKSUM_SKIP:-} "
    norm="${norm//,/ }"
    case "$norm" in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

while IFS='|' read -r target_name zip_prefix; do
    if rac_should_skip_checksum "$target_name"; then
        echo "  skipped:   $target_name (RAC_CHECKSUM_SKIP)" >&2
        continue
    fi
    zip_file="$ZIP_DIR/${zip_prefix}-v${SDK_VERSION}.zip"
    if [ ! -f "$zip_file" ]; then
        echo "  missing:   ${zip_prefix}-v${SDK_VERSION}.zip in $ZIP_DIR" >&2
        missing=$((missing + 1))
        continue
    fi
    sum=$(sha256_of "$zip_file")
    if ! process_checksum_line \
        "$target_name" "$sum" "$FLUTTER_MLX_PODSPEC" flutter-podspec; then
        failed=$((failed + 1))
    fi
    processed=$((processed + 1))
done <<'EOF'
RunAnywhereMLXRuntime|RunAnywhereMLXRuntime-ios
RunAnywhereMLXMetal|RunAnywhereMLXMetal-ios
EOF

mlx_resources_zip="$ZIP_DIR/RunAnywhereMLXResources-ios-v${SDK_VERSION}.zip"
if [ ! -f "$mlx_resources_zip" ]; then
    echo "  missing:   RunAnywhereMLXResources-ios-v${SDK_VERSION}.zip in $ZIP_DIR" >&2
    missing=$((missing + 1))
else
    mlx_resources_sum=$(sha256_of "$mlx_resources_zip")
    if ! process_checksum_line \
        RunAnywhereMLXResources "$mlx_resources_sum" "$FLUTTER_MLX_PODSPEC" flutter-podspec; then
        failed=$((failed + 1))
    fi
    processed=$((processed + 1))
fi

echo ""
echo ">> Done. $processed processed, $missing missing, $failed failed."

if [ "$MODE" = "check" ]; then
    if [ "$missing" -ne 0 ] || [ "$failed" -ne 0 ]; then
        echo "ERROR: built Swift archives do not match the immutable tagged manifest" >&2
        exit 1
    fi
    echo ">> Root/Flutter manifests and the Flutter MLX podspec match every release archive."
    if [ -n "$DIST_SWIFT_PACKAGE" ]; then
        echo ">> runanywhere-swift distribution manifest matches too: $DIST_SWIFT_PACKAGE"
    fi
else
    if [ "$missing" -ne 0 ] || [ "$failed" -ne 0 ]; then
        echo "ERROR: could not update every Swift binary target checksum" >&2
        exit 1
    fi
    echo ""
    echo ">> Verify with:"
    echo "    git diff -- Package.swift bindings/flutter/packages/*/ios/*/Package.swift $FLUTTER_MLX_PODSPEC"
    if [ -n "$DIST_SWIFT_PACKAGE" ]; then
        echo "    git -C ${RUNANYWHERE_SWIFT_DIST_REPO%/} diff -- Package.swift"
        echo ""
        echo ">> Remember: commit + push the runanywhere-swift repo and tag it"
        echo "   ${SDK_VERSION} (no 'v' prefix) so 'from: \"${SDK_VERSION}\"' resolves."
    fi
fi
