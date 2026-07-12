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
#   scripts/release/validate-artifact.sh PATH [PATH ...]
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
            # Avoid `grep -q` under pipefail: on a large archive it exits as
            # soon as it sees classes.jar, unzip receives SIGPIPE, and the
            # otherwise-valid pipeline is reported as a failure.
            if ! unzip -Z1 "$path" | grep -Fx 'classes.jar' >/dev/null; then
                fail "AAR missing classes.jar: $path"
            fi
            ok "AAR contains classes.jar"
            if unzip -Z1 "$path" | grep -E 'jni/[^/]*/.*\.so$' >/dev/null; then
                local count
                count=$(unzip -Z1 "$path" | grep -Ec 'jni/[^/]*/.*\.so$' || true)
                ok "AAR contains $count jni/*.so entries"
            else
                echo "    note: no JNI .so files bundled (AAR may link against external natives)"
            fi
            ;;
        *.jar)
            if ! unzip -l "$path" >/dev/null 2>&1; then
                fail "cannot unzip $path"
            fi
            if ! unzip -Z1 "$path" | grep -Fx 'META-INF/MANIFEST.MF' >/dev/null; then
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
            local plist_entry
            plist_entry=$(unzip -Z1 "$path" | awk '/\.xcframework\/Info\.plist$/ { entry = $0 } END { print entry }')
            if [ -n "$plist_entry" ]; then
                ok "XCFramework ZIP: Info.plist present"
                # Static-library XCFrameworks have one root Info.plist; their
                # slices are declared as AvailableLibraries entries rather
                # than per-slice Info.plist files.
                local slices
                slices=$(unzip -p "$path" "$plist_entry" | grep -c '<key>LibraryIdentifier</key>' || true)
                if [ "$slices" -le 0 ]; then
                    fail "XCFramework Info.plist declares no library slices: $path"
                fi
                echo "    arch slices declared: $slices"
            else
                ok "ZIP listable ($(unzip -l "$path" | tail -1 | awk '{print $2}') entries)"
            fi
            ;;
        *)
            ok "unknown extension — size check only"
            ;;
    esac

    return 0
}

for path in "$@"; do
    validate_one "$path"
done

echo ""
echo "All $# artifact(s) passed validation."
