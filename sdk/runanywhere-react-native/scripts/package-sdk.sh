#!/usr/bin/env bash
# =============================================================================
# sdk/runanywhere-react-native/scripts/package-sdk.sh
# =============================================================================
# Unified SDK packaging contract for the React Native SDK. Consumes pre-built
# iOS XCFrameworks + Android .so files, stages each native binary only into the
# RN package that owns it, and produces npm tarballs with checksums.
#
# USAGE:
#   package-sdk.sh [--mode local|ci] [--natives-from PATH]
#                  [--include-private-qhexrt]
#
# OPTIONS:
#   --mode local|ci      Build mode (default: auto-detect from $CI)
#   --natives-from PATH  Directory with iOS xcframeworks + Android .so files.
#                        iOS uses the Swift-shaped binary names:
#                        core=RACommons, llamacpp=RABackendLLAMACPP,
#                        mlx=RABackendMLX+RunAnywhereMLXRuntime+
#                            RunAnywhereMLXMetal, with Hub/Crypto resources in
#                            PATH/RunAnywhereMLXRuntimeResources,
#                        onnx=RABackendONNX+RABackendSherpa.
#                        Android uses only canonical ownership roots
#                        PATH/<abi>/{jni,llamacpp,onnx}/*.so.
#   --include-private-qhexrt
#                        INTERNAL ONLY. Stage the private QHexRT package and
#                        emit it under dist/sdk-rn-internal/ from
#                        PATH/arm64-v8a/qhexrt/*.so. Public packaging always
#                        skips QHexRT and removes stale private natives.
#
# OUTPUTS:
#   dist/sdk-rn/*.tgz     + .sha256    (one per public npm workspace)
#   dist/sdk-rn-internal/*.tgz + .sha256 (private opt-in only)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
RN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${REPO_ROOT}/scripts/setup/detect-mode.sh"

NATIVES_FROM=""
INCLUDE_PRIVATE_QHEXRT=0

while [ $# -gt 0 ]; do
    case "$1" in
        --mode) RAC_BUILD_MODE="$2"; shift 2 ;;
        --natives-from) NATIVES_FROM="$2"; shift 2 ;;
        --include-private-qhexrt) INCLUDE_PRIVATE_QHEXRT=1; shift ;;
        --help|-h) sed -n '8,29p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 1 ;;
    esac
done

echo ">> React Native SDK packaging (mode=${RAC_BUILD_MODE})"

QHEXRT_ROOT="$RN_ROOT/packages/qhexrt"
DIST_DIR="$RN_ROOT/dist/sdk-rn"
INTERNAL_DIST_DIR="$RN_ROOT/dist/sdk-rn-internal"
PUBLIC_PACKAGE_DIRS=(core llamacpp mlx onnx)

validation_failure() {
    local description="$1"
    echo "ERROR: $description" >&2
    exit 1
}

# Public packaging must never inherit private output from a prior local build.
# An explicit internal run re-stages the complete private inventory below and
# writes its tarball outside the public release artifact directory.
rm -rf \
    "$QHEXRT_ROOT/android/src/main/jniLibs" \
    "$QHEXRT_ROOT/android/src/main/assets/runanywhere/qhexrt/skels" \
    "$DIST_DIR" \
    "$INTERNAL_DIST_DIR"

if [ "$INCLUDE_PRIVATE_QHEXRT" = "1" ] && [ -z "$NATIVES_FROM" ]; then
    echo "ERROR: --include-private-qhexrt requires --natives-from PATH" >&2
    exit 1
fi

if [ -n "$NATIVES_FROM" ]; then
    [ -d "$NATIVES_FROM" ] || { echo "ERROR: --natives-from not found: $NATIVES_FROM" >&2; exit 1; }
    echo ">> Staging natives from $NATIVES_FROM with explicit package ownership"

    stage_ios() {
        local pkg_dir="$1"
        shift
        local ios_bin="$pkg_dir/ios/Binaries"
        local framework

        for framework in "$@"; do
            if [ ! -d "$NATIVES_FROM/${framework}.xcframework" ]; then
                echo "ERROR: missing iOS framework for $(basename "$pkg_dir"): ${framework}.xcframework" >&2
                exit 1
            fi
        done

        rm -rf "$ios_bin" "$pkg_dir/ios/Frameworks"
        mkdir -p "$ios_bin"
        for framework in "$@"; do
            cp -R "$NATIVES_FROM/${framework}.xcframework" "$ios_bin/"
        done
    }

    stage_mlx_ios_resources() {
        local src="$NATIVES_FROM/RunAnywhereMLXRuntimeResources"
        local mlx_ios="$RN_ROOT/packages/mlx/ios"
        local resources="$mlx_ios/Resources"
        local notices="$mlx_ios/ThirdPartyNotices"
        local bundle required

        [ -d "$src" ] || {
            echo "ERROR: missing MLX runtime resources: $src" >&2
            exit 1
        }
        for bundle in swift-crypto_Crypto swift-transformers_Hub; do
            if [ ! -d "$src/${bundle}.bundle" ]; then
                echo "ERROR: missing MLX runtime resource bundle: ${bundle}.bundle" >&2
                exit 1
            fi
        done
        for required in \
            "swift-crypto_Crypto.bundle/PrivacyInfo.xcprivacy" \
            "swift-transformers_Hub.bundle/gpt2_tokenizer_config.json" \
            "swift-transformers_Hub.bundle/t5_tokenizer_config.json"; do
            if [ ! -s "$src/$required" ]; then
                echo "ERROR: missing or empty MLX runtime resource: $required" >&2
                exit 1
            fi
        done
        for bundle in RunAnywhereMLXMetalDevice RunAnywhereMLXMetalSimulator; do
            if [ -e "$src/${bundle}.bundle" ]; then
                echo "ERROR: obsolete MLX Metal sidecar is not publishable: ${bundle}.bundle" >&2
                exit 1
            fi
        done
        if [ ! -d "$src/ThirdPartyNotices" ] || \
           [ -z "$(find "$src/ThirdPartyNotices" -type f -print -quit)" ]; then
            echo "ERROR: MLX runtime third-party notices are missing or empty" >&2
            exit 1
        fi

        rm -rf "$resources" "$notices"
        mkdir -p "$resources"
        cp -R "$src/swift-crypto_Crypto.bundle" "$resources/"
        cp -R "$src/swift-transformers_Hub.bundle" "$resources/"
        cp -R "$src/ThirdPartyNotices" "$notices"
    }

    android_component_dir() {
        local abi="$1"
        local component="$2"
        printf '%s\n' "$NATIVES_FROM/$abi/$component"
    }

    android_abi_supplied() {
        local abi="$1"
        local component src
        for component in jni llamacpp onnx; do
            src="$(android_component_dir "$abi" "$component")"
            if [ -d "$src" ] && find "$src" -maxdepth 1 -type f -name '*.so' -print -quit | grep -q .; then
                return 0
            fi
        done
        return 1
    }

    validate_android_layout() {
        local abi left right file name child child_name
        for abi in arm64-v8a armeabi-v7a x86_64 x86; do
            if find "$NATIVES_FROM/$abi" -maxdepth 1 -type f -name '*.so' -print -quit 2>/dev/null | grep -q .; then
                echo "ERROR: non-canonical Android layout under $NATIVES_FROM/$abi; use {jni,llamacpp,onnx} ownership directories" >&2
                exit 1
            fi
            for child in "$NATIVES_FROM/$abi"/*; do
                [ -d "$child" ] || continue
                child_name="$(basename "$child")"
                case "$child_name" in
                    jni|llamacpp|onnx|qhexrt) ;;
                    *)
                        if find "$child" -maxdepth 1 -type f -name '*.so' -print -quit | grep -q .; then
                            echo "ERROR: unknown Android ownership directory: $child" >&2
                            exit 1
                        fi
                        ;;
                esac
            done
            android_abi_supplied "$abi" || continue
            for left in jni llamacpp onnx; do
                for right in jni llamacpp onnx; do
                    [ "$left" != "$right" ] || continue
                    for file in "$NATIVES_FROM/$abi/$left"/*.so; do
                        [ -f "$file" ] || continue
                        name="$(basename "$file")"
                        [ "$name" = "libc++_shared.so" ] && continue
                        if [ -f "$NATIVES_FROM/$abi/$right/$name" ]; then
                            echo "ERROR: duplicate Android library ownership for $abi/$name ($left and $right)" >&2
                            exit 1
                        fi
                    done
                done
            done
        done
    }

    stage_android() {
        local pkg_dir="$1"
        local component="$2"
        shift 2
        local android_jni="$pkg_dir/android/src/main/jniLibs"
        local abi src lib

        # Validate the complete package inventory for every supplied ABI before
        # replacing a working staging tree. Missing public natives are fatal.
        for abi in arm64-v8a armeabi-v7a x86_64 x86; do
            android_abi_supplied "$abi" || continue
            src="$(android_component_dir "$abi" "$component")"
            [ -d "$src" ] || { echo "ERROR: missing canonical Android component directory: $src" >&2; exit 1; }
            for lib in "$@"; do
                if [ ! -f "$src/$lib" ]; then
                    echo "ERROR: missing Android library for $(basename "$pkg_dir")/$abi: $lib" >&2
                    exit 1
                fi
            done
            for lib in "$src"/*.so; do
                [ -f "$lib" ] || continue
                local allowed=0 expected
                for expected in "$@"; do
                    if [ "$(basename "$lib")" = "$expected" ]; then
                        allowed=1
                        break
                    fi
                done
                if [ "$allowed" != "1" ]; then
                    echo "ERROR: unexpected Android library in $component ownership directory: $abi/$(basename "$lib")" >&2
                    exit 1
                fi
            done
        done

        rm -rf "$android_jni"
        for abi in arm64-v8a armeabi-v7a x86_64 x86; do
            android_abi_supplied "$abi" || continue
            src="$(android_component_dir "$abi" "$component")"
            mkdir -p "$android_jni/$abi"
            for lib in "$@"; do
                cp -f "$src/$lib" "$android_jni/$abi/"
                chmod u+w "$android_jni/$abi/$lib"
            done
        done
    }

    stage_qhexrt_skels() {
        local assets_root="$RN_ROOT/packages/qhexrt/android/src/main/assets/runanywhere/qhexrt/skels"
        local src lib
        src="$NATIVES_FROM/arm64-v8a/qhexrt"
        [ -d "$src" ] || { echo "ERROR: missing private QHexRT ownership directory: $src" >&2; exit 1; }

        for lib in libQnnHtpV75Skel.so libQnnHtpV79Skel.so libQnnHtpV81Skel.so; do
            if [ ! -f "$src/$lib" ]; then
                echo "ERROR: missing QHexRT DSP skel: $lib" >&2
                exit 1
            fi
        done

        rm -rf "$assets_root"
        mkdir -p "$assets_root/arm64-v8a"
        for lib in libQnnHtpV75Skel.so libQnnHtpV79Skel.so libQnnHtpV81Skel.so; do
            cp -f "$src/$lib" "$assets_root/arm64-v8a/"
            chmod u+w "$assets_root/arm64-v8a/$lib"
        done
    }

    stage_qhexrt_android() {
        local src android_jni lib
        src="$NATIVES_FROM/arm64-v8a/qhexrt"
        [ -d "$src" ] || { echo "ERROR: missing private QHexRT ownership directory: $src" >&2; exit 1; }
        android_jni="$QHEXRT_ROOT/android/src/main/jniLibs/arm64-v8a"

        for lib in \
            librac_backend_qhexrt.so libc++_shared.so \
            libQnnHtp.so libQnnHtpNetRunExtensions.so libQnnHtpPrepare.so libQnnSystem.so \
            libQnnHtpV75CalculatorStub.so libQnnHtpV75Stub.so \
            libQnnHtpV79CalculatorStub.so libQnnHtpV79Stub.so \
            libQnnHtpV81CalculatorStub.so libQnnHtpV81Stub.so; do
            if [ ! -f "$src/$lib" ]; then
                echo "ERROR: missing private QHexRT Android library: $lib" >&2
                exit 1
            fi
        done

        rm -rf "$QHEXRT_ROOT/android/src/main/jniLibs"
        mkdir -p "$android_jni"
        for lib in \
            librac_backend_qhexrt.so libc++_shared.so \
            libQnnHtp.so libQnnHtpNetRunExtensions.so libQnnHtpPrepare.so libQnnSystem.so \
            libQnnHtpV75CalculatorStub.so libQnnHtpV75Stub.so \
            libQnnHtpV79CalculatorStub.so libQnnHtpV79Stub.so \
            libQnnHtpV81CalculatorStub.so libQnnHtpV81Stub.so; do
            cp -f "$src/$lib" "$android_jni/"
            chmod u+w "$android_jni/$lib"
        done
        if [ -f "$src/librac_backend_qhexrt_jni.so" ]; then
            cp -f "$src/librac_backend_qhexrt_jni.so" "$android_jni/"
            chmod u+w "$android_jni/librac_backend_qhexrt_jni.so"
        fi
    }

    HAS_IOS=0
    if find "$NATIVES_FROM" -maxdepth 1 -type d -name '*.xcframework' -print -quit | grep -q .; then
        HAS_IOS=1
        stage_ios "$RN_ROOT/packages/core" RACommons
        stage_ios "$RN_ROOT/packages/llamacpp" RABackendLLAMACPP
        stage_ios \
            "$RN_ROOT/packages/mlx" \
            RABackendMLX \
            RunAnywhereMLXRuntime \
            RunAnywhereMLXMetal
        stage_mlx_ios_resources
        stage_ios "$RN_ROOT/packages/onnx" RABackendONNX RABackendSherpa RABackendCoreML
    fi

    HAS_ANDROID=0
    validate_android_layout
    for abi in arm64-v8a armeabi-v7a x86_64 x86; do
        if android_abi_supplied "$abi"; then
            HAS_ANDROID=1
            break
        fi
    done
    if [ "$HAS_ANDROID" = "1" ]; then
        stage_android "$RN_ROOT/packages/core" jni \
            librac_commons.so librunanywhere_jni.so librac_backend_cloud.so \
            libomp.so libc++_shared.so
        stage_android "$RN_ROOT/packages/llamacpp" llamacpp \
            librac_backend_llamacpp.so librac_backend_llamacpp_jni.so \
            librunanywhere_llamacpp.so libc++_shared.so
        stage_android "$RN_ROOT/packages/onnx" onnx \
            librac_backend_onnx.so librac_backend_onnx_jni.so librac_backend_sherpa.so \
            librunanywhere_onnx.so librunanywhere_sherpa.so \
            libonnxruntime.so libsherpa-onnx-c-api.so libsherpa-onnx-jni.so \
            libc++_shared.so

        if [ "$INCLUDE_PRIVATE_QHEXRT" = "1" ]; then
            echo ">> INTERNAL: staging private QHexRT natives"
            stage_qhexrt_android
            stage_qhexrt_skels
            qhexrt_include="$RN_ROOT/packages/qhexrt/android/src/main/jniLibs/include"
            mkdir -p "$qhexrt_include"
            cp -R "$REPO_ROOT/engines/qhexrt/include/." "$qhexrt_include/"
        fi
    fi

    if [ "$HAS_IOS" = "0" ] && [ "$HAS_ANDROID" = "0" ]; then
        echo "ERROR: --natives-from contains no supported public native artifacts" >&2
        exit 1
    fi
    if [ "$INCLUDE_PRIVATE_QHEXRT" = "1" ] && [ "$HAS_ANDROID" = "0" ]; then
        echo "ERROR: --include-private-qhexrt requires Android native artifacts" >&2
        exit 1
    fi
fi

# The Nitro bridge is compiled by the consuming Android app and includes the
# public RAC C API from the core package. Always refresh that exact public
# header tree after native staging has replaced jniLibs, so a release tarball
# cannot inherit stale headers or omit them entirely.
PUBLIC_RAC_HEADERS="$REPO_ROOT/sdk/runanywhere-commons/include/rac"
CANONICAL_PRIVACY_MANIFEST="$REPO_ROOT/sdk/runanywhere-swift/Sources/RunAnywhere/PrivacyInfo.xcprivacy"
CORE_RAC_HEADERS="$RN_ROOT/packages/core/android/src/main/jniLibs/include/rac"
[ -d "$PUBLIC_RAC_HEADERS" ] || { echo "ERROR: public RAC headers not found: $PUBLIC_RAC_HEADERS" >&2; exit 1; }
[ -f "$CANONICAL_PRIVACY_MANIFEST" ] || { echo "ERROR: canonical Apple privacy manifest not found: $CANONICAL_PRIVACY_MANIFEST" >&2; exit 1; }
rm -rf "$CORE_RAC_HEADERS"
mkdir -p "$(dirname "$CORE_RAC_HEADERS")"
cp -R "$PUBLIC_RAC_HEADERS" "$CORE_RAC_HEADERS"

# Defense in depth: a public package tree must never contain a private backend
# or QNN runtime, even if an input directory combines public and private builds.
if find \
    "$RN_ROOT/packages/core" \
    "$RN_ROOT/packages/llamacpp" \
    "$RN_ROOT/packages/mlx" \
    "$RN_ROOT/packages/onnx" \
    -type f \( \
        -name 'librac_backend_qhexrt*.so' -o \
        -name 'libQnn*.so' -o \
        -name 'libadsprpc.so' -o \
        -name 'libcdsprpc.so' \
    \) \
    -print -quit | grep -q .; then
    echo "ERROR: private QHexRT native found in a public React Native package" >&2
    exit 1
fi

# MLX is never publishable as a TypeScript-only facade. Its podspec declares
# all three frameworks unconditionally, so enforce the same fail-closed contract
# before npm packing even when the caller reuses an already-staged tree.
for framework in RABackendMLX RunAnywhereMLXRuntime RunAnywhereMLXMetal; do
    framework_dir="$RN_ROOT/packages/mlx/ios/Binaries/${framework}.xcframework"
    if [ ! -d "$framework_dir" ]; then
        echo "ERROR: missing required MLX iOS runtime: ${framework}.xcframework" >&2
        exit 1
    fi
    for slice in ios-arm64 ios-arm64-simulator; do
        if [ ! -d "$framework_dir/$slice" ]; then
            echo "ERROR: required MLX runtime is missing $slice: ${framework}.xcframework" >&2
            exit 1
        fi
    done
done
for resource in \
    "swift-crypto_Crypto.bundle/PrivacyInfo.xcprivacy" \
    "swift-transformers_Hub.bundle/gpt2_tokenizer_config.json" \
    "swift-transformers_Hub.bundle/t5_tokenizer_config.json"; do
    if [ ! -s "$RN_ROOT/packages/mlx/ios/Resources/$resource" ]; then
        echo "ERROR: missing or empty required MLX iOS resource: $resource" >&2
        exit 1
    fi
done
if [ ! -d "$RN_ROOT/packages/mlx/ios/ThirdPartyNotices" ] || \
   [ -z "$(find "$RN_ROOT/packages/mlx/ios/ThirdPartyNotices" -type f -print -quit)" ]; then
    echo "ERROR: required MLX iOS third-party notices are missing or empty" >&2
    exit 1
fi
for obsolete in RunAnywhereMLXMetalDevice RunAnywhereMLXMetalSimulator; do
    if [ -e "$RN_ROOT/packages/mlx/ios/Resources/${obsolete}.bundle" ]; then
        echo "ERROR: obsolete MLX Metal sidecar is not publishable: ${obsolete}.bundle" >&2
        exit 1
    fi
done

cd "$RN_ROOT"

# The RN SDK declares `packageManager: "yarn@3.6.1"`. Release packaging must
# resolve exactly the committed Yarn lock; a mutable install or npm fallback
# can select a different Nitro/native ABI and is never publishable.
if ! command -v corepack >/dev/null 2>&1; then
    echo "ERROR: Corepack is required for immutable React Native packaging." >&2
    exit 1
fi
if [ "$(corepack yarn --version)" != "3.6.1" ]; then
    echo "ERROR: React Native packaging requires the pinned Yarn 3.6.1 toolchain." >&2
    exit 1
fi

YARN_CWD=""
if [ -f "yarn.lock" ]; then
    YARN_CWD="$RN_ROOT"
elif [ -f "${REPO_ROOT}/yarn.lock" ]; then
    YARN_CWD="$REPO_ROOT"
fi

if [ -z "$YARN_CWD" ]; then
    echo "ERROR: committed Yarn lockfile is required for React Native packaging." >&2
    exit 1
fi
echo ">> yarn install --immutable (cwd=$YARN_CWD)"
(cd "$YARN_CWD" && corepack yarn install --immutable)

# Build and pack the canonical generated protocol package once. Public entry
# packages that consume generated protocol types vendor this exact archive, so
# installing a GitHub Release tarball never depends on an unpublished registry
# copy of proto-ts. The MLX registration-only package has no protocol imports.
# proto-ts is a SIBLING workspace member (../shared/proto-ts), so Yarn's
# node-modules linker hoists its deps into the RN root — unreachable when tsc
# compiles proto-ts from its own sibling dir (TS2307 on '@bufbuild/protobuf/wire'
# in a clean CI checkout; only passes locally via a stray repo-root install).
# Install proto-ts standalone from its committed lockfile first, mirroring the Web
# SDK + idl-drift-check recipe. --workspaces=false stops npm from detecting the
# monorepo root and failing on the `workspace:*` protocol.
echo ">> npm ci proto-ts (standalone, so tsc can resolve @bufbuild/protobuf)"
(cd "$REPO_ROOT/sdk/shared/proto-ts" && npm ci --workspaces=false --no-audit --no-fund)
echo ">> yarn build:proto"
corepack yarn build:proto
PROTO_STAGING="$(mktemp -d "${TMPDIR:-/tmp}/runanywhere-rn-proto.XXXXXX")"
trap 'rm -rf "$PROTO_STAGING"' EXIT
(cd "$REPO_ROOT/sdk/shared/proto-ts" && npm pack --silent --pack-destination "$PROTO_STAGING" >/dev/null)

# Generate the core Nitro bindings from the locked workspace.
echo ">> yarn core:nitrogen"
if ! corepack yarn core:nitrogen; then
    validation_failure "Nitrogen generation failed for core"
fi

# Typecheck the exact public package set. Private QHexRT participates only in
# an explicitly requested internal package run.
TYPECHECK_PACKAGE_DIRS=("${PUBLIC_PACKAGE_DIRS[@]}")
if [ "$INCLUDE_PRIVATE_QHEXRT" = "1" ]; then
    TYPECHECK_PACKAGE_DIRS+=(qhexrt)
fi
# `core` is a composite TS project referenced by every backend package
# (llamacpp/mlx/onnx/qhexrt via `references: [{ path: "../core" }]`). `tsc --noEmit`
# never writes core/lib/*.d.ts (gitignored, absent on a clean checkout), so the
# first dependent's `tsc --noEmit` fails with TS6305 ("Output file .../core/lib/
# internal.d.ts has not been built..."). Build core's declarations once first —
# mirrors the root package.json `typecheck` script. This lib/ output is never
# shipped (core's package.json files/exports point at src/).
echo ">> build core (emit declarations for composite project references)"
if ! (cd "$RN_ROOT/packages/core" && npx tsc -b); then
    validation_failure "Core declaration build failed"
fi
for pkg in "${TYPECHECK_PACKAGE_DIRS[@]}"; do
    pkg_dir="$RN_ROOT/packages/$pkg"
    if [ -f "$pkg_dir/tsconfig.json" ]; then
        echo ">> typecheck $pkg"
        if ! (cd "$pkg_dir" && npx tsc --noEmit); then
            validation_failure "TypeScript validation failed for $pkg"
        fi
    fi
done

mkdir -p "$DIST_DIR"
if [ "$INCLUDE_PRIVATE_QHEXRT" = "1" ]; then
    mkdir -p "$INTERNAL_DIST_DIR"
fi

# npm's file-selection behavior includes the staged native/header trees named
# by each package's `files` list. It does not, however, publish-transform Yarn's
# workspace protocol. Pack first, then atomically rewrite only the archived
# manifest; tracked workspace manifests remain untouched.
PACKAGE_VERSION="$(node -p "require('./package.json').version")"
[ -n "$PACKAGE_VERSION" ] || { echo "ERROR: React Native package version is empty" >&2; exit 1; }
PROTO_ARCHIVE="$PROTO_STAGING/runanywhere-proto-ts-$PACKAGE_VERSION.tgz"
[ -f "$PROTO_ARCHIVE" ] || { echo "ERROR: npm pack did not produce $PROTO_ARCHIVE" >&2; exit 1; }

# Pack only the declared public release packages. The validator below checks
# their package metadata, so filename changes cannot silently hide omissions.
for pkg in "${PUBLIC_PACKAGE_DIRS[@]}"; do
    pkg_dir="$RN_ROOT/packages/$pkg"
    [ -f "$pkg_dir/package.json" ] || { echo "ERROR: missing public package: $pkg" >&2; exit 1; }
    artifact="$DIST_DIR/runanywhere-$pkg-$PACKAGE_VERSION.tgz"
    echo ">> npm pack $pkg"
    if ! (cd "$pkg_dir" && npm pack --silent --pack-destination "$DIST_DIR" >/dev/null); then
        echo "ERROR: npm pack failed for public package $pkg" >&2
        exit 1
    fi
    [ -f "$artifact" ] || { echo "ERROR: npm pack did not produce $artifact" >&2; exit 1; }
    if [ "$pkg" = "mlx" ]; then
        python3 "$REPO_ROOT/scripts/release/rewrite_npm_package.py" \
            --archive "$artifact" \
            --exact-version "$PACKAGE_VERSION"
    else
        python3 "$REPO_ROOT/scripts/release/rewrite_npm_package.py" \
            --archive "$artifact" \
            --exact-version "$PACKAGE_VERSION" \
            --bundle "@runanywhere/proto-ts=$PROTO_ARCHIVE"
    fi
done

echo ">> Skipping private package @runanywhere/qhexrt (use --include-private-qhexrt for an internal run)"
if [ "$INCLUDE_PRIVATE_QHEXRT" = "1" ]; then
    qhexrt_backend="$QHEXRT_ROOT/android/src/main/jniLibs/arm64-v8a/librac_backend_qhexrt.so"
    [ -f "$qhexrt_backend" ] || { echo "ERROR: private QHexRT backend was not staged" >&2; exit 1; }
    artifact="$INTERNAL_DIST_DIR/runanywhere-qhexrt-$PACKAGE_VERSION.tgz"
    echo ">> INTERNAL: npm pack qhexrt"
    (cd "$QHEXRT_ROOT" && npm pack --silent --pack-destination "$INTERNAL_DIST_DIR" >/dev/null)
    python3 "$REPO_ROOT/scripts/release/rewrite_npm_package.py" \
        --archive "$artifact" \
        --exact-version "$PACKAGE_VERSION" \
        --bundle "@runanywhere/proto-ts=$PROTO_ARCHIVE"
fi

if find "$DIST_DIR" -maxdepth 1 -type f -iname '*qhexrt*' -print -quit | grep -q .; then
    echo "ERROR: private QHexRT artifact was emitted into the public dist directory" >&2
    exit 1
fi
for artifact in "$DIST_DIR"/*.tgz; do
    [ -f "$artifact" ] || continue
    if tar -tzf "$artifact" | \
       grep -E '/(librac_backend_qhexrt[^/]*\.so|libQnn[^/]*\.so|lib[ac]dsprpc\.so)$' >/dev/null; then
        echo "ERROR: private QHexRT native found in public artifact: $(basename "$artifact")" >&2
        exit 1
    fi
done

if ! python3 "$SCRIPT_DIR/validate_public_packages.py" \
    --dist "$DIST_DIR" \
    --rac-headers "$PUBLIC_RAC_HEADERS" \
    --proto-archive "$PROTO_ARCHIVE" \
    --privacy-manifest "$CANONICAL_PRIVACY_MANIFEST" \
    --expected-version "$PACKAGE_VERSION"; then
    validation_failure "public React Native package-set validation failed"
fi

if [ "$INCLUDE_PRIVATE_QHEXRT" = "1" ] && \
   ! find "$INTERNAL_DIST_DIR" -maxdepth 1 -type f -name '*.tgz' -print -quit | grep -q .; then
    echo "ERROR: internal QHexRT npm package was not produced" >&2
    exit 1
fi

echo ""
echo ">> Artifacts in $DIST_DIR:"
for f in "$DIST_DIR"/*.tgz; do
    [ -f "$f" ] || continue
    artifact_dir="$(dirname "$f")"
    artifact_name="$(basename "$f")"
    if command -v shasum >/dev/null 2>&1; then
        (cd "$artifact_dir" && shasum -a 256 "$artifact_name" > "$artifact_name.sha256")
        (cd "$artifact_dir" && shasum -a 256 --check "$artifact_name.sha256")
    else
        (cd "$artifact_dir" && sha256sum "$artifact_name" > "$artifact_name.sha256")
        (cd "$artifact_dir" && sha256sum --check "$artifact_name.sha256")
    fi
    echo "  $(basename "$f")"
done

if [ "$INCLUDE_PRIVATE_QHEXRT" = "1" ]; then
    echo ""
    echo ">> Internal artifacts in $INTERNAL_DIST_DIR:"
    for f in "$INTERNAL_DIST_DIR"/*.tgz; do
        [ -f "$f" ] || continue
        artifact_dir="$(dirname "$f")"
        artifact_name="$(basename "$f")"
        if command -v shasum >/dev/null 2>&1; then
            (cd "$artifact_dir" && shasum -a 256 "$artifact_name" > "$artifact_name.sha256")
            (cd "$artifact_dir" && shasum -a 256 --check "$artifact_name.sha256")
        else
            (cd "$artifact_dir" && sha256sum "$artifact_name" > "$artifact_name.sha256")
            (cd "$artifact_dir" && sha256sum --check "$artifact_name.sha256")
        fi
        echo "  $(basename "$f")"
    done
fi

# Clean-install each advertised public entry transaction without lifecycle
# scripts or host peer packages. The full pinned RN Android consumer below the
# release workflow validates peers/native compilation; these focused installs
# prove protocol-consuming tarballs carry their own exact proto payload and
# runtime dependency instead of consulting the registry for proto-ts. MLX is
# also clean-installed, but intentionally carries no unused proto payload.
INSTALL_SMOKE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/runanywhere-rn-install.XXXXXX")"
trap 'rm -rf "$PROTO_STAGING" "$INSTALL_SMOKE_ROOT"' EXIT
verify_candidate_install() {
    local label="$1"
    local entry_package="$2"
    local expects_bundled_proto="$3"
    shift 3
    local install_root="$INSTALL_SMOKE_ROOT/$label"
    mkdir -p "$install_root"
    (
        cd "$install_root"
        npm init --yes >/dev/null
        npm install \
            --ignore-scripts \
            --omit=peer \
            --no-audit \
            --no-fund \
            --package-lock=false \
            "$@" >/dev/null
        ENTRY_PACKAGE="$entry_package" \
        EXPECTS_BUNDLED_PROTO="$expects_bundled_proto" \
        EXPECTED_VERSION="$PACKAGE_VERSION" \
        node - <<'NODE'
const fs = require('fs');
const path = require('path');
const { createRequire } = require('module');

const packageRoot = path.join(process.cwd(), 'node_modules', ...process.env.ENTRY_PACKAGE.split('/'));
const manifest = JSON.parse(fs.readFileSync(path.join(packageRoot, 'package.json'), 'utf8'));
if (manifest.version !== process.env.EXPECTED_VERSION) {
  throw new Error(`${manifest.name} resolved ${manifest.version}`);
}
const bundledProto = path.join(
  packageRoot,
  'node_modules/@runanywhere/proto-ts/package.json'
);
if (process.env.EXPECTS_BUNDLED_PROTO === '1') {
  const protoManifest = JSON.parse(fs.readFileSync(bundledProto, 'utf8'));
  if (protoManifest.version !== process.env.EXPECTED_VERSION) {
    throw new Error(`proto-ts resolved ${protoManifest.version}`);
  }
  const entryRequire = createRequire(path.join(packageRoot, 'package.json'));
  entryRequire.resolve('@bufbuild/protobuf/wire');
  console.log(`verified ${manifest.name}@${manifest.version} with bundled proto-ts@${protoManifest.version}`);
} else {
  if (fs.existsSync(bundledProto)) {
    throw new Error(`${manifest.name} unexpectedly bundles proto-ts`);
  }
  console.log(`verified ${manifest.name}@${manifest.version} without an unused proto-ts payload`);
}
NODE
    )
}

CORE_ARTIFACT="$DIST_DIR/runanywhere-core-$PACKAGE_VERSION.tgz"
verify_candidate_install core @runanywhere/core 1 "$CORE_ARTIFACT"
verify_candidate_install \
    llamacpp \
    @runanywhere/llamacpp \
    1 \
    "$CORE_ARTIFACT" \
    "$DIST_DIR/runanywhere-llamacpp-$PACKAGE_VERSION.tgz"
verify_candidate_install \
    mlx \
    @runanywhere/mlx \
    0 \
    "$CORE_ARTIFACT" \
    "$DIST_DIR/runanywhere-mlx-$PACKAGE_VERSION.tgz"
verify_candidate_install \
    onnx \
    @runanywhere/onnx \
    1 \
    "$CORE_ARTIFACT" \
    "$DIST_DIR/runanywhere-onnx-$PACKAGE_VERSION.tgz"

if [ -x "${REPO_ROOT}/scripts/release/validate-artifact.sh" ]; then
    echo ""
    "${REPO_ROOT}/scripts/release/validate-artifact.sh" "$DIST_DIR"/*.tgz 2>/dev/null
fi
