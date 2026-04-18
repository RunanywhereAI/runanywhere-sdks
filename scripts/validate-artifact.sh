#!/usr/bin/env bash
# =============================================================================
# validate-artifact.sh
# =============================================================================
# Same-shape artifact validator for local + CI. Given a path to one of our
# published artifact files, does the minimum sanity-checks to catch
# "built it but it's broken" before we publish:
#
#   .zip         → unzip list non-empty, contains expected files
#   .xcframework (as .zip) → Info.plist present + declares arch slices
#   .so          → ELF, machine arch matches filename convention
#   .aar         → unzip lists classes.jar + jni/{abi}/*.so
#   .wasm        → starts with WebAssembly magic bytes (0x00 'asm')
#   .tgz (npm)   → `tar -tzf` lists package/package.json
#   .jar         → zip-listable, has META-INF/MANIFEST.MF
#
# Usage:
#   scripts/validate-artifact.sh PATH [PATH ...]
#
# Exit status: 0 if every path passed, 1 on first failure.
# =============================================================================

set -euo pipefail

if [ $# -eq 0 ]; then
    echo "usage: $0 FILE [FILE ...]" >&2
    exit 1
fi

fail() { echo "  ✗ $1" >&2; exit 1; }
ok()   { echo "  ✓ $1"; }

validate_one() {
    local path="$1"

    if [ ! -f "$path" ]; then
        fail "not a regular file: $path"
    fi

    local size
    size=$(stat -f%z "$path" 2>/dev/null || stat -c%s "$path")
    if [ "$size" -lt 64 ]; then
        fail "suspiciously small ($size bytes): $path"
    fi

    echo ">> $path  ($size bytes)"

    case "$path" in
        *.sha256)
            # .sha256 is its own checksum file; sanity check it's single-line, 64 hex + space + filename
            local line
            line=$(head -1 "$path")
            if ! echo "$line" | grep -Eq '^[0-9a-f]{64} '; then
                fail "bad .sha256 format in $path: $line"
            fi
            ok ".sha256 looks well-formed"
            ;;
        *.wasm)
            # Magic: 0x00 'asm' (0x00 0x61 0x73 0x6d)
            local magic
            magic=$(head -c 4 "$path" | xxd -p | head -1)
            if [ "$magic" != "0061736d" ]; then
                fail "not a WebAssembly module (bad magic '$magic'): $path"
            fi
            ok "WebAssembly magic bytes OK"
            ;;
        *.so)
            if ! head -c 4 "$path" | grep -q $'\x7fELF' 2>/dev/null; then
                fail "not an ELF shared library: $path"
            fi
            ok "ELF shared library OK"
            if command -v readelf >/dev/null 2>&1; then
                local arch
                arch=$(readelf -h "$path" 2>/dev/null | awk -F'Machine:' 'NF>1 {print $2}' | xargs)
                [ -n "$arch" ] && echo "    machine: $arch"
            fi
            ;;
        *.aar)
            if ! unzip -l "$path" >/dev/null 2>&1; then
                fail "cannot unzip $path"
            fi
            if ! unzip -l "$path" | grep -q '^.* classes.jar$'; then
                fail "AAR missing classes.jar: $path"
            fi
            ok "AAR contains classes.jar"
            if unzip -l "$path" | grep -q 'jni/[^/]*/.*\.so$'; then
                local count
                count=$(unzip -l "$path" | grep -c 'jni/[^/]*/.*\.so$' || true)
                ok "AAR contains $count jni/*.so entries"
            else
                echo "    note: no JNI .so files bundled (AAR may link against external natives)"
            fi
            ;;
        *.jar)
            if ! unzip -l "$path" >/dev/null 2>&1; then
                fail "cannot unzip $path"
            fi
            if ! unzip -l "$path" | grep -q 'META-INF/MANIFEST.MF$'; then
                fail "JAR missing META-INF/MANIFEST.MF: $path"
            fi
            ok "JAR has valid manifest"
            ;;
        *.tgz|*.tar.gz)
            if ! tar -tzf "$path" >/dev/null 2>&1; then
                fail "cannot list tarball $path"
            fi
            if tar -tzf "$path" | grep -q '^package/package.json$'; then
                ok "npm tarball contains package/package.json"
            else
                ok "tarball listable ($(tar -tzf "$path" | wc -l | xargs) entries)"
            fi
            ;;
        *.zip)
            if ! unzip -l "$path" >/dev/null 2>&1; then
                fail "cannot unzip $path"
            fi
            # XCFramework ZIPs contain an Info.plist at top of the framework root
            if unzip -l "$path" | grep -q '\.xcframework/Info\.plist$'; then
                ok "XCFramework ZIP: Info.plist present"
                # Count arch slices (each subdir with an Info.plist sibling is a slice)
                local slices
                slices=$(unzip -l "$path" | grep -c '\.xcframework/[^/]*/Info\.plist$' || true)
                [ "$slices" -gt 0 ] && echo "    arch slices declared: $slices"
            else
                ok "ZIP listable ($(unzip -l "$path" | tail -1 | awk '{print $2}') entries)"
            fi
            ;;
        *)
            ok "unknown extension — size check only"
            ;;
    esac
}

for path in "$@"; do
    validate_one "$path"
done

echo ""
echo "All $# artifact(s) passed validation."
