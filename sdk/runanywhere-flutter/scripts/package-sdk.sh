#!/usr/bin/env bash
# =============================================================================
# sdk/runanywhere-flutter/scripts/package-sdk.sh
# =============================================================================
# Unified SDK packaging contract for the Flutter SDK. Consumes pre-built
# iOS XCFrameworks + Android .so files, stages them into each Flutter package
# for local/CI consumer validation, then validates the public package shape
# with `flutter pub publish --dry-run`.
#
# Public packages intentionally exclude gitignored staged binaries and retain
# pinned Gradle, CocoaPods, and SwiftPM download/checksum paths instead. MLX is
# CocoaPods-only because its precompiled Hub/Crypto accessors require app-root
# resource bundles. No tarball is produced.
#
# USAGE:
#   package-sdk.sh [--mode local|ci] [--natives-from PATH]
#                  [--include-private-qhexrt]
#
# OPTIONS:
#   --mode local|ci      Build mode (default: auto-detect from $CI)
#   --natives-from PATH  Directory with iOS xcframeworks + Android .so files.
#                        Expected: PATH/*.xcframework, MLX Hub/Crypto/notices
#                        in PATH/RunAnywhereMLXRuntimeResources, and/or
#                        canonical Android ownership roots
#                        PATH/<abi>/{jni,llamacpp,onnx}/*.so.
#                        These are staged for consumer validation, not embedded
#                        in the public pub package.
#   --include-private-qhexrt
#                        INTERNAL ONLY. Stage and validate the private QHexRT
#                        package from PATH/arm64-v8a/qhexrt/*.so. Public
#                        packaging removes any previously staged private natives.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
FLUTTER_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${REPO_ROOT}/scripts/setup/detect-mode.sh"

NATIVES_FROM=""
INCLUDE_PRIVATE_QHEXRT=0

validation_failure() {
    local description="$1"
    echo "ERROR: $description" >&2
    exit 1
}

while [ $# -gt 0 ]; do
    case "$1" in
        --mode) RAC_BUILD_MODE="$2"; shift 2 ;;
        --natives-from) NATIVES_FROM="$2"; shift 2 ;;
        --include-private-qhexrt) INCLUDE_PRIVATE_QHEXRT=1; shift ;;
        --help|-h) sed -n '13,27p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 1 ;;
    esac
done

echo ">> Flutter SDK packaging (mode=${RAC_BUILD_MODE})"

QHEXRT_ROOT="$FLUTTER_ROOT/packages/runanywhere_qhexrt"

# A public packaging run must not inherit private binaries from a prior local
# QHexRT build. Internal packaging re-stages them below from an explicit input.
rm -rf \
    "$QHEXRT_ROOT/android/src/main/jniLibs" \
    "$QHEXRT_ROOT/android/src/main/assets/runanywhere/qhexrt/skels"

if [ "$INCLUDE_PRIVATE_QHEXRT" = "1" ] && [ -z "$NATIVES_FROM" ]; then
    echo "ERROR: --include-private-qhexrt requires --natives-from PATH" >&2
    exit 1
fi

if [ -n "$NATIVES_FROM" ]; then
    [ -d "$NATIVES_FROM" ] || { echo "ERROR: --natives-from not found: $NATIVES_FROM" >&2; exit 1; }
    echo ">> Staging public natives from $NATIVES_FROM with explicit package ownership"

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
        local abi component left right file name child child_name
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

    stage_ios() {
        local pkg_dir="$1"
        shift
        local ios_bin
        ios_bin="$pkg_dir/ios/$(basename "$pkg_dir")/Frameworks"
        local framework

        # Validate the complete package inventory before replacing a working
        # local staging tree.
        for framework in "$@"; do
            if [ ! -d "$NATIVES_FROM/${framework}.xcframework" ]; then
                echo "ERROR: missing iOS framework for $(basename "$pkg_dir"): ${framework}.xcframework" >&2
                exit 1
            fi
        done

        rm -rf "$ios_bin"
        mkdir -p "$ios_bin"
        for framework in "$@"; do
            cp -R "$NATIVES_FROM/${framework}.xcframework" "$ios_bin/"
        done
    }

    validate_mlx_ios_resources_source() {
        local src="$NATIVES_FROM/RunAnywhereMLXRuntimeResources"
        local required obsolete resource_count

        [ -d "$src" ] || {
            echo "ERROR: missing MLX runtime resources: $src" >&2
            exit 1
        }
        for required in \
            "swift-crypto_Crypto.bundle/PrivacyInfo.xcprivacy" \
            "swift-transformers_Hub.bundle/gpt2_tokenizer_config.json" \
            "swift-transformers_Hub.bundle/t5_tokenizer_config.json"; do
            if [ ! -s "$src/$required" ]; then
                echo "ERROR: missing or empty MLX runtime resource: $required" >&2
                exit 1
            fi
        done
        if [ ! -d "$src/ThirdPartyNotices" ] || \
           [ -z "$(find "$src/ThirdPartyNotices" -type f -print -quit)" ]; then
            echo "ERROR: MLX runtime third-party notices are missing or empty" >&2
            exit 1
        fi
        for obsolete in RunAnywhereMLXMetalDevice RunAnywhereMLXMetalSimulator; do
            if [ -e "$src/${obsolete}.bundle" ]; then
                echo "ERROR: obsolete MLX Metal sidecar is not publishable: ${obsolete}.bundle" >&2
                exit 1
            fi
        done
        resource_count="$(find "$src" -mindepth 1 -maxdepth 1 -type d -name '*.bundle' | wc -l | tr -d ' ')"
        if [ "$resource_count" != "2" ]; then
            echo "ERROR: MLX resources must contain exactly the Hub and Crypto bundles" >&2
            exit 1
        fi
    }

    validate_mlx_ios_framework_source() {
        local framework slice root

        for framework in RABackendMLX RunAnywhereMLXRuntime RunAnywhereMLXMetal; do
            root="$NATIVES_FROM/${framework}.xcframework"
            if [ ! -f "$root/Info.plist" ]; then
                echo "ERROR: incomplete MLX iOS framework: ${framework}.xcframework" >&2
                exit 1
            fi
            plutil -lint "$root/Info.plist" >/dev/null || {
                echo "ERROR: invalid MLX XCFramework Info.plist: ${framework}.xcframework" >&2
                exit 1
            }
            for slice in ios-arm64 ios-arm64-simulator; do
                if [ ! -d "$root/$slice" ]; then
                    echo "ERROR: MLX iOS framework is missing $slice: ${framework}.xcframework" >&2
                    exit 1
                fi
            done
        done
        for slice in ios-arm64 ios-arm64-simulator; do
            if [ ! -s "$NATIVES_FROM/RunAnywhereMLXMetal.xcframework/$slice/RunAnywhereMLXMetal.framework/default.metallib" ]; then
                echo "ERROR: MLX Metal framework is missing $slice/default.metallib" >&2
                exit 1
            fi
        done
    }

    stage_mlx_ios_resources() {
        local src="$NATIVES_FROM/RunAnywhereMLXRuntimeResources"
        local mlx_root="$FLUTTER_ROOT/packages/runanywhere_mlx/ios/runanywhere_mlx"
        local resources="$mlx_root/Resources"
        local notices="$mlx_root/ThirdPartyNotices"

        rm -rf "$resources" "$notices"
        mkdir -p "$resources"
        cp -R "$src/swift-crypto_Crypto.bundle" "$resources/"
        cp -R "$src/swift-transformers_Hub.bundle" "$resources/"
        cp -R "$src/ThirdPartyNotices" "$notices"
    }

    stage_android() {
        local pkg_dir="$1"
        local component="$2"
        shift 2
        local android_jni="$pkg_dir/android/src/main/jniLibs"
        local abi src lib

        # Validate every required public library for every supplied ABI before
        # removing or copying package output. This prevents partial packages.
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
            done
        done
    }

    HAS_IOS=0
    if find "$NATIVES_FROM" -maxdepth 1 -type d -name '*.xcframework' -print -quit | grep -q .; then
        HAS_IOS=1
        # Preflight every MLX resource before replacing any package-owned
        # framework, so a malformed input cannot leave a partially refreshed
        # local fallback tree.
        validate_mlx_ios_framework_source
        validate_mlx_ios_resources_source
        stage_ios "$FLUTTER_ROOT/packages/runanywhere" RACommons
        stage_ios "$FLUTTER_ROOT/packages/runanywhere_llamacpp" RABackendLLAMACPP
        stage_ios "$FLUTTER_ROOT/packages/runanywhere_mlx" \
            RABackendMLX RunAnywhereMLXRuntime RunAnywhereMLXMetal
        stage_mlx_ios_resources
        stage_ios "$FLUTTER_ROOT/packages/runanywhere_onnx" RABackendONNX RABackendSherpa RABackendCoreML
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
        stage_android "$FLUTTER_ROOT/packages/runanywhere" jni \
            librac_commons.so librunanywhere_jni.so librac_backend_cloud.so \
            libomp.so libc++_shared.so
        stage_android "$FLUTTER_ROOT/packages/runanywhere_llamacpp" llamacpp \
            librac_backend_llamacpp.so librac_backend_llamacpp_jni.so \
            librunanywhere_llamacpp.so libc++_shared.so
        stage_android "$FLUTTER_ROOT/packages/runanywhere_onnx" onnx \
            librac_backend_onnx.so librac_backend_onnx_jni.so librac_backend_sherpa.so \
            librunanywhere_onnx.so librunanywhere_sherpa.so \
            libonnxruntime.so libsherpa-onnx-c-api.so libsherpa-onnx-jni.so \
            libc++_shared.so
    fi

    if [ "$HAS_IOS" = "0" ] && [ "$HAS_ANDROID" = "0" ]; then
        echo "ERROR: --natives-from contains no supported public native artifacts" >&2
        exit 1
    fi

    if [ "$INCLUDE_PRIVATE_QHEXRT" = "1" ]; then
        echo ">> INTERNAL: staging private QHexRT natives"
        "$QHEXRT_ROOT/scripts/stage-natives.sh" \
            --natives-from "$NATIVES_FROM/arm64-v8a/qhexrt"
    fi
fi

SWIFT_PRIVACY_MANIFEST="${REPO_ROOT}/sdk/runanywhere-swift/Sources/RunAnywhere/PrivacyInfo.xcprivacy"
FLUTTER_PRIVACY_MANIFEST="${FLUTTER_ROOT}/packages/runanywhere/ios/runanywhere/Sources/runanywhere/PrivacyInfo.xcprivacy"
if ! cmp -s "$SWIFT_PRIVACY_MANIFEST" "$FLUTTER_PRIVACY_MANIFEST"; then
    echo "ERROR: Flutter and Swift privacy manifests must remain byte-identical" >&2
    exit 1
fi
plutil -lint "$FLUTTER_PRIVACY_MANIFEST" >/dev/null

# Flutter publishes as an independent archive, so its ObjC++ HTTP transport
# cannot include a source file through a monorepo-relative path. Keep the small
# package mirror byte-identical to the canonical cross-SDK implementation.
SHARED_HTTP_TRANSPORT="${REPO_ROOT}/sdk/shared/ios/URLSessionHttpTransport/URLSessionHttpTransportImpl.inc.mm"
FLUTTER_HTTP_TRANSPORT="${FLUTTER_ROOT}/packages/runanywhere/ios/runanywhere/Sources/runanywhere_native/URLSessionHttpTransportImpl.inc.mm"
if ! cmp -s "$SHARED_HTTP_TRANSPORT" "$FLUTTER_HTTP_TRANSPORT"; then
    echo "ERROR: Flutter URLSession transport mirror drifted from the canonical shared implementation" >&2
    exit 1
fi

# Defense in depth: public package directories may contain only their explicit
# allowlists above. Refuse packaging if any private QHexRT/QNN binary escaped
# into a public package tree.
if find \
    "$FLUTTER_ROOT/packages/runanywhere" \
    "$FLUTTER_ROOT/packages/runanywhere_llamacpp" \
    "$FLUTTER_ROOT/packages/runanywhere_mlx" \
    "$FLUTTER_ROOT/packages/runanywhere_onnx" \
    -type f \( \
        -name 'librac_backend_qhexrt*.so' -o \
        -name 'libQnn*.so' -o \
        -name 'libadsprpc.so' -o \
        -name 'libcdsprpc.so' \
    \) \
    -print -quit | grep -q .; then
    echo "ERROR: private QHexRT native found in a public Flutter package" >&2
    exit 1
fi

# Public pub packages use pinned remote-download/checksum contracts. Every
# staged XCFramework, resource bundle, and generated notice stays out of the
# pub archive. The MLX podspec downloads its complete four-asset payload.
validate_mlx_local_payload() {
    local mlx_root="$FLUTTER_ROOT/packages/runanywhere_mlx/ios/runanywhere_mlx"
    local frameworks="$mlx_root/Frameworks"
    local resources="$mlx_root/Resources"
    local notices="$mlx_root/ThirdPartyNotices"
    local path framework slice required obsolete payload_count resource_count

    for obsolete in RunAnywhereMLXMetalDevice RunAnywhereMLXMetalSimulator; do
        if [ -e "$resources/${obsolete}.bundle" ]; then
            echo "ERROR: obsolete MLX Metal sidecar is not publishable: ${obsolete}.bundle" >&2
            exit 1
        fi
    done

    payload_count=0
    for path in \
        "$frameworks/RABackendMLX.xcframework" \
        "$frameworks/RunAnywhereMLXRuntime.xcframework" \
        "$frameworks/RunAnywhereMLXMetal.xcframework" \
        "$resources/swift-crypto_Crypto.bundle" \
        "$resources/swift-transformers_Hub.bundle" \
        "$notices"; do
        if [ -e "$path" ]; then
            payload_count=$((payload_count + 1))
        fi
    done

    # A clean source package downloads via CocoaPods. Any local fallback that
    # does exist must be the complete, validated six-entry payload.
    [ "$payload_count" = "0" ] && return
    if [ "$payload_count" != "6" ]; then
        echo "ERROR: local Flutter MLX payload is partial ($payload_count of 6 required entries)" >&2
        exit 1
    fi

    for framework in RABackendMLX RunAnywhereMLXRuntime RunAnywhereMLXMetal; do
        if [ ! -f "$frameworks/${framework}.xcframework/Info.plist" ]; then
            echo "ERROR: Flutter MLX framework is incomplete: ${framework}.xcframework" >&2
            exit 1
        fi
        for slice in ios-arm64 ios-arm64-simulator; do
            if [ ! -d "$frameworks/${framework}.xcframework/$slice" ]; then
                echo "ERROR: Flutter MLX framework is missing $slice: ${framework}.xcframework" >&2
                exit 1
            fi
        done
    done
    for slice in ios-arm64 ios-arm64-simulator; do
        if [ ! -s "$frameworks/RunAnywhereMLXMetal.xcframework/$slice/RunAnywhereMLXMetal.framework/default.metallib" ]; then
            echo "ERROR: Flutter MLX Metal framework is missing $slice/default.metallib" >&2
            exit 1
        fi
    done

    for required in \
        "swift-crypto_Crypto.bundle/PrivacyInfo.xcprivacy" \
        "swift-transformers_Hub.bundle/gpt2_tokenizer_config.json" \
        "swift-transformers_Hub.bundle/t5_tokenizer_config.json"; do
        if [ ! -s "$resources/$required" ]; then
            echo "ERROR: missing or empty Flutter MLX resource: $required" >&2
            exit 1
        fi
    done
    resource_count="$(find "$resources" -mindepth 1 -maxdepth 1 -type d -name '*.bundle' | wc -l | tr -d ' ')"
    if [ "$resource_count" != "2" ]; then
        echo "ERROR: Flutter MLX must stage exactly the Hub and Crypto resource bundles" >&2
        exit 1
    fi
    if [ ! -d "$notices" ] || [ -z "$(find "$notices" -type f -print -quit)" ]; then
        echo "ERROR: Flutter MLX third-party notices are missing or empty" >&2
        exit 1
    fi
}

validate_public_remote_binary_contract() {
    local pkg component pkg_dir build_gradle binary_config podspec package_manifest
    local file relative expected_target expected_targets expected_count actual_count
    local actual_pubignore expected_pubignore
    for pkg in runanywhere runanywhere_llamacpp runanywhere_mlx runanywhere_onnx; do
        case "$pkg" in
            runanywhere)
                component="jni"
                expected_count=1
                expected_targets="RACommons"
                ;;
            runanywhere_llamacpp)
                component="llamacpp"
                expected_count=1
                expected_targets="RABackendLLAMACPP"
                ;;
            runanywhere_mlx)
                component=""
                expected_count=4
                expected_targets="RABackendMLX RunAnywhereMLXRuntime RunAnywhereMLXMetal"
                ;;
            runanywhere_onnx)
                component="onnx"
                expected_count=3
                expected_targets="RABackendONNX RABackendSherpa RABackendCoreML"
                ;;
        esac
        pkg_dir="$FLUTTER_ROOT/packages/$pkg"
        build_gradle="$pkg_dir/android/build.gradle"
        binary_config="$pkg_dir/android/binary_config.gradle"
        podspec="$pkg_dir/ios/$pkg.podspec"
        package_manifest="$pkg_dir/ios/$pkg/Package.swift"
        cmp -s "$REPO_ROOT/LICENSE" "$pkg_dir/LICENSE" || { echo "ERROR: $pkg must ship the canonical RunAnywhere LICENSE" >&2; exit 1; }
        grep -Fq "s.license          = { :type => 'RunAnywhere License', :file => '../LICENSE' }" "$podspec" || { echo "ERROR: $pkg podspec has incorrect license metadata" >&2; exit 1; }
        if [ "$pkg" = "runanywhere_mlx" ]; then
            [ -f "$pkg_dir/.pubignore" ] || { echo "ERROR: runanywhere_mlx requires its reviewed generated-payload .pubignore" >&2; exit 1; }
            expected_pubignore="$(printf '%s\n' \
                '.dart_tool/' \
                '.flutter-plugins' \
                '.flutter-plugins-dependencies' \
                'build/' \
                '*.iml' \
                'ios/runanywhere_mlx/Frameworks/' \
                'ios/runanywhere_mlx/Resources/' \
                'ios/runanywhere_mlx/ThirdPartyNotices/')"
            actual_pubignore="$(sed -E '/^[[:space:]]*(#|$)/d' "$pkg_dir/.pubignore")"
            if [ "$actual_pubignore" != "$expected_pubignore" ]; then
                echo "ERROR: runanywhere_mlx .pubignore drifted from the reviewed generated-payload contract" >&2
                exit 1
            fi
        elif [ -e "$pkg_dir/.pubignore" ]; then
            echo "ERROR: $pkg .pubignore would override the remote-binary publish contract" >&2
            exit 1
        fi

        # MLX is Apple-only. Other public packages download per-ABI Android
        # archives through Gradle and validate the published SHA-256 sidecar.
        if [ "$pkg" != "runanywhere_mlx" ]; then
            grep -Fq 'verifyDownloadedArchive' "$build_gradle" || { echo "ERROR: $pkg is missing checksum verification" >&2; exit 1; }
            # shellcheck disable=SC2016 # Match the literal Gradle interpolation expression.
            grep -Fq '${downloadUrl}.sha256' "$build_gradle" || { echo "ERROR: $pkg is missing checksum sidecar download" >&2; exit 1; }
            grep -Fq "\${abi}/$component" "$build_gradle" || { echo "ERROR: $pkg does not consume canonical $component archive ownership" >&2; exit 1; }
            grep -Fq 'runanywhere.releaseBaseUrl' "$binary_config" || { echo "ERROR: $pkg is missing pinned remote binary configuration" >&2; exit 1; }
        fi

        # CocoaPods fetches the same immutable Apple release archives during
        # prepare_command. Only the fixture base URL can change; the declared
        # checksum cannot be overridden.
        grep -Fq 's.prepare_command = <<-CMD' "$podspec" || { echo "ERROR: $pkg podspec is missing prepare_command" >&2; exit 1; }
        grep -Fq 'RUNANYWHERE_FLUTTER_IOS_RELEASE_BASE_URL' "$podspec" || { echo "ERROR: $pkg podspec is missing the test-only release URL override" >&2; exit 1; }
        grep -Fq "shasum -a 256" "$podspec" || { echo "ERROR: $pkg podspec is missing Apple archive checksum verification" >&2; exit 1; }
        grep -Fq -- "--proto '=https,file'" "$podspec" || { echo "ERROR: $pkg podspec does not restrict download protocols" >&2; exit 1; }
        grep -Fq -- '-ios-v#{s.version}.zip' "$podspec" || { echo "ERROR: $pkg podspec is missing versioned Apple release archive URLs" >&2; exit 1; }

        if [ "$pkg" = "runanywhere_mlx" ]; then
            [ ! -e "$package_manifest" ] || { echo "ERROR: runanywhere_mlx must remain CocoaPods-only; remove its SwiftPM manifest" >&2; exit 1; }
            actual_count="$(grep -Ec "^[[:space:]]*'[^']+' => '[0-9a-f]{64}'[,]?$" "$podspec" || true)"
            [ "$actual_count" -eq "$expected_count" ] || { echo "ERROR: runanywhere_mlx podspec has $actual_count immutable checksums; expected $expected_count" >&2; exit 1; }
            for expected_target in $expected_targets RunAnywhereMLXResources; do
                grep -Fq "'$expected_target' =>" "$podspec" || { echo "ERROR: runanywhere_mlx podspec is missing the $expected_target checksum" >&2; exit 1; }
            done
            grep -Fq 'download_archive RunAnywhereMLXResources' "$podspec" || { echo "ERROR: runanywhere_mlx podspec is missing the independent resources download" >&2; exit 1; }
            for marker in swift-crypto_Crypto.bundle swift-transformers_Hub.bundle; do
                grep -Fq "$marker" "$podspec" || { echo "ERROR: runanywhere_mlx podspec is missing $marker" >&2; exit 1; }
            done
            # shellcheck disable=SC2016 # Match the literal CocoaPods interpolation expression.
            grep -Fq '$(inherited) -Wl,-u,_ra_mlx_runtime_is_available' "$podspec" || { echo "ERROR: runanywhere_mlx podspec is missing the precise MLX linker anchor" >&2; exit 1; }
            grep -Fq 'RunAnywhereMLXRuntimeResources' "$podspec" || { echo "ERROR: runanywhere_mlx podspec is missing the resource archive root" >&2; exit 1; }
            if grep -Fq -- '-all_load' "$podspec" || grep -Fq -- '-force_load' "$podspec"; then
                echo "ERROR: runanywhere_mlx podspec must use only the precise linker anchor" >&2
                exit 1
            fi
        else
            # SwiftPM chooses a staged local framework for monorepo development
            # and the checksum-pinned remote target for clean pub.dev consumers.
            grep -Fq 'func runAnywhereBinaryTarget(name: String, checksum: String)' "$package_manifest" || { echo "ERROR: $pkg SwiftPM manifest is missing local/remote binary selection" >&2; exit 1; }
            grep -Fq 'https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/v\(sdkVersion)/\(name)-ios-v\(sdkVersion).zip' "$package_manifest" || { echo "ERROR: $pkg SwiftPM manifest is missing the fixed HTTPS release URL" >&2; exit 1; }
            actual_count="$(grep -Ec 'checksum: "[0-9a-f]{64}"' "$package_manifest" || true)"
            [ "$actual_count" -eq "$expected_count" ] || { echo "ERROR: $pkg SwiftPM manifest has $actual_count immutable checksums; expected $expected_count" >&2; exit 1; }
            for expected_target in $expected_targets; do
                grep -Fq "name: \"$expected_target\"" "$package_manifest" || { echo "ERROR: $pkg SwiftPM manifest is missing $expected_target" >&2; exit 1; }
            done
        fi
        for expected_target in $expected_targets; do
            grep -Fq "$expected_target" "$podspec" || { echo "ERROR: $pkg podspec is missing $expected_target" >&2; exit 1; }
        done

        # Every locally staged binary must remain excluded from the pub archive.
        for file in "$pkg_dir/android/src/main/jniLibs"/*/*.so; do
            [ -f "$file" ] || continue
            relative="${file#"$REPO_ROOT"/}"
            if ! git -C "$REPO_ROOT" check-ignore -q -- "$relative"; then
                echo "ERROR: staged public native would enter the pub inventory: $relative" >&2
                exit 1
            fi
        done
        while IFS= read -r -d '' file; do
            relative="${file#"$REPO_ROOT"/}"
            if ! git -C "$REPO_ROOT" check-ignore -q -- "$relative"; then
                echo "ERROR: staged Apple native would enter the pub inventory: $relative" >&2
                exit 1
            fi
        done < <(find "$pkg_dir/ios/$pkg/Frameworks" -type f -print0 2>/dev/null)

        if [ "$pkg" = "runanywhere_mlx" ]; then
            while IFS= read -r -d '' file; do
                relative="${file#"$REPO_ROOT"/}"
                if ! git -C "$REPO_ROOT" check-ignore -q -- "$relative"; then
                    echo "ERROR: staged MLX resource/notices file is not gitignored: $relative" >&2
                    exit 1
                fi
            done < <(find \
                "$pkg_dir/ios/$pkg/Resources" \
                "$pkg_dir/ios/$pkg/ThirdPartyNotices" \
                -type f -print0 2>/dev/null)
        fi
    done

    relative="${FLUTTER_HTTP_TRANSPORT#"$REPO_ROOT"/}"
    if git -C "$REPO_ROOT" check-ignore -q -- "$relative"; then
        echo "ERROR: package-local URLSession transport would be omitted from pub inventory: $relative" >&2
        exit 1
    fi
}
validate_mlx_local_payload
validate_public_remote_binary_contract

# Bootstrap with melos if available
cd "$FLUTTER_ROOT"
if command -v melos >/dev/null 2>&1; then
    echo ">> melos bootstrap"
    if ! melos bootstrap; then
        validation_failure "melos bootstrap failed"
    fi
fi

# Validate each package with flutter pub publish --dry-run
for pkg_dir in "$FLUTTER_ROOT/packages"/*/; do
    pkg=$(basename "$pkg_dir")
    if [ ! -f "$pkg_dir/pubspec.yaml" ]; then
        continue
    fi
    if [ "$pkg" = "runanywhere_qhexrt" ]; then
        if [ "$INCLUDE_PRIVATE_QHEXRT" = "1" ]; then
            echo ">> Validating private package $pkg without a publish dry-run"
            (cd "$pkg_dir" && flutter pub get)
        else
            echo ">> Skipping private package $pkg (use --include-private-qhexrt for an internal run)"
        fi
        continue
    fi
    echo ""
    echo ">> Validating $pkg"
    (
        cd "$pkg_dir"
        if ! flutter pub get; then
            validation_failure "pub get failed for $pkg"
        fi
        if ! flutter pub publish --dry-run; then
            validation_failure "pub publish dry-run failed for $pkg"
        fi
    )
done

echo ""
echo ">> Flutter SDK packages validated. No tarball emitted — consumers"
echo "   use pinned Android Gradle and Apple CocoaPods/SwiftPM downloads."
echo "   MLX is CocoaPods-only; all staged native payloads stay out of pub."
