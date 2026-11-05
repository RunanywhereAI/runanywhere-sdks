#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# build-litertlm-android.sh: builds the LiteRT-LM C API for Android arm64 from the
# tag pinned in core/VERSIONS and lays out the tree engines/litertlm consumes:
#
#   engines/litertlm/prebuilt/current/include/c/{api_export,conversation,engine,error_reporter}.h
#   engines/litertlm/prebuilt/current/lib/arm64-v8a/liblitert-lm.so
#   engines/litertlm/prebuilt/current/lib/arm64-v8a/libLiteRtDispatch_GoogleTensor.so
#   engines/litertlm/prebuilt/current/lib/arm64-v8a/<LiteRT-LM's prebuilt/android_arm64/*.so>
#
# LiteRT-LM releases C API binaries for iOS and macOS only. Its Android AAR exports
# JNI symbols and nothing else, so Android builds //c:litert-lm from source.
#
# Requires: git, git-lfs, bazelisk or bazel, a JDK, ANDROID_HOME, and ANDROID_NDK_HOME
# pointing at NDK r28b or newer (LiteRT-LM's minimum; the rest of this repo stays on
# the NDK_VERSION in core/VERSIONS, and the library links its C++ runtime statically).
#
# Usage: ./scripts/build/build-litertlm-android.sh [--force]
#   LITERTLM_BUILD_DIR   clone location (default: build/litertlm-src)
#   LITERTLM_BAZEL_ARGS  extra startup options for bazel, e.g. --output_base=/short/path

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=core/scripts/load-versions.sh
source "${REPO_ROOT}/core/scripts/load-versions.sh"

FORCE=0
if [ "${1:-}" = "--force" ]; then
    FORCE=1
fi

DEST="${REPO_ROOT}/engines/litertlm/prebuilt/current"
SRC="${LITERTLM_BUILD_DIR:-${REPO_ROOT}/build/litertlm-src}"
TAG="v${LITERT_LM_VERSION:?LITERT_LM_VERSION is not set in core/VERSIONS}"
COMMIT="${LITERT_LM_COMMIT:?LITERT_LM_COMMIT is not set in core/VERSIONS}"
ABI="arm64-v8a"
HEADERS=(api_export conversation engine error_reporter)

if [ -f "${DEST}/lib/${ABI}/liblitert-lm.so" ] && [ -f "${DEST}/lib/${ABI}/libLiteRtDispatch_GoogleTensor.so" ] &&
    [ "${FORCE}" -eq 0 ]; then
    echo "LiteRT-LM C API already at ${DEST} (--force to rebuild)"
    exit 0
fi

: "${ANDROID_HOME:?ANDROID_HOME must point at the Android SDK}"
: "${ANDROID_NDK_HOME:?ANDROID_NDK_HOME must point at NDK r28b or newer}"
if command -v bazelisk >/dev/null 2>&1; then
    BAZEL=bazelisk
elif command -v bazel >/dev/null 2>&1; then
    BAZEL=bazel
else
    echo "error: bazelisk or bazel is required" >&2
    exit 1
fi
git lfs version >/dev/null

if [ ! -d "${SRC}/.git" ]; then
    # The LFS prebuilts of other platforms are large and unused here.
    GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1 --branch "${TAG}" \
        https://github.com/google-ai-edge/LiteRT-LM.git "${SRC}"
fi
actual_commit="$(git -C "${SRC}" rev-parse HEAD)"
if [ "${actual_commit}" != "${COMMIT}" ]; then
    echo "error: ${SRC} is at ${actual_commit}, expected ${COMMIT} (${TAG})" >&2
    exit 1
fi
git -C "${SRC}" lfs pull --include "prebuilt/android_arm64/*"

# Flags beyond --config=android_arm64:
#   max-page-size / common-page-size: this target otherwise links with 4 KB LOAD
#     alignment, which validate_elf_16kb_alignment in build-core-android.sh refuses.
#   soname: the target links with a version script and no soname, and bionic then
#     refuses a directly linked consumer: cannot find "liblitert-lm.so" from verneed[0].
BAZEL_FLAGS=(
    --config=android_arm64
    -c opt
    --linkopt=-Wl,-z,max-page-size=16384
    --linkopt=-Wl,-z,common-page-size=16384
    --linkopt=-Wl,-soname,liblitert-lm.so
)
# shellcheck disable=SC2086  # startup options are a word list by design
(cd "${SRC}" && "${BAZEL}" ${LITERTLM_BAZEL_ARGS:-} build "${BAZEL_FLAGS[@]}" //c:litert-lm)
# shellcheck disable=SC2086
BAZEL_BIN="$(cd "${SRC}" && "${BAZEL}" ${LITERTLM_BAZEL_ARGS:-} info "${BAZEL_FLAGS[@]}" bazel-bin)"

# The Google Tensor NPU's dispatch library, from the LiteRT commit this tag pins: the runtime
# asks for LiteRtDispatchQueryInterface, which the litert-npu-runtime-google-tensor AAR
# (2.3.2 at this writing) does not export. The target lists a package that only exists inside
# Google, through hooks that google_tensor_hook.cc compiles in only with
# LITERT_GOOGLE_TENSOR_HAS_HOOKS, so that one line goes before the build.
DISPATCH_FLAGS=(
    --config=android_arm64
    -c opt
    --linkopt=-Wl,-z,max-page-size=16384
    --linkopt=-Wl,-z,common-page-size=16384
)
DISPATCH_PATH="litert/vendors/google_tensor/dispatch"
# shellcheck disable=SC2086
OUTPUT_BASE="$(cd "${SRC}" && "${BAZEL}" ${LITERTLM_BAZEL_ARGS:-} info "${DISPATCH_FLAGS[@]}" output_base)"
DISPATCH_BUILD_FILE="${OUTPUT_BASE}/external/litert/${DISPATCH_PATH}/BUILD"
chmod u+w "${DISPATCH_BUILD_FILE}"
sed -i.orig '/^ *"\/\/litert\/vendors\/google_tensor\/hooks",$/d' "${DISPATCH_BUILD_FILE}"
# shellcheck disable=SC2086
(cd "${SRC}" && "${BAZEL}" ${LITERTLM_BAZEL_ARGS:-} build "${DISPATCH_FLAGS[@]}" \
    "@litert//${DISPATCH_PATH}:dispatch_api_so")

STAGE="$(mktemp -d "${REPO_ROOT}/engines/litertlm/.prebuilt-stage.XXXXXX")"
trap 'rm -rf "${STAGE}"' EXIT
mkdir -p "${STAGE}/include/c" "${STAGE}/lib/${ABI}"
for header in "${HEADERS[@]}"; do
    cp "${SRC}/c/${header}.h" "${STAGE}/include/c/"
done
cp "${SRC}/prebuilt/android_arm64/"*.so "${STAGE}/lib/${ABI}/"
cp "${BAZEL_BIN}/c/liblitert-lm.so" "${STAGE}/lib/${ABI}/"
cp "${BAZEL_BIN}/external/litert/${DISPATCH_PATH}/libLiteRtDispatch_GoogleTensor.so" "${STAGE}/lib/${ABI}/"
chmod -R u+w "${STAGE}"

# Prebuilts that are still LFS pointers would be text files of ~130 bytes.
for library in "${STAGE}/lib/${ABI}"/*.so; do
    if [ "$(head -c 4 "${library}" | od -An -tx1 | tr -d ' \n')" != "7f454c46" ]; then
        echo "error: ${library} is not an ELF file (git lfs pull incomplete?)" >&2
        exit 1
    fi
done

mkdir -p "$(dirname "${DEST}")"
rm -rf "${DEST}"
mv "${STAGE}" "${DEST}"
trap - EXIT
chmod 755 "${DEST}"
echo "LiteRT-LM C API ${TAG} staged at ${DEST}"
