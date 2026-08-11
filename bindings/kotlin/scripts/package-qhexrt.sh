#!/usr/bin/env bash
# =============================================================================
# bindings/kotlin/scripts/package-qhexrt.sh
# =============================================================================
# Public QHexRT Kotlin packaging contract. Stages the already-built arm64-v8a
# QHexRT module natives (engine + redistributable QAIRT/QNN host libs + DSP
# skels) and produces a self-contained local Maven repository plus checksum.
#
# This is intentionally a sibling of package-sdk.sh. The default public packager
# continues to strip/reject QHexRT; this script is the only path that publishes
# runanywhere-qhexrt-android.
#
# USAGE:
#   package-qhexrt.sh [--mode local|ci]
#
# OPTIONS:
#   --mode local|ci      Build mode (default: auto-detect from $CI)
#
# Prerequisites:
#   scripts/build/build-core-android.sh arm64-v8a must have staged:
#     modules/runanywhere-core-qhexrt/src/main/jniLibs/arm64-v8a/*.so
#     modules/runanywhere-core-qhexrt/src/main/assets/runanywhere/qhexrt/skels/arm64-v8a/*.so
#
# OUTPUTS (VERSION is SDK_VERSION, VERSION, or commons/VERSION without a leading v):
#   dist/sdk-kotlin-qhexrt/runanywhere-kotlin-qhexrt-maven-vVERSION.zip + .sha256
# =============================================================================

set -euo pipefail
shopt -s nullglob

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
KOTLIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${REPO_ROOT}/scripts/setup/detect-mode.sh"

while [ $# -gt 0 ]; do
    case "$1" in
        --mode)
            [ $# -ge 2 ] || { echo "ERROR: --mode requires a value" >&2; exit 1; }
            RAC_BUILD_MODE="$2"
            shift 2
            ;;
        --help|-h)
            sed -n '8,26p' "$0"
            exit 0
            ;;
        *)
            echo "ERROR: unknown option: $1" >&2
            exit 1
            ;;
    esac
done

CANONICAL_VERSION_FILE="${REPO_ROOT}/core/VERSION"
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

QHEXRT_ROOT="${KOTLIN_ROOT}/modules/runanywhere-core-qhexrt"
JNI_DIR="${QHEXRT_ROOT}/src/main/jniLibs/arm64-v8a"
SKEL_DIR="${QHEXRT_ROOT}/src/main/assets/runanywhere/qhexrt/skels/arm64-v8a"
NOTICES_FILE="${QHEXRT_ROOT}/src/main/resources/META-INF/THIRD-PARTY-NOTICES-QAIRT.txt"
DIST_DIR="${KOTLIN_ROOT}/dist/sdk-kotlin-qhexrt"
PUBLIC_MAVEN_GROUP_PATH="io/github/sanchitmonga22"
ARTIFACT="runanywhere-qhexrt-android"
ABI="arm64-v8a"

QHEXRT_HOST_LIBS=(
    "libc++_shared.so"
    "librac_backend_qhexrt.so"
    "librac_backend_qhexrt_jni.so"
    "libQnnHtp.so"
    "libQnnHtpNetRunExtensions.so"
    "libQnnHtpPrepare.so"
    "libQnnSystem.so"
    "libQnnHtpV75CalculatorStub.so"
    "libQnnHtpV75Stub.so"
    "libQnnHtpV79CalculatorStub.so"
    "libQnnHtpV79Stub.so"
    "libQnnHtpV81CalculatorStub.so"
    "libQnnHtpV81Stub.so"
)
QHEXRT_SKEL_LIBS=(
    "libQnnHtpV75Skel.so"
    "libQnnHtpV79Skel.so"
    "libQnnHtpV81Skel.so"
)

TEMP_ROOT=""
cleanup() {
    [ -z "$TEMP_ROOT" ] || rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

ensure_temp_root() {
    if [ -z "$TEMP_ROOT" ]; then
        TEMP_ROOT="$(mktemp -d)"
    fi
}

validate_inventory() {
    local label="$1"
    local dir="$2"
    shift 2
    local required=("$@")
    local name path required_csv allowed want

    [ -d "$dir" ] || fail "missing $label directory: $dir"
    required_csv="$(printf '%s\n' "${required[@]}" | LC_ALL=C sort | paste -sd, -)"
    for name in "${required[@]}"; do
        [ -s "$dir/$name" ] || fail "missing $label file: $dir/$name"
    done
    for path in "$dir"/*; do
        [ -e "$path" ] || continue
        name="$(basename "$path")"
        case "$name" in
            *.so) ;;
            *) fail "unexpected non-.so in $label: $path" ;;
        esac
        allowed=0
        for want in "${required[@]}"; do
            if [ "$name" = "$want" ]; then
                allowed=1
                break
            fi
        done
        [ "$allowed" -eq 1 ] || fail "undeclared $label file: $path (allowed: $required_csv)"
    done
}

echo ">> Kotlin QHexRT packaging (mode=${RAC_BUILD_MODE}, version=${VERSION_VALUE})"

validate_inventory "QHexRT jniLibs/$ABI" "$JNI_DIR" "${QHEXRT_HOST_LIBS[@]}"
validate_inventory "QHexRT skels/$ABI" "$SKEL_DIR" "${QHEXRT_SKEL_LIBS[@]}"
[ -s "$NOTICES_FILE" ] || fail "missing QAIRT third-party notices: $NOTICES_FILE"

rm -rf "$DIST_DIR" "$QHEXRT_ROOT/build"
cd "$KOTLIN_ROOT"
ensure_temp_root
MAVEN_LOCAL="${TEMP_ROOT}/maven-local"
BUNDLE_ROOT="${TEMP_ROOT}/bundle"
REPOSITORY_ROOT="${BUNDLE_ROOT}/repository"
ARCHIVE_NAME="runanywhere-kotlin-qhexrt-maven-v${VERSION_VALUE}.zip"
ARCHIVE_PATH="${DIST_DIR}/${ARCHIVE_NAME}"
GRADLE_TASKS=(
    :modules:runanywhere-core-qhexrt:publishReleasePublicationToMavenLocal
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

publication="${MAVEN_LOCAL}/${PUBLIC_MAVEN_GROUP_PATH}/${ARTIFACT}/${VERSION_VALUE}"
[ -d "$publication" ] || fail "missing Maven publication directory: $publication"
destination="${REPOSITORY_ROOT}/${PUBLIC_MAVEN_GROUP_PATH}/${ARTIFACT}/${VERSION_VALUE}"
mkdir -p "$destination"
for suffix in aar pom module sources.jar; do
    case "$suffix" in
        sources.jar) filename="${ARTIFACT}-${VERSION_VALUE}-sources.jar" ;;
        *) filename="${ARTIFACT}-${VERSION_VALUE}.${suffix}" ;;
    esac
    [ -s "$publication/$filename" ] || fail "missing Maven publication file: $publication/$filename"
    cp -f "$publication/$filename" "$destination/$filename"
done

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

python3 "$SCRIPT_DIR/validate_qhexrt_artifacts.py" --dist "$DIST_DIR" --version "$VERSION_VALUE"
"${REPO_ROOT}/scripts/release/validate-artifact.sh" "$ARCHIVE_PATH"

echo ""
echo ">> QHexRT Kotlin artifacts in $DIST_DIR:"
echo "  $ARCHIVE_NAME"
echo "  $ARCHIVE_NAME.sha256"
