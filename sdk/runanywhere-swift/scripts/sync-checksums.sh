#!/usr/bin/env bash
# =============================================================================
# sync-checksums.sh
# =============================================================================
# Updates the SHA-256 checksum lines in Package.swift's remote binaryTarget
# entries to match freshly-built XCFramework zips. Run after the native
# iOS/macOS builds have produced the zips and before cutting a release tag.
#
# Usage:
#   sdk/runanywhere-swift/scripts/sync-checksums.sh ZIP_DIR
#   sdk/runanywhere-swift/scripts/sync-checksums.sh --check ZIP_DIR
#
# Example:
#   sdk/runanywhere-swift/scripts/sync-checksums.sh sdk/runanywhere-commons/dist
#   sdk/runanywhere-swift/scripts/sync-checksums.sh release-artifacts/native-ios-macos
#
# Looks for files of the form:
#   {name}-v{version}.zip
# where {name} is one of:
#   RACommons, RABackendLLAMACPP, RABackendONNX, RABackendSherpa,
#   RABackendMLX
#
# and updates the corresponding `checksum: "..."` line in Package.swift.
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

if [ ! -f "$PACKAGE_SWIFT" ]; then
    echo "ERROR: Package.swift not found at $PACKAGE_SWIFT" >&2
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
    python3 - "$MODE" "$binary_name" "$new_sum" "$PACKAGE_SWIFT" <<'PY'
import re, sys

mode, binary_name, new_sum, path = sys.argv[1:]
with open(path) as f:
    src = f.read()

# Find the remote-mode binaryTarget: `name: "X", url: "...", checksum: "..."`.
# We require `url:` between name and checksum to avoid the local-mode entry
# (which uses `path:` and has no checksum) — without this anchor, the non-
# greedy `.*?` would skip past the local entry and match the checksum of
# the NEXT remote target in the file, causing cross-target mis-assignment.
pattern = re.compile(
    r'(name:\s*"' + re.escape(binary_name) + r'"\s*,\s*url:\s*"[^"]+"\s*,\s*checksum:\s*")([0-9a-f]{64})(")',
    re.DOTALL,
)

m = pattern.search(src)
if not m:
    print(f"  error: no remote binary target named '{binary_name}' found in Package.swift",
          file=sys.stderr)
    sys.exit(1)

old_sum = m.group(2)
if mode == "check":
    if old_sum != new_sum:
        print(f"  mismatch: {binary_name}", file=sys.stderr)
        print(f"    Package.swift: {old_sum}", file=sys.stderr)
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
    echo ">> Verifying release ZIP checksums against tagged Package.swift"
else
    echo ">> Syncing Package.swift checksums from $ZIP_DIR"
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
    if ! process_checksum_line "$binary_name" "$sum"; then
        failed=$((failed + 1))
    fi
    processed=$((processed + 1))
done < <(declare_mapping)

echo ""
echo ">> Done. $processed processed, $missing missing, $failed failed."

if [ "$MODE" = "check" ]; then
    if [ "$missing" -ne 0 ] || [ "$failed" -ne 0 ]; then
        echo "ERROR: built Swift archives do not match the immutable tagged manifest" >&2
        exit 1
    fi
    echo ">> Tagged Package.swift matches every Swift release archive."
else
    if [ "$missing" -ne 0 ] || [ "$failed" -ne 0 ]; then
        echo "ERROR: could not update every Swift binary target checksum" >&2
        exit 1
    fi
    echo ""
    echo ">> Verify with:"
    echo "    git diff -- Package.swift"
fi
