#!/usr/bin/env bash
# Build, validate, and archive the Play upload bundle without putting release
# credentials in Gradle arguments or shell output.
set +x
set -euo pipefail
umask 077

# Values inherited from the caller start exported. Make them shell-local before
# running even path-discovery helpers; only the two Gradle invocations that need
# them receive a freshly exported child environment below.
for release_name in \
    RUNANYWHERE_BASE_URL \
    RUNANYWHERE_API_KEY \
    RUNANYWHERE_PRIVACY_POLICY_URL \
    RUNANYWHERE_WEB_SEARCH_URL \
    KEYSTORE_PATH \
    KEYSTORE_PASSWORD \
    KEY_ALIAS \
    KEY_PASSWORD \
    UPLOAD_CERT_SHA256 \
    SDK_VERSION; do
    export -n "${release_name}" 2>/dev/null || true
done
unset release_name

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${APP_ROOT}/../../.." && pwd)"
QUALCOMM_ROOT="$(cd "${REPO_ROOT}/.." && pwd)"

KEYCHAIN_SERVICE="com.runanywhere.android.release"
BUNDLETOOL_VERSION="1.18.3"
BUNDLETOOL_SHA256="a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29"
BUNDLETOOL_URL="https://github.com/google/bundletool/releases/download/${BUNDLETOOL_VERSION}/\
bundletool-all-${BUNDLETOOL_VERSION}.jar"
EXPECTED_QAIRT_VERSION="2.47.0"
EXPECTED_QAIRT_BUILD_ID="260601114230"
EXPECTED_ANDROID_NDK_REVISION="27.3.13750724"

case "$(uname -s)" in
    Darwin) USE_KEYCHAIN=1 ;;
    *) USE_KEYCHAIN=0 ;;
esac
SKIP_NATIVE_REBUILD=0
ALLOW_DIRTY=0
ARCHIVE_DIR=""
ARCHIVE_PARTIAL=""
BUNDLETOOL_DOWNLOAD=""

usage() {
    cat >&2 <<'USAGE'
Usage: ./scripts/build-play-aab.sh [options]

Options:
  --keychain             Fill missing inputs from macOS Keychain.
  --no-keychain          Use environment variables only (recommended for CI).
  --skip-native-rebuild  Reuse staged native files, but rebuild/stage release AARs.
  --allow-dirty          Permit a traceable development archive from dirty sources.
  --archive-dir PATH     Override the new archive directory.
  -h, --help             Show this help.

Environment variables take precedence over Keychain items. Keychain account
names must exactly match the required environment-variable names documented in
docs/PLAY_STORE_RELEASE.md under service com.runanywhere.android.release.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --keychain)
            USE_KEYCHAIN=1
            shift
            ;;
        --no-keychain)
            USE_KEYCHAIN=0
            shift
            ;;
        --skip-native-rebuild)
            SKIP_NATIVE_REBUILD=1
            shift
            ;;
        --allow-dirty)
            ALLOW_DIRTY=1
            shift
            ;;
        --archive-dir)
            [[ $# -ge 2 ]] || { usage; exit 2; }
            ARCHIVE_DIR="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage
            exit 2
            ;;
    esac
done

cleanup() {
    unset RUNANYWHERE_API_KEY KEYSTORE_PASSWORD KEY_PASSWORD SDK_VERSION
    if [[ -n "${ARCHIVE_PARTIAL}" && -d "${ARCHIVE_PARTIAL}" ]]; then
        rm -rf -- "${ARCHIVE_PARTIAL}"
    fi
    if [[ -n "${BUNDLETOOL_DOWNLOAD}" && -f "${BUNDLETOOL_DOWNLOAD}" ]]; then
        rm -f -- "${BUNDLETOOL_DOWNLOAD}"
    fi
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

required_inputs=(
    RUNANYWHERE_BASE_URL
    RUNANYWHERE_API_KEY
    RUNANYWHERE_PRIVACY_POLICY_URL
    RUNANYWHERE_WEB_SEARCH_URL
    KEYSTORE_PATH
    KEYSTORE_PASSWORD
    KEY_ALIAS
    KEY_PASSWORD
    UPLOAD_CERT_SHA256
    SDK_VERSION
)

run_release_gradle() (
    set +x
    for name in "${required_inputs[@]}"; do
        export "${name}"
    done
    exec ./gradlew "$@" \
        --no-daemon \
        --max-workers=2 \
        --dependency-verification strict \
        -Pkotlin.compiler.execution.strategy=in-process
)

run_sdk_versioned() (
    set +x
    export SDK_VERSION
    exec "$@"
)

run_sdk_gradle() (
    set +x
    export SDK_VERSION
    cd "${REPO_ROOT}/sdk/runanywhere-kotlin"
    exec ./gradlew "$@" \
        --no-daemon \
        --max-workers=2 \
        --dependency-verification strict \
        -Prunanywhere.useLocalNatives=true \
        -Pkotlin.compiler.execution.strategy=in-process
)

run_app_gradle() (
    set +x
    cd "${APP_ROOT}"
    exec ./gradlew "$@" \
        --no-daemon \
        --max-workers=2 \
        --dependency-verification strict \
        -Pkotlin.compiler.execution.strategy=in-process
)

# Environment wins. On macOS, only values that are still blank are queried
# from the fixed service. `security -w` writes to this command substitution;
# the value is never echoed or placed in a child process's argv.
if [[ "${USE_KEYCHAIN}" -eq 1 ]]; then
    require_command security
    for name in "${required_inputs[@]}"; do
        if [[ -z "${!name:-}" ]]; then
            keychain_value="$(security find-generic-password \
                -s "${KEYCHAIN_SERVICE}" \
                -a "${name}" \
                -w 2>/dev/null || true)"
            if [[ -n "${keychain_value}" ]]; then
                printf -v "${name}" '%s' "${keychain_value}"
            fi
            unset keychain_value
        fi
    done
fi

missing_inputs=()
for name in "${required_inputs[@]}"; do
    if [[ -z "${!name:-}" ]]; then
        missing_inputs+=("${name}")
    fi
done
if [[ "${#missing_inputs[@]}" -ne 0 ]]; then
    echo "ERROR: missing required Play release inputs:" >&2
    printf '  %s\n' "${missing_inputs[@]}" >&2
    exit 2
fi

cd "${APP_ROOT}"

# Resolve a relative keystore exactly as Gradle does from the app root. It
# remains shell-local until run_release_gradle exports it to that child only.
if [[ "${KEYSTORE_PATH}" != /* ]]; then
    KEYSTORE_PATH="${APP_ROOT}/${KEYSTORE_PATH}"
fi
[[ -f "${KEYSTORE_PATH}" && -r "${KEYSTORE_PATH}" ]] || \
    fail "KEYSTORE_PATH does not point to a readable upload keystore"
KEYSTORE_PATH="$(cd "$(dirname "${KEYSTORE_PATH}")" && pwd -P)/$(basename "${KEYSTORE_PATH}")"
expected_cert_sha256="$(
    tr -d '[:space:]:' <<<"${UPLOAD_CERT_SHA256}" | \
        tr '[:lower:]' '[:upper:]'
)"
[[ "${expected_cert_sha256}" =~ ^[0-9A-F]{64}$ ]] || \
    fail "UPLOAD_CERT_SHA256 must contain exactly 64 hexadecimal digits"
UPLOAD_CERT_SHA256="${expected_cert_sha256}"
[[ "${SDK_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([._+-][A-Za-z0-9._+-]+)?$ ]] || \
    fail "SDK_VERSION must be an explicit release version such as 0.1.5"
case "${SDK_VERSION}" in
    *[Ss][Nn][Aa][Pp][Ss][Hh][Oo][Tt]*) fail "SDK_VERSION must not be a SNAPSHOT version" ;;
esac
expected_sdk_version="${SDK_VERSION}"

for command_name in awk chmod cmake cp date diff env find git grep java jq keytool jarsigner mktemp mv python3 shasum sort stat strings tr unzip; do
    require_command "${command_name}"
done
[[ -x ./gradlew ]] || fail "Gradle wrapper is missing or not executable"

dependency_state_files=(
    "${APP_ROOT}/gradle/verification-metadata.xml"
    "${APP_ROOT}/app/gradle.lockfile"
    "${REPO_ROOT}/sdk/runanywhere-kotlin/gradle/verification-metadata.xml"
    "${REPO_ROOT}/sdk/runanywhere-kotlin/gradle.lockfile"
    "${REPO_ROOT}/sdk/runanywhere-kotlin/modules/runanywhere-core-llamacpp/gradle.lockfile"
    "${REPO_ROOT}/sdk/runanywhere-kotlin/modules/runanywhere-core-onnx/gradle.lockfile"
    "${REPO_ROOT}/sdk/runanywhere-kotlin/modules/runanywhere-core-qhexrt/gradle.lockfile"
)
for dependency_state_file in "${dependency_state_files[@]}"; do
    [[ -s "${dependency_state_file}" ]] || \
        fail "required Gradle dependency state is missing: ${dependency_state_file}"
done
unset dependency_state_file

# Run the existing Gradle gate before any native compilation. It validates the
# HTTPS endpoints, upload keystore, and expected upload-certificate fingerprint.
echo "==> Validating Play release configuration"
run_release_gradle :app:verifyPlayRelease

bundletool_cache="${APP_ROOT}/build/tools/bundletool-all-${BUNDLETOOL_VERSION}.jar"
mkdir -p "$(dirname "${bundletool_cache}")"
if [[ ! -f "${bundletool_cache}" ]]; then
    require_command curl
    bundletool_download_candidate="$(mktemp "${bundletool_cache}.partial.XXXXXX")"
    BUNDLETOOL_DOWNLOAD="${bundletool_download_candidate}"
    curl --fail --location --silent --show-error --retry 2 \
        --output "${BUNDLETOOL_DOWNLOAD}" \
        "${BUNDLETOOL_URL}"
    downloaded_sha="$(shasum -a 256 "${BUNDLETOOL_DOWNLOAD}")"
    downloaded_sha="${downloaded_sha%% *}"
    if [[ "${downloaded_sha}" != "${BUNDLETOOL_SHA256}" ]]; then
        fail "downloaded bundletool checksum did not match the pinned release"
    fi
    mv "${BUNDLETOOL_DOWNLOAD}" "${bundletool_cache}"
    BUNDLETOOL_DOWNLOAD=""
fi
cached_sha="$(shasum -a 256 "${bundletool_cache}")"
cached_sha="${cached_sha%% *}"
[[ "${cached_sha}" == "${BUNDLETOOL_SHA256}" ]] || \
    fail "cached bundletool checksum did not match the pinned release"
BUNDLETOOL_COMMAND=(java -jar "${bundletool_cache}")
bundletool_reported_version="$("${BUNDLETOOL_COMMAND[@]}" version 2>&1)"
bundletool_reported_version="$(tr -d '[:space:]' <<<"${bundletool_reported_version}")"
[[ "${bundletool_reported_version}" == "${BUNDLETOOL_VERSION}" ]] || \
    fail "bundletool ${BUNDLETOOL_VERSION} is required"

export ANDROID_HOME="${ANDROID_HOME:-${HOME}/Library/Android/sdk}"
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-${ANDROID_HOME}/ndk/${EXPECTED_ANDROID_NDK_REVISION}}"
export ANDROID_NDK_ROOT="${ANDROID_NDK_ROOT:-${ANDROID_NDK_HOME}}"
export ANDROID_NDK="${ANDROID_NDK:-${ANDROID_NDK_HOME}}"
export QHEXRT_SOURCE_DIR="${QHEXRT_SOURCE_DIR:-${QUALCOMM_ROOT}/QHexRT}"
export QNN_SDK_ROOT="${QNN_SDK_ROOT:-${QAIRT_ROOT:-${QUALCOMM_ROOT}/qairt/2.47.0.260601}}"
export QAIRT_ROOT="${QAIRT_ROOT:-${QNN_SDK_ROOT}}"

[[ -d "${ANDROID_NDK_HOME}" ]] || fail "Android NDK not found at ANDROID_NDK_HOME"
NDK_MANIFEST="${ANDROID_NDK_HOME}/source.properties"
[[ -f "${NDK_MANIFEST}" ]] || fail "Android NDK source.properties is missing"
android_ndk_revision="$(awk -F= '
    $1 ~ /^Pkg\.Revision/ {
        gsub(/[[:space:]]/, "", $2)
        print $2
        exit
    }
' "${NDK_MANIFEST}")"
[[ "${android_ndk_revision}" == "${EXPECTED_ANDROID_NDK_REVISION}" ]] || \
    fail "Android NDK revision does not match the pinned release"
case "$(uname -s)" in
    Darwin) ndk_host_tag="darwin-x86_64" ;;
    Linux) ndk_host_tag="linux-x86_64" ;;
    *) fail "unsupported host for Android ELF validation" ;;
esac
ANDROID_READELF="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/${ndk_host_tag}/bin/llvm-readelf"
[[ -x "${ANDROID_READELF}" ]] || fail "NDK llvm-readelf is missing"

[[ -d "${QNN_SDK_ROOT}/include/QNN" ]] || fail "QAIRT/QNN headers not found at QNN_SDK_ROOT"
[[ -d "${QNN_SDK_ROOT}/lib/aarch64-android" ]] || fail "QAIRT Android runtime not found at QNN_SDK_ROOT"
qnn_sdk_canonical="$(cd "${QNN_SDK_ROOT}" && pwd -P)"
qairt_canonical="$(cd "${QAIRT_ROOT}" && pwd -P)"
[[ "${qnn_sdk_canonical}" == "${qairt_canonical}" ]] || \
    fail "QNN_SDK_ROOT and QAIRT_ROOT must identify the same release"
QAIRT_MANIFEST="${qairt_canonical}/sdk.yaml"
[[ -f "${QAIRT_MANIFEST}" ]] || fail "QAIRT sdk.yaml is missing"
qairt_version="$(awk '$1 == "version:" {print $2; exit}' "${QAIRT_MANIFEST}")"
qairt_build_id="$(awk '$1 == "build_id:" {print $2; exit}' "${QAIRT_MANIFEST}")"
[[ -n "${qairt_version}" && -n "${qairt_build_id}" ]] || fail "could not read QAIRT version metadata"
[[ "${qairt_version}" == "${EXPECTED_QAIRT_VERSION}" && \
   "${qairt_build_id}" == "${EXPECTED_QAIRT_BUILD_ID}" ]] || \
    fail "QAIRT version/build does not match the pinned release"

[[ -d "${QHEXRT_SOURCE_DIR}/.git" || -f "${QHEXRT_SOURCE_DIR}/.git" ]] || \
    fail "QHexRT source checkout is not a Git worktree"
[[ -f "${QHEXRT_SOURCE_DIR}/CMakeLists.txt" ]] || fail "QHexRT source checkout not found"
[[ -f "${QHEXRT_SOURCE_DIR}/include/qhexrt/qhexrt_c.h" ]] || fail "QHexRT public C header not found"
sdk_initial_status="$(git -C "${REPO_ROOT}" status --porcelain --untracked-files=all)"
qhexrt_initial_status="$(git -C "${QHEXRT_SOURCE_DIR}" status --porcelain --untracked-files=all)"
if [[ "${ALLOW_DIRTY}" -eq 0 && \
      ( -n "${sdk_initial_status}" || -n "${qhexrt_initial_status}" ) ]]; then
    unset sdk_initial_status qhexrt_initial_status
    fail "Play release requires clean SDK and QHexRT worktrees (use --allow-dirty only for development)"
fi
unset sdk_initial_status qhexrt_initial_status

if [[ "${SKIP_NATIVE_REBUILD}" -eq 0 ]]; then
    for command_name in install; do
        require_command "${command_name}"
    done
    echo "==> Rebuilding private QHexRT static libraries"
    cmake -E remove_directory "${QHEXRT_SOURCE_DIR}/build-android"
    cmake \
        -S "${QHEXRT_SOURCE_DIR}" \
        -B "${QHEXRT_SOURCE_DIR}/build-android" \
        -DCMAKE_TOOLCHAIN_FILE="${QHEXRT_SOURCE_DIR}/cmake/toolchains/android.cmake" \
        -DANDROID_NDK="${ANDROID_NDK_HOME}" \
        -DQHEXRT_QNN_SDK_ROOT="${QNN_SDK_ROOT}" \
        -DQHEXRT_BUILD_TOOLS=OFF
    cmake --build "${QHEXRT_SOURCE_DIR}/build-android" \
        --target qhexrt_core qhexrt_host \
        --parallel 2

    qhexrt_prebuilt="${REPO_ROOT}/engines/qhexrt/prebuilt"
    mkdir -p "${qhexrt_prebuilt}/include/qhexrt" "${qhexrt_prebuilt}/lib/arm64-v8a"
    install -m 0644 \
        "${QHEXRT_SOURCE_DIR}/include/qhexrt/qhexrt_c.h" \
        "${qhexrt_prebuilt}/include/qhexrt/qhexrt_c.h"
    install -m 0644 \
        "${QHEXRT_SOURCE_DIR}/build-android/libqhexrt_core.a" \
        "${qhexrt_prebuilt}/lib/arm64-v8a/libqhexrt_core.a"
    install -m 0644 \
        "${QHEXRT_SOURCE_DIR}/build-android/libqhexrt_host.a" \
        "${qhexrt_prebuilt}/lib/arm64-v8a/libqhexrt_host.a"

    echo "==> Rebuilding and staging arm64-v8a SDK native libraries from a clean tree"
    cmake -E remove_directory "${REPO_ROOT}/build/android-arm64"
    env RAC_BUILD_JOBS=2 \
        "${REPO_ROOT}/scripts/build/build-core-android.sh" arm64-v8a
else
    echo "==> Reusing staged native libraries (--skip-native-rebuild)"
fi

staged_core="${REPO_ROOT}/sdk/runanywhere-kotlin/src/main/jniLibs/arm64-v8a"
staged_llama="${REPO_ROOT}/sdk/runanywhere-kotlin/modules/runanywhere-core-llamacpp/src/main/jniLibs/arm64-v8a"
staged_onnx="${REPO_ROOT}/sdk/runanywhere-kotlin/modules/runanywhere-core-onnx/src/main/jniLibs/arm64-v8a"
staged_qhexrt="${REPO_ROOT}/sdk/runanywhere-kotlin/modules/runanywhere-core-qhexrt/src/main/jniLibs/arm64-v8a"
staged_skels="${REPO_ROOT}/sdk/runanywhere-kotlin/modules/runanywhere-core-qhexrt/\
src/main/assets/runanywhere/qhexrt/skels/arm64-v8a"
for stale_abi in armeabi-v7a x86 x86_64; do
    cmake -E remove_directory "${staged_core%/*}/${stale_abi}"
    cmake -E remove_directory "${staged_llama%/*}/${stale_abi}"
    cmake -E remove_directory "${staged_onnx%/*}/${stale_abi}"
    cmake -E remove_directory "${staged_qhexrt%/*}/${stale_abi}"
    cmake -E remove_directory "${staged_skels%/*}/${stale_abi}"
done
required_staged_host_natives=(
    "${staged_core}/libc++_shared.so"
    "${staged_core}/libomp.so"
    "${staged_core}/librac_backend_cloud.so"
    "${staged_core}/librac_commons.so"
    "${staged_core}/librunanywhere_jni.so"
    "${staged_llama}/libc++_shared.so"
    "${staged_llama}/librac_backend_llamacpp.so"
    "${staged_llama}/librac_backend_llamacpp_jni.so"
    "${staged_llama}/librunanywhere_llamacpp.so"
    "${staged_onnx}/libc++_shared.so"
    "${staged_onnx}/libonnxruntime.so"
    "${staged_onnx}/librac_backend_onnx.so"
    "${staged_onnx}/librac_backend_onnx_jni.so"
    "${staged_onnx}/librac_backend_sherpa.so"
    "${staged_onnx}/librunanywhere_onnx.so"
    "${staged_onnx}/librunanywhere_sherpa.so"
    "${staged_onnx}/libsherpa-onnx-c-api.so"
    "${staged_onnx}/libsherpa-onnx-jni.so"
    "${staged_qhexrt}/librac_backend_qhexrt.so"
    "${staged_qhexrt}/librac_backend_qhexrt_jni.so"
    "${staged_qhexrt}/libQnnHtp.so"
    "${staged_qhexrt}/libQnnHtpNetRunExtensions.so"
    "${staged_qhexrt}/libQnnHtpPrepare.so"
    "${staged_qhexrt}/libQnnSystem.so"
    "${staged_qhexrt}/libQnnHtpV75CalculatorStub.so"
    "${staged_qhexrt}/libQnnHtpV75Stub.so"
    "${staged_qhexrt}/libQnnHtpV79CalculatorStub.so"
    "${staged_qhexrt}/libQnnHtpV79Stub.so"
    "${staged_qhexrt}/libQnnHtpV81CalculatorStub.so"
    "${staged_qhexrt}/libQnnHtpV81Stub.so"
    "${staged_qhexrt}/libc++_shared.so"
)
required_staged_skels=(
    "${staged_skels}/libQnnHtpV75Skel.so"
    "${staged_skels}/libQnnHtpV79Skel.so"
    "${staged_skels}/libQnnHtpV81Skel.so"
)
for artifact in "${required_staged_host_natives[@]}" "${required_staged_skels[@]}"; do
    [[ -s "${artifact}" ]] || fail "required staged native artifact is missing: ${artifact}"
done
for staged_dir_and_count in \
    "${staged_core}:5" \
    "${staged_llama}:4" \
    "${staged_onnx}:9" \
    "${staged_qhexrt}:13"; do
    staged_dir="${staged_dir_and_count%:*}"
    expected_staged_count="${staged_dir_and_count##*:}"
    actual_staged_count="$(find "${staged_dir}" -maxdepth 1 -type f -name '*.so' | awk 'END {print NR + 0}')"
    [[ "${actual_staged_count}" -eq "${expected_staged_count}" ]] || \
        fail "staged native module contains missing or stale Android libraries: ${staged_dir}"
done

shopt -s nullglob
staged_skel_files=("${staged_skels}"/*Skel.so)
staged_jni_skels=("${staged_qhexrt}"/*Skel.so)
shopt -u nullglob
[[ "${#staged_skel_files[@]}" -eq 3 ]] || fail "staged QHexRT assets must contain exactly three DSP skels"
[[ "${#staged_jni_skels[@]}" -eq 0 ]] || fail "DSP skels must not be staged as Android JNI libraries"

strings "${staged_qhexrt}/librac_backend_qhexrt.so" | \
    grep -F 'qhexrt:engine-available' >/dev/null || fail "staged QHexRT backend was compiled as a stub"

minimum_elf_load_alignment() {
    local elf_file="$1"
    local align_hex
    local align_dec
    local load_count=0
    local minimum=0
    while IFS= read -r align_hex; do
        [[ "${align_hex}" == 0x* ]] || continue
        align_dec=$((align_hex))
        load_count=$((load_count + 1))
        if [[ "${align_dec}" -lt 16384 ]]; then
            return 1
        fi
        if [[ "${minimum}" -eq 0 || "${align_dec}" -lt "${minimum}" ]]; then
            minimum="${align_dec}"
        fi
    done < <("${ANDROID_READELF}" -l "${elf_file}" 2>/dev/null | \
        awk '/^[[:space:]]*LOAD[[:space:]]/ {print $NF}')
    [[ "${load_count}" -gt 0 ]] || return 1
    printf '0x%x\n' "${minimum}"
}

while IFS= read -r staged_elf; do
    minimum_elf_load_alignment "${staged_elf}" >/dev/null || \
        fail "staged Android ELF is not 16 KB LOAD-aligned: ${staged_elf}"
done < <(find "${staged_core}" "${staged_llama}" "${staged_onnx}" "${staged_qhexrt}" \
    -maxdepth 1 -type f -name '*.so' -print)

# The default path is from-scratch for managed outputs too. The explicit native
# reuse flag preserves Gradle caches for a repeat development archive.
if [[ "${SKIP_NATIVE_REBUILD}" -eq 0 ]]; then
    echo "==> Cleaning Kotlin SDK and Android app Gradle outputs"
    run_sdk_gradle clean
    run_app_gradle :app:clean
fi

# Always rebuild and restage the release AARs, including the QHexRT module, so
# the app never consumes a debug or stale-variant AAR by accident.
echo "==> Building and staging release AARs"
run_sdk_versioned "${APP_ROOT}/scripts/stage-sdk-aars.sh" release

dependency_evidence_dir="${APP_ROOT}/build/release-dependency-evidence"
cmake -E remove_directory "${dependency_evidence_dir}"
mkdir -p "${dependency_evidence_dir}"

write_staged_aar_hashes() {
    local output="$1"
    local aar_name
    local aar_path
    local aar_sha256
    : > "${output}"
    for aar_name in \
        runanywhere-sdk.aar \
        runanywhere-llamacpp.aar \
        runanywhere-onnx.aar \
        runanywhere-qhexrt.aar; do
        aar_path="${APP_ROOT}/libs/${aar_name}"
        [[ -s "${aar_path}" ]] || fail "staged SDK AAR is missing: ${aar_path}"
        aar_sha256="$(shasum -a 256 "${aar_path}")"
        aar_sha256="${aar_sha256%% *}"
        printf '%s  %s\n' "${aar_sha256}" "${aar_name}" >> "${output}"
    done
}

staged_aar_hashes_before="${dependency_evidence_dir}/staged-aar-sha256.txt"
write_staged_aar_hashes "${staged_aar_hashes_before}"

echo "==> Capturing strict release dependency graphs"
run_sdk_gradle :dependencies --configuration releaseRuntimeClasspath > \
    "${dependency_evidence_dir}/sdk-release-runtime-dependencies.txt"
for sdk_module in \
    runanywhere-core-llamacpp \
    runanywhere-core-onnx \
    runanywhere-core-qhexrt; do
    run_sdk_gradle \
        ":modules:${sdk_module}:dependencies" \
        --configuration releaseRuntimeClasspath > \
        "${dependency_evidence_dir}/${sdk_module}-release-runtime-dependencies.txt"
done
unset sdk_module
run_app_gradle :app:dependencies --configuration releaseRuntimeClasspath > \
    "${dependency_evidence_dir}/app-release-runtime-dependencies.txt"

# packageReleaseBundle owns the native-symbol ZIP, but AGP can update an
# existing archive without deleting entries from an older multi-ABI build.
# Reuse mode keeps app/build, so invalidate both the extractor output and the
# final ZIP. assembleRelease then runs mergeReleaseNativeDebugMetadata to
# recreate it from the current arm64-only AARs without recompiling the SDK.
if [[ "${SKIP_NATIVE_REBUILD}" -eq 1 ]]; then
    echo "==> Invalidating cached release native-symbol packaging"
    cmake -E remove_directory \
        "${APP_ROOT}/app/build/intermediates/native_symbol_tables/release"
    cmake -E remove_directory \
        "${APP_ROOT}/app/build/outputs/native-debug-symbols/release"
fi

echo "==> Running Android unit tests and release lint"
run_app_gradle \
    :app:testDebugUnitTest \
    :app:lintRelease

echo "==> Building guarded release APK and Play bundle"
run_release_gradle \
    :app:assembleRelease \
    :app:bundleRelease

staged_aar_hashes_after="${dependency_evidence_dir}/staged-aar-sha256-after-build.txt"
write_staged_aar_hashes "${staged_aar_hashes_after}"
diff -u "${staged_aar_hashes_before}" "${staged_aar_hashes_after}" >/dev/null || \
    fail "staged SDK AAR bytes changed during the app build"
rm -f "${staged_aar_hashes_after}"

# No post-build verifier needs backend or signing inputs. Drop them before
# invoking bundletool, jarsigner, jq, or archival helpers.
for name in "${required_inputs[@]}"; do
    unset "${name}"
done

shopt -s nullglob
release_aabs=("${APP_ROOT}"/app/build/outputs/bundle/release/*.aab)
shopt -u nullglob
[[ "${#release_aabs[@]}" -eq 1 ]] || \
    fail "expected exactly one release AAB, found ${#release_aabs[@]}"
AAB="${release_aabs[0]}"
[[ -s "${AAB}" ]] || fail "release AAB is empty"

MAPPING="${APP_ROOT}/app/build/outputs/mapping/release/mapping.txt"
NATIVE_SYMBOLS="${APP_ROOT}/app/build/outputs/native-debug-symbols/release/native-debug-symbols.zip"
SBOM="${APP_ROOT}/app/build/reports/release-sbom.cdx.json"
for artifact in "${MAPPING}" "${NATIVE_SYMBOLS}" "${SBOM}"; do
    [[ -s "${artifact}" ]] || fail "required release evidence is missing: ${artifact}"
done
unzip -tq "${NATIVE_SYMBOLS}" >/dev/null || fail "native debug-symbol archive is invalid"

unzip -tq "${AAB}" >/dev/null || fail "release AAB is not a valid ZIP archive"
bundletool_validation="$("${BUNDLETOOL_COMMAND[@]}" validate --bundle="${AAB}" 2>&1)" || {
    unset bundletool_validation
    fail "bundletool rejected the release AAB"
}
unset bundletool_validation

jarsigner_output="$(LC_ALL=C jarsigner -verify -verbose "${AAB}" 2>&1)" || {
    unset jarsigner_output
    fail "jarsigner rejected the release AAB"
}
if ! grep -q '^jar verified\.$' <<<"${jarsigner_output}"; then
    unset jarsigner_output
    fail "release AAB did not pass JAR signature verification"
fi
if grep -Eiq 'unsigned entr(y|ies)' <<<"${jarsigner_output}"; then
    unset jarsigner_output
    fail "release AAB contains unsigned entries"
fi
unset jarsigner_output

signature_coverage_json="$(python3 \
    "${APP_ROOT}/scripts/verify-aab-signature-coverage.py" \
    "${AAB}")" || fail "release AAB payload signature coverage is incomplete"
signed_payload_entry_count="$(jq -r '.signedPayloadEntryCount // 0' <<<"${signature_coverage_json}")"
unset signature_coverage_json
[[ "${signed_payload_entry_count}" =~ ^[1-9][0-9]*$ ]] || \
    fail "release AAB payload signature coverage could not be counted"

certificate_output="$(LC_ALL=C keytool -printcert -jarfile "${AAB}" 2>&1)" || {
    unset certificate_output
    fail "could not read the release AAB signing certificate"
}
signer_count="$(grep -c '^Signer #' <<<"${certificate_output}" || true)"
[[ "${signer_count}" -eq 1 ]] || {
    unset certificate_output
    fail "expected exactly one release AAB signer"
}
actual_cert_sha256="$(awk '
    /SHA256:/ {
        line=$0
        sub(/^.*SHA256:[[:space:]]*/, "", line)
        gsub(/:/, "", line)
        print toupper(line)
        exit
    }
' <<<"${certificate_output}")"
unset certificate_output
[[ "${actual_cert_sha256}" =~ ^[0-9A-F]{64}$ ]] || fail "could not parse the release AAB signing certificate SHA-256"
[[ "${actual_cert_sha256}" == "${expected_cert_sha256}" ]] || \
    fail "release AAB signing certificate does not match UPLOAD_CERT_SHA256"

application_id="$("${BUNDLETOOL_COMMAND[@]}" dump manifest --bundle="${AAB}" --xpath='/manifest/@package')"
version_code="$("${BUNDLETOOL_COMMAND[@]}" dump manifest --bundle="${AAB}" --xpath='/manifest/@android:versionCode')"
version_name="$("${BUNDLETOOL_COMMAND[@]}" dump manifest --bundle="${AAB}" --xpath='/manifest/@android:versionName')"
min_sdk="$("${BUNDLETOOL_COMMAND[@]}" dump manifest \
    --bundle="${AAB}" --xpath='/manifest/uses-sdk/@android:minSdkVersion')"
target_sdk="$("${BUNDLETOOL_COMMAND[@]}" dump manifest \
    --bundle="${AAB}" --xpath='/manifest/uses-sdk/@android:targetSdkVersion')"
debuggable="$("${BUNDLETOOL_COMMAND[@]}" dump manifest \
    --bundle="${AAB}" --xpath='/manifest/application/@android:debuggable')"

[[ "${application_id}" == "com.runanywhere.runanywhereai" ]] || fail "unexpected release application ID"
[[ "${version_code}" =~ ^[1-9][0-9]*$ ]] || fail "release version code is not a positive integer"
[[ "${version_name}" =~ ^[A-Za-z0-9._+-]+$ ]] || fail "release version name is missing or unsafe"
[[ "${min_sdk}" =~ ^[0-9]+$ && "${target_sdk}" =~ ^[0-9]+$ ]] || fail "could not read release SDK metadata"
[[ "${debuggable}" != "true" ]] || fail "release bundle is debuggable"
[[ "${expected_sdk_version}" == "${version_name}" ]] || \
    fail "SDK_VERSION does not exactly match the app release version"
jq -e --arg version "${version_name}" '
    .metadata.component.version == $version and
    ([.components[] | select(.group == "com.runanywhere.local")] as $local |
        ($local | length) == 4 and
        all($local[]; .version == $version))
' "${SBOM}" >/dev/null || fail "release SBOM does not use the exact SDK/app release version"

if [[ -z "${ARCHIVE_DIR}" ]]; then
    archive_stamp="$(date -u +%Y%m%dT%H%M%SZ)"
    ARCHIVE_DIR="${APP_ROOT}/build/play-release/${version_name}-${version_code}-${archive_stamp}"
elif [[ "${ARCHIVE_DIR}" != /* ]]; then
    ARCHIVE_DIR="${APP_ROOT}/${ARCHIVE_DIR}"
fi
[[ ! -e "${ARCHIVE_DIR}" ]] || fail "archive destination already exists"
mkdir -p "$(dirname "${ARCHIVE_DIR}")"
archive_partial_candidate="$(mktemp -d "${ARCHIVE_DIR}.partial.XXXXXX")"
ARCHIVE_PARTIAL="${archive_partial_candidate}"

archive_aab="RunAnywhere-${version_name}-${version_code}-release.aab"
cp "${AAB}" "${ARCHIVE_PARTIAL}/${archive_aab}"
cp "${MAPPING}" "${ARCHIVE_PARTIAL}/mapping.txt"
cp "${NATIVE_SYMBOLS}" "${ARCHIVE_PARTIAL}/native-debug-symbols.zip"
cp "${SBOM}" "${ARCHIVE_PARTIAL}/release-sbom.cdx.json"
mkdir -p \
    "${ARCHIVE_PARTIAL}/gradle-dependency-state/app" \
    "${ARCHIVE_PARTIAL}/gradle-dependency-state/sdk/modules/runanywhere-core-llamacpp" \
    "${ARCHIVE_PARTIAL}/gradle-dependency-state/sdk/modules/runanywhere-core-onnx" \
    "${ARCHIVE_PARTIAL}/gradle-dependency-state/sdk/modules/runanywhere-core-qhexrt"
cp "${APP_ROOT}/gradle/verification-metadata.xml" \
    "${ARCHIVE_PARTIAL}/gradle-dependency-state/app/verification-metadata.xml"
cp "${APP_ROOT}/app/gradle.lockfile" \
    "${ARCHIVE_PARTIAL}/gradle-dependency-state/app/gradle.lockfile"
cp "${REPO_ROOT}/sdk/runanywhere-kotlin/gradle/verification-metadata.xml" \
    "${ARCHIVE_PARTIAL}/gradle-dependency-state/sdk/verification-metadata.xml"
cp "${REPO_ROOT}/sdk/runanywhere-kotlin/gradle.lockfile" \
    "${ARCHIVE_PARTIAL}/gradle-dependency-state/sdk/gradle.lockfile"
for sdk_module in \
    runanywhere-core-llamacpp \
    runanywhere-core-onnx \
    runanywhere-core-qhexrt; do
    cp "${REPO_ROOT}/sdk/runanywhere-kotlin/modules/${sdk_module}/gradle.lockfile" \
        "${ARCHIVE_PARTIAL}/gradle-dependency-state/sdk/modules/${sdk_module}/gradle.lockfile"
done
unset sdk_module
cp -R "${dependency_evidence_dir}" "${ARCHIVE_PARTIAL}/dependency-evidence"
"${BUNDLETOOL_COMMAND[@]}" dump config --bundle="${AAB}" > "${ARCHIVE_PARTIAL}/bundletool-config.json"
"${BUNDLETOOL_COMMAND[@]}" dump manifest --bundle="${AAB}" > "${ARCHIVE_PARTIAL}/AndroidManifest.xml"

elf_validation_dir="${ARCHIVE_PARTIAL}/.elf-validation"
mkdir "${elf_validation_dir}"
aab_entries="${elf_validation_dir}/entries.txt"
unzip -Z1 "${AAB}" > "${aab_entries}"

unzip -Z1 "${NATIVE_SYMBOLS}" | LC_ALL=C sort > \
    "${ARCHIVE_PARTIAL}/native-debug-symbols-layout.txt"
native_symbol_count=0
while IFS= read -r symbol_entry; do
    [[ "${symbol_entry}" == */ ]] && continue
    [[ "${symbol_entry}" =~ ^arm64-v8a/[^/]+\.so\.sym$ ]] || \
        fail "native debug-symbol archive contains a stale or non-arm64 entry"
    symbol_runtime="${symbol_entry#arm64-v8a/}"
    symbol_runtime="${symbol_runtime%.sym}"
    symbol_runtime_count="$(awk -v expected="base/lib/arm64-v8a/${symbol_runtime}" \
        '$0 == expected {count++} END {print count + 0}' "${aab_entries}")"
    [[ "${symbol_runtime_count}" -eq 1 ]] || \
        fail "native debug-symbol archive does not correspond to the AAB"
    native_symbol_count=$((native_symbol_count + 1))
done < "${ARCHIVE_PARTIAL}/native-debug-symbols-layout.txt"
[[ "${native_symbol_count}" -gt 0 ]] || fail "native debug-symbol archive is empty"

expected_runtime_names="${elf_validation_dir}/expected-runtime-names.txt"
{
    for staged_runtime in "${required_staged_host_natives[@]}"; do
        basename "${staged_runtime}"
    done
    printf '%s\n' \
        libandroidx.graphics.path.so \
        libimage_processing_util_jni.so \
        libsurface_util_jni.so
} | LC_ALL=C sort -u > "${expected_runtime_names}"
while IFS= read -r runtime_name; do
    runtime_count="$(awk -v expected="base/lib/arm64-v8a/${runtime_name}" \
        '$0 == expected {count++} END {print count + 0}' "${aab_entries}")"
    [[ "${runtime_count}" -eq 1 ]] || fail "AAB is missing a required SDK native runtime"
done < "${expected_runtime_names}"

expected_aab_skels=(
    base/assets/runanywhere/qhexrt/skels/arm64-v8a/libQnnHtpV75Skel.so
    base/assets/runanywhere/qhexrt/skels/arm64-v8a/libQnnHtpV79Skel.so
    base/assets/runanywhere/qhexrt/skels/arm64-v8a/libQnnHtpV81Skel.so
)
awk '/libQnnHtpV[0-9]+Skel\.so$/ {print}' "${aab_entries}" | \
    LC_ALL=C sort > "${ARCHIVE_PARTIAL}/qhexrt-skel-layout.txt"
aab_skel_count="$(awk 'END {print NR + 0}' "${ARCHIVE_PARTIAL}/qhexrt-skel-layout.txt")"
[[ "${aab_skel_count}" -eq 3 ]] || fail "AAB must contain exactly the V75/V79/V81 DSP skels"
for expected_skel in "${expected_aab_skels[@]}"; do
    expected_count="$(awk -v expected="${expected_skel}" '$0 == expected {count++} END {print count + 0}' "${aab_entries}")"
    [[ "${expected_count}" -eq 1 ]] || fail "AAB is missing an exact QHexRT DSP skel asset"
done
lib_skel_count="$(awk '/^base\/lib\/.*Skel\.so$/ {count++} END {print count + 0}' "${aab_entries}")"
[[ "${lib_skel_count}" -eq 0 ]] || fail "AAB packages a DSP skel as an Android JNI library"
other_native_abi_count="$(awk '
    /^base\/lib\// && $0 !~ /^base\/lib\/arm64-v8a\// {count++}
    END {print count + 0}
' "${aab_entries}")"
[[ "${other_native_abi_count}" -eq 0 ]] || fail "AAB contains a native ABI other than arm64-v8a"

aab_elf_entries="${elf_validation_dir}/arm64-elf-entries.txt"
awk '/^base\/lib\/arm64-v8a\/[^\/]+\.so$/ {print}' "${aab_entries}" | \
    LC_ALL=C sort > "${aab_elf_entries}"
aab_elf_names="${elf_validation_dir}/arm64-elf-names.txt"
awk -F/ '{print $NF}' "${aab_elf_entries}" | LC_ALL=C sort > "${aab_elf_names}"
diff -u "${expected_runtime_names}" "${aab_elf_names}" >/dev/null || \
    fail "AAB arm64 native-library set differs from the reviewed release allowlist"
arm64_elf_count="$(awk 'END {print NR + 0}' "${aab_elf_entries}")"
[[ "${arm64_elf_count}" -gt 0 ]] || fail "AAB contains no arm64-v8a native libraries"
: > "${ARCHIVE_PARTIAL}/native-elf-load-alignment.txt"
elf_index=0
overall_min_alignment_dec=0
while IFS= read -r elf_entry; do
    elf_index=$((elf_index + 1))
    extracted_elf="${elf_validation_dir}/${elf_index}-$(basename "${elf_entry}")"
    unzip -p "${AAB}" "${elf_entry}" > "${extracted_elf}"
    minimum_alignment="$(minimum_elf_load_alignment "${extracted_elf}")" || \
        fail "AAB contains an arm64 ELF with LOAD alignment below 0x4000"
    minimum_alignment_dec=$((minimum_alignment))
    if [[ "${overall_min_alignment_dec}" -eq 0 || \
          "${minimum_alignment_dec}" -lt "${overall_min_alignment_dec}" ]]; then
        overall_min_alignment_dec="${minimum_alignment_dec}"
    fi
    printf '%s\t%s\n' "${elf_entry}" "${minimum_alignment}" >> \
        "${ARCHIVE_PARTIAL}/native-elf-load-alignment.txt"
done < "${aab_elf_entries}"
[[ "${elf_index}" -eq "${arm64_elf_count}" ]] || fail "AAB ELF validation count changed unexpectedly"
overall_min_alignment="$(printf '0x%x' "${overall_min_alignment_dec}")"
rm -rf "${elf_validation_dir}"

jq -e '
    .optimizations.uncompressNativeLibraries.enabled == true and
    .optimizations.uncompressNativeLibraries.alignment == "PAGE_ALIGNMENT_16K"
' "${ARCHIVE_PARTIAL}/bundletool-config.json" >/dev/null || \
    fail "bundletool config does not require 16 KB native-library page alignment"

aab_sha256="$(shasum -a 256 "${AAB}" | awk '{print $1}')"
if stat -f '%z' "${AAB}" >/dev/null 2>&1; then
    aab_bytes="$(stat -f '%z' "${AAB}")"
else
    aab_bytes="$(stat -c '%s' "${AAB}")"
fi
bundletool_version="$(jq -r '.bundletool.version // empty' "${ARCHIVE_PARTIAL}/bundletool-config.json")"
[[ "${bundletool_version}" == "${BUNDLETOOL_VERSION}" ]] || \
    fail "AAB records an unexpected bundletool version"
sdk_git_commit="$(git -C "${REPO_ROOT}" rev-parse HEAD)"
if [[ -n "$(git -C "${REPO_ROOT}" status --porcelain --untracked-files=all)" ]]; then
    sdk_git_dirty=true
else
    sdk_git_dirty=false
fi
qhexrt_git_commit="$(git -C "${QHEXRT_SOURCE_DIR}" rev-parse HEAD)"
if [[ -n "$(git -C "${QHEXRT_SOURCE_DIR}" status --porcelain --untracked-files=all)" ]]; then
    qhexrt_git_dirty=true
else
    qhexrt_git_dirty=false
fi
if [[ "${ALLOW_DIRTY}" -eq 0 && \
      ( "${sdk_git_dirty}" == true || "${qhexrt_git_dirty}" == true ) ]]; then
    fail "source worktree changed during the release build"
fi
if [[ "${SKIP_NATIVE_REBUILD}" -eq 0 ]]; then
    native_rebuilt=true
else
    native_rebuilt=false
fi
built_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

jq -n \
    --arg applicationId "${application_id}" \
    --arg versionName "${version_name}" \
    --argjson versionCode "${version_code}" \
    --argjson minSdk "${min_sdk}" \
    --argjson targetSdk "${target_sdk}" \
    --arg aabFile "${archive_aab}" \
    --arg aabSha256 "${aab_sha256}" \
    --argjson aabBytes "${aab_bytes}" \
    --arg uploadCertSha256 "${actual_cert_sha256}" \
    --arg sdkVersion "${expected_sdk_version}" \
    --arg bundletoolVersion "${bundletool_version}" \
    --argjson signedPayloadEntryCount "${signed_payload_entry_count}" \
    --argjson arm64ElfCount "${arm64_elf_count}" \
    --arg minimumElfLoadAlignment "${overall_min_alignment}" \
    --arg qairtVersion "${qairt_version}" \
    --arg qairtBuildId "${qairt_build_id}" \
    --arg androidNdkRevision "${android_ndk_revision}" \
    --arg sdkGitCommit "${sdk_git_commit}" \
    --argjson sdkGitDirty "${sdk_git_dirty}" \
    --arg qhexrtGitCommit "${qhexrt_git_commit}" \
    --argjson qhexrtGitDirty "${qhexrt_git_dirty}" \
    --argjson nativeRebuilt "${native_rebuilt}" \
    --arg builtAt "${built_at}" \
    '{
        schemaVersion: 1,
        applicationId: $applicationId,
        versionName: $versionName,
        versionCode: $versionCode,
        minSdk: $minSdk,
        targetSdk: $targetSdk,
        artifact: {
            file: $aabFile,
            bytes: $aabBytes,
            sha256: $aabSha256
        },
        uploadCertificateSha256: $uploadCertSha256,
        sdkVersion: $sdkVersion,
        signedPayloadEntryCount: $signedPayloadEntryCount,
        nativeLibraryPageAlignment: "PAGE_ALIGNMENT_16K",
        arm64ElfCount: $arm64ElfCount,
        minimumElfLoadAlignment: $minimumElfLoadAlignment,
        bundletoolVersion: $bundletoolVersion,
        qairt: {
            version: $qairtVersion,
            buildId: $qairtBuildId
        },
        androidNdkRevision: $androidNdkRevision,
        source: {
            sdk: {
                gitCommit: $sdkGitCommit,
                dirty: $sdkGitDirty
            },
            qhexrt: {
                gitCommit: $qhexrtGitCommit,
                dirty: $qhexrtGitDirty
            },
            nativeRebuilt: $nativeRebuilt
        },
        builtAt: $builtAt
    }' > "${ARCHIVE_PARTIAL}/release-metadata.json"
printf '%s\n' "${actual_cert_sha256}" > "${ARCHIVE_PARTIAL}/upload-certificate-sha256.txt"

(
    cd "${ARCHIVE_PARTIAL}"
    find . -type f ! -name SHA256SUMS -print | LC_ALL=C sort | while IFS= read -r file; do
        shasum -a 256 "${file}"
    done > SHA256SUMS
)
chmod -R go-rwx "${ARCHIVE_PARTIAL}"
mv "${ARCHIVE_PARTIAL}" "${ARCHIVE_DIR}"
ARCHIVE_PARTIAL=""

if [[ "${sdk_git_dirty}" == true || "${qhexrt_git_dirty}" == true ]]; then
    echo "==> Development archive ready (dirty-source override; not Play-ready)"
else
    echo "==> Play release archive ready"
fi
echo "Archive: ${ARCHIVE_DIR}"
echo "Application: ${application_id} ${version_name} (${version_code})"
echo "AAB SHA-256: ${aab_sha256}"
echo "Upload certificate SHA-256: ${actual_cert_sha256}"
echo "Bundle native alignment: PAGE_ALIGNMENT_16K"
