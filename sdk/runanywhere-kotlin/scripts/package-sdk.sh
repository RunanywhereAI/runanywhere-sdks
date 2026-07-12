#!/usr/bin/env bash
# =============================================================================
# sdk/runanywhere-kotlin/scripts/package-sdk.sh
# =============================================================================
# Public Kotlin SDK packaging contract. Consumes the canonical Android native
# archives and produces a self-contained local Maven repository plus checksum.
# Private QHexRT/QNN inputs and stale private module outputs are rejected.
#
# USAGE:
#   package-sdk.sh [--mode local|ci] [--natives-from PATH]
#
# OPTIONS:
#   --mode local|ci      Build mode (default: auto-detect from $CI)
#   --natives-from PATH  Canonical per-ABI Android archives or an extracted
#                        PATH/<abi>/{jni,llamacpp,onnx} tree. If omitted, the
#                        already-staged public module jniLibs trees are used.
#
# OUTPUTS (VERSION is SDK_VERSION, VERSION, or commons/VERSION without a leading v):
#   dist/sdk-kotlin/runanywhere-kotlin-maven-vVERSION.zip + .sha256
#
# The ZIP contains the exact release publications for runanywhere-sdk,
# runanywhere-llamacpp, and runanywhere-onnx: AAR, POM, Gradle module metadata,
# and sources JAR. Consumers resolve their transitive dependencies normally.
# =============================================================================

set -euo pipefail
shopt -s nullglob

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
KOTLIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${REPO_ROOT}/scripts/setup/detect-mode.sh"

NATIVES_FROM=""
while [ $# -gt 0 ]; do
    case "$1" in
        --mode)
            [ $# -ge 2 ] || { echo "ERROR: --mode requires a value" >&2; exit 1; }
            RAC_BUILD_MODE="$2"
            shift 2
            ;;
        --natives-from)
            [ $# -ge 2 ] || { echo "ERROR: --natives-from requires a value" >&2; exit 1; }
            NATIVES_FROM="$2"
            shift 2
            ;;
        --help|-h)
            sed -n '8,23p' "$0"
            exit 0
            ;;
        *)
            echo "ERROR: unknown option: $1" >&2
            exit 1
            ;;
    esac
done

CANONICAL_VERSION_FILE="${REPO_ROOT}/sdk/runanywhere-commons/VERSION"
if [ -n "${SDK_VERSION:-}" ]; then
    VERSION_VALUE="$SDK_VERSION"
elif [ -n "${VERSION:-}" ]; then
    VERSION_VALUE="$VERSION"
else
    [ -s "$CANONICAL_VERSION_FILE" ] || {
        echo "ERROR: canonical version file is missing or empty: $CANONICAL_VERSION_FILE" >&2
        exit 1
    }
    VERSION_VALUE="$(tr -d '[:space:]' < "$CANONICAL_VERSION_FILE")"
fi
VERSION_VALUE="${VERSION_VALUE#v}"
if ! [[ "$VERSION_VALUE" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    echo "ERROR: invalid SDK version: $VERSION_VALUE" >&2
    exit 1
fi
export SDK_VERSION="$VERSION_VALUE"

CORE_JNI_DIR="${KOTLIN_ROOT}/src/main/jniLibs"
LLAMACPP_JNI_DIR="${KOTLIN_ROOT}/modules/runanywhere-core-llamacpp/src/main/jniLibs"
ONNX_JNI_DIR="${KOTLIN_ROOT}/modules/runanywhere-core-onnx/src/main/jniLibs"
QHEXRT_ROOT="${KOTLIN_ROOT}/modules/runanywhere-core-qhexrt"
DIST_DIR="${KOTLIN_ROOT}/dist/sdk-kotlin"
PUBLIC_MAVEN_GROUP_PATH="io/github/sanchitmonga22"
PUBLIC_ARTIFACTS=(runanywhere-sdk runanywhere-llamacpp runanywhere-onnx)
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
ALL_PUBLIC_LIBS=("${CORE_LIBS[@]}" "${LLAMACPP_LIBS[@]}" "${ONNX_LIBS[@]}")

TEMP_ROOT=""
cleanup() {
    [ -z "$TEMP_ROOT" ] || rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT

ensure_temp_root() {
    if [ -z "$TEMP_ROOT" ]; then
        TEMP_ROOT="$(mktemp -d)"
    fi
}

fail() {
    echo "ERROR: $*" >&2
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

reject_private_path() {
    local path="$1"
    local lowered
    lowered="$(printf '%s' "$path" | tr '[:upper:]' '[:lower:]')"
    case "$lowered" in
        *qhexrt*|*qnn*)
            fail "private QHexRT/QNN input is not publishable: $path"
            ;;
    esac
}

scan_source_tree() {
    local root="$1"
    local source_file
    while IFS= read -r -d '' source_file; do
        reject_private_path "${source_file#"$root"/}"
        if [ "${source_file##*.}" = "so" ] && ! contains_value "$(basename "$source_file")" "${ALL_PUBLIC_LIBS[@]}"; then
            fail "undeclared/private native input is not publishable: $source_file"
        fi
    done < <(find "$root" -type f -print0)
}

validate_archive_entries() {
    local archive="$1"
    local entry
    while IFS= read -r entry; do
        reject_private_path "$entry"
        case "/$entry/" in
            *'/../'*) fail "unsafe archive entry in $archive: $entry" ;;
        esac
        case "$entry" in
            /*) fail "absolute archive entry in $archive: $entry" ;;
        esac
    done < <(unzip -Z1 "$archive")
}

stage_native_dir() {
    local source_dir="$1"
    local destination_dir="$2"
    shift 2
    [ -d "$source_dir" ] || return 0

    local source_file library
    while IFS= read -r -d '' source_file; do
        library="$(basename "$source_file")"
        contains_value "$library" "$@" || fail "native $library is not declared for $source_dir"
        mkdir -p "$destination_dir"
        [ ! -e "$destination_dir/$library" ] || fail "duplicate staged native: $destination_dir/$library"
        cp -f "$source_file" "$destination_dir/$library"
    done < <(find "$source_dir" -maxdepth 1 -type f -name '*.so' -print0)
}

stage_source_root() {
    local root="$1"
    local abi
    for abi in "${SUPPORTED_ABIS[@]}"; do
        # Canonical release layout.
        stage_native_dir "$root/$abi/jni" "$CORE_JNI_DIR/$abi" "${CORE_LIBS[@]}"
        stage_native_dir "$root/$abi/llamacpp" "$LLAMACPP_JNI_DIR/$abi" "${LLAMACPP_LIBS[@]}"
        stage_native_dir "$root/$abi/onnx" "$ONNX_JNI_DIR/$abi" "${ONNX_LIBS[@]}"
    done
}

validate_component_inventory() {
    local component="$1"
    local directory="$2"
    shift 2
    local expected actual library
    expected="$(printf '%s\n' "$@" | LC_ALL=C sort)"
    actual="$(find "$directory" -maxdepth 1 -type f -name '*.so' -exec basename {} \; | LC_ALL=C sort)"
    if [ "$actual" != "$expected" ]; then
        echo "Expected $component natives:" >&2
        printf '  %s\n' "$@" >&2
        echo "Actual $component natives in $directory:" >&2
        find "$directory" -maxdepth 1 -type f -name '*.so' -exec basename {} \; | LC_ALL=C sort | sed 's/^/  /' >&2
        fail "$component native inventory mismatch"
    fi
    for library in "$directory"/*.so; do
        reject_private_path "$library"
    done
}

validate_component_abis() {
    local component="$1"
    local directory="$2"
    local expected actual
    [ -d "$directory" ] || fail "missing $component native root: $directory"
    expected="$(printf '%s\n' "${SUPPORTED_ABIS[@]}" | LC_ALL=C sort)"
    actual="$(find "$directory" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | LC_ALL=C sort)"
    if [ "$actual" != "$expected" ]; then
        echo "Expected $component ABIs:" >&2
        printf '  %s\n' "${SUPPORTED_ABIS[@]}" >&2
        echo "Actual $component ABIs in $directory:" >&2
        find "$directory" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; \
            | LC_ALL=C sort | sed 's/^/  /' >&2
        fail "$component ABI inventory mismatch"
    fi
}

validate_staged_natives() {
    local abi
    validate_component_abis "core" "$CORE_JNI_DIR"
    validate_component_abis "LlamaCPP" "$LLAMACPP_JNI_DIR"
    validate_component_abis "ONNX" "$ONNX_JNI_DIR"
    for abi in "${SUPPORTED_ABIS[@]}"; do
        validate_component_inventory "core/$abi" "$CORE_JNI_DIR/$abi" "${CORE_LIBS[@]}"
        validate_component_inventory "llamacpp/$abi" "$LLAMACPP_JNI_DIR/$abi" "${LLAMACPP_LIBS[@]}"
        validate_component_inventory "onnx/$abi" "$ONNX_JNI_DIR/$abi" "${ONNX_LIBS[@]}"
    done
}

echo ">> Kotlin SDK public packaging (mode=${RAC_BUILD_MODE}, version=${VERSION_VALUE})"

# This package is public. Remove ignored private staging and stale private
# module outputs before Gradle is invoked, then invoke no QHexRT task below.
rm -rf \
    "$QHEXRT_ROOT/build" \
    "$QHEXRT_ROOT/src/main/jniLibs" \
    "$QHEXRT_ROOT/src/main/assets/runanywhere/qhexrt" \
    "$DIST_DIR"

if [ -n "$NATIVES_FROM" ]; then
    [ -d "$NATIVES_FROM" ] || fail "--natives-from not found: $NATIVES_FROM"
    echo ">> Staging declared public natives from $NATIVES_FROM"
    scan_source_tree "$NATIVES_FROM"
    rm -rf "$CORE_JNI_DIR" "$LLAMACPP_JNI_DIR" "$ONNX_JNI_DIR"

    ensure_temp_root
    SOURCE_ROOTS=("$NATIVES_FROM")
    archive_index=0
    while IFS= read -r -d '' archive; do
        reject_private_path "$archive"
        validate_archive_entries "$archive"
        extract_dir="$TEMP_ROOT/archive-$archive_index"
        mkdir -p "$extract_dir"
        echo "   extracting: $(basename "$archive")"
        unzip -qo "$archive" -d "$extract_dir"
        scan_source_tree "$extract_dir"
        SOURCE_ROOTS+=("$extract_dir")
        archive_index=$((archive_index + 1))
    done < <(find "$NATIVES_FROM" -maxdepth 2 -type f -iname '*android*.zip' -print0)

    for source_root in "${SOURCE_ROOTS[@]}"; do
        stage_source_root "$source_root"
    done
fi

validate_staged_natives

cd "$KOTLIN_ROOT"
ensure_temp_root
MAVEN_LOCAL="${TEMP_ROOT}/maven-local"
BUNDLE_ROOT="${TEMP_ROOT}/bundle"
REPOSITORY_ROOT="${BUNDLE_ROOT}/repository"
ARCHIVE_NAME="runanywhere-kotlin-maven-v${VERSION_VALUE}.zip"
ARCHIVE_PATH="${DIST_DIR}/${ARCHIVE_NAME}"
GRADLE_TASKS=(
    :publishReleasePublicationToMavenLocal
    :modules:runanywhere-core-llamacpp:publishReleasePublicationToMavenLocal
    :modules:runanywhere-core-onnx:publishReleasePublicationToMavenLocal
)
GRADLE_ARGS=(
    --no-daemon
    -Prunanywhere.useLocalNatives=true
    -Prunanywhere.skipSigning=true
    -x buildLocalJniLibs
    "-Dmaven.repo.local=${MAVEN_LOCAL}"
)

echo ">> ./gradlew ${GRADLE_TASKS[*]} ${GRADLE_ARGS[*]}"
JITPACK=false USE_RUNANYWHERE_NAMESPACE=false \
    ./gradlew "${GRADLE_TASKS[@]}" "${GRADLE_ARGS[@]}"

for artifact in "${PUBLIC_ARTIFACTS[@]}"; do
    publication="${MAVEN_LOCAL}/${PUBLIC_MAVEN_GROUP_PATH}/${artifact}/${VERSION_VALUE}"
    [ -d "$publication" ] || fail "missing Maven publication directory: $publication"
    destination="${REPOSITORY_ROOT}/${PUBLIC_MAVEN_GROUP_PATH}/${artifact}/${VERSION_VALUE}"
    mkdir -p "$destination"
    for suffix in aar pom module sources.jar; do
        case "$suffix" in
            sources.jar) filename="${artifact}-${VERSION_VALUE}-sources.jar" ;;
            *) filename="${artifact}-${VERSION_VALUE}.${suffix}" ;;
        esac
        [ -s "$publication/$filename" ] || fail "missing Maven publication file: $publication/$filename"
        cp -f "$publication/$filename" "$destination/$filename"
    done
done

scan_source_tree "$REPOSITORY_ROOT"
mkdir -p "$DIST_DIR"
find "$BUNDLE_ROOT" -exec touch -h -t 198001010000 {} +
rm -f "$ARCHIVE_PATH"
(
    cd "$BUNDLE_ROOT"
    LC_ALL=C find repository -print \
        | LC_ALL=C sort \
        | zip -qXy "$ARCHIVE_PATH" -@
)

if command -v shasum >/dev/null 2>&1; then
    (cd "$DIST_DIR" && shasum -a 256 "$ARCHIVE_NAME" > "$ARCHIVE_NAME.sha256")
else
    (cd "$DIST_DIR" && sha256sum "$ARCHIVE_NAME" > "$ARCHIVE_NAME.sha256")
fi

python3 "$SCRIPT_DIR/validate_public_artifacts.py" --dist "$DIST_DIR" --version "$VERSION_VALUE"
"${REPO_ROOT}/scripts/release/validate-artifact.sh" "$ARCHIVE_PATH"

echo ""
echo ">> Public Kotlin artifacts in $DIST_DIR:"
echo "  $ARCHIVE_NAME"
echo "  $ARCHIVE_NAME.sha256"
