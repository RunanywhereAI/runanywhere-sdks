#!/bin/bash
# =============================================================================
# download-sherpa-onnx.sh
# Download Sherpa-ONNX Android native libraries
#
# Sherpa-ONNX provides pre-built Android AAR/native libraries.
# This script downloads them for STT, TTS, and VAD support.
#
# 16KB Page Size Alignment (Google Play requirement)
# --------------------------------------------------
# Starting November 1, 2025, Google Play requires all apps targeting
# Android 15+ (API 35+) to have 16KB-aligned native libraries.
#
# ✅ Sherpa-ONNX v1.12.20+ pre-built binaries ARE 16KB aligned!
#    (Fixed in https://github.com/k2-fsa/sherpa-onnx/pull/2520)
#
# Usage:
#   ./download-sherpa-onnx.sh              # Download pre-built (16KB aligned)
#   ./download-sherpa-onnx.sh --check      # Verify library alignment
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SHERPA_DIR="${RAC_SHERPA_DIR:-${ROOT_DIR}/third_party/sherpa-onnx-android}"

# shellcheck source-path=SCRIPTDIR
# shellcheck source=../load-versions.sh
source "${SCRIPT_DIR}/../load-versions.sh"

SHERPA_VERSION="${SHERPA_ONNX_VERSION_ANDROID:-}"
SHERPA_ONNX_REPO="${SHERPA_ONNX_REPO_ANDROID:-}"
DOWNLOAD_URL="${RAC_SHERPA_DOWNLOAD_URL:-https://github.com/${SHERPA_ONNX_REPO}/releases/download/v${SHERPA_VERSION}/sherpa-onnx-v${SHERPA_VERSION}-android.tar.bz2}"
CACHE_IDENTITY_FILE="${SHERPA_DIR}/.sherpa-android-provenance"
HEADER_IDENTITY_FILE="${SHERPA_DIR}/include/.header-provenance"
SHERPA_EMBEDDED_BUILD_ROOT="/home/home/Projects/sherpa-onnx"
SHERPA_SANITIZED_BUILD_ROOT="/runanywhere/third-party/sherpa"
SHERPA_TRANSFORM_MANIFEST="${SCRIPT_DIR}/sherpa-onnx-android-path-sanitization-v1.13.2.txt"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TEMP_DIR=""

cleanup() {
    if [ -n "${TEMP_DIR}" ] && [ -d "${TEMP_DIR}" ]; then
        rm -rf "${TEMP_DIR}"
    fi
}

fail() {
    printf '%bERROR: %s%b\n' "${RED}" "$*" "${NC}" >&2
    return 1
}

require_configuration() {
    local variable
    for variable in \
        ONNX_VERSION_ANDROID \
        ONNX_COMMIT_ANDROID \
        NDK_VERSION \
        SHERPA_ONNX_VERSION_ANDROID \
        SHERPA_ONNX_REPO_ANDROID \
        SHERPA_ONNX_COMMIT_ANDROID \
        SHERPA_ONNX_ANDROID_SHA256 \
        SHERPA_ONNX_UPSTREAM_COMMIT_ANDROID \
        SHERPA_ONNX_PATCH_SHA256_ANDROID \
        SHERPA_ONNX_HEADER_REPO_ANDROID \
        SHERPA_ONNX_HEADER_COMMIT_ANDROID; do
        if [ -z "${!variable:-}" ]; then
            fail "${variable} was not loaded from VERSIONS"
            return 1
        fi
    done

    if [[ ! "${SHERPA_ONNX_ANDROID_SHA256}" =~ ^[0-9a-fA-F]{64}$ ]]; then
        fail "SHERPA_ONNX_ANDROID_SHA256 must contain exactly 64 hexadecimal characters"
        return 1
    fi
}

print_cache_identity() {
    printf '%s\n' \
        "repo=${SHERPA_ONNX_REPO_ANDROID}" \
        "version=${SHERPA_ONNX_VERSION_ANDROID}" \
        "source_commit=${SHERPA_ONNX_COMMIT_ANDROID}" \
        "archive_sha256=${SHERPA_ONNX_ANDROID_SHA256}" \
        "upstream_commit=${SHERPA_ONNX_UPSTREAM_COMMIT_ANDROID}" \
        "patch_sha256=${SHERPA_ONNX_PATCH_SHA256_ANDROID}" \
        "header_repo=${SHERPA_ONNX_HEADER_REPO_ANDROID}" \
        "header_commit=${SHERPA_ONNX_HEADER_COMMIT_ANDROID}" \
        "onnxruntime_version=${ONNX_VERSION_ANDROID}" \
        "onnxruntime_commit=${ONNX_COMMIT_ANDROID}" \
        "embedded_path_rewrite=${SHERPA_EMBEDDED_BUILD_ROOT}=>${SHERPA_SANITIZED_BUILD_ROOT}" \
        "transform_manifest_sha256=$(sha256_file "${SHERPA_TRANSFORM_MANIFEST}")"
}

print_header_identity() {
    printf '%s\n' \
        "sherpa_repo=${SHERPA_ONNX_HEADER_REPO_ANDROID}" \
        "sherpa_commit=${SHERPA_ONNX_HEADER_COMMIT_ANDROID}" \
        "onnxruntime_version=${ONNX_VERSION_ANDROID}" \
        "onnxruntime_commit=${ONNX_COMMIT_ANDROID}"
}

write_identity_file() {
    local output="$1"
    local producer="$2"
    local temporary="${output}.tmp.$$"
    mkdir -p "$(dirname "${output}")"
    "${producer}" > "${temporary}"
    mv "${temporary}" "${output}"
}

cache_identity_matches() {
    [ -f "${CACHE_IDENTITY_FILE}" ] && cmp -s <(print_cache_identity) "${CACHE_IDENTITY_FILE}"
}

headers_are_current() {
    [ -f "${SHERPA_DIR}/include/sherpa-onnx/c-api/c-api.h" ] &&
        [ -f "${SHERPA_DIR}/include/sherpa-onnx/c-api/cxx-api.h" ] &&
        [ -f "${SHERPA_DIR}/include/onnxruntime_c_api.h" ] &&
        [ -f "${SHERPA_DIR}/include/onnxruntime_cxx_api.h" ] &&
        [ -f "${SHERPA_DIR}/include/onnxruntime_ep_c_api.h" ] &&
        [ -f "${HEADER_IDENTITY_FILE}" ] &&
        cmp -s <(print_header_identity) "${HEADER_IDENTITY_FILE}"
}

sha256_file() {
    local file="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "${file}" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "${file}" | awk '{print $1}'
    else
        fail "Neither sha256sum nor shasum is available"
        return 1
    fi
}

verify_sha256() {
    local expected="$1"
    local file="$2"
    local actual
    expected="$(printf '%s' "${expected}" | tr '[:upper:]' '[:lower:]')"
    actual="$(sha256_file "${file}")"
    actual="$(printf '%s' "${actual}" | tr '[:upper:]' '[:lower:]')"
    if [ "${actual}" != "${expected}" ]; then
        fail "SHA-256 mismatch for ${file}: expected ${expected}, got ${actual}"
        return 1
    fi
    printf 'Verified SHA-256: %s\n' "${actual}"
}

download_file() {
    local url="$1"
    local output="$2"
    if ! curl --fail --location --silent --show-error \
        --retry 3 --retry-delay 2 --connect-timeout 15 \
        --output "${output}" "${url}"; then
        rm -f "${output}"
        fail "Failed to download ${url}"
        return 1
    fi
}

extract_archive_safely() {
    local archive="$1"
    local destination="$2"

    python3 - "${archive}" "${destination}" <<'PY'
import pathlib
import sys
import tarfile

archive_path = pathlib.Path(sys.argv[1])
destination = pathlib.Path(sys.argv[2]).resolve()
destination.mkdir(parents=True, exist_ok=True)

with tarfile.open(archive_path, mode="r:bz2") as archive:
    members = archive.getmembers()
    if not members:
        raise SystemExit("archive is empty")

    for member in members:
        name = member.name
        member_path = pathlib.PurePosixPath(name)
        if not name or "\\" in name or member_path.is_absolute():
            raise SystemExit(f"unsafe archive member path: {name!r}")
        if ".." in member_path.parts:
            raise SystemExit(f"archive member escapes destination: {name!r}")
        if not (member.isfile() or member.isdir()):
            raise SystemExit(f"unsupported archive member type: {name!r}")

        target = (destination / pathlib.Path(*member_path.parts)).resolve()
        try:
            target.relative_to(destination)
        except ValueError as error:
            raise SystemExit(f"archive member escapes destination: {name!r}") from error

    archive.extractall(destination, members=members)
PY
}

find_readelf() {
    local candidate
    local ndk_root

    if [ -n "${RAC_SHERPA_READELF:-}" ]; then
        if [ -x "${RAC_SHERPA_READELF}" ]; then
            printf '%s\n' "${RAC_SHERPA_READELF}"
            return 0
        fi
        if command -v "${RAC_SHERPA_READELF}" >/dev/null 2>&1; then
            command -v "${RAC_SHERPA_READELF}"
            return 0
        fi
        fail "RAC_SHERPA_READELF is not executable: ${RAC_SHERPA_READELF}"
        return 1
    fi

    if command -v llvm-readelf >/dev/null 2>&1; then
        command -v llvm-readelf
        return 0
    fi
    if command -v readelf >/dev/null 2>&1; then
        command -v readelf
        return 0
    fi

    for ndk_root in \
        "${ANDROID_NDK_HOME:-}" \
        "${ANDROID_NDK:-}" \
        "${HOME}/Library/Android/sdk/ndk/${NDK_VERSION}" \
        "${ANDROID_HOME:-}/ndk/${NDK_VERSION}"; do
        [ -n "${ndk_root}" ] || continue
        for candidate in "${ndk_root}"/toolchains/llvm/prebuilt/*/bin/llvm-readelf; do
            if [ -x "${candidate}" ]; then
                printf '%s\n' "${candidate}"
                return 0
            fi
        done
    done

    fail "llvm-readelf/readelf was not found; install Android NDK ${NDK_VERSION}"
    return 1
}

validate_elf_16kb_alignment() {
    local so_file="$1"
    local readelf="$2"
    local headers
    local alignments
    local align_hex
    local align_dec
    local load_count=0
    local failed=0

    if ! headers="$("${readelf}" -W -l "${so_file}" 2>/dev/null)"; then
        printf 'ERROR: readelf could not inspect %s\n' "${so_file}" >&2
        return 1
    fi
    alignments="$(printf '%s\n' "${headers}" | awk '/^[[:space:]]*LOAD[[:space:]]/ {print $NF}')"

    while IFS= read -r align_hex; do
        [ -n "${align_hex}" ] || continue
        load_count=$((load_count + 1))
        if [[ ! "${align_hex}" =~ ^0x[0-9a-fA-F]+$ ]]; then
            printf 'ERROR: %s has malformed PT_LOAD alignment %s\n' \
                "${so_file}" "${align_hex}" >&2
            failed=1
            continue
        fi
        align_dec=$((align_hex))
        if [ "${align_dec}" -lt 16384 ]; then
            printf 'ERROR: %s has PT_LOAD alignment %s; expected >= 0x4000\n' \
                "${so_file}" "${align_hex}" >&2
            failed=1
        fi
    done <<< "${alignments}"

    if [ "${load_count}" -eq 0 ]; then
        printf 'ERROR: %s has no readable ELF PT_LOAD segments\n' "${so_file}" >&2
        failed=1
    fi
    return "${failed}"
}

sanitize_embedded_build_paths() {
    local jni_root="$1"
    local manifest="${2:-${SHERPA_TRANSFORM_MANIFEST}}"
    python3 - \
        "${jni_root}" \
        "${manifest}" \
        "${SHERPA_ONNX_VERSION_ANDROID}" \
        "${SHERPA_EMBEDDED_BUILD_ROOT}" \
        "${SHERPA_SANITIZED_BUILD_ROOT}" <<'PY'
import hashlib
from pathlib import Path
import sys

root = Path(sys.argv[1])
manifest_path = Path(sys.argv[2])
expected_version = sys.argv[3]
source = sys.argv[4].encode()
replacement = sys.argv[5].encode()
if len(source) != len(replacement):
    raise SystemExit("embedded build-path replacement must preserve binary offsets")

lines = [
    line.strip()
    for line in manifest_path.read_text(encoding="utf-8").splitlines()
    if line.strip() and not line.lstrip().startswith("#")
]
if not lines or lines[0] != f"version={expected_version}":
    raise SystemExit("path-sanitization manifest version does not match VERSIONS")

expected = {}
for line in lines[1:]:
    path, raw_digest, count_text, transformed_digest = line.split()
    expected[path] = (raw_digest, int(count_text), transformed_digest)
actual_paths = {
    library.relative_to(root).as_posix() for library in root.rglob("*.so")
}
if actual_paths != set(expected):
    raise SystemExit(
        "path-sanitization manifest inventory mismatch: "
        f"missing={sorted(set(expected) - actual_paths)} "
        f"extra={sorted(actual_paths - set(expected))}"
    )

total = 0
for relative_path, (raw_digest, expected_count, transformed_digest) in sorted(expected.items()):
    library = root / relative_path
    payload = library.read_bytes()
    digest = hashlib.sha256(payload).hexdigest()
    if digest == transformed_digest:
        if payload.count(source) != 0 or payload.count(replacement) != expected_count:
            raise SystemExit(f"transformed path counts drifted in {relative_path}")
        total += expected_count
        continue
    if digest != raw_digest:
        raise SystemExit(f"raw or transformed SHA-256 mismatch for {relative_path}")
    if payload.count(source) != expected_count or payload.count(replacement) != 0:
        raise SystemExit(f"raw embedded path counts drifted in {relative_path}")
    transformed = payload.replace(source, replacement)
    if transformed.count(source) != 0 or transformed.count(replacement) != expected_count:
        raise SystemExit(f"embedded path replacement was incomplete in {relative_path}")
    if hashlib.sha256(transformed).hexdigest() != transformed_digest:
        raise SystemExit(f"transformed SHA-256 mismatch for {relative_path}")
    library.write_bytes(transformed)
    total += expected_count
print(f"Verified {len(expected)} transformed libraries and {total} exact path replacement(s).")
PY
}

validate_no_host_paths() {
    local jni_root="$1"
    python3 - "${jni_root}" <<'PY'
from pathlib import Path
import sys

markers = (b"/Users/", b"/home/", b"/var/folders/", b":\\\\Users\\\\")
failed = []
for library in sorted(Path(sys.argv[1]).rglob("*.so")):
    payload = library.read_bytes()
    if any(marker in payload for marker in markers):
        failed.append(str(library))
if failed:
    raise SystemExit("absolute host build path remains in: " + ", ".join(failed))
PY
}

validate_library_tree() {
    local jni_root="$1"
    local readelf
    local so_file
    local count=0
    local failed=0

    if ! readelf="$(find_readelf)"; then
        return 1
    fi
    while IFS= read -r -d '' so_file; do
        count=$((count + 1))
        if validate_elf_16kb_alignment "${so_file}" "${readelf}"; then
            printf '%bOK%b  %s\n' "${GREEN}" "${NC}" "${so_file#"${jni_root}"/}"
        else
            failed=1
        fi
    done < <(find "${jni_root}" -type f -name '*.so' -print0)

    if [ "${count}" -eq 0 ]; then
        fail "No shared libraries were found under ${jni_root}"
        return 1
    fi
    if [ "${failed}" -ne 0 ]; then
        fail "One or more Android libraries failed the strict 16 KiB ELF check"
        return 1
    fi
    if ! validate_no_host_paths "${jni_root}"; then
        fail "One or more Android libraries expose an absolute host build path"
        return 1
    fi
    printf 'Verified %d shared libraries: every PT_LOAD alignment is >= 0x4000.\n' "${count}"
}

download_headers() {
    local sherpa_base
    local onnx_base
    local include_dir="${SHERPA_DIR}/include"

    sherpa_base="https://raw.githubusercontent.com/${SHERPA_ONNX_HEADER_REPO_ANDROID}/${SHERPA_ONNX_HEADER_COMMIT_ANDROID}/sherpa-onnx/c-api"
    onnx_base="https://raw.githubusercontent.com/microsoft/onnxruntime/${ONNX_COMMIT_ANDROID}/include/onnxruntime/core/session"

    rm -rf "${include_dir}/sherpa-onnx"
    rm -f \
        "${include_dir}/onnxruntime_c_api.h" \
        "${include_dir}/onnxruntime_cxx_api.h" \
        "${include_dir}/onnxruntime_cxx_inline.h" \
        "${include_dir}/onnxruntime_float16.h" \
        "${include_dir}/onnxruntime_ep_c_api.h" \
        "${include_dir}/onnxruntime_ep_device_ep_metadata_keys.h" \
        "${HEADER_IDENTITY_FILE}" \
        "${include_dir}/.sherpa-header-version" \
        "${include_dir}/.onnx-header-version"
    mkdir -p "${include_dir}/sherpa-onnx/c-api"

    printf 'Downloading Sherpa-ONNX headers from %s@%s...\n' \
        "${SHERPA_ONNX_HEADER_REPO_ANDROID}" "${SHERPA_ONNX_HEADER_COMMIT_ANDROID}"
    download_file "${sherpa_base}/c-api.h" "${include_dir}/sherpa-onnx/c-api/c-api.h"
    download_file "${sherpa_base}/cxx-api.h" "${include_dir}/sherpa-onnx/c-api/cxx-api.h"

    printf 'Downloading ONNX Runtime %s headers from commit %s...\n' \
        "${ONNX_VERSION_ANDROID}" "${ONNX_COMMIT_ANDROID}"
    download_file "${onnx_base}/onnxruntime_c_api.h" "${include_dir}/onnxruntime_c_api.h"
    download_file "${onnx_base}/onnxruntime_cxx_api.h" "${include_dir}/onnxruntime_cxx_api.h"
    download_file "${onnx_base}/onnxruntime_cxx_inline.h" "${include_dir}/onnxruntime_cxx_inline.h"
    download_file "${onnx_base}/onnxruntime_float16.h" "${include_dir}/onnxruntime_float16.h"
    download_file "${onnx_base}/onnxruntime_ep_c_api.h" "${include_dir}/onnxruntime_ep_c_api.h"
    download_file "${onnx_base}/onnxruntime_ep_device_ep_metadata_keys.h" \
        "${include_dir}/onnxruntime_ep_device_ep_metadata_keys.h"

    write_identity_file "${HEADER_IDENTITY_FILE}" print_header_identity
}

ensure_headers() {
    if headers_are_current; then
        return 0
    fi
    printf '%bHeader cache is missing or stale; refreshing immutable headers.%b\n' \
        "${YELLOW}" "${NC}"
    download_headers
}

find_jni_source() {
    local extracted_root="$1"
    local candidate

    if [ -d "${extracted_root}/jniLibs" ]; then
        printf '%s\n' "${extracted_root}/jniLibs"
        return 0
    fi
    for candidate in \
        "${extracted_root}"/sherpa-onnx-*-android \
        "${extracted_root}"/build-android*; do
        if [ -d "${candidate}/jniLibs" ]; then
            printf '%s\n' "${candidate}/jniLibs"
            return 0
        fi
    done

    fail "The verified archive does not contain a jniLibs directory"
    return 1
}

print_usage() {
    printf 'Usage: %s [options]\n\n' "$0"
    printf 'Options:\n'
    printf '  --check   Verify cache identity and strict ELF alignment\n'
    printf '  --help    Show this help message\n'
}

run_check() {
    if [ ! -d "${SHERPA_DIR}/jniLibs" ]; then
        fail "No libraries found at ${SHERPA_DIR}/jniLibs"
        return 1
    fi
    if ! cache_identity_matches; then
        fail "Cached Sherpa-ONNX identity does not match the pinned VERSIONS contract"
        return 1
    fi
    if ! headers_are_current; then
        fail "Cached public headers do not match their immutable source commits"
        return 1
    fi
    validate_library_tree "${SHERPA_DIR}/jniLibs"
}

download_and_install() {
    local archive
    local extracted
    local jni_source

    TEMP_DIR="$(mktemp -d)"
    archive="${TEMP_DIR}/sherpa-onnx-android.tar.bz2"
    extracted="${TEMP_DIR}/extracted"

    printf 'Downloading %s...\n' "${DOWNLOAD_URL}"
    download_file "${DOWNLOAD_URL}" "${archive}"
    verify_sha256 "${SHERPA_ONNX_ANDROID_SHA256}" "${archive}"

    printf 'Validating and extracting archive members...\n'
    extract_archive_safely "${archive}" "${extracted}"
    if ! jni_source="$(find_jni_source "${extracted}")"; then
        return 1
    fi
    sanitize_embedded_build_paths "${jni_source}"
    validate_library_tree "${jni_source}"

    rm -rf "${SHERPA_DIR}"
    mkdir -p "${SHERPA_DIR}"
    cp -R "${jni_source}" "${SHERPA_DIR}/jniLibs"
    ensure_headers
    write_identity_file "${CACHE_IDENTITY_FILE}" print_cache_identity

    printf '%bSherpa-ONNX Android %s installed with verified provenance and alignment.%b\n' \
        "${GREEN}" "${SHERPA_VERSION}" "${NC}"
    printf 'Location: %s\n' "${SHERPA_DIR}"
}

main() {
    local check_only=false
    local arg

    trap cleanup EXIT
    require_configuration
    for arg in "$@"; do
        case "${arg}" in
            --check)
                check_only=true
                ;;
            --help|-h)
                print_usage
                return 0
                ;;
            *)
                print_usage >&2
                fail "Unknown option: ${arg}"
                return 1
                ;;
        esac
    done

    if [ "${check_only}" = true ]; then
        run_check
        return
    fi

    printf '%b=======================================%b\n' "${BLUE}" "${NC}"
    printf '%bSherpa-ONNX Android Downloader%b\n' "${BLUE}" "${NC}"
    printf '%b=======================================%b\n' "${BLUE}" "${NC}"
    printf 'Version: %s\nSource: %s@%s\n' \
        "${SHERPA_VERSION}" "${SHERPA_ONNX_REPO}" "${SHERPA_ONNX_COMMIT_ANDROID}"

    if [ -d "${SHERPA_DIR}/jniLibs" ] && cache_identity_matches; then
        if validate_library_tree "${SHERPA_DIR}/jniLibs"; then
            ensure_headers
            printf '%bVerified Sherpa-ONNX cache is already current.%b\n' "${GREEN}" "${NC}"
            return 0
        fi
        printf '%bCached libraries failed validation; replacing them.%b\n' "${YELLOW}" "${NC}"
    elif [ -e "${SHERPA_DIR}" ]; then
        printf '%bCached identity is missing or stale; replacing it.%b\n' "${YELLOW}" "${NC}"
    fi

    download_and_install
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
