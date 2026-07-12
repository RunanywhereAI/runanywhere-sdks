#!/usr/bin/env bash
# Exercises the public Flutter plugins' remote Android download path against a
# local release fixture, including a fail-closed checksum corruption case.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
FLUTTER_PACKAGES="${REPO_ROOT}/sdk/runanywhere-flutter/packages"
KOTLIN_ROOT="${REPO_ROOT}/sdk/runanywhere-kotlin"
ANDROID_PROJECT="${REPO_ROOT}/examples/flutter/RunAnywhereAI/android"
VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/sdk/runanywhere-commons/VERSION")"
FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/rac-flutter-release.XXXXXX")"
trap 'rm -rf "${FIXTURE}"' EXIT

release_dir="${FIXTURE}/v${VERSION}"
mkdir -p "${release_dir}"

for abi in arm64-v8a armeabi-v7a x86_64; do
    stage="${FIXTURE}/stage-${abi}"
    mkdir -p "${stage}/${abi}"/{jni,llamacpp,onnx}
    for component in jni llamacpp onnx; do
        case "${component}" in
            jni) source_dir="${KOTLIN_ROOT}/src/main/jniLibs/${abi}" ;;
            llamacpp) source_dir="${KOTLIN_ROOT}/modules/runanywhere-core-llamacpp/src/main/jniLibs/${abi}" ;;
            onnx) source_dir="${KOTLIN_ROOT}/modules/runanywhere-core-onnx/src/main/jniLibs/${abi}" ;;
        esac
        if ! find "${source_dir}" -maxdepth 1 -type f -name '*.so' -print -quit | grep -q .; then
            echo "error: no staged ${component}/${abi} native libraries at ${source_dir}" >&2
            exit 1
        fi
        cp "${source_dir}/"*.so "${stage}/${abi}/${component}/"
    done

    archive="RACommons-android-${abi}-v${VERSION}.zip"
    (
        cd "${stage}"
        zip -X -q -r "${release_dir}/${archive}" "${abi}"
    )
    (
        cd "${release_dir}"
        shasum -a 256 "${archive}" > "${archive}.sha256"
    )
done

gradle=(
    "${ANDROID_PROJECT}/gradlew"
    -p "${ANDROID_PROJECT}"
    -Prunanywhere.useLocalNatives=false
    "-Prunanywhere.releaseBaseUrl=file://${FIXTURE}"
    --no-daemon
)

"${gradle[@]}" \
    :runanywhere:downloadNativeLibs \
    :runanywhere_llamacpp:downloadNativeLibs \
    :runanywhere_onnx:downloadNativeLibs

core_libs=(
    libc++_shared.so libomp.so librac_backend_cloud.so librac_commons.so
    librunanywhere_jni.so
)
llamacpp_libs=(
    libc++_shared.so librac_backend_llamacpp.so
    librac_backend_llamacpp_jni.so librunanywhere_llamacpp.so
)
onnx_libs=(
    libc++_shared.so libonnxruntime.so librac_backend_onnx.so
    librac_backend_onnx_jni.so librac_backend_sherpa.so
    librunanywhere_onnx.so librunanywhere_sherpa.so
    libsherpa-onnx-c-api.so libsherpa-onnx-jni.so
)

assert_inventory() {
    local dir="$1"
    shift
    local lib actual
    for lib in "$@"; do
        test -f "$dir/$lib"
    done
    actual="$(find "$dir" -maxdepth 1 -type f -name '*.so' | wc -l | tr -d ' ')"
    if [ "$actual" -ne "$#" ]; then
        echo "error: unexpected remote native inventory in $dir (expected $#, found $actual)" >&2
        exit 1
    fi
}

for abi in arm64-v8a armeabi-v7a x86_64; do
    assert_inventory \
        "${FLUTTER_PACKAGES}/runanywhere/android/build/jniLibs/${abi}" \
        "${core_libs[@]}"
    assert_inventory \
        "${FLUTTER_PACKAGES}/runanywhere_llamacpp/android/build/jniLibs/${abi}" \
        "${llamacpp_libs[@]}"
    assert_inventory \
        "${FLUTTER_PACKAGES}/runanywhere_onnx/android/build/jniLibs/${abi}" \
        "${onnx_libs[@]}"
done

bad_archive="RACommons-android-arm64-v8a-v${VERSION}.zip"
printf '%064d  %s\n' 0 "${bad_archive}" > "${release_dir}/${bad_archive}.sha256"
negative_log="${FIXTURE}/checksum-negative.log"
if "${gradle[@]}" :runanywhere:downloadNativeLibs --rerun-tasks >"${negative_log}" 2>&1; then
    echo "error: corrupted Flutter release checksum was accepted" >&2
    exit 1
fi
if ! grep -q "Checksum mismatch" "${negative_log}"; then
    echo "error: corrupted checksum failed for an unexpected reason" >&2
    cat "${negative_log}" >&2
    exit 1
fi

echo "Flutter remote Android downloads: checksum success + corruption rejection passed"
