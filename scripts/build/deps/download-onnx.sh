#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../lib/common.sh"

usage() {
    cat <<'EOF'
Usage: scripts/build/deps/download-onnx.sh <ios|macos>

Downloads the prebuilt ONNX Runtime for the given platform into
sdk/runanywhere-commons/third_party/:
  ios     pod-archive xcframework from onnxruntime.ai → onnxruntime-ios/
  macos   universal2 (arm64 + x86_64) tgz from GitHub  → onnxruntime-macos/

Versions come from sdk/runanywhere-commons/VERSIONS
(ONNX_VERSION_IOS / ONNX_VERSION_MACOS).
EOF
}

PLATFORM="${1:-}"
case "${PLATFORM}" in
    ios|macos) ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "expected platform argument: ios or macos" ;;
esac

COMMONS_ROOT="${RAC_ROOT}/sdk/runanywhere-commons"
source "${RAC_ROOT}/scripts/lib/load-versions.sh"
require_cmd curl

download_ios() {
    local onnx_dir="${COMMONS_ROOT}/third_party/onnxruntime-ios"
    [ -n "${ONNX_VERSION_IOS:-}" ] || die "ONNX_VERSION_IOS not loaded from VERSIONS file"
    local version="${ONNX_VERSION_IOS}"
    local url="https://download.onnxruntime.ai/pod-archive-onnxruntime-c-${version}.zip"

    info "Downloading ONNX Runtime iOS xcframework v${version}..."

    local temp_dir temp_zip
    temp_dir=$(mktemp -d)
    temp_zip="${temp_dir}/onnxruntime.zip"

    info "Downloading from ${url}..."
    curl -L --progress-bar -o "${temp_zip}" "${url}"

    [ -f "${temp_zip}" ] || die "Download failed"

    log "Download complete. Size: $(du -h "${temp_zip}" | cut -f1)"

    info "Extracting xcframework..."
    rm -rf "${onnx_dir}"
    mkdir -p "${onnx_dir}"

    unzip -q "${temp_zip}" -d "${temp_dir}/extracted"

    local xcframework
    xcframework=$(find "${temp_dir}/extracted" -name "onnxruntime.xcframework" -type d | head -1)
    if [ -z "${xcframework}" ]; then
        error "onnxruntime.xcframework not found in archive"
        ls -R "${temp_dir}/extracted"
        exit 1
    fi

    cp -R "${xcframework}" "${onnx_dir}/"

    if [ -d "${temp_dir}/extracted/Headers" ]; then
        cp -R "${temp_dir}/extracted/Headers" "${onnx_dir}/"
    fi

    rm -rf "${temp_dir}"

    ok "ONNX Runtime xcframework downloaded to ${onnx_dir}/onnxruntime.xcframework"
    log "Contents:"
    ls -lh "${onnx_dir}/onnxruntime.xcframework"
}

download_macos() {
    local onnx_dir="${COMMONS_ROOT}/third_party/onnxruntime-macos"
    [ -n "${ONNX_VERSION_MACOS:-}" ] || die "ONNX_VERSION_MACOS not loaded from VERSIONS file"
    local version="${ONNX_VERSION_MACOS}"
    local url="https://github.com/microsoft/onnxruntime/releases/download/v${version}/onnxruntime-osx-universal2-${version}.tgz"

    info "ONNX Runtime macOS downloader (v${version})"

    if [ -d "${onnx_dir}/lib" ] && [ -f "${onnx_dir}/lib/libonnxruntime.dylib" ]; then
        ok "ONNX Runtime macOS already exists at ${onnx_dir}"
        log "   To force re-download, remove: rm -rf ${onnx_dir}"
        return 0
    fi

    local temp_dir temp_file
    temp_dir=$(mktemp -d)
    temp_file="${temp_dir}/onnxruntime.tgz"

    info "Downloading from ${url}..."
    curl -L --progress-bar -o "${temp_file}" "${url}"

    if [ ! -f "${temp_file}" ] || [ ! -s "${temp_file}" ]; then
        rm -rf "${temp_dir}"
        die "Download failed"
    fi

    log "Download complete. Size: $(du -h "${temp_file}" | cut -f1)"

    info "Extracting..."
    mkdir -p "${onnx_dir}"
    tar -xzf "${temp_file}" -C "${temp_dir}"

    local extracted_dir
    extracted_dir=$(find "${temp_dir}" -maxdepth 1 -type d -name "onnxruntime-*" | head -1)
    if [ -z "${extracted_dir}" ]; then
        rm -rf "${temp_dir}"
        die "Could not find extracted ONNX Runtime directory"
    fi

    cp -R "${extracted_dir}/lib" "${onnx_dir}/"
    cp -R "${extracted_dir}/include" "${onnx_dir}/"

    rm -rf "${temp_dir}"

    ok "ONNX Runtime macOS v${version} installed to ${onnx_dir}"
    log "Contents:"
    ls -lh "${onnx_dir}/lib/"
}

case "${PLATFORM}" in
    ios)   download_ios ;;
    macos) download_macos ;;
esac
