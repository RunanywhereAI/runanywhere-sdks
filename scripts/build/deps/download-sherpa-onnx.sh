#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../lib/common.sh"

usage() {
    cat <<'EOF'
Usage: scripts/build/deps/download-sherpa-onnx.sh <android|ios|linux|macos> [options]

Fetches Sherpa-ONNX for the given platform into
sdk/runanywhere-commons/third_party/:
  android   prebuilt jniLibs + Sherpa/ORT headers → sherpa-onnx-android/
            (from the RunAnywhere fork; 16KB page-aligned, Play Store ready)
  ios       prebuilt xcframework from runanywhere-binaries → sherpa-onnx-ios/
  linux     prebuilt shared libs (x86_64 or aarch64)       → sherpa-onnx-linux/
  macos     BUILDS static libs from source (arm64, ~5-10m) → sherpa-onnx-macos/

Platform options:
  android:  --check    Verify 16KB alignment of existing libraries
  linux:    --force    Re-download even if already present

Versions come from sdk/runanywhere-commons/VERSIONS
(SHERPA_ONNX_VERSION_<PLATFORM>, SHERPA_ONNX_REPO_ANDROID).
EOF
}

PLATFORM="${1:-}"
case "${PLATFORM}" in
    android|ios|linux|macos) shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "expected platform argument: android, ios, linux, or macos" ;;
esac

COMMONS_ROOT="${RAC_ROOT}/sdk/runanywhere-commons"
source "${RAC_ROOT}/scripts/lib/load-versions.sh"

# ---------------------------------------------------------------------- android
download_android() {
    local sherpa_dir="${COMMONS_ROOT}/third_party/sherpa-onnx-android"

    [ -n "${SHERPA_ONNX_VERSION_ANDROID:-}" ] || die "SHERPA_ONNX_VERSION_ANDROID not loaded from VERSIONS file"
    local sherpa_version="${SHERPA_ONNX_VERSION_ANDROID}"
    # RunAnywhere Sherpa-ONNX fork (whisper per-token confidence); repo from VERSIONS
    local sherpa_repo="${SHERPA_ONNX_REPO_ANDROID}"
    local download_url="https://github.com/${sherpa_repo}/releases/download/v${sherpa_version}/sherpa-onnx-v${sherpa_version}-android.tar.bz2"

    local check_only=false
    for arg in "$@"; do
        case $arg in
            --check) check_only=true ;;
        esac
    done

    check_alignment() {
        local so_file="$1"

        local readelf_bin=""
        if command -v llvm-readelf &> /dev/null; then
            readelf_bin="llvm-readelf"
        elif [ -d "$HOME/Library/Android/sdk/ndk" ]; then
            local ndk_path
            ndk_path=$(ls -d "$HOME/Library/Android/sdk/ndk"/*/ 2>/dev/null | sort -V | tail -1)
            if [ -f "$ndk_path/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-readelf" ]; then
                readelf_bin="$ndk_path/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-readelf"
            fi
        fi

        if [ -z "$readelf_bin" ]; then
            echo "unknown"
            return
        fi

        local load_output
        load_output=$("$readelf_bin" -l "$so_file" 2>/dev/null | grep "LOAD" || true)

        local has_4kb=false
        local has_16kb=false

        while IFS= read -r line; do
            local align_val
            align_val=$(echo "$line" | grep -oE '0x[0-9a-fA-F]+' | tail -1)
            case "$align_val" in
                0x1000|0x001000) has_4kb=true ;;
                0x4000|0x004000) has_16kb=true ;;
            esac
        done <<< "$load_output"

        if [ "$has_4kb" = true ] && [ "$has_16kb" = false ]; then
            echo "4KB"
        elif [ "$has_16kb" = true ]; then
            echo "16KB"
        else
            echo "unknown"
        fi
    }

    if [ "$check_only" = true ]; then
        step "Checking Sherpa-ONNX library alignment"

        [ -d "${sherpa_dir}/jniLibs" ] || die "No libraries found at ${sherpa_dir}/jniLibs"

        local all_16kb=true
        local so_file alignment filename abi
        for so_file in "${sherpa_dir}/jniLibs"/*/*.so; do
            if [ -f "$so_file" ]; then
                alignment=$(check_alignment "$so_file")
                filename=$(basename "$so_file")
                abi=$(basename "$(dirname "$so_file")")

                if [ "$alignment" = "16KB" ]; then
                    ok "$abi/$filename - 16KB aligned"
                elif [ "$alignment" = "4KB" ]; then
                    error "$abi/$filename - 4KB aligned (NOT Play Store ready)"
                    all_16kb=false
                else
                    warn "$abi/$filename - Unknown alignment"
                fi
            fi
        done

        if [ "$all_16kb" = true ]; then
            ok "All libraries are 16KB aligned - Play Store ready!"
        else
            error "Some libraries are NOT 16KB aligned."
            error "Please re-download with: rm -rf ${sherpa_dir} && $0 android"
        fi
        exit 0
    fi

    step "Sherpa-ONNX Android downloader"
    log "Version: ${sherpa_version}"
    log "Pre-built libraries are 16KB aligned (Play Store ready)"

    download_header() {
        local url="$1"
        local output="$2"
        if ! curl -sfL "${url}" -o "${output}"; then
            error "Failed to download ${url}"
            rm -f "${output}"
            return 1
        fi
    }

    download_sherpa_headers() {
        mkdir -p "${sherpa_dir}/include/sherpa-onnx/c-api"
        log "Downloading headers from Sherpa-ONNX source (v${sherpa_version})..."
        download_header "https://raw.githubusercontent.com/${sherpa_repo}/v${sherpa_version}/sherpa-onnx/c-api/c-api.h" \
            "${sherpa_dir}/include/sherpa-onnx/c-api/c-api.h"
        download_header "https://raw.githubusercontent.com/${sherpa_repo}/v${sherpa_version}/sherpa-onnx/c-api/cxx-api.h" \
            "${sherpa_dir}/include/sherpa-onnx/c-api/cxx-api.h"
        echo "${sherpa_version}" > "${sherpa_dir}/include/.sherpa-header-version"
    }

    ensure_headers() {
        # Headers MUST come from the EXACT SAME version as the prebuilt .so files.
        if [ ! -d "${sherpa_dir}/include/sherpa-onnx" ]; then
            log "Downloading Sherpa-ONNX headers (v${sherpa_version})..."
            download_sherpa_headers
            ok "Sherpa-ONNX headers installed (v${sherpa_version})"
        else
            local existing_ver=""
            if [ -f "${sherpa_dir}/include/.sherpa-header-version" ]; then
                existing_ver=$(cat "${sherpa_dir}/include/.sherpa-header-version")
            fi
            # Treat missing sentinel or version mismatch the same way
            if [ "${existing_ver}" != "${sherpa_version}" ]; then
                warn "Sherpa header version mismatch (have '${existing_ver}', need '${sherpa_version}')"
                warn "Re-downloading headers to match .so version..."
                rm -rf "${sherpa_dir}/include/sherpa-onnx"
                rm -f "${sherpa_dir}/include/.sherpa-header-version"
                download_sherpa_headers
                ok "Sherpa headers updated to v${sherpa_version}"
            fi
        fi

        # ONNX Runtime headers (required for ONNX backend compilation)
        [ -n "${ONNX_VERSION_ANDROID:-}" ] || die "ONNX_VERSION_ANDROID not loaded from VERSIONS file"
        local onnx_rt_version="${ONNX_VERSION_ANDROID}"

        local need_onnx_headers=false
        if [ ! -f "${sherpa_dir}/include/onnxruntime_c_api.h" ] || [ ! -f "${sherpa_dir}/include/onnxruntime_cxx_api.h" ] || [ ! -f "${sherpa_dir}/include/onnxruntime_ep_c_api.h" ]; then
            need_onnx_headers=true
        elif [ -f "${sherpa_dir}/include/.onnx-header-version" ]; then
            local existing_onnx_ver
            existing_onnx_ver=$(cat "${sherpa_dir}/include/.onnx-header-version")
            if [ "${existing_onnx_ver}" != "${onnx_rt_version}" ]; then
                warn "ONNX Runtime header version mismatch (have '${existing_onnx_ver}', need '${onnx_rt_version}')"
                need_onnx_headers=true
            fi
        else
            need_onnx_headers=true
        fi

        if [ "${need_onnx_headers}" = true ]; then
            log "Downloading ONNX Runtime headers (v${onnx_rt_version})..."
            local onnx_header_base="https://raw.githubusercontent.com/microsoft/onnxruntime/v${onnx_rt_version}/include/onnxruntime/core/session"
            mkdir -p "${sherpa_dir}/include"
            download_header "${onnx_header_base}/onnxruntime_c_api.h" \
                "${sherpa_dir}/include/onnxruntime_c_api.h"
            download_header "${onnx_header_base}/onnxruntime_cxx_api.h" \
                "${sherpa_dir}/include/onnxruntime_cxx_api.h"
            download_header "${onnx_header_base}/onnxruntime_cxx_inline.h" \
                "${sherpa_dir}/include/onnxruntime_cxx_inline.h"
            download_header "${onnx_header_base}/onnxruntime_float16.h" \
                "${sherpa_dir}/include/onnxruntime_float16.h"
            # ORT 1.24.x: onnxruntime_c_api.h includes onnxruntime_ep_c_api.h at EOF.
            download_header "${onnx_header_base}/onnxruntime_ep_c_api.h" \
                "${sherpa_dir}/include/onnxruntime_ep_c_api.h"
            download_header "${onnx_header_base}/onnxruntime_ep_device_ep_metadata_keys.h" \
                "${sherpa_dir}/include/onnxruntime_ep_device_ep_metadata_keys.h"
            echo "${onnx_rt_version}" > "${sherpa_dir}/include/.onnx-header-version"
            ok "ONNX Runtime headers installed (v${onnx_rt_version})"
        fi
    }

    if [ -d "${sherpa_dir}/jniLibs" ]; then
        if [ -f "${sherpa_dir}/jniLibs/arm64-v8a/libsherpa-onnx-jni.so" ]; then
            ok "Sherpa-ONNX Android libraries already exist"
            log "   Location: ${sherpa_dir}"

            ensure_headers

            log "To force re-download, remove the directory first:"
            log "   rm -rf ${sherpa_dir}"
            exit 0
        else
            warn "Existing directory appears incomplete, re-downloading..."
            rm -rf "${sherpa_dir}"
        fi
    fi

    local temp_dir temp_archive http_code
    temp_dir=$(mktemp -d)
    temp_archive="${temp_dir}/sherpa-onnx-android.tar.bz2"

    info "Downloading from ${download_url}..."

    http_code=$(curl -L -w "%{http_code}" -o "${temp_archive}" "${download_url}" 2>/dev/null) || true

    if [ "${http_code}" = "200" ] && [ -f "${temp_archive}" ] && [ -s "${temp_archive}" ]; then
        log "Download complete. Size: $(du -h "${temp_archive}" | cut -f1)"

        info "Extracting..."
        mkdir -p "${sherpa_dir}"
        tar -xjf "${temp_archive}" -C "${temp_dir}"

        local extracted_dir
        extracted_dir=$(find "${temp_dir}" -maxdepth 1 -type d -name "sherpa-onnx-*-android" | head -1)
        if [ -z "${extracted_dir}" ]; then
            extracted_dir=$(find "${temp_dir}" -maxdepth 1 -type d -name "build-android*" | head -1)
        fi

        # Copy JNI libraries - handle different extraction structures
        if [ -n "${extracted_dir}" ] && [ -d "${extracted_dir}/jniLibs" ]; then
            cp -R "${extracted_dir}/jniLibs" "${sherpa_dir}/"
        elif [ -n "${extracted_dir}" ] && [ -d "${extracted_dir}/lib" ]; then
            mkdir -p "${sherpa_dir}/jniLibs"
            local abi_dir abi_name
            for abi_dir in "${extracted_dir}/lib"/*; do
                if [ -d "$abi_dir" ]; then
                    abi_name=$(basename "$abi_dir")
                    mkdir -p "${sherpa_dir}/jniLibs/${abi_name}"
                    cp "${abi_dir}"/*.so "${sherpa_dir}/jniLibs/${abi_name}/" 2>/dev/null || true
                fi
            done
        elif [ -d "${temp_dir}/jniLibs" ]; then
            cp -R "${temp_dir}/jniLibs" "${sherpa_dir}/"
        else
            error "Could not find jniLibs in extracted archive"
            ls -la "${temp_dir}"
            rm -rf "${temp_dir}"
            exit 1
        fi

        if [ -n "${extracted_dir}" ] && [ -d "${extracted_dir}/include" ]; then
            cp -R "${extracted_dir}/include" "${sherpa_dir}/"
        elif [ -d "${temp_dir}/include" ]; then
            cp -R "${temp_dir}/include" "${sherpa_dir}/"
        fi

        rm -rf "${temp_dir}"

        ensure_headers

        ok "Sherpa-ONNX Android libraries downloaded to ${sherpa_dir}"
        log "Contents:"
        ls -lh "${sherpa_dir}"
        if [ -d "${sherpa_dir}/jniLibs" ]; then
            log "JNI Libraries:"
            find "${sherpa_dir}/jniLibs" -name "*.so" -exec ls -lh {} \;
        fi
        if [ -d "${sherpa_dir}/include" ]; then
            log "Headers:"
            find "${sherpa_dir}/include" -name "*.h"
        fi
    else
        rm -rf "${temp_dir}"
        error "Sherpa-ONNX download failed (HTTP: ${http_code})"
        log "Manual download options:"
        log "1. Download directly from Sherpa-ONNX releases:"
        log "   ${download_url}"
        log "2. Extract and copy jniLibs to:"
        log "   ${sherpa_dir}/jniLibs/"
        exit 1
    fi
}

# -------------------------------------------------------------------------- ios
download_ios() {
    # Sherpa-ONNX doesn't publish prebuilt iOS binaries; we host our own build
    # on the runanywhere-binaries releases.
    local sherpa_dir="${COMMONS_ROOT}/third_party/sherpa-onnx-ios"

    [ -n "${SHERPA_ONNX_VERSION_IOS:-}" ] || die "SHERPA_ONNX_VERSION_IOS not loaded from VERSIONS file"
    local sherpa_version="${SHERPA_ONNX_VERSION_IOS}"
    local download_url="https://github.com/RunanywhereAI/runanywhere-binaries/releases/download/sherpa-onnx-v${sherpa_version}/sherpa-onnx.xcframework.zip"

    step "Sherpa-ONNX iOS xcframework downloader"
    log "Version: ${sherpa_version}"

    if [ -d "${sherpa_dir}/sherpa-onnx.xcframework" ]; then
        if [ -f "${sherpa_dir}/sherpa-onnx.xcframework/ios-arm64/libsherpa-onnx.a" ] && \
           [ -f "${sherpa_dir}/sherpa-onnx.xcframework/ios-arm64_x86_64-simulator/libsherpa-onnx.a" ]; then
            ok "Sherpa-ONNX xcframework already exists and appears valid"
            log "   Location: ${sherpa_dir}/sherpa-onnx.xcframework"
            log "To force re-download, remove the directory first:"
            log "   rm -rf ${sherpa_dir}/sherpa-onnx.xcframework"
            exit 0
        else
            warn "Existing xcframework appears incomplete, re-downloading..."
            rm -rf "${sherpa_dir}/sherpa-onnx.xcframework"
        fi
    fi

    local temp_dir temp_zip http_code
    temp_dir=$(mktemp -d)
    temp_zip="${temp_dir}/sherpa-onnx.xcframework.zip"

    info "Downloading from ${download_url}..."

    http_code=$(curl -L -w "%{http_code}" -o "${temp_zip}" "${download_url}" 2>/dev/null) || true

    if [ "${http_code}" = "200" ] && [ -f "${temp_zip}" ] && [ -s "${temp_zip}" ]; then
        log "Download complete. Size: $(du -h "${temp_zip}" | cut -f1)"

        info "Extracting xcframework..."
        mkdir -p "${sherpa_dir}"

        unzip -q "${temp_zip}" -d "${temp_dir}/extracted"

        local xcframework
        xcframework=$(find "${temp_dir}/extracted" -name "sherpa-onnx.xcframework" -type d | head -1)
        if [ -z "${xcframework}" ]; then
            error "sherpa-onnx.xcframework not found in archive"
            ls -R "${temp_dir}/extracted"
            rm -rf "${temp_dir}"
            exit 1
        fi

        cp -R "${xcframework}" "${sherpa_dir}/"

        rm -rf "${temp_dir}"

        ok "Sherpa-ONNX xcframework downloaded to ${sherpa_dir}/sherpa-onnx.xcframework"
        log "Contents:"
        ls -lh "${sherpa_dir}/sherpa-onnx.xcframework"
    else
        rm -rf "${temp_dir}"
        error "Pre-built Sherpa-ONNX not available for download (HTTP: ${http_code})"
        log "Options:"
        log "1. Upload pre-built Sherpa-ONNX to runanywhere-binaries:"
        log "   - Create zip: cd third_party/sherpa-onnx-ios && zip -r sherpa-onnx.xcframework.zip sherpa-onnx.xcframework"
        log "   - Create release: sherpa-onnx-v${sherpa_version} on runanywhere-binaries"
        log "   - Upload the zip file"
        log "2. Build from source (slow, ~10-15 minutes):"
        log "   ./src/backends/onnx/scripts/build-sherpa-onnx-ios.sh"
        exit 1
    fi
}

# ------------------------------------------------------------------------ linux
download_linux() {
    local dest_dir="${COMMONS_ROOT}/third_party/sherpa-onnx-linux"
    local version="${SHERPA_ONNX_VERSION_LINUX:-1.12.18}"
    local arch
    arch=$(uname -m)

    local force_download=false

    while [[ "${1:-}" == --* ]]; do
        case "$1" in
            --force) force_download=true; shift ;;
            *) die "Unknown option: $1" ;;
        esac
    done

    if [ -d "${dest_dir}/lib" ] && [ "$force_download" = false ]; then
        ok "Sherpa-ONNX already downloaded at ${dest_dir}"
        log "Use --force to re-download"
        exit 0
    fi

    local url archive_name
    if [ "$arch" = "aarch64" ]; then
        url="https://github.com/k2-fsa/sherpa-onnx/releases/download/v${version}/sherpa-onnx-v${version}-linux-aarch64-shared-cpu.tar.bz2"
        archive_name="sherpa-onnx-v${version}-linux-aarch64-shared-cpu"
    elif [ "$arch" = "x86_64" ]; then
        # sherpa-onnx publishes Linux x64 as `-shared` (no `-cpu` suffix);
        # aarch64 keeps the `-shared-cpu` suffix.
        url="https://github.com/k2-fsa/sherpa-onnx/releases/download/v${version}/sherpa-onnx-v${version}-linux-x64-shared.tar.bz2"
        archive_name="sherpa-onnx-v${version}-linux-x64-shared"
    else
        die "Unsupported architecture: $arch (supported: x86_64, aarch64)"
    fi

    step "Downloading Sherpa-ONNX for Linux"
    log "Version: ${version}"
    log "Architecture: ${arch}"
    log "URL: ${url}"
    log "Destination: ${dest_dir}"

    if [ -d "${dest_dir}" ]; then
        info "Removing existing Sherpa-ONNX directory..."
        rm -rf "${dest_dir}"
    fi

    local temp_dir
    temp_dir=$(mktemp -d)
    trap 'rm -rf "${temp_dir}"' EXIT

    info "Downloading Sherpa-ONNX v${version}..."
    # `--fail` makes curl exit non-zero on HTTP 4xx/5xx so a 404 page doesn't
    # end up being passed to tar/bzip2 below as a 9-byte "Not Found" file.
    curl -L --fail -o "${temp_dir}/sherpa-onnx.tar.bz2" "${url}"

    # Anything under 1 MB is almost certainly an error page that slipped past
    # --fail (e.g. proxy-mediated redirect).
    local dl_size
    dl_size=$(stat -c%s "${temp_dir}/sherpa-onnx.tar.bz2" 2>/dev/null || stat -f%z "${temp_dir}/sherpa-onnx.tar.bz2")
    if [ "${dl_size}" -lt 1048576 ]; then
        die "Downloaded file is suspiciously small (${dl_size} bytes). URL may be wrong: ${url}"
    fi

    info "Extracting archive..."
    mkdir -p "${dest_dir}"
    tar -xjf "${temp_dir}/sherpa-onnx.tar.bz2" -C "${temp_dir}"

    mv "${temp_dir}/${archive_name}"/* "${dest_dir}/"

    # C API headers are not included in pre-built binaries since v1.12.23+
    if [ ! -d "${dest_dir}/include/sherpa-onnx/c-api" ]; then
        info "Downloading C API headers..."
        mkdir -p "${dest_dir}/include/sherpa-onnx/c-api"
        curl -sL "https://raw.githubusercontent.com/k2-fsa/sherpa-onnx/v${version}/sherpa-onnx/c-api/c-api.h" \
            -o "${dest_dir}/include/sherpa-onnx/c-api/c-api.h"
    fi

    info "Verifying installation..."
    [ -f "${dest_dir}/lib/libsherpa-onnx-c-api.so" ] || die "libsherpa-onnx-c-api.so not found!"
    [ -f "${dest_dir}/include/sherpa-onnx/c-api/c-api.h" ] || die "C API header not found!"

    ok "Sherpa-ONNX v${version} downloaded successfully!"
    log "Contents:"
    log "  Libraries: ${dest_dir}/lib/"
    ls -la "${dest_dir}/lib/"*.so* 2>/dev/null | head -10 | awk '{print "    " $9 ": " $5}'
    log "  Headers: ${dest_dir}/include/"
    ls "${dest_dir}/include/" 2>/dev/null | head -5 | awk '{print "    " $1}'
    log "Library sizes:"
    ls -lh "${dest_dir}/lib/"*.so 2>/dev/null | awk '{print "  " $9 ": " $5}' | head -5
    ok "Done!"
}

# ------------------------------------------------------------------------ macos
download_macos() {
    # Official releases only provide shared libraries for macOS; we need
    # static libs to bundle into xcframeworks, so this builds from source
    # (arm64, ~5-10 minutes on Apple Silicon).
    local sherpa_dir="${COMMONS_ROOT}/third_party/sherpa-onnx-macos"
    local build_temp="${COMMONS_ROOT}/build/sherpa-onnx-macos-build"

    [ -n "${SHERPA_ONNX_VERSION_MACOS:-}" ] || die "SHERPA_ONNX_VERSION_MACOS not loaded from VERSIONS file"
    local sherpa_version="${SHERPA_ONNX_VERSION_MACOS}"

    step "Sherpa-ONNX macOS static builder"
    log "Version: ${sherpa_version}"
    log "Architecture: arm64 (Apple Silicon)"

    if [ -f "${sherpa_dir}/lib/libsherpa-onnx-c-api.a" ]; then
        ok "Sherpa-ONNX macOS static libs already exist at ${sherpa_dir}"
        log "   To force rebuild, remove: rm -rf ${sherpa_dir}"
        exit 0
    fi

    require_cmd cmake git

    info "Cloning sherpa-onnx v${sherpa_version}..."
    rm -rf "${build_temp}"
    mkdir -p "${build_temp}"

    git clone --depth 1 --branch "v${sherpa_version}" \
        https://github.com/k2-fsa/sherpa-onnx.git \
        "${build_temp}/sherpa-onnx"

    info "Building static libraries for macOS arm64 (takes ~5-10 minutes)..."

    local build_dir="${build_temp}/sherpa-onnx/build-macos-static"
    mkdir -p "${build_dir}"
    cd "${build_dir}"

    cmake "${build_temp}/sherpa-onnx" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_ARCHITECTURES="arm64" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="14.0" \
        -DBUILD_SHARED_LIBS=OFF \
        -DSHERPA_ONNX_ENABLE_C_API=ON \
        -DSHERPA_ONNX_ENABLE_BINARY=OFF \
        -DSHERPA_ONNX_ENABLE_TESTS=OFF \
        -DSHERPA_ONNX_ENABLE_PYTHON=OFF \
        -DSHERPA_ONNX_ENABLE_PORTAUDIO=OFF \
        -DSHERPA_ONNX_ENABLE_WEBSOCKET=OFF \
        -DSHERPA_ONNX_ENABLE_GPU=OFF

    cmake --build . --config Release -j"$(sysctl -n hw.ncpu)"

    info "Collecting build artifacts..."
    mkdir -p "${sherpa_dir}/lib"
    mkdir -p "${sherpa_dir}/include"

    find "${build_dir}" -name "libsherpa-onnx-c-api.a" -exec cp {} "${sherpa_dir}/lib/" \;

    local lib lib_file
    for lib in \
        sherpa-onnx-core sherpa-onnx-fst sherpa-onnx-fstfar \
        sherpa-onnx-kaldifst-core kaldi-decoder-core kaldi-native-fbank-core \
        piper_phonemize espeak-ng ucd cppinyin_core ssentencepiece_core kissfft-float; do
        lib_file=$(find "${build_dir}" -name "lib${lib}.a" 2>/dev/null | head -1)
        if [ -n "${lib_file}" ]; then
            cp "${lib_file}" "${sherpa_dir}/lib/"
        fi
    done

    local onnx_lib
    onnx_lib=$(find "${build_dir}" -name "libonnxruntime.a" 2>/dev/null | head -1)
    if [ -n "${onnx_lib}" ]; then
        cp "${onnx_lib}" "${sherpa_dir}/lib/"
    fi

    if [ -d "${build_temp}/sherpa-onnx/sherpa-onnx/c-api" ]; then
        mkdir -p "${sherpa_dir}/include/sherpa-onnx/c-api"
        cp "${build_temp}/sherpa-onnx/sherpa-onnx/c-api/"*.h "${sherpa_dir}/include/sherpa-onnx/c-api/" 2>/dev/null || true
    fi

    local generated_headers header_dir
    generated_headers=$(find "${build_dir}" -path "*/sherpa-onnx/c-api/c-api.h" | head -1)
    if [ -n "${generated_headers}" ]; then
        header_dir=$(dirname "${generated_headers}")
        mkdir -p "${sherpa_dir}/include/sherpa-onnx/c-api"
        cp "${header_dir}/"*.h "${sherpa_dir}/include/sherpa-onnx/c-api/" 2>/dev/null || true
    fi

    if [ -f "${sherpa_dir}/lib/libsherpa-onnx-c-api.a" ]; then
        ok "Sherpa-ONNX macOS static build complete!"
        log "Output: ${sherpa_dir}"
        log "Libraries:"
        ls -lh "${sherpa_dir}/lib/"*.a 2>/dev/null || log "  (none found)"
        log "Headers:"
        find "${sherpa_dir}/include" -name "*.h" 2>/dev/null || log "  (none found)"
    else
        error "Build failed - libsherpa-onnx-c-api.a not found"
        log "Build directory: ${build_dir}"
        log "Check build logs above for errors."
        exit 1
    fi

    info "Cleaning up build directory..."
    rm -rf "${build_temp}"
    ok "Done!"
}

case "${PLATFORM}" in
    android) download_android "$@" ;;
    ios)     download_ios "$@" ;;
    linux)   download_linux "$@" ;;
    macos)   download_macos "$@" ;;
esac
