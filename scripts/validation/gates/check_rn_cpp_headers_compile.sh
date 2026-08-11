#!/usr/bin/env bash
# Compile every hand-written React Native C++ header against the real generated
# Nitro specs.
#
# The RN bridge C++ is otherwise compiled ONLY by an app build (CocoaPods /
# Gradle), which PR CI does not run — so a spec change that regenerates a pure
# virtual without updating the hand-written `override` shipped a header that
# could not compile, and every CI job stayed green. This is that missing
# compile.
#
# `-fsyntax-only` on the headers is enough for this bug class: override matching
# against the spec's pure virtuals is resolved when the class is defined, so a
# signature that no longer overrides anything fails here exactly as it would in
# an app build — without needing a linked libc++/RACommons or an NDK.
#
# Run from anywhere. Requires `yarn install` to have run in
# bindings/react-native (for the Nitro and React Native jsi headers).

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
RN="$REPO/bindings/react-native"
NM="$RN/node_modules"
COMMONS_INCLUDE="$REPO/core/include"

CXX="${CXX:-}"
if [[ -z "$CXX" ]]; then
    for candidate in clang++ g++; do
        if command -v "$candidate" >/dev/null 2>&1; then
            CXX="$candidate"
            break
        fi
    done
fi
if [[ -z "$CXX" ]]; then
    echo "::error::no C++ compiler found (set CXX)"
    exit 1
fi

# Fail closed: a missing dependency must not read as "nothing to check".
for required in \
    "$NM/react-native-nitro-modules/cpp" \
    "$NM/react-native/ReactCommon/jsi/jsi/jsi.h" \
    "$COMMONS_INCLUDE"; do
    if [[ ! -e "$required" ]]; then
        echo "::error::missing ${required#"$REPO"/} — run \`yarn install\` in bindings/react-native"
        exit 1
    fi
done

# Nitro headers are included as <NitroModules/X.hpp>; CocoaPods and the Nitro
# CMake package expose them under that prefix. Mirror it with a symlink tree.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/NitroModules"
find "$NM/react-native-nitro-modules/cpp" -name "*.hpp" -exec ln -sf {} "$STAGE/NitroModules/" \;

# RACommons ships a FLAT header dir in the xcframework, and the bridge includes
# them unqualified ("rac_core.h"). Reproduce that by adding every subdirectory.
INCLUDES=()
while IFS= read -r dir; do
    INCLUDES+=("-I$dir")
done < <(find "$COMMONS_INCLUDE" -type d)

INCLUDES+=(
    "-I$STAGE"
    "-I$NM/react-native/ReactCommon/jsi"
    "-I$NM/react-native/ReactCommon"
)

checked=0
failed=0
for header in "$RN"/packages/*/cpp/*.hpp; do
    [[ -e "$header" ]] || continue
    package="$(basename "$(dirname "$(dirname "$header")")")"
    spec_dir="$RN/packages/$package/nitrogen/generated/shared/c++"
    if [[ ! -d "$spec_dir" ]]; then
        echo "::error::${header#"$REPO"/}: no generated Nitro spec — run \`yarn ${package}:nitrogen\`"
        failed=$((failed + 1))
        continue
    fi

    checked=$((checked + 1))
    if ! output="$("$CXX" -fsyntax-only -std=c++20 -Wno-pragma-once-outside-header \
        -I "$spec_dir" "${INCLUDES[@]}" -x c++ "$header" 2>&1)"; then
        echo "::error::${header#"$REPO"/} does not compile against the generated Nitro spec"
        echo "$output" | head -20
        failed=$((failed + 1))
    fi
done

if [[ "$checked" -eq 0 ]]; then
    echo "::error::found no hand-written RN C++ headers — this gate is misconfigured"
    exit 1
fi

if [[ "$failed" -gt 0 ]]; then
    echo
    echo "Regenerate with \`yarn <package>:nitrogen\`, then update the hand-written header to match."
    exit 1
fi

echo "RN C++ headers compile against the generated Nitro specs ($checked headers, $CXX)"
