#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# build-core-xcframework.sh — wraps the ios-device, ios-simulator, and
# macos-release CMake presets and runs `xcodebuild -create-xcframework` to
# produce the `.xcframework` bundles the Swift SDK consumes on Apple platforms:
#
#   sdk/runanywhere-swift/Binaries/RACommons.xcframework
#   sdk/runanywhere-swift/Binaries/RABackendLLAMACPP.xcframework
#   sdk/runanywhere-swift/Binaries/RABackendONNX.xcframework          (skipped if RAC_BACKEND_ONNX=OFF)
#   sdk/runanywhere-swift/Binaries/RABackendSherpa.xcframework
#   sdk/runanywhere-swift/Binaries/RABackendCoreML.xcframework        (Apple-only; CoreML Stable-Diffusion engine)
#   sdk/runanywhere-swift/Binaries/RABackendMLX.xcframework           (Apple-only, skipped if RAC_BACKEND_MLX=OFF)
#   sdk/runanywhere-swift/Binaries/RunAnywhereMLXRuntime.xcframework  (Apple-only, skipped if RAC_BACKEND_MLX=OFF)
#   sdk/runanywhere-swift/Binaries/RunAnywhereMLXMetal.xcframework    (platform-selected Metal resource framework)
#   sdk/runanywhere-swift/Binaries/RunAnywhereMLXRuntimeResources/   (Swift resource bundles/notices)
#
# Engine plugins under engines/{llamacpp,onnx} use SHARED_ONLY inside
# rac_add_engine_plugin(...), so on iOS (RAC_STATIC_PLUGINS=ON) they still
# produce standalone `librac_backend_<name>.a` archives alongside
# `librac_commons.a`. All three have to be re-packaged into
# `.xcframework`s containing ios-arm64, ios-arm64-simulator, and macos-arm64
# slices. Every product in Package.swift advertises macOS, so every binary
# target in that product graph must carry the macOS slice.
#
# Environment knobs:
#   RAC_BACKEND_ONNX=OFF     skip the ONNX backend (used when the operator
#                            hasn't extracted third_party/onnxruntime-ios)
#   RAC_BACKEND_MLX=OFF      skip the MLX backend bridge
#   DRY_RUN=1                only print the planned commands, don't invoke
#                            cmake/xcodebuild. Useful in CI preflight and
#                            the `release-swift-binaries.sh DRY_RUN=1` path.
set -euo pipefail
export ZERO_AR_DATE=1
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-315532800}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DEST="${REPO_ROOT}/sdk/runanywhere-swift/Binaries"
ARCHIVE_MEMBER_NORMALIZER="${REPO_ROOT}/sdk/runanywhere-swift/scripts/normalize-static-archive.py"
# The source path is anchored dynamically so the script works from any cwd.
# shellcheck disable=SC1091
source "${REPO_ROOT}/sdk/runanywhere-commons/scripts/load-versions.sh"

if [ "$(uname -s)" != "Darwin" ]; then
    echo "error: build-core-xcframework.sh only runs on macOS" >&2
    exit 1
fi

DRY_RUN="${DRY_RUN:-0}"
RAC_BACKEND_ONNX="${RAC_BACKEND_ONNX:-ON}"
RAC_BACKEND_SHERPA="${RAC_BACKEND_SHERPA:-ON}"
RAC_BACKEND_COREML="${RAC_BACKEND_COREML:-ON}"
RAC_BACKEND_MLX="${RAC_BACKEND_MLX:-ON}"
if [ "${RAC_BACKEND_SHERPA}" != "ON" ] || [ "${RAC_BACKEND_COREML}" != "ON" ]; then
    echo "error: the Swift package unconditionally requires Sherpa and CoreML binaries; RAC_BACKEND_SHERPA and RAC_BACKEND_COREML must be ON" >&2
    exit 1
fi
COMMONS_HEADERS="${REPO_ROOT}/sdk/runanywhere-commons/include"
STAGING_DIR="${REPO_ROOT}/build/ios-xcframework-staging"
BUILD_JOBS="${RAC_BUILD_JOBS:-$(sysctl -n hw.logicalcpu)}"
MLX_RUNTIME_SOURCE="${REPO_ROOT}/sdk/runanywhere-swift/Sources/MLXRuntimeDistribution"
MLX_RUNTIME_BUILD_ROOT="${REPO_ROOT}/build/mlx-runtime-distribution"
MLX_METAL_BUNDLE_ID="ai.runanywhere.mlx.metal"

run() {
    # Thin wrapper that either prints the command (DRY_RUN=1) or executes it.
    # Quoting is preserved via "$@" — callers must pass each argv entry as a
    # separate shell word, not a single string with shell metacharacters.
    if [ "${DRY_RUN}" = "1" ]; then
        printf '[DRY RUN] '
        printf '%q ' "$@"
        printf '\n'
    else
        "$@"
    fi
}

# xcodebuild does not preserve the -library argument order when it emits an
# XCFramework Info.plist. Canonicalize that metadata before archiving so two
# identical builds cannot acquire different SwiftPM checksums.
normalize_xcframework_info_plist() {
    local xcframework="$1"
    local plist="${xcframework}/Info.plist"

    if [ ! -f "${plist}" ]; then
        echo "error: XCFramework Info.plist not found: ${plist}" >&2
        exit 1
    fi

    python3 - "${plist}" <<'PY'
import os
import plistlib
import sys
import tempfile

path = sys.argv[1]
with open(path, "rb") as stream:
    document = plistlib.load(stream)

libraries = document.get("AvailableLibraries")
if not isinstance(libraries, list) or not libraries:
    raise SystemExit(f"error: {path} has no AvailableLibraries entries")

identifiers = [entry.get("LibraryIdentifier") for entry in libraries]
if any(not isinstance(identifier, str) or not identifier for identifier in identifiers):
    raise SystemExit(f"error: {path} has an invalid LibraryIdentifier")
if len(set(identifiers)) != len(identifiers):
    raise SystemExit(f"error: {path} has duplicate LibraryIdentifier entries")

def stable_key(entry):
    canonical_entry = plistlib.dumps(
        entry,
        fmt=plistlib.FMT_XML,
        sort_keys=True,
    )
    return entry["LibraryIdentifier"], canonical_entry

document["AvailableLibraries"] = sorted(libraries, key=stable_key)

directory = os.path.dirname(path)
descriptor, temporary_path = tempfile.mkstemp(prefix="Info.plist.", dir=directory)
try:
    with os.fdopen(descriptor, "wb") as stream:
        plistlib.dump(
            document,
            stream,
            fmt=plistlib.FMT_XML,
            sort_keys=True,
        )
    os.chmod(temporary_path, 0o644)
    os.replace(temporary_path, path)
except BaseException:
    try:
        os.unlink(temporary_path)
    except FileNotFoundError:
        pass
    raise
PY
    plutil -lint "${plist}" >/dev/null
}

prepare_archive_input() {
    local input="$1"
    local arch="$2"
    local scratch_dir="$3"

    if [ "${DRY_RUN}" = "1" ]; then
        echo "${input}"
        return
    fi
    if [ ! -f "${input}" ]; then
        echo "error: required archive not found: ${input}" >&2
        exit 1
    fi
    if ! xcrun lipo "${input}" -verify_arch "${arch}" >/dev/null 2>&1; then
        echo "error: ${input} does not contain architecture ${arch}" >&2
        exit 1
    fi

    local info
    info="$(xcrun lipo -info "${input}")"
    if printf '%s' "${info}" | grep -q "^Non-fat file:"; then
        echo "${input}"
        return
    fi

    run mkdir -p "${scratch_dir}"
    local prepared
    prepared="${scratch_dir}/$(basename "${input}").${arch}.a"
    run xcrun lipo -thin "${arch}" "${input}" -output "${prepared}"
    echo "${prepared}"
}

merge_static_archives() {
    local output="$1"
    shift
    local inputs=("$@")

    if [ "${#inputs[@]}" -eq 0 ]; then
        echo "error: merge_static_archives called without input archives" >&2
        exit 1
    fi

    if [ "${DRY_RUN}" != "1" ]; then
        local input
        for input in "${inputs[@]}"; do
            if [ ! -f "${input}" ]; then
                echo "error: required archive not found: ${input}" >&2
                exit 1
            fi
        done
    fi

    run mkdir -p "$(dirname "${output}")"
    run rm -f "${output}"
    run xcrun libtool -static -o "${output}" "${inputs[@]}"
}

# Collapse byte-identical duplicate members in a static archive, in place.
#
# The macOS ONNX slice folds in the pinned `libonnxruntime.a`, which is itself a
# fat-merge of ONNX Runtime's sub-archives. Assembling it re-packed a handful of
# object files (onnx-ml.pb.cc.o, onnx-data.pb.cc.o, onnx-operators-ml.pb.cc.o)
# more than once, so the same onnx::* protobuf symbols are defined by two
# byte-identical members. A normal consumer link only pulls the first
# definition, but a full-backend macOS app links the slice with -all_load, which
# force-loads every member and fails with hundreds of duplicate symbols.
#
# De-dup by (member name, content hash): keep the first occurrence of each unique
# object and drop only byte-identical repeats — distinct objects that merely
# share a basename (e.g. onnx's many defs.cc.o) are preserved, so no code is
# lost. This mirrors the iOS slice, where ONNX Runtime ships as one prelinked
# object with no duplicate members.
dedup_byte_identical_archive_members() {
    local archive="$1"
    local label="$2"

    if [ "${DRY_RUN}" = "1" ]; then
        return
    fi
    if [ ! -f "${archive}" ]; then
        echo "error: dedup target archive not found: ${archive}" >&2
        exit 1
    fi

    local scratch_dir="${STAGING_DIR}/dedup/$(basename "${archive}")"
    run rm -rf "${scratch_dir}"
    run mkdir -p "${scratch_dir}"

    local summary
    summary="$(python3 - "${archive}" "${scratch_dir}" <<'PY'
import hashlib
import os
import sys

archive = sys.argv[1]
outdir = sys.argv[2]
data = open(archive, "rb").read()
if data[:8] != b"!<arch>\n":
    raise SystemExit(f"error: {archive} is not a static archive")

pos = 8
index = 0
kept = []
seen = set()
total = 0
while pos + 60 <= len(data):
    header = data[pos:pos + 60]
    if header[58:60] != b"\x60\n":  # ar member header magic 0x60 0x0A (\x60 avoids a raw backtick that macOS /bin/bash 3.2 mis-parses inside $()<<'PY')
        raise SystemExit(f"error: {archive}: bad member header at byte {pos}")
    raw_name = header[0:16].decode("ascii", "replace").rstrip()
    size = int(header[48:58].decode("ascii").strip())
    body = data[pos + 60:pos + 60 + size]
    name = raw_name
    if raw_name.startswith("#1/"):
        namelen = int(raw_name[3:])
        name = body[:namelen].split(b"\0", 1)[0].decode("ascii", "replace")
        body = body[namelen:]
    pos += 60 + size + (size % 2)
    if name in ("__.SYMDEF", "__.SYMDEF SORTED", "//", "/"):
        continue
    total += 1
    key = (name, hashlib.sha256(body).hexdigest())
    if key in seen:
        continue
    seen.add(key)
    member_dir = os.path.join(outdir, f"{index:05d}")
    os.makedirs(member_dir, exist_ok=True)
    with open(os.path.join(member_dir, name), "wb") as stream:
        stream.write(body)
    kept.append(os.path.join(member_dir, name))
    index += 1

# NUL-terminate every path (including the last) so the bash `read -d ''`
# loop below reads all fields — a bare `\0`.join() leaves the final path
# unterminated, and `read` drops an unterminated trailing field.
with open(os.path.join(outdir, "keep.nul"), "wb") as stream:
    for path in kept:
        stream.write(path.encode())
        stream.write(b"\0")

print(f"{total} {len(kept)} {total - len(kept)}")
PY
)"

    local total kept removed
    read -r total kept removed <<<"${summary}"

    if [ "${removed}" -eq 0 ]; then
        echo "  ✓ ${label}: no byte-identical duplicate members (${total} members)"
        run rm -rf "${scratch_dir}"
        return
    fi

    local keep_files=()
    local path
    while IFS= read -r -d '' path; do
        keep_files+=("${path}")
    done <"${scratch_dir}/keep.nul"

    # Fail closed if the manifest read lost any member — a silently short
    # repack drops object files (and their symbols) from the slice.
    if [ "${#keep_files[@]}" -ne "${kept}" ]; then
        echo "error: ${label} dedup manifest mismatch (expected ${kept} members, read ${#keep_files[@]})" >&2
        exit 1
    fi

    run rm -f "${archive}"
    run xcrun libtool -static -o "${archive}" "${keep_files[@]}"
    run rm -rf "${scratch_dir}"
    echo "  ✓ ${label}: de-duped ${removed} byte-identical member(s) (${total} → ${kept})"
}

# Some pinned upstream Apple archives embed their CI checkout roots in
# __FILE__ strings. Rewrite only the reviewed, version-pinned prefixes while
# preserving every byte offset, then fail closed if any host path remains.
# The expected counts intentionally make an upstream binary change require a
# fresh audit instead of silently accepting a new or incomplete rewrite.
sanitize_and_validate_archive_host_paths() {
    local archive="$1"
    local label="$2"
    shift 2

    if [ "${DRY_RUN}" = "1" ]; then
        return
    fi

    python3 - "${archive}" "${label}" "$@" <<'PY'
import os
from pathlib import Path
import stat
import sys
import tempfile

archive = Path(sys.argv[1])
label = sys.argv[2]
arguments = sys.argv[3:]
if len(arguments) % 3 != 0:
    raise SystemExit(f"error: invalid host-path rewrite specification for {label}")

payload = archive.read_bytes()
replacement_total = 0
for offset in range(0, len(arguments), 3):
    source = arguments[offset].encode()
    replacement = arguments[offset + 1].encode()
    expected_count = int(arguments[offset + 2])
    if len(source) != len(replacement):
        raise SystemExit(
            f"error: {label} host-path replacement must preserve binary offsets"
        )
    actual_count = payload.count(source)
    if actual_count != expected_count:
        raise SystemExit(
            f"error: {label} expected {expected_count} occurrence(s) of "
            f"{source.decode()!r}, found {actual_count}"
        )
    if payload.count(replacement) != 0:
        raise SystemExit(
            f"error: {label} replacement {replacement.decode()!r} was already present"
        )
    payload = payload.replace(source, replacement)
    replacement_total += actual_count

host_markers = (b"/Users/", b"/home/", b"/var/folders/", b"\\Users\\")
remaining = [marker.decode(errors="replace") for marker in host_markers if marker in payload]
if remaining:
    raise SystemExit(
        f"error: {label} still contains unreviewed host path marker(s): "
        + ", ".join(remaining)
    )

if replacement_total:
    mode = stat.S_IMODE(archive.stat().st_mode)
    descriptor, temporary_path = tempfile.mkstemp(
        prefix=f".{archive.name}.", dir=archive.parent
    )
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(payload)
        os.chmod(temporary_path, mode)
        os.replace(temporary_path, archive)
    finally:
        if os.path.exists(temporary_path):
            os.unlink(temporary_path)

print(f"  ✓ {label} host-path audit ({replacement_total} replacement(s))")
PY
}

RAC_PROTO_STATIC_DEPS=()

collect_protobuf_static_deps() {
    local build_root="$1"
    local dep
    local absl_count=0
    local protobuf_has_absl_refs=0
    local protobuf_archives=()
    RAC_PROTO_STATIC_DEPS=()

    if [ "${DRY_RUN}" = "1" ] || [ ! -d "${build_root}/_deps" ]; then
        return
    fi

    while IFS= read -r dep; do
        RAC_PROTO_STATIC_DEPS+=("${dep}")
        case "$(basename "${dep}")" in
            libabsl*.a)
                absl_count=$((absl_count + 1))
                ;;
            libprotobuf*.a)
                protobuf_archives+=("${dep}")
                ;;
        esac
    done < <(find "${build_root}/_deps" -type f \( \
        -name "libprotobuf.a" -o \
        -name "libprotobuf-lite.a" -o \
        -name "libabsl*.a" -o \
        -name "libutf8*.a" \
    \) | sort)

    if [ "${DRY_RUN}" != "1" ] && [ "${#RAC_PROTO_STATIC_DEPS[@]}" -eq 0 ]; then
        echo "error: no vendored protobuf/abseil static archives found under ${build_root}/_deps" >&2
        echo "       RACommons.xcframework must bundle protobuf runtime objects." >&2
        exit 1
    fi

    if [ "${#protobuf_archives[@]}" -gt 0 ] && [ "${absl_count}" -eq 0 ]; then
        for dep in "${protobuf_archives[@]}"; do
            if nm -u "${dep}" 2>/dev/null | grep -q "absl"; then
                protobuf_has_absl_refs=1
                break
            fi
        done
        if [ "${protobuf_has_absl_refs}" = "1" ]; then
            echo "error: vendored protobuf archive references absl, but no static libabsl*.a archives were found under ${build_root}/_deps" >&2
            echo "       Reconfigure with RAC_VENDOR_PROTOBUF=ON and protobuf_FORCE_FETCH_DEPENDENCIES=ON before packaging RACommons.xcframework." >&2
            exit 1
        fi
    fi
}

merge_commons_slice() {
    local build_root="$1"
    local slice_dir="$2"
    local output="$3"
    local arch="$4"
    local scratch_dir="${STAGING_DIR}/prepared/${slice_dir}/commons"
    local inputs=(
        "${build_root}/sdk/runanywhere-commons/${slice_dir}/librac_commons.a"
        "${build_root}/_deps/libarchive-build/libarchive/${slice_dir}/libarchive.a"
    )

    # libcurl was removed from the native HTTP transport, but older dependency
    # graphs may still produce it. Bundle it only when it exists.
    local bundled_curl="${build_root}/_deps/curl_fetched-build/lib/${slice_dir}/libcurl.a"
    if [ "${DRY_RUN}" = "1" ] || [ -f "${bundled_curl}" ]; then
        inputs+=("${bundled_curl}")
    fi
    collect_protobuf_static_deps "${build_root}"
    if [ -n "${RAC_PROTO_STATIC_DEPS[*]-}" ]; then
        inputs+=("${RAC_PROTO_STATIC_DEPS[@]}")
    fi

    local prepared=()
    local input
    for input in "${inputs[@]}"; do
        prepared+=("$(prepare_archive_input "${input}" "${arch}" "${scratch_dir}")")
    done

    merge_static_archives "${output}" "${prepared[@]}"
}

merge_commons_macos_slice() {
    local build_root="$1"
    local output="$2"
    local arch="$3"
    local scratch_dir="${STAGING_DIR}/prepared/Release-macos/commons"
    local inputs=(
        "${build_root}/sdk/runanywhere-commons/librac_commons.a"
        "${build_root}/_deps/libarchive-build/libarchive/libarchive.a"
    )

    # libcurl was removed from the native HTTP transport, but older dependency
    # graphs may still produce it. Bundle it only when it exists.
    local bundled_curl="${build_root}/_deps/curl_fetched-build/lib/libcurl.a"
    if [ "${DRY_RUN}" = "1" ] || [ -f "${bundled_curl}" ]; then
        inputs+=("${bundled_curl}")
    fi
    collect_protobuf_static_deps "${build_root}"
    if [ -n "${RAC_PROTO_STATIC_DEPS[*]-}" ]; then
        inputs+=("${RAC_PROTO_STATIC_DEPS[@]}")
    fi

    local prepared=()
    local input
    for input in "${inputs[@]}"; do
        prepared+=("$(prepare_archive_input "${input}" "${arch}" "${scratch_dir}")")
    done

    merge_static_archives "${output}" "${prepared[@]}"
}

validate_isolated_protobuf_archive() {
    local archive="$1"
    local label="$2"

    if [ "${DRY_RUN}" = "1" ]; then
        return
    fi

    local symbols="${STAGING_DIR}/protobuf-symbols-${label}.txt"
    if ! nm -gU "${archive}" 2>/dev/null | c++filt > "${symbols}"; then
        echo "error: could not inspect external symbols in ${archive}" >&2
        exit 1
    fi
    if grep -Fq "google::protobuf::" "${symbols}"; then
        echo "error: ${label} RACommons exports the process-global google::protobuf namespace" >&2
        echo "       Static ONNX/Sherpa consumers can carry a different protobuf runtime; rebuild with RAC_ISOLATE_PROTOBUF_NAMESPACE=ON." >&2
        exit 1
    fi
    if ! grep -Fq "runanywhere_internal::protobuf::" "${symbols}"; then
        echo "error: ${label} RACommons is missing the isolated RunAnywhere protobuf runtime" >&2
        exit 1
    fi
    echo "  ✓ ${label} protobuf symbols are namespace-isolated"
}

find_onnxruntime_ios_archive() {
    local slice_dir="$1"
    local arch_dir

    if [ "${slice_dir}" = "Release-iphoneos" ]; then
        arch_dir="ios-arm64"
    else
        arch_dir="ios-arm64_x86_64-simulator"
    fi

    local candidates=(
        "${IOS_ONNXRT}/${arch_dir}/libonnxruntime.a"
        "${IOS_ONNXRT}/${arch_dir}/onnxruntime.a"
        "${IOS_ONNXRT}/${arch_dir}/onnxruntime.framework/onnxruntime"
    )
    local candidate
    for candidate in "${candidates[@]}"; do
        if [ "${DRY_RUN}" = "1" ] || [ -f "${candidate}" ]; then
            echo "${candidate}"
            return
        fi
    done

    echo "error: could not locate ONNX Runtime iOS archive for ${slice_dir}" >&2
    exit 1
}

merge_llamacpp_backend_slice() {
    local build_root="$1"
    local slice_dir="$2"
    local output="$3"
    local arch="$4"
    local scratch_dir="${STAGING_DIR}/prepared/${slice_dir}/llamacpp"
    local inputs=(
        "${build_root}/engines/llamacpp/${slice_dir}/librac_backend_llamacpp.a"
        "${build_root}/_deps/llamacpp-build/src/${slice_dir}/libllama.a"
        "${build_root}/_deps/llamacpp-build/common/${slice_dir}/libllama-common.a"
        "${build_root}/_deps/llamacpp-build/common/${slice_dir}/libllama-common-base.a"
        "${build_root}/_deps/llamacpp-build/ggml/src/${slice_dir}/libggml.a"
        "${build_root}/_deps/llamacpp-build/ggml/src/${slice_dir}/libggml-base.a"
        "${build_root}/_deps/llamacpp-build/ggml/src/${slice_dir}/libggml-cpu.a"
    )

    if [ "${DRY_RUN}" = "1" ] || [ -f "${build_root}/_deps/llamacpp-build/ggml/src/ggml-metal/${slice_dir}/libggml-metal.a" ]; then
        inputs+=("${build_root}/_deps/llamacpp-build/ggml/src/ggml-metal/${slice_dir}/libggml-metal.a")
    fi
    if [ "${DRY_RUN}" = "1" ] || [ -f "${build_root}/_deps/llamacpp-build/ggml/src/ggml-blas/${slice_dir}/libggml-blas.a" ]; then
        inputs+=("${build_root}/_deps/llamacpp-build/ggml/src/ggml-blas/${slice_dir}/libggml-blas.a")
    fi
    if [ "${DRY_RUN}" = "1" ] || [ -f "${build_root}/_deps/llamacpp-build/vendor/cpp-httplib/${slice_dir}/libcpp-httplib.a" ]; then
        inputs+=("${build_root}/_deps/llamacpp-build/vendor/cpp-httplib/${slice_dir}/libcpp-httplib.a")
    fi

    local prepared=()
    local input
    for input in "${inputs[@]}"; do
        prepared+=("$(prepare_archive_input "${input}" "${arch}" "${scratch_dir}")")
    done

    merge_static_archives "${output}" "${prepared[@]}"
}

merge_llamacpp_backend_macos_slice() {
    local build_root="$1"
    local output="$2"
    local arch="$3"
    local scratch_dir="${STAGING_DIR}/prepared/Release-macos/llamacpp"
    local inputs=(
        "${build_root}/engines/llamacpp/librac_backend_llamacpp.a"
        "${build_root}/_deps/llamacpp-build/src/libllama.a"
        "${build_root}/_deps/llamacpp-build/common/libllama-common.a"
        "${build_root}/_deps/llamacpp-build/common/libllama-common-base.a"
        "${build_root}/_deps/llamacpp-build/ggml/src/libggml.a"
        "${build_root}/_deps/llamacpp-build/ggml/src/libggml-base.a"
        "${build_root}/_deps/llamacpp-build/ggml/src/libggml-cpu.a"
    )

    local optional
    for optional in \
        "${build_root}/_deps/llamacpp-build/ggml/src/ggml-metal/libggml-metal.a" \
        "${build_root}/_deps/llamacpp-build/ggml/src/ggml-blas/libggml-blas.a" \
        "${build_root}/_deps/llamacpp-build/vendor/cpp-httplib/libcpp-httplib.a"; do
        if [ "${DRY_RUN}" = "1" ] || [ -f "${optional}" ]; then
            inputs+=("${optional}")
        fi
    done

    local prepared=()
    local input
    for input in "${inputs[@]}"; do
        prepared+=("$(prepare_archive_input "${input}" "${arch}" "${scratch_dir}")")
    done

    merge_static_archives "${output}" "${prepared[@]}"
}

merge_onnx_backend_slice() {
    local build_root="$1"
    local slice_dir="$2"
    local output="$3"
    local arch="$4"
    local scratch_dir="${STAGING_DIR}/prepared/${slice_dir}/onnx"
    # ONNX owns generic ONNX Runtime services. When RABackendSherpa is being
    # built as its own xcframework, keep sherpa's implementation objects and
    # the sherpa-onnx prebuilt archives out of this slice so consumers linking
    # both RABackendONNX + RABackendSherpa don't see duplicate symbols.
    local inputs=(
        "${build_root}/engines/onnx/${slice_dir}/librac_backend_onnx.a"
        "${build_root}/runtimes/onnxrt/${slice_dir}/librac_runtime_onnxrt.a"
        "$(find_onnxruntime_ios_archive "${slice_dir}")"
    )

    if [ "${RAC_BACKEND_SHERPA}" = "OFF" ]; then
        if [ "${DRY_RUN}" = "1" ] || [ -f "${build_root}/engines/sherpa/${slice_dir}/librac_backend_sherpa.a" ]; then
            inputs+=("${build_root}/engines/sherpa/${slice_dir}/librac_backend_sherpa.a")
        fi
        local sherpa_dir
        if [ "${slice_dir}" = "Release-iphoneos" ]; then
            sherpa_dir="${REPO_ROOT}/sdk/runanywhere-commons/third_party/sherpa-onnx-ios/sherpa-onnx.xcframework/ios-arm64"
        else
            sherpa_dir="${REPO_ROOT}/sdk/runanywhere-commons/third_party/sherpa-onnx-ios/sherpa-onnx.xcframework/ios-arm64_x86_64-simulator"
        fi
        if [ "${DRY_RUN}" = "1" ] || [ -d "${sherpa_dir}" ]; then
            local sherpa_archive
            for sherpa_archive in "${sherpa_dir}"/*.a; do
                if [ "${DRY_RUN}" = "1" ] || [ -f "${sherpa_archive}" ]; then
                    inputs+=("${sherpa_archive}")
                fi
            done
        fi
    fi

    local prepared=()
    local input
    for input in "${inputs[@]}"; do
        prepared+=("$(prepare_archive_input "${input}" "${arch}" "${scratch_dir}")")
    done

    merge_static_archives "${output}" "${prepared[@]}"
}

merge_onnx_backend_macos_slice() {
    local build_root="$1"
    local output="$2"
    local arch="$3"
    local scratch_dir="${STAGING_DIR}/prepared/Release-macos/onnx"
    local inputs=(
        "${build_root}/engines/onnx/librac_backend_onnx.a"
        "${build_root}/runtimes/onnxrt/librac_runtime_onnxrt.a"
        "${MACOS_SHERPA_ROOT}/lib/libonnxruntime.a"
    )

    local prepared=()
    local input
    for input in "${inputs[@]}"; do
        prepared+=("$(prepare_archive_input "${input}" "${arch}" "${scratch_dir}")")
    done

    merge_static_archives "${output}" "${prepared[@]}"
    # The pinned macOS libonnxruntime.a re-packs a few onnx protobuf objects
    # verbatim, so the merged slice carries duplicate onnx::* symbols that break
    # a full-backend macOS app's -all_load link. Collapse the byte-identical
    # repeats (iOS avoids this by shipping ONNX Runtime as one prelinked object).
    dedup_byte_identical_archive_members "${output}" "macos RABackendONNX"
}

# Sherpa engine slice. Fold in the sherpa-onnx prebuilt archives because this
# xcframework owns the speech implementation objects and their static deps.
merge_sherpa_backend_slice() {
    local build_root="$1"
    local slice_dir="$2"
    local output="$3"
    local arch="$4"
    local scratch_dir="${STAGING_DIR}/prepared/${slice_dir}/sherpa"
    local inputs=(
        "${build_root}/engines/sherpa/${slice_dir}/librac_backend_sherpa.a"
    )
    local sherpa_dir

    if [ "${slice_dir}" = "Release-iphoneos" ]; then
        sherpa_dir="${REPO_ROOT}/sdk/runanywhere-commons/third_party/sherpa-onnx-ios/sherpa-onnx.xcframework/ios-arm64"
    else
        sherpa_dir="${REPO_ROOT}/sdk/runanywhere-commons/third_party/sherpa-onnx-ios/sherpa-onnx.xcframework/ios-arm64_x86_64-simulator"
    fi

    if [ "${DRY_RUN}" = "1" ] || [ -d "${sherpa_dir}" ]; then
        local sherpa_archive
        for sherpa_archive in "${sherpa_dir}"/*.a; do
            if [ "${DRY_RUN}" = "1" ] || [ -f "${sherpa_archive}" ]; then
                inputs+=("${sherpa_archive}")
            fi
        done
    fi

    local prepared=()
    local input
    for input in "${inputs[@]}"; do
        prepared+=("$(prepare_archive_input "${input}" "${arch}" "${scratch_dir}")")
    done

    merge_static_archives "${output}" "${prepared[@]}"
}

merge_sherpa_backend_macos_slice() {
    local build_root="$1"
    local output="$2"
    local arch="$3"
    local scratch_dir="${STAGING_DIR}/prepared/Release-macos/sherpa"
    local inputs=(
        "${build_root}/engines/sherpa/librac_backend_sherpa.a"
        "${MACOS_SHERPA_STATIC_DEPS[@]}"
    )

    local prepared=()
    local input
    for input in "${inputs[@]}"; do
        prepared+=("$(prepare_archive_input "${input}" "${arch}" "${scratch_dir}")")
    done

    merge_static_archives "${output}" "${prepared[@]}"
}

merge_mlx_backend_slice() {
    local build_root="$1"
    local slice_dir="$2"
    local output="$3"
    local arch="$4"
    local scratch_dir="${STAGING_DIR}/prepared/${slice_dir}/mlx"
    local inputs=(
        "${build_root}/engines/mlx/${slice_dir}/librac_backend_mlx.a"
    )

    local prepared=()
    local input
    for input in "${inputs[@]}"; do
        prepared+=("$(prepare_archive_input "${input}" "${arch}" "${scratch_dir}")")
    done

    merge_static_archives "${output}" "${prepared[@]}"
}

merge_mlx_backend_macos_slice() {
    local build_root="$1"
    local output="$2"
    local arch="$3"
    local scratch_dir="${STAGING_DIR}/prepared/Release-macos/mlx"
    local inputs=(
        "${build_root}/engines/mlx/librac_backend_mlx.a"
    )

    local prepared=()
    local input
    for input in "${inputs[@]}"; do
        prepared+=("$(prepare_archive_input "${input}" "${arch}" "${scratch_dir}")")
    done

    merge_static_archives "${output}" "${prepared[@]}"
}

# CoreML engine slice (Apple Stable-Diffusion pipeline). Fold in the
# rac_runtime_coreml archive because the coreml engine links it (Pattern 3:
# "engine IS our code on a device-runtime") and it is NOT folded into
# rac_commons — mirrors how the ONNX slice folds in librac_runtime_onnxrt.a.
# Both are first-party archives (system frameworks only, no third-party host
# paths), so no path sanitization is required. This keeps
# RABackendCoreML.xcframework self-contained.
merge_coreml_backend_slice() {
    local build_root="$1"
    local slice_dir="$2"
    local output="$3"
    local arch="$4"
    local scratch_dir="${STAGING_DIR}/prepared/${slice_dir}/coreml"
    local inputs=(
        "${build_root}/engines/coreml/${slice_dir}/librac_backend_coreml.a"
        "${build_root}/runtimes/coreml/${slice_dir}/librac_runtime_coreml.a"
    )

    local prepared=()
    local input
    for input in "${inputs[@]}"; do
        prepared+=("$(prepare_archive_input "${input}" "${arch}" "${scratch_dir}")")
    done

    merge_static_archives "${output}" "${prepared[@]}"
}

merge_coreml_backend_macos_slice() {
    local build_root="$1"
    local output="$2"
    local arch="$3"
    local scratch_dir="${STAGING_DIR}/prepared/Release-macos/coreml"
    local inputs=(
        "${build_root}/engines/coreml/librac_backend_coreml.a"
        "${build_root}/runtimes/coreml/librac_runtime_coreml.a"
    )

    local prepared=()
    local input
    for input in "${inputs[@]}"; do
        prepared+=("$(prepare_archive_input "${input}" "${arch}" "${scratch_dir}")")
    done

    merge_static_archives "${output}" "${prepared[@]}"
}

# ────────────────────────────────────────────────────────────────────────────
# Prereq: the iOS ONNX Runtime xcframework. Only when ONNX is enabled.
# ────────────────────────────────────────────────────────────────────────────
IOS_ONNXRT="${REPO_ROOT}/sdk/runanywhere-commons/third_party/onnxruntime-ios/onnxruntime.xcframework"
if [ "${RAC_BACKEND_ONNX}" = "ON" ] && [ ! -d "${IOS_ONNXRT}" ] && [ "${DRY_RUN}" != "1" ]; then
    cat >&2 <<EOF
error: ONNX Runtime iOS xcframework not found at
  ${IOS_ONNXRT}

Run this first (one-time, per checkout):
  ./sdk/runanywhere-commons/scripts/ios/download-onnx.sh

Or re-run with RAC_BACKEND_ONNX=OFF to skip the ONNX backend entirely.
EOF
    exit 1
fi

# ────────────────────────────────────────────────────────────────────────────
# Prereq: the iOS Sherpa-ONNX xcframework. The Swift package always ships the
# Sherpa backend. Without it, engines/sherpa's CMake gate sets
# SHERPA_ONNX_AVAILABLE=0 → RAC_SHERPA_ROUTABLE=0, which strips
# stt_ops/tts_ops/vad_ops from the sherpa plugin vtable. The xcframework
# still ships, but every STT/TTS/VAD load with `framework=sherpa` hits the
# "no backend route supports requested model" router rejection (FIXLOOP-TR-1).
# ────────────────────────────────────────────────────────────────────────────
IOS_SHERPA="${REPO_ROOT}/sdk/runanywhere-commons/third_party/sherpa-onnx-ios/sherpa-onnx.xcframework"
if [ "${RAC_BACKEND_SHERPA}" = "ON" ] && [ ! -d "${IOS_SHERPA}" ] && [ "${DRY_RUN}" != "1" ]; then
    cat >&2 <<EOF
error: Sherpa-ONNX iOS xcframework not found at
  ${IOS_SHERPA}

Run this first (one-time, per checkout):
  ./sdk/runanywhere-commons/scripts/ios/download-sherpa-onnx.sh

EOF
    exit 1
fi

# The macOS ONNX and Sherpa slices are fully static. Both consume the pinned
# inventory produced from the exact SHERPA_ONNX_COMMIT_MACOS revision; the
# ONNX slice folds in libonnxruntime.a and the Sherpa slice folds in the speech
# archives. Enumerate the contract instead of globbing so an incomplete
# download/build cannot produce an apparently valid but link-broken release.
MACOS_SHERPA_ROOT="${REPO_ROOT}/sdk/runanywhere-commons/third_party/sherpa-onnx-macos"
MACOS_SHERPA_STATIC_DEPS=(
    "${MACOS_SHERPA_ROOT}/lib/libsherpa-onnx-c-api.a"
    "${MACOS_SHERPA_ROOT}/lib/libsherpa-onnx-core.a"
    "${MACOS_SHERPA_ROOT}/lib/libsherpa-onnx-fst.a"
    "${MACOS_SHERPA_ROOT}/lib/libsherpa-onnx-fstfar.a"
    "${MACOS_SHERPA_ROOT}/lib/libsherpa-onnx-kaldifst-core.a"
    "${MACOS_SHERPA_ROOT}/lib/libkaldi-decoder-core.a"
    "${MACOS_SHERPA_ROOT}/lib/libkaldi-native-fbank-core.a"
    "${MACOS_SHERPA_ROOT}/lib/libpiper_phonemize.a"
    "${MACOS_SHERPA_ROOT}/lib/libespeak-ng.a"
    "${MACOS_SHERPA_ROOT}/lib/libucd.a"
    "${MACOS_SHERPA_ROOT}/lib/libssentencepiece_core.a"
    "${MACOS_SHERPA_ROOT}/lib/libkissfft-float.a"
)
if [ "${RAC_BACKEND_ONNX}" = "ON" ] && [ "${DRY_RUN}" != "1" ]; then
    macos_required=(
        "${MACOS_SHERPA_ROOT}/lib/libonnxruntime.a"
        "${MACOS_SHERPA_ROOT}/include/onnxruntime_c_api.h"
        "${MACOS_SHERPA_ROOT}/include/onnxruntime_cxx_api.h"
        "${MACOS_SHERPA_ROOT}/include/sherpa-onnx/c-api/c-api.h"
        "${MACOS_SHERPA_STATIC_DEPS[@]}"
    )
    for required in "${macos_required[@]}"; do
        if [ ! -f "${required}" ]; then
            echo "error: required pinned macOS static dependency not found: ${required}" >&2
            echo "       Run ./sdk/runanywhere-commons/scripts/macos/download-sherpa-onnx.sh" >&2
            exit 1
        fi
        if [[ "${required}" == *.a ]] && ! xcrun lipo "${required}" -verify_arch arm64 >/dev/null 2>&1; then
            echo "error: required macOS archive is not arm64: ${required}" >&2
            exit 1
        fi
    done
fi

mkdir -p "${DEST}"
run rm -rf "${STAGING_DIR}"
run mkdir -p "${STAGING_DIR}"

# ────────────────────────────────────────────────────────────────────────────
# 1 & 2. Configure + build iOS slices (device + simulator) and matching
#        macOS slices for every advertised Swift binary target.
# ────────────────────────────────────────────────────────────────────────────
cmake_extra=(
    "-DCMAKE_C_FLAGS=-ffile-prefix-map=${REPO_ROOT}=/runanywhere-sdks -fmacro-prefix-map=${REPO_ROOT}=/runanywhere-sdks -fdebug-prefix-map=${REPO_ROOT}=/runanywhere-sdks"
    "-DCMAKE_CXX_FLAGS=-ffile-prefix-map=${REPO_ROOT}=/runanywhere-sdks -fmacro-prefix-map=${REPO_ROOT}=/runanywhere-sdks -fdebug-prefix-map=${REPO_ROOT}=/runanywhere-sdks"
    "-DCMAKE_OBJC_FLAGS=-ffile-prefix-map=${REPO_ROOT}=/runanywhere-sdks -fmacro-prefix-map=${REPO_ROOT}=/runanywhere-sdks -fdebug-prefix-map=${REPO_ROOT}=/runanywhere-sdks"
    "-DCMAKE_OBJCXX_FLAGS=-ffile-prefix-map=${REPO_ROOT}=/runanywhere-sdks -fmacro-prefix-map=${REPO_ROOT}=/runanywhere-sdks -fdebug-prefix-map=${REPO_ROOT}=/runanywhere-sdks"
    "-DRAC_ENABLE_PROTOBUF=ON"
    "-DRAC_INCLUDE_LOCAL_DEV_CONFIG=OFF"
    "-DRAC_ENABLE_SOLUTIONS=${RAC_ENABLE_SOLUTIONS:-ON}"
    "-DRAC_VENDOR_PROTOBUF=ON"
    "-DCMAKE_DISABLE_FIND_PACKAGE_Protobuf=TRUE"
    "-DCMAKE_DISABLE_FIND_PACKAGE_absl=TRUE"
    "-Dprotobuf_FORCE_FETCH_DEPENDENCIES=ON"
    # Force the complete requested engine set on every configure. These preset
    # build directories are intentionally reusable, so relying on option
    # defaults can otherwise preserve an earlier OFF cache entry while the
    # packaging phase still expects the corresponding archive.
    "-DRAC_BUILD_BACKENDS=ON"
    "-DRAC_BACKEND_CLOUD=ON"
    "-DRAC_BACKEND_RAG=ON"
    "-DRAC_BACKEND_LLAMACPP=ON"
    "-DRAC_BACKEND_ONNX=${RAC_BACKEND_ONNX}"
    "-DRAC_RUNTIME_ONNXRT=${RAC_BACKEND_ONNX}"
    "-DRAC_BACKEND_SHERPA=${RAC_BACKEND_SHERPA}"
    "-DRAC_BACKEND_MLX=${RAC_BACKEND_MLX}"
)
ios_cmake_extra=(
    "-DRAC_BACKEND_COREML=${RAC_BACKEND_COREML}"
    "-DRAC_RUNTIME_COREML=${RAC_BACKEND_COREML}"
    "-DGGML_NATIVE=OFF"
    "-DCMAKE_OSX_DEPLOYMENT_TARGET=${IOS_DEPLOYMENT_TARGET}"
)
echo "▶ Configure ios-device"
run cmake --preset ios-device "${cmake_extra[@]}" "${ios_cmake_extra[@]}"
echo "▶ Build ios-device (Release)"
ios_build_targets=(rac_commons rac_backend_llamacpp)
if [ "${RAC_BACKEND_ONNX}" = "ON" ]; then
    ios_build_targets+=(rac_backend_onnx)
fi
if [ "${RAC_BACKEND_SHERPA}" = "ON" ]; then
    ios_build_targets+=(rac_backend_sherpa)
fi
# CoreML engine (Stable Diffusion) is Apple-only. Building rac_backend_coreml
# also transitively builds its rac_runtime_coreml dependency; both are folded
# into RABackendCoreML.xcframework below.
if [ "${RAC_BACKEND_COREML}" = "ON" ]; then
    ios_build_targets+=(rac_backend_coreml)
fi
if [ "${RAC_BACKEND_MLX}" = "ON" ]; then
    ios_build_targets+=(rac_backend_mlx)
fi
run cmake --build --preset ios-device --config Release --target "${ios_build_targets[@]}" --parallel "${BUILD_JOBS}"

echo "▶ Configure ios-simulator"
run cmake --preset ios-simulator "${cmake_extra[@]}" "${ios_cmake_extra[@]}"
echo "▶ Build ios-simulator (Release)"
run cmake --build --preset ios-simulator --config Release --target "${ios_build_targets[@]}" --parallel "${BUILD_JOBS}"

echo "▶ Configure macos-release"
macos_cmake_args=(
    "-DCMAKE_C_FLAGS=-ffile-prefix-map=${REPO_ROOT}=/runanywhere-sdks -fmacro-prefix-map=${REPO_ROOT}=/runanywhere-sdks -fdebug-prefix-map=${REPO_ROOT}=/runanywhere-sdks"
    "-DCMAKE_CXX_FLAGS=-ffile-prefix-map=${REPO_ROOT}=/runanywhere-sdks -fmacro-prefix-map=${REPO_ROOT}=/runanywhere-sdks -fdebug-prefix-map=${REPO_ROOT}=/runanywhere-sdks"
    "-DCMAKE_OBJC_FLAGS=-ffile-prefix-map=${REPO_ROOT}=/runanywhere-sdks -fmacro-prefix-map=${REPO_ROOT}=/runanywhere-sdks -fdebug-prefix-map=${REPO_ROOT}=/runanywhere-sdks"
    "-DCMAKE_OBJCXX_FLAGS=-ffile-prefix-map=${REPO_ROOT}=/runanywhere-sdks -fmacro-prefix-map=${REPO_ROOT}=/runanywhere-sdks -fdebug-prefix-map=${REPO_ROOT}=/runanywhere-sdks"
    "-DRAC_BUILD_BACKENDS=ON"
    # The macOS slice ships inside the XCFramework and is linked statically by
    # SPM consumers (swift test, macOS apps) — there is no sibling shared-lib
    # loading there, so in-tree engines (e.g. cloud) must fold into
    # rac_commons exactly like the iOS slices, or unconditionally-referenced
    # symbols (rac_backend_cloud_register) fail the consumer link.
    "-DRAC_STATIC_PLUGINS=ON"
    "-DRAC_BACKEND_CLOUD=ON"
    "-DRAC_BACKEND_RAG=ON"
    "-DRAC_BACKEND_LLAMACPP=ON"
    "-DRAC_BACKEND_ONNX=${RAC_BACKEND_ONNX}"
    # Reset runtime state alongside its owning backend. A polluted reusable
    # cache can otherwise leave the runtime and engine in contradictory states.
    "-DRAC_RUNTIME_ONNXRT=${RAC_BACKEND_ONNX}"
    "-DRAC_RUNTIME_COREML=${RAC_BACKEND_COREML}"
    "-DRAC_BACKEND_SHERPA=${RAC_BACKEND_SHERPA}"
    "-DRAC_BACKEND_COREML=${RAC_BACKEND_COREML}"
    "-DRAC_BACKEND_MLX=${RAC_BACKEND_MLX}"
    "-DGGML_NATIVE=OFF"
    "-DCMAKE_DISABLE_FIND_PACKAGE_Protobuf=TRUE"
    "-DCMAKE_DISABLE_FIND_PACKAGE_absl=TRUE"
    "-DCMAKE_OSX_ARCHITECTURES=arm64"
    "-DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOS_DEPLOYMENT_TARGET}"
    "-DRAC_ENABLE_PROTOBUF=ON"
    "-DRAC_ENABLE_SOLUTIONS=${RAC_ENABLE_SOLUTIONS:-ON}"
    "-DRAC_VENDOR_PROTOBUF=ON"
    "-Dprotobuf_FORCE_FETCH_DEPENDENCIES=ON"
)
run cmake --preset macos-release "${macos_cmake_args[@]}"
echo "▶ Build macos-release"
macos_build_targets=(rac_commons rac_backend_llamacpp)
if [ "${RAC_BACKEND_ONNX}" = "ON" ]; then
    macos_build_targets+=(rac_backend_onnx)
fi
if [ "${RAC_BACKEND_SHERPA}" = "ON" ]; then
    macos_build_targets+=(rac_backend_sherpa)
fi
# CoreML engine (Stable Diffusion) pulls in rac_runtime_coreml transitively.
if [ "${RAC_BACKEND_COREML}" = "ON" ]; then
    macos_build_targets+=(rac_backend_coreml)
fi
if [ "${RAC_BACKEND_MLX}" = "ON" ]; then
    macos_build_targets+=(rac_backend_mlx)
fi
run cmake --build --preset macos-release --target "${macos_build_targets[@]}" --parallel "${BUILD_JOBS}"

# ────────────────────────────────────────────────────────────────────────────
# 3. Locate archives and package each target as an xcframework with both
#    device + simulator slices.
#
# Under the Xcode generator, static-library targets land at
#   ${CMAKE_BINARY_DIR}/<source-subdir>/Release-iphoneos/lib<target>.a
# and
#   ${CMAKE_BINARY_DIR}/<source-subdir>/Release-iphonesimulator/lib<target>.a
# ────────────────────────────────────────────────────────────────────────────
DEV_BIN="${REPO_ROOT}/build/ios-device"
SIM_BIN="${REPO_ROOT}/build/ios-simulator"
MAC_BIN="${REPO_ROOT}/build/macos-release"

# find_lib <subdir-under-bin> <libname>
find_lib() {
    local dev_path="${DEV_BIN}/$1/Release-iphoneos/$2"
    local sim_path="${SIM_BIN}/$1/Release-iphonesimulator/$2"
    if [ "${DRY_RUN}" = "1" ]; then
        # In dry-run mode the files don't exist; emit placeholders so
        # downstream `run xcodebuild -create-xcframework` still prints
        # something meaningful.
        echo "${dev_path}|${sim_path}"
        return
    fi
    if [ ! -f "${dev_path}" ]; then
        echo "error: expected device archive not found: ${dev_path}" >&2
        exit 1
    fi
    if [ ! -f "${sim_path}" ]; then
        echo "error: expected simulator archive not found: ${sim_path}" >&2
        exit 1
    fi
    echo "${dev_path}|${sim_path}"
}

# build_xcframework_from_paths <device-lib> <simulator-lib> <xcframework-name> [--with-headers]
#
# Only the first (RACommons) xcframework ships the commons C header tree via
# `-headers`. Backend xcframeworks share the same canonical commons headers,
# but bundling the same tree into every `.xcframework`'s `Headers/` directory
# causes `error: Multiple commands produce .../include/rac/.../*.h` when Xcode's
# SPM binary-target integration processes all three bundles in the same build
# graph. Downstream Swift modules import the commons headers via
# `RACommonsBinary` anyway, so the backend xcframeworks only need to carry
# their `.a` archives — the headers come from RACommons.xcframework.
build_xcframework_from_paths() {
    local dev_lib="$1"
    local sim_lib="$2"
    local xcf_name="$3"
    local mode="${4:-}"

    local xcf="${DEST}/${xcf_name}"
    echo "▶ Create-xcframework → ${xcf}"
    run rm -rf "${xcf}"
    if [ "${mode}" = "--with-headers" ]; then
        run xcodebuild -create-xcframework \
            -library "${dev_lib}" -headers "${COMMONS_HEADERS}" \
            -library "${sim_lib}" -headers "${COMMONS_HEADERS}" \
            -output  "${xcf}"
    else
        run xcodebuild -create-xcframework \
            -library "${dev_lib}" \
            -library "${sim_lib}" \
            -output  "${xcf}"
    fi
    run normalize_xcframework_info_plist "${xcf}"
}

# build_xcframework_from_paths_with_macos <device-lib> <simulator-lib> <macos-lib> <xcframework-name> [--with-headers]
build_xcframework_from_paths_with_macos() {
    local dev_lib="$1"
    local sim_lib="$2"
    local mac_lib="$3"
    local xcf_name="$4"
    local mode="${5:-}"

    local xcf="${DEST}/${xcf_name}"
    echo "▶ Create-xcframework → ${xcf}"
    run rm -rf "${xcf}"
    if [ "${mode}" = "--with-headers" ]; then
        run xcodebuild -create-xcframework \
            -library "${dev_lib}" -headers "${COMMONS_HEADERS}" \
            -library "${sim_lib}" -headers "${COMMONS_HEADERS}" \
            -library "${mac_lib}" -headers "${COMMONS_HEADERS}" \
            -output  "${xcf}"
    else
        run xcodebuild -create-xcframework \
            -library "${dev_lib}" \
            -library "${sim_lib}" \
            -library "${mac_lib}" \
            -output  "${xcf}"
    fi
    run normalize_xcframework_info_plist "${xcf}"
}

# The C++ RABackendMLX archive is only the callback/plugin shell. Flutter and
# React Native CocoaPods consumers also need the canonical Swift MLXRuntime
# implementation and its upstream MLX dependencies. Build that implementation
# as a separate static framework while deliberately omitting RACommons and the
# MLX shell from its archive: final app linking then resolves every rac_* symbol
# against the same process-wide Commons registry used by the core package.
validate_mlx_runtime_archive() {
    local archive="$1"
    local label="$2"
    local metal_bundle="$3"

    if [ "${DRY_RUN}" = "1" ]; then
        return
    fi
    if [ ! -f "${archive}" ]; then
        echo "error: ${label} MLX runtime archive not found: ${archive}" >&2
        exit 1
    fi

    local defined_symbols undefined_symbols archive_members lifecycle_count
    defined_symbols="$(nm -gU "${archive}" 2>/dev/null)"
    undefined_symbols="$(nm -gu "${archive}" 2>/dev/null)"
    archive_members="$(ar -t "${archive}")"
    lifecycle_count="$(grep -Ec \
        ' [TDS] _ra_mlx_(register_runtime|unregister_runtime|runtime_is_registered|runtime_is_available)$' \
        <<< "${defined_symbols}" || true)"
    if [ "${lifecycle_count}" -ne 4 ]; then
        echo "error: ${label} MLX runtime must define exactly four lifecycle symbols; found ${lifecycle_count}" >&2
        exit 1
    fi

    if grep -Eq ' [TDSB] _rac_' <<< "${defined_symbols}"; then
        echo "error: ${label} MLX runtime embeds rac_* definitions and would create a second Commons registry" >&2
        grep -E ' [TDSB] _rac_' <<< "${defined_symbols}" | head -20 >&2
        exit 1
    fi

    local required_undefined=(_ra_mlx_metal_resource_anchor)
    if [ "${label}" = "ios-device" ]; then
        required_undefined+=(
            _ra_mlx_set_clear_cancel_callback
            _rac_backend_mlx_register
            _rac_backend_mlx_unregister
            _rac_error_message
            _rac_mlx_set_callbacks
        )
    fi
    local symbol
    for symbol in "${required_undefined[@]}"; do
        if ! grep -Fxq "${symbol}" <<< "${undefined_symbols}"; then
            echo "error: ${label} MLX runtime must leave ${symbol} unresolved for its peer artifact" >&2
            exit 1
        fi
    done

    if [ "${label}" = "ios-simulator" ]; then
        local forbidden_simulator_undefined=(
            _ra_mlx_set_clear_cancel_callback
            _rac_backend_mlx_register
            _rac_mlx_set_callbacks
        )
        for symbol in "${forbidden_simulator_undefined[@]}"; do
            if grep -Fxq "${symbol}" <<< "${undefined_symbols}"; then
                echo "error: ${label} MLX runtime unexpectedly retains registration-path symbol ${symbol}" >&2
                exit 1
            fi
        done
    fi

    if grep -Eq 'rac_mlx_engine|rac_backend_mlx_register|rac_static_register_mlx' \
        <<< "${archive_members}"; then
        echo "error: ${label} MLX runtime contains the separately-distributed C++ MLX shell" >&2
        exit 1
    fi

    python3 - "${archive}" "${label}" "${metal_bundle}" <<'PY'
from pathlib import Path
import sys

archive = Path(sys.argv[1])
label = sys.argv[2]
bundle_id = sys.argv[3].encode()
payload = archive.read_bytes()

if payload.count(bundle_id) != 1:
    raise SystemExit(
        f"error: {label} MLX runtime expected one {bundle_id.decode()!r} bundle lookup, "
        f"found {payload.count(bundle_id)}"
    )

for marker in (
    b"/Users/",
    b"/home/",
    b"/tmp/runanywhere-mlx-runtime-",
    b"/var/folders/",
    b"\\Users\\",
):
    if marker in payload:
        raise SystemExit(
            f"error: {label} MLX runtime contains host path marker {marker.decode(errors='replace')!r}"
        )
PY
}

sanitize_mlx_runtime_generated_paths() {
    local archive="$1"
    local scratch="$2"
    if [ "${DRY_RUN}" = "1" ]; then
        return
    fi

    # SwiftPM-generated Bundle.module accessors embed their build fallback as
    # a string literal, so compiler prefix maps cannot rewrite it. The release
    # scratch root is intentionally fixed under /tmp; replace only that exact
    # generated accessor prefix, never arbitrary `/tmp/` literals that an
    # upstream dependency may legitimately use at runtime. `/src` and `/tmp`
    # are equal length, so the archive layout remains intact. Runtime lookup
    # uses Bundle.main and never depends on this build-machine fallback.
    python3 - "${archive}" "${scratch}" <<'PY'
from pathlib import Path
import sys

archive = Path(sys.argv[1])
scratch = sys.argv[2]
payload = archive.read_bytes()
source = scratch.encode()
if not source.startswith(b"/tmp/runanywhere-mlx-runtime-"):
    raise SystemExit(f"error: unexpected MLX release scratch path: {scratch}")
replacement = b"/src" + source[len(b"/tmp"):]
if len(source) != len(replacement):
    raise SystemExit("error: sanitized MLX scratch prefix must preserve byte length")
count = payload.count(source)
if count == 0:
    raise SystemExit(f"error: expected generated SwiftPM scratch paths in {archive}: {scratch}")
archive.write_bytes(payload.replace(source, replacement))
PY
}

validate_mlx_runtime_payload_host_paths() {
    local payload="$1"
    local label="$2"
    if [ "${DRY_RUN}" = "1" ]; then
        return
    fi

    python3 - "${payload}" "${label}" <<'PY'
from pathlib import Path
import sys

payload = Path(sys.argv[1])
label = sys.argv[2]
data = payload.read_bytes()
for marker in (b"/Users/", b"/home/", b"/var/folders/", b"\\Users\\"):
    if marker in data:
        raise SystemExit(
            f"error: {label} contains host path marker {marker.decode(errors='replace')!r}"
        )
PY
}

build_mlx_runtime_swift_slice() {
    local label="$1"
    local triple="$2"
    local sdk_name="$3"
    local metal_bundle="$4"
    local scratch="$5"
    local built_archive="$6"
    local staged_archive="$7"
    local sdk_path
    sdk_path="$(xcrun --sdk "${sdk_name}" --show-sdk-path)"

    local canonical_build_root="/runanywhere/build/mlx-runtime"
    local canonical_source_root="/runanywhere/source"
    local prefix_flags=(
        -Xswiftc -debug-prefix-map -Xswiftc "${scratch}=${canonical_build_root}"
        -Xswiftc -file-prefix-map -Xswiftc "${scratch}=${canonical_build_root}"
        -Xswiftc -debug-prefix-map -Xswiftc "${REPO_ROOT}=${canonical_source_root}"
        -Xswiftc -file-prefix-map -Xswiftc "${REPO_ROOT}=${canonical_source_root}"
        -Xcc "-ffile-prefix-map=${scratch}=${canonical_build_root}"
        -Xcc "-fdebug-prefix-map=${scratch}=${canonical_build_root}"
        -Xcc "-fmacro-prefix-map=${scratch}=${canonical_build_root}"
        -Xcc "-ffile-prefix-map=${REPO_ROOT}=${canonical_source_root}"
        -Xcc "-fdebug-prefix-map=${REPO_ROOT}=${canonical_source_root}"
        -Xcc "-fmacro-prefix-map=${REPO_ROOT}=${canonical_source_root}"
        -Xcxx "-ffile-prefix-map=${scratch}=${canonical_build_root}"
        -Xcxx "-fdebug-prefix-map=${scratch}=${canonical_build_root}"
        -Xcxx "-fmacro-prefix-map=${scratch}=${canonical_build_root}"
        -Xcxx "-ffile-prefix-map=${REPO_ROOT}=${canonical_source_root}"
        -Xcxx "-fdebug-prefix-map=${REPO_ROOT}=${canonical_source_root}"
        -Xcxx "-fmacro-prefix-map=${REPO_ROOT}=${canonical_source_root}"
        -Xcxx -USWIFTPM_BUNDLE
        -Xcxx "-DSWIFTPM_BUNDLE=\"${metal_bundle}\""
    )

    echo "▶ Build ${label} canonical Swift MLX runtime"
    run rm -rf "${scratch}"
    run env \
        RUNANYWHERE_BUILD_MLX_DISTRIBUTION_FRAMEWORK=1 \
        RUNANYWHERE_USE_LOCAL_NATIVES=1 \
        swift build \
        --package-path "${REPO_ROOT}" \
        --configuration release \
        --product RunAnywhereMLXRuntime \
        --jobs "${BUILD_JOBS}" \
        --triple "${triple}" \
        --sdk "${sdk_path}" \
        --scratch-path "${scratch}" \
        "${prefix_flags[@]}"

    run mkdir -p "$(dirname "${staged_archive}")"
    run cp "${built_archive}" "${staged_archive}"
    run /usr/bin/strip -S "${staged_archive}"
    sanitize_mlx_runtime_generated_paths "${staged_archive}" "${scratch}"
    validate_mlx_runtime_archive "${staged_archive}" "${label}" "${metal_bundle}"
}

assemble_mlx_runtime_framework() {
    local archive="$1"
    local plist="$2"
    local framework="$3"

    run rm -rf "${framework}"
    run mkdir -p "${framework}/Headers" "${framework}/Modules"
    run cp "${archive}" "${framework}/RunAnywhereMLXRuntime"
    run cp "${MLX_RUNTIME_SOURCE}/include/RunAnywhereMLXRuntime.h" "${framework}/Headers/"
    run cp "${MLX_RUNTIME_SOURCE}/include/module.modulemap" "${framework}/Modules/"
    run cp "${plist}" "${framework}/Info.plist"
}

build_mlx_metal_framework() {
    local label="$1"
    local triple="$2"
    local sdk_name="$3"
    local metallib="$4"
    local plist="$5"
    local framework="$6"
    local sdk_path
    sdk_path="$(xcrun --sdk "${sdk_name}" --show-sdk-path)"

    run rm -rf "${framework}"
    run mkdir -p "${framework}/Headers" "${framework}/Modules"
    run xcrun --sdk "${sdk_name}" clang \
        -target "${triple}" \
        -isysroot "${sdk_path}" \
        -fobjc-arc \
        -fapplication-extension \
        -dynamiclib \
        -framework Foundation \
        -install_name @rpath/RunAnywhereMLXMetal.framework/RunAnywhereMLXMetal \
        -compatibility_version 1.0 \
        -current_version 1.0 \
        "${MLX_RUNTIME_SOURCE}/RunAnywhereMLXMetal.m" \
        -I "${MLX_RUNTIME_SOURCE}/Metal/include" \
        -o "${framework}/RunAnywhereMLXMetal"
    run /usr/bin/strip -S "${framework}/RunAnywhereMLXMetal"
    run cp "${MLX_RUNTIME_SOURCE}/Metal/include/RunAnywhereMLXMetal.h" "${framework}/Headers/"
    run cp "${MLX_RUNTIME_SOURCE}/Metal/include/module.modulemap" \
        "${framework}/Modules/module.modulemap"
    run cp "${metallib}" "${framework}/default.metallib"
    run cp "${plist}" "${framework}/Info.plist"

    if [ "${DRY_RUN}" != "1" ]; then
        local metal_symbols metal_load_commands
        metal_symbols="$(nm -gU "${framework}/RunAnywhereMLXMetal" 2>/dev/null)"
        metal_load_commands="$(otool -l "${framework}/RunAnywhereMLXMetal")"
        validate_mlx_runtime_payload_host_paths \
            "${framework}/RunAnywhereMLXMetal" "${label} MLX Metal binary"
        validate_mlx_runtime_payload_host_paths \
            "${framework}/default.metallib" "${label} MLX Metal library"
        if [ "$(grep -Ec ' [TDS] _ra_mlx_metal_resource_anchor$' \
            <<< "${metal_symbols}" || true)" -ne 1 ]; then
            echo "error: ${label} MLX Metal framework must export exactly one resource anchor" >&2
            exit 1
        fi
        if grep -Eq ' [TDSB] _(rac_|ra_mlx_(register|unregister|runtime))' \
            <<< "${metal_symbols}"; then
            echo "error: ${label} MLX Metal framework contains runtime or Commons symbols" >&2
            exit 1
        fi
        if ! grep -Fq 'cmd LC_UUID' <<< "${metal_load_commands}"; then
            echo "error: ${label} MLX Metal framework is missing the LC_UUID required by Xcode embedding" >&2
            exit 1
        fi
    fi
}

stage_mlx_runtime_notices() {
    local checkout_root="$1"
    local notices_dir="$2"

    run rm -rf "${notices_dir}"
    run mkdir -p "${notices_dir}"
    if [ "${DRY_RUN}" = "1" ]; then
        return
    fi

    # SwiftPM resolves the complete manifest graph even when this packaging
    # lane builds one product. Preserve every checkout's top-level license or
    # notice so aggregate-link attribution cannot silently drift when an
    # upstream product adds a transitive dependency.
    local package_dir package_name notice source_name
    for package_dir in "${checkout_root}"/*; do
        [ -d "${package_dir}" ] || continue
        package_name="$(basename "${package_dir}")"
        for notice in "${package_dir}"/LICENSE* "${package_dir}"/NOTICE*; do
            [ -f "${notice}" ] || continue
            source_name="$(basename "${notice}")"
            cp "${notice}" "${notices_dir}/${package_name}-${source_name}"
        done
    done
    if [ -z "$(find "${notices_dir}" -type f -print -quit)" ]; then
        echo "error: no MLX runtime third-party notices were staged" >&2
        exit 1
    fi
}

build_mlx_runtime_xcframework() {
    local device_scratch="/tmp/runanywhere-mlx-runtime-device"
    local simulator_scratch="/tmp/runanywhere-mlx-runtime-simulator"
    local device_build_dir="${device_scratch}/arm64-apple-ios/release"
    local simulator_build_dir="${simulator_scratch}/arm64-apple-ios-simulator/release"
    local staging="${MLX_RUNTIME_BUILD_ROOT}/staging"
    local device_archive="${staging}/device/libRunAnywhereMLXRuntime.a"
    local simulator_archive="${staging}/simulator/libRunAnywhereMLXRuntime.a"
    local device_metal_derived="${MLX_RUNTIME_BUILD_ROOT}/metal-device"
    local simulator_metal_derived="${MLX_RUNTIME_BUILD_ROOT}/metal-simulator"
    local mlx_project="${device_scratch}/checkouts/mlx-swift/xcode/MLX.xcodeproj"
    local device_metallib="${device_metal_derived}/Build/Products/Release-iphoneos/Cmlx.framework/default.metallib"
    local simulator_metallib="${simulator_metal_derived}/Build/Products/Release-iphonesimulator/Cmlx.framework/default.metallib"
    local device_framework="${staging}/device/RunAnywhereMLXRuntime.framework"
    local simulator_framework="${staging}/simulator/RunAnywhereMLXRuntime.framework"
    local device_metal_framework="${staging}/metal-device/RunAnywhereMLXMetal.framework"
    local simulator_metal_framework="${staging}/metal-simulator/RunAnywhereMLXMetal.framework"
    local resources="${DEST}/RunAnywhereMLXRuntimeResources"
    local output="${DEST}/RunAnywhereMLXRuntime.xcframework"
    local metal_output="${DEST}/RunAnywhereMLXMetal.xcframework"

    run rm -rf "${MLX_RUNTIME_BUILD_ROOT}"
    build_mlx_runtime_swift_slice \
        ios-device arm64-apple-ios17.5 iphoneos \
        "${MLX_METAL_BUNDLE_ID}" \
        "${device_scratch}" \
        "${device_build_dir}/libRunAnywhereMLXRuntime.a" \
        "${device_archive}"
    build_mlx_runtime_swift_slice \
        ios-simulator arm64-apple-ios17.5-simulator iphonesimulator \
        "${MLX_METAL_BUNDLE_ID}" \
        "${simulator_scratch}" \
        "${simulator_build_dir}/libRunAnywhereMLXRuntime.a" \
        "${simulator_archive}"

    echo "▶ Build MLX device and simulator Metal libraries"
    run xcodebuild -quiet \
        -project "${mlx_project}" \
        -scheme Cmlx \
        -configuration Release \
        -destination generic/platform=iOS \
        -derivedDataPath "${device_metal_derived}" \
        BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
        SKIP_INSTALL=NO \
        CODE_SIGNING_ALLOWED=NO \
        build
    run xcodebuild -quiet \
        -project "${mlx_project}" \
        -scheme Cmlx \
        -configuration Release \
        -sdk iphonesimulator \
        -derivedDataPath "${simulator_metal_derived}" \
        SUPPORTED_PLATFORMS=iphonesimulator \
        ARCHS=arm64 \
        ONLY_ACTIVE_ARCH=YES \
        BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
        SKIP_INSTALL=NO \
        CODE_SIGNING_ALLOWED=NO \
        build

    if [ "${DRY_RUN}" != "1" ]; then
        xcrun metallib --app-store-validate "${device_metallib}"
        xcrun metallib --app-store-validate "${simulator_metallib}"
    fi

    assemble_mlx_runtime_framework \
        "${device_archive}" \
        "${MLX_RUNTIME_SOURCE}/Resources/DeviceInfo.plist" \
        "${device_framework}"
    assemble_mlx_runtime_framework \
        "${simulator_archive}" \
        "${MLX_RUNTIME_SOURCE}/Resources/SimulatorInfo.plist" \
        "${simulator_framework}"

    echo "▶ Create-xcframework → ${output}"
    run rm -rf "${output}"
    run xcodebuild -create-xcframework \
        -framework "${device_framework}" \
        -framework "${simulator_framework}" \
        -output "${output}"
    run normalize_xcframework_info_plist "${output}"

    # Static framework wrappers are not embedded in applications, so their
    # resources would be dropped. Put the platform-specific metallib in a tiny
    # dynamic XCFramework. Xcode selects and embeds exactly one device or
    # simulator slice; Cmlx finds it by CFBundleIdentifier in allFrameworks.
    # The static runtime has a strong undefined reference to its C anchor, so
    # dead-strip cannot discard the resource framework. Swift-generated
    # Bundle.module accessors in swift-crypto and swift-transformers still
    # require their platform-neutral bundles at the application resource root.
    run rm -rf "${resources}"
    run mkdir -p "${resources}"
    run rm -rf "${metal_output}"
    build_mlx_metal_framework \
        ios-device \
        arm64-apple-ios17.5 \
        iphoneos \
        "${device_metallib}" \
        "${MLX_RUNTIME_SOURCE}/Resources/DeviceMetalInfo.plist" \
        "${device_metal_framework}"
    build_mlx_metal_framework \
        ios-simulator \
        arm64-apple-ios17.5-simulator \
        iphonesimulator \
        "${simulator_metallib}" \
        "${MLX_RUNTIME_SOURCE}/Resources/SimulatorMetalInfo.plist" \
        "${simulator_metal_framework}"
    run xcodebuild -create-xcframework \
        -framework "${device_metal_framework}" \
        -framework "${simulator_metal_framework}" \
        -output "${metal_output}"
    run normalize_xcframework_info_plist "${metal_output}"
    run cp -R "${device_build_dir}/swift-crypto_Crypto.bundle" "${resources}/"
    run cp -R "${device_build_dir}/swift-transformers_Hub.bundle" "${resources}/"
    stage_mlx_runtime_notices \
        "${device_scratch}/checkouts" \
        "${resources}/ThirdPartyNotices"

    if [ "${DRY_RUN}" != "1" ]; then
        for identifier in ios-arm64 ios-arm64-simulator; do
            local framework="${output}/${identifier}/RunAnywhereMLXRuntime.framework"
            plutil -lint "${framework}/Info.plist" >/dev/null
        done
        for identifier in ios-arm64 ios-arm64-simulator; do
            local metal_framework="${metal_output}/${identifier}/RunAnywhereMLXMetal.framework"
            [ -f "${metal_framework}/default.metallib" ] || {
                echo "error: MLX Metal ${identifier} is missing default.metallib" >&2
                exit 1
            }
            plutil -lint "${metal_framework}/Info.plist" >/dev/null
        done
    fi
}

COMMONS_DEV_LIB="${STAGING_DIR}/Release-iphoneos/librac_commons.a"
COMMONS_SIM_LIB="${STAGING_DIR}/Release-iphonesimulator/librac_commons.a"
COMMONS_MAC_LIB="${STAGING_DIR}/Release-macos/librac_commons.a"
merge_commons_slice "${DEV_BIN}" "Release-iphoneos" "${COMMONS_DEV_LIB}" "arm64"
merge_commons_slice "${SIM_BIN}" "Release-iphonesimulator" "${COMMONS_SIM_LIB}" "arm64"
merge_commons_macos_slice "${MAC_BIN}" "${COMMONS_MAC_LIB}" "arm64"
# CMake's Xcode generator disambiguates duplicate object basenames with a
# checkout-path-derived digest. Keep the reviewed, pinned collision inventory
# explicit so a new upstream content-addressed member fails closed.
run python3 "${ARCHIVE_MEMBER_NORMALIZER}" "${COMMONS_DEV_LIB}" parser=2
run python3 "${ARCHIVE_MEMBER_NORMALIZER}" "${COMMONS_SIM_LIB}" parser=2
run python3 "${ARCHIVE_MEMBER_NORMALIZER}" "${COMMONS_MAC_LIB}"
sanitize_and_validate_archive_host_paths "${COMMONS_DEV_LIB}" "ios-device RACommons"
sanitize_and_validate_archive_host_paths "${COMMONS_SIM_LIB}" "ios-simulator RACommons"
sanitize_and_validate_archive_host_paths "${COMMONS_MAC_LIB}" "macos RACommons"
validate_isolated_protobuf_archive "${COMMONS_DEV_LIB}" "ios-device"
validate_isolated_protobuf_archive "${COMMONS_SIM_LIB}" "ios-simulator"
validate_isolated_protobuf_archive "${COMMONS_MAC_LIB}" "macos"

LLAMACPP_DEV_LIB="${STAGING_DIR}/Release-iphoneos/librac_backend_llamacpp.a"
LLAMACPP_SIM_LIB="${STAGING_DIR}/Release-iphonesimulator/librac_backend_llamacpp.a"
LLAMACPP_MAC_LIB="${STAGING_DIR}/Release-macos/librac_backend_llamacpp.a"
merge_llamacpp_backend_slice "${DEV_BIN}" "Release-iphoneos" "${LLAMACPP_DEV_LIB}" "arm64"
merge_llamacpp_backend_slice "${SIM_BIN}" "Release-iphonesimulator" "${LLAMACPP_SIM_LIB}" "arm64"
merge_llamacpp_backend_macos_slice "${MAC_BIN}" "${LLAMACPP_MAC_LIB}" "arm64"
LLAMACPP_HASHED_MEMBER_INVENTORY=(
    llama=2 ggml=2 ggml-cpu=2 ggml-metal-device=2 quants=2 repack=2
)
run python3 "${ARCHIVE_MEMBER_NORMALIZER}" "${LLAMACPP_DEV_LIB}" "${LLAMACPP_HASHED_MEMBER_INVENTORY[@]}"
run python3 "${ARCHIVE_MEMBER_NORMALIZER}" "${LLAMACPP_SIM_LIB}" "${LLAMACPP_HASHED_MEMBER_INVENTORY[@]}"
run python3 "${ARCHIVE_MEMBER_NORMALIZER}" "${LLAMACPP_MAC_LIB}"
sanitize_and_validate_archive_host_paths "${LLAMACPP_DEV_LIB}" "ios-device RABackendLLAMACPP"
sanitize_and_validate_archive_host_paths "${LLAMACPP_SIM_LIB}" "ios-simulator RABackendLLAMACPP"
sanitize_and_validate_archive_host_paths "${LLAMACPP_MAC_LIB}" "macos RABackendLLAMACPP"

build_xcframework_from_paths_with_macos "${COMMONS_DEV_LIB}" "${COMMONS_SIM_LIB}" "${COMMONS_MAC_LIB}" "RACommons.xcframework" --with-headers
build_xcframework_from_paths_with_macos "${LLAMACPP_DEV_LIB}" "${LLAMACPP_SIM_LIB}" "${LLAMACPP_MAC_LIB}" "RABackendLLAMACPP.xcframework"
if [ "${RAC_BACKEND_ONNX}" = "ON" ]; then
    ONNX_DEV_LIB="${STAGING_DIR}/Release-iphoneos/librac_backend_onnx.a"
    ONNX_SIM_LIB="${STAGING_DIR}/Release-iphonesimulator/librac_backend_onnx.a"
    ONNX_MAC_LIB="${STAGING_DIR}/Release-macos/librac_backend_onnx.a"
    merge_onnx_backend_slice "${DEV_BIN}" "Release-iphoneos" "${ONNX_DEV_LIB}" "arm64"
    merge_onnx_backend_slice "${SIM_BIN}" "Release-iphonesimulator" "${ONNX_SIM_LIB}" "arm64"
    merge_onnx_backend_macos_slice "${MAC_BIN}" "${ONNX_MAC_LIB}" "arm64"
    run python3 "${ARCHIVE_MEMBER_NORMALIZER}" "${ONNX_DEV_LIB}"
    run python3 "${ARCHIVE_MEMBER_NORMALIZER}" "${ONNX_SIM_LIB}"
    run python3 "${ARCHIVE_MEMBER_NORMALIZER}" "${ONNX_MAC_LIB}"
    sanitize_and_validate_archive_host_paths \
        "${ONNX_DEV_LIB}" "ios-device RABackendONNX" \
        "/Users/runner/work/1/s" "/runanywhere/vendor/rt" 512 \
        "/Users/runner/work/1/b" "/runanywhere/build/ort" 99
    sanitize_and_validate_archive_host_paths \
        "${ONNX_SIM_LIB}" "ios-simulator RABackendONNX" \
        "/Users/runner/work/1/s" "/runanywhere/vendor/rt" 512 \
        "/Users/runner/work/1/b" "/runanywhere/build/ort" 99
    sanitize_and_validate_archive_host_paths \
        "${ONNX_MAC_LIB}" "macos RABackendONNX" \
        "/Users/runner/work/onnxruntime-build/onnxruntime-build" \
        "/runanywhere/vendor/onnxruntime/source/build/checkout0" 1632
    build_xcframework_from_paths_with_macos "${ONNX_DEV_LIB}" "${ONNX_SIM_LIB}" "${ONNX_MAC_LIB}" "RABackendONNX.xcframework"
else
    run rm -rf "${DEST}/RABackendONNX.xcframework"
    echo "▶ Skipping RABackendONNX.xcframework (RAC_BACKEND_ONNX=OFF)"
fi

# RABackendSherpa.xcframework as the speech peer of RABackendONNX.
if [ "${RAC_BACKEND_SHERPA}" = "ON" ]; then
    SHERPA_DEV_LIB="${STAGING_DIR}/Release-iphoneos/librac_backend_sherpa.a"
    SHERPA_SIM_LIB="${STAGING_DIR}/Release-iphonesimulator/librac_backend_sherpa.a"
    SHERPA_MAC_LIB="${STAGING_DIR}/Release-macos/librac_backend_sherpa.a"
    if [ "${DRY_RUN}" = "1" ] || [ -f "${DEV_BIN}/engines/sherpa/Release-iphoneos/librac_backend_sherpa.a" ]; then
        merge_sherpa_backend_slice "${DEV_BIN}" "Release-iphoneos" "${SHERPA_DEV_LIB}" "arm64"
        merge_sherpa_backend_slice "${SIM_BIN}" "Release-iphonesimulator" "${SHERPA_SIM_LIB}" "arm64"
        merge_sherpa_backend_macos_slice "${MAC_BIN}" "${SHERPA_MAC_LIB}" "arm64"
        run python3 "${ARCHIVE_MEMBER_NORMALIZER}" "${SHERPA_DEV_LIB}"
        run python3 "${ARCHIVE_MEMBER_NORMALIZER}" "${SHERPA_SIM_LIB}"
        run python3 "${ARCHIVE_MEMBER_NORMALIZER}" "${SHERPA_MAC_LIB}"
        sanitize_and_validate_archive_host_paths \
            "${SHERPA_DEV_LIB}" "ios-device RABackendSherpa" \
            "/Users/runner/work/sherpa-onnx/sherpa-onnx" \
            "/runanywhere/vendor/sherpa-onnx/src/source" 274
        sanitize_and_validate_archive_host_paths \
            "${SHERPA_SIM_LIB}" "ios-simulator RABackendSherpa" \
            "/Users/runner/work/sherpa-onnx/sherpa-onnx" \
            "/runanywhere/vendor/sherpa-onnx/src/source" 274
        sanitize_and_validate_archive_host_paths \
            "${SHERPA_MAC_LIB}" "macos RABackendSherpa"
        build_xcframework_from_paths_with_macos "${SHERPA_DEV_LIB}" "${SHERPA_SIM_LIB}" "${SHERPA_MAC_LIB}" "RABackendSherpa.xcframework"
    else
        echo "error: required Sherpa backend archive was not built" >&2
        exit 1
    fi
else
    echo "▶ Skipping RABackendSherpa.xcframework (RAC_BACKEND_SHERPA=OFF)"
fi

# RABackendCoreML.xcframework — the Apple-only CoreML Stable-Diffusion engine
# (serves the DIFFUSION primitive at priority 100). Apple-only and always ON in
# this build (RAC_BACKEND_COREML forced ON in ios_cmake_extra / macos_cmake_args
# above). The Swift ONNXRuntime target links this archive so the diffusion
# vtable is present in the plugin registry; commons' RAC_STATIC_PLUGIN_REGISTER
# (coreml) shim (compiled into rac_commons) references rac_plugin_entry_coreml,
# pulling the archive at the final link. Folds in librac_runtime_coreml.a.
if [ "${RAC_BACKEND_COREML}" = "ON" ]; then
    COREML_DEV_LIB="${STAGING_DIR}/Release-iphoneos/librac_backend_coreml.a"
    COREML_SIM_LIB="${STAGING_DIR}/Release-iphonesimulator/librac_backend_coreml.a"
    COREML_MAC_LIB="${STAGING_DIR}/Release-macos/librac_backend_coreml.a"
    if [ "${DRY_RUN}" = "1" ] || [ -f "${DEV_BIN}/engines/coreml/Release-iphoneos/librac_backend_coreml.a" ]; then
        merge_coreml_backend_slice "${DEV_BIN}" "Release-iphoneos" "${COREML_DEV_LIB}" "arm64"
        merge_coreml_backend_slice "${SIM_BIN}" "Release-iphonesimulator" "${COREML_SIM_LIB}" "arm64"
        merge_coreml_backend_macos_slice "${MAC_BIN}" "${COREML_MAC_LIB}" "arm64"
        run python3 "${ARCHIVE_MEMBER_NORMALIZER}" "${COREML_DEV_LIB}"
        run python3 "${ARCHIVE_MEMBER_NORMALIZER}" "${COREML_SIM_LIB}"
        run python3 "${ARCHIVE_MEMBER_NORMALIZER}" "${COREML_MAC_LIB}"
        sanitize_and_validate_archive_host_paths "${COREML_DEV_LIB}" "ios-device RABackendCoreML"
        sanitize_and_validate_archive_host_paths "${COREML_SIM_LIB}" "ios-simulator RABackendCoreML"
        sanitize_and_validate_archive_host_paths "${COREML_MAC_LIB}" "macos RABackendCoreML"
        build_xcframework_from_paths_with_macos "${COREML_DEV_LIB}" "${COREML_SIM_LIB}" "${COREML_MAC_LIB}" "RABackendCoreML.xcframework"
    else
        echo "error: required CoreML backend archive was not built" >&2
        exit 1
    fi
else
    echo "▶ Skipping RABackendCoreML.xcframework (RAC_BACKEND_COREML=OFF)"
fi

# RABackendMLX.xcframework provides the C++ callback-backed plugin shell. The
# Swift MLXRuntime target links this archive plus mlx-swift-lm.
if [ "${RAC_BACKEND_MLX}" = "ON" ]; then
    MLX_DEV_LIB="${STAGING_DIR}/Release-iphoneos/librac_backend_mlx.a"
    MLX_SIM_LIB="${STAGING_DIR}/Release-iphonesimulator/librac_backend_mlx.a"
    MLX_MAC_LIB="${STAGING_DIR}/Release-macos/librac_backend_mlx.a"
    merge_mlx_backend_slice "${DEV_BIN}" "Release-iphoneos" "${MLX_DEV_LIB}" "arm64"
    merge_mlx_backend_slice "${SIM_BIN}" "Release-iphonesimulator" "${MLX_SIM_LIB}" "arm64"
    merge_mlx_backend_macos_slice "${MAC_BIN}" "${MLX_MAC_LIB}" "arm64"
    run python3 "${ARCHIVE_MEMBER_NORMALIZER}" "${MLX_DEV_LIB}"
    run python3 "${ARCHIVE_MEMBER_NORMALIZER}" "${MLX_SIM_LIB}"
    run python3 "${ARCHIVE_MEMBER_NORMALIZER}" "${MLX_MAC_LIB}"
    sanitize_and_validate_archive_host_paths "${MLX_DEV_LIB}" "ios-device RABackendMLX"
    sanitize_and_validate_archive_host_paths "${MLX_SIM_LIB}" "ios-simulator RABackendMLX"
    sanitize_and_validate_archive_host_paths "${MLX_MAC_LIB}" "macos RABackendMLX"
    build_xcframework_from_paths_with_macos "${MLX_DEV_LIB}" "${MLX_SIM_LIB}" "${MLX_MAC_LIB}" "RABackendMLX.xcframework"
    build_mlx_runtime_xcframework
else
    run rm -rf \
        "${DEST}/RABackendMLX.xcframework" \
        "${DEST}/RunAnywhereMLXRuntime.xcframework" \
        "${DEST}/RunAnywhereMLXMetal.xcframework" \
        "${DEST}/RunAnywhereMLXRuntimeResources"
    echo "▶ Skipping RABackendMLX and RunAnywhereMLXRuntime XCFrameworks (RAC_BACKEND_MLX=OFF)"
fi

sync_react_native_frameworks() {
    local rn_root="${REPO_ROOT}/sdk/runanywhere-react-native/packages"
    if [ ! -d "${rn_root}" ]; then
        return
    fi

    echo "▶ Sync React Native local iOS binaries"
    run mkdir -p "${rn_root}/core/ios/Binaries"
    run rm -rf "${rn_root}/core/ios/Binaries/RACommons.xcframework"
    run cp -R "${DEST}/RACommons.xcframework" "${rn_root}/core/ios/Binaries/"

    # RN backend podspecs vendor xcframeworks from ios/Binaries (matches
    # package-sdk.sh --natives-from staging and the new podspec contract).
    # Clean up the legacy ios/Frameworks paths so the source layout cannot
    # serve a stale framework while CocoaPods looks at ios/Binaries.
    run mkdir -p "${rn_root}/llamacpp/ios/Binaries"
    run rm -rf "${rn_root}/llamacpp/ios/Binaries/RABackendLLAMACPP.xcframework"
    run rm -rf "${rn_root}/llamacpp/ios/Frameworks/RABackendLLAMACPP.xcframework"
    run cp -R "${DEST}/RABackendLLAMACPP.xcframework" "${rn_root}/llamacpp/ios/Binaries/"

    if [ -d "${DEST}/RABackendONNX.xcframework" ]; then
        run mkdir -p "${rn_root}/onnx/ios/Binaries"
        run rm -rf "${rn_root}/onnx/ios/Binaries/RABackendONNX.xcframework"
        run rm -rf "${rn_root}/onnx/ios/Frameworks/RABackendONNX.xcframework"
        run rm -rf "${rn_root}/onnx/ios/Frameworks/onnxruntime.xcframework"
        run cp -R "${DEST}/RABackendONNX.xcframework" "${rn_root}/onnx/ios/Binaries/"
    fi

    # Stage the Sherpa plugin xcframework alongside ONNX's
    # (sherpa is the long-term owner of speech primitives).
    if [ -d "${DEST}/RABackendSherpa.xcframework" ]; then
        run mkdir -p "${rn_root}/onnx/ios/Binaries"
        run rm -rf "${rn_root}/onnx/ios/Binaries/RABackendSherpa.xcframework"
        run rm -rf "${rn_root}/onnx/ios/Frameworks/RABackendSherpa.xcframework"
        run cp -R "${DEST}/RABackendSherpa.xcframework" "${rn_root}/onnx/ios/Binaries/"
    fi

    local rn_mlx="${rn_root}/mlx/ios"
    run rm -rf \
        "${rn_mlx}/Binaries/RABackendMLX.xcframework" \
        "${rn_mlx}/Binaries/RunAnywhereMLXRuntime.xcframework" \
        "${rn_mlx}/Binaries/RunAnywhereMLXMetal.xcframework" \
        "${rn_mlx}/Resources/RunAnywhereMLXMetalDevice.bundle" \
        "${rn_mlx}/Resources/RunAnywhereMLXMetalSimulator.bundle" \
        "${rn_mlx}/Resources/swift-crypto_Crypto.bundle" \
        "${rn_mlx}/Resources/swift-transformers_Hub.bundle" \
        "${rn_mlx}/ThirdPartyNotices" \
        "${rn_mlx}/Frameworks"

    if [ "${RAC_BACKEND_MLX}" = "ON" ] \
        && [ -d "${DEST}/RABackendMLX.xcframework" ] \
        && [ -d "${DEST}/RunAnywhereMLXRuntime.xcframework" ] \
        && [ -d "${DEST}/RunAnywhereMLXMetal.xcframework" ]; then
        run mkdir -p "${rn_mlx}/Binaries" "${rn_mlx}/Resources"
        run cp -R "${DEST}/RABackendMLX.xcframework" "${rn_mlx}/Binaries/"
        run cp -R "${DEST}/RunAnywhereMLXRuntime.xcframework" "${rn_mlx}/Binaries/"
        run cp -R "${DEST}/RunAnywhereMLXMetal.xcframework" "${rn_mlx}/Binaries/"
        run cp -R \
            "${DEST}/RunAnywhereMLXRuntimeResources/swift-crypto_Crypto.bundle" \
            "${DEST}/RunAnywhereMLXRuntimeResources/swift-transformers_Hub.bundle" \
            "${rn_mlx}/Resources/"
        run cp -R \
            "${DEST}/RunAnywhereMLXRuntimeResources/ThirdPartyNotices" \
            "${rn_mlx}/ThirdPartyNotices"
    fi
}

# Copy locally built XCFrameworks into each Flutter plugin's package-owned
# native directory. Core/LlamaCPP/ONNX support CocoaPods and SwiftPM; MLX is
# CocoaPods-only so its Hub/Crypto bundles land at the application root.
# Remove the superseded ios/Frameworks copies; active package contracts
# reference ios/<package>/Frameworks only.
#
# Plugin → xcframework mapping:
#   runanywhere             ← RACommons.xcframework
#   runanywhere_llamacpp    ← RABackendLLAMACPP.xcframework
#   runanywhere_onnx        ← RABackendONNX.xcframework
#   runanywhere_mlx         ← RABackendMLX.xcframework +
#                              RunAnywhereMLXRuntime.xcframework +
#                              RunAnywhereMLXMetal.xcframework
sync_flutter_frameworks() {
    local flutter_root="${REPO_ROOT}/sdk/runanywhere-flutter/packages"
    if [ ! -d "${flutter_root}" ]; then
        return
    fi

    echo "▶ Sync Flutter local iOS binaries"

    local flutter_core="${flutter_root}/runanywhere/ios/runanywhere/Frameworks"
    local flutter_llama="${flutter_root}/runanywhere_llamacpp/ios/runanywhere_llamacpp/Frameworks"
    local flutter_onnx="${flutter_root}/runanywhere_onnx/ios/runanywhere_onnx/Frameworks"
    local flutter_mlx_root="${flutter_root}/runanywhere_mlx/ios/runanywhere_mlx"
    local flutter_mlx="${flutter_mlx_root}/Frameworks"
    local flutter_mlx_resources="${flutter_mlx_root}/Resources"

    run rm -rf \
        "${flutter_root}/runanywhere/ios/Frameworks/RACommons.xcframework" \
        "${flutter_root}/runanywhere_llamacpp/ios/Frameworks/RABackendLLAMACPP.xcframework" \
        "${flutter_root}/runanywhere_onnx/ios/Frameworks/RABackendONNX.xcframework" \
        "${flutter_root}/runanywhere_onnx/ios/Frameworks/RABackendSherpa.xcframework" \
        "${flutter_root}/runanywhere_onnx/ios/Frameworks/onnxruntime.xcframework" \
        "${flutter_root}/runanywhere_mlx/ios/Frameworks/RABackendMLX.xcframework" \
        "${flutter_root}/runanywhere_mlx/ios/Frameworks/RunAnywhereMLXRuntime.xcframework" \
        "${flutter_root}/runanywhere_mlx/ios/Frameworks/RunAnywhereMLXMetal.xcframework"

    run mkdir -p \
        "${flutter_core}" \
        "${flutter_llama}" \
        "${flutter_onnx}" \
        "${flutter_mlx}" \
        "${flutter_mlx_resources}"

    if [ -d "${DEST}/RACommons.xcframework" ]; then
        run rm -rf "${flutter_core}/RACommons.xcframework"
        run cp -R "${DEST}/RACommons.xcframework" "${flutter_core}/"
    fi

    if [ -d "${DEST}/RABackendLLAMACPP.xcframework" ]; then
        run rm -rf "${flutter_llama}/RABackendLLAMACPP.xcframework"
        run cp -R "${DEST}/RABackendLLAMACPP.xcframework" "${flutter_llama}/"
    fi

    if [ -d "${DEST}/RABackendONNX.xcframework" ]; then
        run rm -rf "${flutter_onnx}/RABackendONNX.xcframework"
        run cp -R "${DEST}/RABackendONNX.xcframework" "${flutter_onnx}/"
        # Stale onnxruntime.xcframework (pre-v0.19.0) is no longer shipped —
        # ONNX Runtime is now statically linked into RABackendONNX.a.
        run rm -rf "${flutter_onnx}/onnxruntime.xcframework"
    fi

    # Ship RABackendSherpa.xcframework inside runanywhere_onnx
    # for now (sherpa peers with onnx on speech). A future runanywhere_sherpa
    # plugin can consume it directly.
    if [ -d "${DEST}/RABackendSherpa.xcframework" ]; then
        run rm -rf "${flutter_onnx}/RABackendSherpa.xcframework"
        run cp -R "${DEST}/RABackendSherpa.xcframework" "${flutter_onnx}/"
    fi

    run rm -rf \
        "${flutter_mlx}/RABackendMLX.xcframework" \
        "${flutter_mlx}/RunAnywhereMLXRuntime.xcframework" \
        "${flutter_mlx}/RunAnywhereMLXMetal.xcframework" \
        "${flutter_mlx_resources}/RunAnywhereMLXMetalDevice.bundle" \
        "${flutter_mlx_resources}/RunAnywhereMLXMetalSimulator.bundle" \
        "${flutter_mlx_resources}/swift-crypto_Crypto.bundle" \
        "${flutter_mlx_resources}/swift-transformers_Hub.bundle" \
        "${flutter_mlx_root}/ThirdPartyNotices"

    if [ "${RAC_BACKEND_MLX}" = "ON" ] \
        && [ -d "${DEST}/RABackendMLX.xcframework" ] \
        && [ -d "${DEST}/RunAnywhereMLXRuntime.xcframework" ] \
        && [ -d "${DEST}/RunAnywhereMLXMetal.xcframework" ]; then
        run cp -R "${DEST}/RABackendMLX.xcframework" "${flutter_mlx}/"
        run cp -R "${DEST}/RunAnywhereMLXRuntime.xcframework" "${flutter_mlx}/"
        run cp -R "${DEST}/RunAnywhereMLXMetal.xcframework" "${flutter_mlx}/"
        run cp -R \
            "${DEST}/RunAnywhereMLXRuntimeResources/swift-crypto_Crypto.bundle" \
            "${DEST}/RunAnywhereMLXRuntimeResources/swift-transformers_Hub.bundle" \
            "${flutter_mlx_resources}/"
        run cp -R \
            "${DEST}/RunAnywhereMLXRuntimeResources/ThirdPartyNotices" \
            "${flutter_mlx_root}/ThirdPartyNotices"
    fi
}

sync_react_native_frameworks
sync_flutter_frameworks

echo ""
echo "✓ XCFrameworks written to: ${DEST}"
