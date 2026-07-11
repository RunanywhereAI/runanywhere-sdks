#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Assemble the cross-ABI Android archives consumed by the React Native and
# Flutter Gradle plugins from release.yml's per-ABI RACommons archives.
set -euo pipefail

usage() {
    echo "usage: assemble-android-release-assets.sh <release-directory> <version>" >&2
}

if [ "$#" -ne 2 ]; then
    usage
    exit 2
fi

RELEASE_DIR="$1"
VERSION="$2"

if [ ! -d "${RELEASE_DIR}" ]; then
    echo "error: release directory does not exist: ${RELEASE_DIR}" >&2
    exit 1
fi

case "${VERSION}" in
    ''|*[!0-9A-Za-z.-]*)
        echo "error: invalid release version: ${VERSION}" >&2
        exit 2
        ;;
esac

RELEASE_DIR="$(cd "${RELEASE_DIR}" && pwd)"
ABIS=(arm64-v8a armeabi-v7a x86_64)
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rac-android-release.XXXXXX")"
trap 'rm -rf "${WORK_DIR}"' EXIT

COMMONS_NAME="RACommons-android-v${VERSION}.zip"
LLAMACPP_NAME="RABackendLlamaCPP-android-v${VERSION}.zip"
ONNX_NAME="RABackendONNX-android-v${VERSION}.zip"
LLAMACPP_ROOT="RABackendLlamaCPP-android-v${VERSION}"
ONNX_ROOT="RABackendONNX-android-v${VERSION}"

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

verify_sidecar() {
    local archive="$1"
    local sidecar="${archive}.sha256"
    local expected actual

    if [ ! -f "${sidecar}" ]; then
        echo "error: missing checksum sidecar: ${sidecar}" >&2
        exit 1
    fi

    expected="$(awk 'NR == 1 { print $1 }' "${sidecar}")"
    actual="$(sha256_file "${archive}")"
    if [ -z "${expected}" ] || [ "${expected}" != "${actual}" ]; then
        echo "error: checksum mismatch for ${archive}" >&2
        exit 1
    fi
}

copy_component() {
    local source_dir="$1"
    local target_dir="$2"
    local label="$3"

    if [ ! -d "${source_dir}" ] || ! find "${source_dir}" -maxdepth 1 -type f -name '*.so' -print -quit | grep -q .; then
        echo "error: ${label} contains no shared libraries: ${source_dir}" >&2
        exit 1
    fi

    mkdir -p "${target_dir}"
    cp "${source_dir}"/*.so "${target_dir}/"
}

mkdir -p \
    "${WORK_DIR}/commons/jniLibs" \
    "${WORK_DIR}/llamacpp/${LLAMACPP_ROOT}/llamacpp" \
    "${WORK_DIR}/onnx/${ONNX_ROOT}/onnx"

for abi in "${ABIS[@]}"; do
    source_name="RACommons-android-${abi}-v${VERSION}.zip"
    source_archive="${RELEASE_DIR}/${source_name}"
    extract_dir="${WORK_DIR}/source-${abi}"

    if [ ! -f "${source_archive}" ]; then
        echo "error: missing Android ABI archive: ${source_archive}" >&2
        exit 1
    fi
    verify_sidecar "${source_archive}"

    mkdir -p "${extract_dir}"
    unzip -q "${source_archive}" -d "${extract_dir}"

    copy_component \
        "${extract_dir}/${abi}/jni" \
        "${WORK_DIR}/commons/jniLibs/${abi}" \
        "RACommons ${abi} payload"
    copy_component \
        "${extract_dir}/${abi}/llamacpp" \
        "${WORK_DIR}/llamacpp/${LLAMACPP_ROOT}/llamacpp/${abi}" \
        "LlamaCPP ${abi} payload"
    copy_component \
        "${extract_dir}/${abi}/onnx" \
        "${WORK_DIR}/onnx/${ONNX_ROOT}/onnx/${abi}" \
        "ONNX ${abi} payload"
done

rm -f \
    "${RELEASE_DIR}/${COMMONS_NAME}" "${RELEASE_DIR}/${COMMONS_NAME}.sha256" \
    "${RELEASE_DIR}/${LLAMACPP_NAME}" "${RELEASE_DIR}/${LLAMACPP_NAME}.sha256" \
    "${RELEASE_DIR}/${ONNX_NAME}" "${RELEASE_DIR}/${ONNX_NAME}.sha256"

# Prevent macOS validation runs from adding Finder metadata to the archives.
export COPYFILE_DISABLE=1
(cd "${WORK_DIR}/commons" && zip -qr "${RELEASE_DIR}/${COMMONS_NAME}" jniLibs)
(cd "${WORK_DIR}/llamacpp" && zip -qr "${RELEASE_DIR}/${LLAMACPP_NAME}" "${LLAMACPP_ROOT}")
(cd "${WORK_DIR}/onnx" && zip -qr "${RELEASE_DIR}/${ONNX_NAME}" "${ONNX_ROOT}")

write_sidecar() {
    local name="$1"
    local digest
    digest="$(sha256_file "${RELEASE_DIR}/${name}")"
    printf '%s  %s\n' "${digest}" "${name}" > "${RELEASE_DIR}/${name}.sha256"
    verify_sidecar "${RELEASE_DIR}/${name}"
}

assert_archive_payload() {
    local archive="$1"
    local prefix="$2"
    local abi match_count

    for abi in "${ABIS[@]}"; do
        # grep -q can close the pipe before unzip finishes, which becomes a
        # false failure under pipefail. Count matches so both commands consume
        # the complete archive listing.
        match_count="$(unzip -Z1 "${RELEASE_DIR}/${archive}" | grep -Ec "^${prefix}/${abi}/[^/]+[.]so$" || true)"
        if [ "${match_count}" -lt 1 ]; then
            echo "error: ${archive} has no ${abi} shared-library payload under ${prefix}/" >&2
            exit 1
        fi
    done
}

write_sidecar "${COMMONS_NAME}"
write_sidecar "${LLAMACPP_NAME}"
write_sidecar "${ONNX_NAME}"

assert_archive_payload "${COMMONS_NAME}" "jniLibs"
assert_archive_payload "${LLAMACPP_NAME}" "${LLAMACPP_ROOT}/llamacpp"
assert_archive_payload "${ONNX_NAME}" "${ONNX_ROOT}/onnx"

ANDROID_MANIFEST="${RELEASE_DIR}/ANDROID-ASSETS-MANIFEST.txt"
{
    printf 'version=%s\n' "${VERSION}"
    printf 'abis=%s\n' "${ABIS[*]}"
    for name in "${COMMONS_NAME}" "${LLAMACPP_NAME}" "${ONNX_NAME}"; do
        printf 'asset=%s sha256=%s so_count=%s\n' \
            "${name}" \
            "$(sha256_file "${RELEASE_DIR}/${name}")" \
            "$(unzip -Z1 "${RELEASE_DIR}/${name}" | grep -Ec '[.]so$')"
    done
} > "${ANDROID_MANIFEST}"

# Refresh the top-level release index after adding the aggregate assets.
(cd "${RELEASE_DIR}" && ls -la > MANIFEST.txt)

echo "Assembled and verified Android release assets for v${VERSION}:"
cat "${ANDROID_MANIFEST}"
