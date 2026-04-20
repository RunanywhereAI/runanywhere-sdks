#!/usr/bin/env bash
# =============================================================================
# sync-checksums.sh
# =============================================================================
# Updates the SHA-256 checksum lines in Package.swift's remote binaryTarget
# entries to match freshly-built XCFramework zips. Run after the native
# iOS/macOS builds have produced the zips and before cutting a release tag.
#
# Usage:
#   scripts/sync-checksums.sh ZIP_DIR
#
# Example:
#   scripts/sync-checksums.sh sdk/runanywhere-commons/dist
#   scripts/sync-checksums.sh release-artifacts/native-ios-macos
#
# Looks for files of the form:
#   {name}-v{version}.zip
# where {name} is one of:
#   RACommons, RABackendLLAMACPP, RABackendONNX, RABackendMetalRT,
#   onnxruntime-ios, onnxruntime-macos
#
# and updates the corresponding `checksum: "..."` line in Package.swift.
# =============================================================================

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "usage: $0 ZIP_DIR" >&2
    exit 1
fi

ZIP_DIR="$1"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_SWIFT="${REPO_ROOT}/Package.swift"

if [ ! -f "$PACKAGE_SWIFT" ]; then
    echo "ERROR: Package.swift not found at $PACKAGE_SWIFT" >&2
    exit 1
fi

if [ ! -d "$ZIP_DIR" ]; then
    echo "ERROR: zip dir not found: $ZIP_DIR" >&2
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
    echo "RABackendMetalRTBinary|RABackendMetalRT-ios"
}

sha256_of() {
    # macOS: shasum. Linux: sha256sum. Both emit `<hex>  <file>` on stdout.
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        sha256sum "$1" | awk '{print $1}'
    fi
}

update_checksum_line() {
    # Updates the `checksum: "..."` line that belongs to the `name: "$1"`
    # binaryTarget in Package.swift. Relies on the checksum appearing within
    # a few lines after the name line.
    local binary_name="$1"
    local new_sum="$2"
    python3 - "$binary_name" "$new_sum" "$PACKAGE_SWIFT" <<'PY'
import re, sys

binary_name, new_sum, path = sys.argv[1], sys.argv[2], sys.argv[3]
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
    print(f"  skip: no remote binary target named '{binary_name}' found in Package.swift",
          file=sys.stderr)
    sys.exit(0)

old_sum = m.group(2)
if old_sum == new_sum:
    print(f"  unchanged: {binary_name} ({old_sum[:12]}...)")
    sys.exit(0)

src = src[:m.start(2)] + new_sum + src[m.end(2):]
with open(path, "w") as f:
    f.write(src)
print(f"  bumped:    {binary_name} {old_sum[:12]}... → {new_sum[:12]}...")
PY
}

echo ">> Syncing Package.swift checksums from $ZIP_DIR"

missing=0
updated=0

while IFS='|' read -r binary_name zip_prefix; do
    # Match files like RACommons-v0.20.0.zip, RACommons-v0.20.0-beta.zip, etc.
    zip_file=$(ls "$ZIP_DIR"/${zip_prefix}-v*.zip 2>/dev/null | head -1 || true)
    if [ -z "$zip_file" ]; then
        echo "  missing:   no ${zip_prefix}-v*.zip in $ZIP_DIR"
        missing=$((missing + 1))
        continue
    fi
    sum=$(sha256_of "$zip_file")
    update_checksum_line "$binary_name" "$sum"
    updated=$((updated + 1))
done < <(declare_mapping)

echo ""
echo ">> Done. $updated processed, $missing missing."
echo ""
echo ">> Verify with:"
echo "    git diff -- Package.swift"
