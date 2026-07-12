#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Canonical Android release build and packaging entry point.
#
# Builds the supplied ABI through scripts/build/build-core-android.sh, then
# stages the resulting `.so` libraries (commons + llamacpp + onnx) for
#      that ABI into the versioned release archive
#      `sdk/runanywhere-commons/dist/RACommons-android-<abi>-v<version>.zip`
#      (+ .sha256) that release.yml uploads and `publish` asserts on.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMONS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${COMMONS_ROOT}/../.." && pwd)"
SUPPORTED_ABIS=(arm64-v8a armeabi-v7a x86_64)
CORE_LIBS=(
    libc++_shared.so
    libomp.so
    librac_backend_cloud.so
    librac_commons.so
    librunanywhere_jni.so
)
LLAMACPP_LIBS=(
    libc++_shared.so
    librac_backend_llamacpp.so
    librac_backend_llamacpp_jni.so
    librunanywhere_llamacpp.so
)
ONNX_LIBS=(
    libc++_shared.so
    libonnxruntime.so
    librac_backend_onnx.so
    librac_backend_onnx_jni.so
    librac_backend_sherpa.so
    librunanywhere_onnx.so
    librunanywhere_sherpa.so
    libsherpa-onnx-c-api.so
    libsherpa-onnx-jni.so
)

fail() {
    echo "error: $*" >&2
    exit 1
}

contains_value() {
    local candidate="$1"
    shift
    local value
    for value in "$@"; do
        [ "$candidate" != "$value" ] || return 0
    done
    return 1
}

validate_release_version() {
    local version="$1"
    [[ "$version" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || \
        fail "invalid Android release version: $version"
}

reject_private_path() {
    local path="$1"
    local lowered
    lowered="$(printf '%s' "$path" | tr '[:upper:]' '[:lower:]')"
    case "$lowered" in
        *qhexrt*|*qnn*) fail "private QHexRT/QNN input is not publishable: $path" ;;
    esac
}

validate_component_source() {
    local component="$1"
    local source_dir="$2"
    shift 2
    [ -d "$source_dir" ] && [ ! -L "$source_dir" ] || \
        fail "missing or unsafe $component native directory: $source_dir"

    local entry library magic expected actual
    while IFS= read -r -d '' entry; do
        library="$(basename "$entry")"
        reject_private_path "$library"
        [ -f "$entry" ] && [ ! -L "$entry" ] || \
            fail "$component contains a non-regular or nested input: $entry"
        contains_value "$library" "$@" || \
            fail "$component contains an undeclared native input: $entry"
        [ -s "$entry" ] || fail "$component contains an empty native input: $entry"
        magic="$(dd if="$entry" bs=4 count=1 2>/dev/null | od -An -tx1 | tr -d '[:space:]')"
        [ "$magic" = "7f454c46" ] || fail "$component input is not ELF: $entry"
    done < <(find "$source_dir" -mindepth 1 -maxdepth 1 -print0)

    expected="$(printf '%s\n' "$@" | LC_ALL=C sort)"
    actual="$(find "$source_dir" -mindepth 1 -maxdepth 1 -type f -exec basename {} \; | LC_ALL=C sort)"
    if [ "$actual" != "$expected" ]; then
        echo "Expected $component native inputs:" >&2
        printf '  %s\n' "$@" >&2
        echo "Actual $component native inputs:" >&2
        printf '%s\n' "$actual" | sed 's/^/  /' >&2
        fail "$component native inventory mismatch"
    fi
}

stage_component() {
    local source_dir="$1"
    local destination_dir="$2"
    shift 2
    local library
    mkdir -p "$destination_dir"
    for library in "$@"; do
        cp -f "$source_dir/$library" "$destination_dir/$library"
    done
}

validate_staging_root() {
    local staging="$1"
    local expected_entries actual_entries component
    [ -d "$staging" ] && [ ! -L "$staging" ] || fail "missing or unsafe staging root: $staging"
    expected_entries="$(printf '%s\n' jni llamacpp onnx | LC_ALL=C sort)"
    actual_entries="$(find "$staging" -mindepth 1 -maxdepth 1 -exec basename {} \; | LC_ALL=C sort)"
    [ "$actual_entries" = "$expected_entries" ] || fail \
        "staging must contain exactly {jni,llamacpp,onnx}: $staging"
    for component in jni llamacpp onnx; do
        [ -d "$staging/$component" ] && [ ! -L "$staging/$component" ] || \
            fail "staging component is not a real directory: $staging/$component"
    done

    validate_component_source "jni" "$staging/jni" "${CORE_LIBS[@]}"
    validate_component_source "llamacpp" "$staging/llamacpp" "${LLAMACPP_LIBS[@]}"
    validate_component_source "onnx" "$staging/onnx" "${ONNX_LIBS[@]}"
}

validate_archive() {
    local archive="$1"
    local staging_parent="$2"
    local abi="$3"
    local entry normalized expected actual duplicates
    [ -s "$archive" ] || fail "missing Android archive: $archive"

    actual=""
    while IFS= read -r entry; do
        case "$entry" in
            /*|*\\*|../*|*/../*|*/..) fail "unsafe archive entry in $archive: $entry" ;;
        esac
        reject_private_path "$entry"
        normalized="${entry%/}"
        actual="${actual}${actual:+$'\n'}${normalized}"
    done < <(unzip -Z1 "$archive")
    expected="$(cd "$staging_parent" && LC_ALL=C find "$abi" -print | LC_ALL=C sort)"
    actual="$(printf '%s\n' "$actual" | LC_ALL=C sort)"
    duplicates="$(printf '%s\n' "$actual" | LC_ALL=C sort | uniq -d)"
    [ -z "$duplicates" ] || fail "duplicate Android archive entries: $duplicates"
    [ "$actual" = "$expected" ] || fail "Android archive inventory differs from canonical staging"
}

create_deterministic_archive() {
    local staging_parent="$1"
    local abi="$2"
    local archive="$3"
    local staging="$staging_parent/$abi"
    validate_staging_root "$staging"
    mkdir -p "$(dirname "$archive")"
    archive="$(cd "$(dirname "$archive")" && pwd)/$(basename "$archive")"

    find "$staging" -type d -exec chmod 0755 {} +
    find "$staging" -type f -exec chmod 0755 {} +
    find "$staging" -exec touch -h -t 198001010000 {} +
    rm -f "$archive"
    (
        cd "$staging_parent"
        LC_ALL=C find "$abi" -print \
            | LC_ALL=C sort \
            | zip -qX "$archive" -@
    )
    validate_archive "$archive" "$staging_parent" "$abi"
}

write_checksum() {
    local archive="$1"
    local directory name
    directory="$(cd "$(dirname "$archive")" && pwd)"
    name="$(basename "$archive")"
    if command -v shasum >/dev/null 2>&1; then
        (cd "$directory" && shasum -a 256 "$name" > "$name.sha256")
    elif command -v sha256sum >/dev/null 2>&1; then
        (cd "$directory" && sha256sum "$name" > "$name.sha256")
    else
        fail "neither shasum nor sha256sum is available"
    fi
}

main() {
    if [ "$#" -ne 1 ]; then
        echo "usage: build-android.sh <abi>" >&2
        echo "       <abi> ∈ {arm64-v8a, armeabi-v7a, x86_64}" >&2
        exit 2
    fi
    local abi="$1"

    contains_value "$abi" "${SUPPORTED_ABIS[@]}" || \
        fail "unsupported ABI '$abi' (expected arm64-v8a, armeabi-v7a, or x86_64)"

    local core_script="${REPO_ROOT}/scripts/build/build-core-android.sh"
    [ -x "$core_script" ] || fail "$core_script not found or not executable"

    echo "▶ Delegating Android build to scripts/build/build-core-android.sh ${abi}"
    "$core_script" "$abi"

    # Stage the produced .so libraries (commons + llamacpp + onnx backends) for
    # this ABI into a single per-ABI release zip + checksum under dist/. Sources
    # are the Android-library src/main/jniLibs trees populated by the core build.
    # shellcheck source=load-versions.sh
    source "${SCRIPT_DIR}/load-versions.sh" >/dev/null
    local version="${RAC_RELEASE_VERSION:-${PROJECT_VERSION}}"
    validate_release_version "$version"

    local kotlin_base="${REPO_ROOT}/sdk/runanywhere-kotlin"
    local dist="${COMMONS_ROOT}/dist"
    local staging_parent="${dist}/android-staging"
    local staging="${staging_parent}/${abi}"
    local core_source="${kotlin_base}/src/main/jniLibs/${abi}"
    local llamacpp_source="${kotlin_base}/modules/runanywhere-core-llamacpp/src/main/jniLibs/${abi}"
    local onnx_source="${kotlin_base}/modules/runanywhere-core-onnx/src/main/jniLibs/${abi}"

    # Fail before mutating release staging when any source is missing, private,
    # nested, symlinked, non-ELF, or outside the exact public allowlist.
    validate_component_source "jni" "$core_source" "${CORE_LIBS[@]}"
    validate_component_source "llamacpp" "$llamacpp_source" "${LLAMACPP_LIBS[@]}"
    validate_component_source "onnx" "$onnx_source" "${ONNX_LIBS[@]}"

    rm -rf "$staging"
    mkdir -p "$staging"
    stage_component "$core_source" "$staging/jni" "${CORE_LIBS[@]}"
    stage_component "$llamacpp_source" "$staging/llamacpp" "${LLAMACPP_LIBS[@]}"
    stage_component "$onnx_source" "$staging/onnx" "${ONNX_LIBS[@]}"
    validate_staging_root "$staging"

    local zip_name="RACommons-android-${abi}-v${version}.zip"
    local archive="${dist}/${zip_name}"
    rm -f "$archive" "$archive.sha256"
    create_deterministic_archive "$staging_parent" "$abi" "$archive"
    write_checksum "$archive"

    echo "✓ build-android.sh complete; staged ABI '${abi}' → ${archive}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
