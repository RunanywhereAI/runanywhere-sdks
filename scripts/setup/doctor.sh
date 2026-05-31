#!/usr/bin/env bash
set -uo pipefail

VERBOSE=0
for arg in "$@"; do
    case "$arg" in
        -v|--verbose) VERBOSE=1 ;;
        -h|--help)
            echo "Usage: $0 [-v|--verbose]"
            echo "Scans the host for toolchains and prints what RunAnywhere SDKs can be built here."
            exit 0
            ;;
    esac
done

if [ -t 1 ] && [ "${NO_COLOR:-}" = "" ]; then
    C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
    C_OK=$'\033[32m'; C_BAD=$'\033[31m'; C_NA=$'\033[33m'
else
    C_RESET=''; C_BOLD=''; C_DIM=''; C_OK=''; C_BAD=''; C_NA=''
fi

OK="${C_OK}✓${C_RESET}"
BAD="${C_BAD}✗${C_RESET}"
NA="${C_NA}—${C_RESET}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

have() { command -v "$1" >/dev/null 2>&1; }

run_to() {
    local secs="$1"; shift
    if have timeout; then
        timeout --foreground "${secs}" "$@" </dev/null 2>&1
    elif have gtimeout; then
        gtimeout --foreground "${secs}" "$@" </dev/null 2>&1
    else
        "$@" </dev/null 2>&1
    fi
}

trim_v() { sed -E 's/^[^0-9]*([0-9]+\.[0-9]+(\.[0-9]+)?).*/\1/'; }

row() {
    local label="$1" status="$2" detail="${3:-}"
    printf "  %-22s %s  %s\n" "${label}" "${status}" "${C_DIM}${detail}${C_RESET}"
}

bool_row() {
    local label="$1" ok="$2" detail="${3:-}" hint="${4:-}"
    if [ "${ok}" = "1" ]; then
        row "${label}" "${OK}" "${detail}"
    else
        row "${label}" "${BAD}" "${hint}"
    fi
}

OS_KERNEL=$(uname -s)
case "${OS_KERNEL}" in
    Linux*)
        OS=linux
        if [ -f /etc/os-release ]; then
            OS_PRETTY=$(. /etc/os-release; echo "${PRETTY_NAME:-Linux}")
        else
            OS_PRETTY="Linux"
        fi
        ;;
    Darwin*)
        OS=macos
        OS_PRETTY="macOS $(sw_vers -productVersion 2>/dev/null || echo)"
        ;;
    MINGW*|MSYS*|CYGWIN*) OS=windows; OS_PRETTY="Windows" ;;
    *) OS=unknown; OS_PRETTY="${OS_KERNEL}" ;;
esac
ARCH=$(uname -m)
SHELL_NAME=$(basename "${SHELL:-sh}")

echo
echo "${C_BOLD}RunAnywhere SDK — Doctor${C_RESET}"
echo "========================"
echo
echo "${C_BOLD}System${C_RESET}"
row "OS"       " " "${OS_PRETTY}"
row "Arch"     " " "${ARCH}"
row "Shell"    " " "${SHELL_NAME}"
echo
printf "${C_BOLD}Toolchains${C_RESET} ${C_DIM}(scanning…)${C_RESET}\n"

NDK_VERSION=$(grep -E '^racNdkVersion=' "${REPO_ROOT}/sdk/runanywhere-kotlin/gradle.properties" 2>/dev/null | cut -d= -f2 | tr -d ' \r' || true)
NDK_VERSION="${NDK_VERSION:-27.0.12077973}"

ANDROID_SDK=""
for candidate in \
    "${ANDROID_HOME:-}" \
    "${ANDROID_SDK_ROOT:-}" \
    "$HOME/Android/Sdk" \
    "$HOME/Library/Android/sdk"; do
    if [ -n "${candidate}" ] && [ -d "${candidate}" ]; then
        ANDROID_SDK="${candidate}"
        break
    fi
done
bool_row "Android SDK" $([ -n "${ANDROID_SDK}" ] && echo 1 || echo 0) "${ANDROID_SDK}" "not found"

ANDROID_NDK=""
if [ -n "${ANDROID_NDK_HOME:-}" ] && [ -d "${ANDROID_NDK_HOME}" ]; then
    ANDROID_NDK="${ANDROID_NDK_HOME}"
elif [ -n "${ANDROID_SDK}" ] && [ -d "${ANDROID_SDK}/ndk/${NDK_VERSION}" ]; then
    ANDROID_NDK="${ANDROID_SDK}/ndk/${NDK_VERSION}"
fi
bool_row "Android NDK ${NDK_VERSION}" $([ -n "${ANDROID_NDK}" ] && echo 1 || echo 0) "${ANDROID_NDK}" "not found"

JAVA_OK=0; JAVA_VER=""
if have java; then
    JV=$(run_to 5 java -version)
    JAVA_MAJOR=$(echo "${JV}" | head -1 | sed -E 's/.*"([0-9]+)\.([0-9]+)\.?([0-9]+)?.*/\1/')
    JAVA_VER=$(echo "${JV}" | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
    if [ -n "${JAVA_MAJOR}" ] && [ "${JAVA_MAJOR}" -ge 17 ] 2>/dev/null; then JAVA_OK=1; fi
fi
bool_row "JDK 17+" "${JAVA_OK}" "${JAVA_VER}" "install JDK 17 or newer"

CMAKE_OK=0; CMAKE_VER=""
if have cmake; then CMAKE_VER=$(run_to 3 cmake --version | head -1 | trim_v); CMAKE_OK=1; fi
bool_row "CMake" "${CMAKE_OK}" "${CMAKE_VER}" "not found"

NINJA_OK=0; NINJA_VER=""
if have ninja; then NINJA_VER=$(run_to 3 ninja --version); NINJA_OK=1; fi
bool_row "Ninja" "${NINJA_OK}" "${NINJA_VER}" "not found"

NODE_OK=0; NODE_VER=""
if have node; then
    NODE_VER=$(run_to 3 node -v | sed 's/^v//')
    NODE_MAJOR=$(echo "${NODE_VER}" | cut -d. -f1)
    [ -n "${NODE_MAJOR}" ] && [ "${NODE_MAJOR}" -ge 20 ] 2>/dev/null && NODE_OK=1
fi
bool_row "Node ≥20" "${NODE_OK}" "${NODE_VER}" "install Node 20 or newer"

YARN_OK=0; YARN_VER=""
if have yarn; then YARN_VER=$(run_to 3 yarn -v); YARN_OK=1; fi
bool_row "Yarn" "${YARN_OK}" "${YARN_VER}" "not found"

NPM_OK=0; NPM_VER=""
if have npm; then NPM_VER=$(run_to 3 npm -v); NPM_OK=1; fi
bool_row "npm" "${NPM_OK}" "${NPM_VER}" "not found"

FLUTTER_OK=0; FLUTTER_VER=""
if have flutter; then
    FOUT=$(run_to 8 flutter --version || true)
    FLUTTER_VER=$(echo "${FOUT}" | head -1 | sed -E 's/Flutter ([0-9.]+).*/\1/')
    [ -n "${FLUTTER_VER}" ] && FLUTTER_OK=1
fi
bool_row "Flutter" "${FLUTTER_OK}" "${FLUTTER_VER}" "not found (or first-run is slow; rerun)"

DART_OK=0; DART_VER=""
if have dart; then
    DOUT=$(run_to 5 dart --version || true)
    DART_VER=$(echo "${DOUT}" | sed -E 's/.*Dart SDK version: ([^ ]+).*/\1/')
    [ -n "${DART_VER}" ] && DART_OK=1
fi
bool_row "Dart" "${DART_OK}" "${DART_VER}" "not found"

PROTOC_OK=0; PROTOC_VER=""
if have protoc; then PROTOC_VER=$(run_to 3 protoc --version | sed 's/libprotoc //'); PROTOC_OK=1; fi
bool_row "protoc" "${PROTOC_OK}" "${PROTOC_VER}" "not found"

CC_OK=0
if have cc || have gcc || have clang; then CC_OK=1; fi
bool_row "C/C++ compiler" "${CC_OK}" "" "install gcc or clang"

XCODE_OK=0; XCODE_VER=""
SWIFT_OK=0; SWIFT_VER=""
if [ "${OS}" = "macos" ]; then
    if have xcodebuild; then
        XOUT=$(run_to 10 xcodebuild -version || true)
        XCODE_VER=$(echo "${XOUT}" | head -1 | sed -E 's/Xcode (.+)/\1/')
        [ -n "${XCODE_VER}" ] && XCODE_OK=1
    fi
    bool_row "Xcode" "${XCODE_OK}" "${XCODE_VER}" "install via App Store"

    if have swift; then
        SOUT=$(run_to 5 swift --version || true)
        SWIFT_VER=$(echo "${SOUT}" | head -1 | sed -E 's/.*Swift version ([0-9.]+).*/\1/')
        [ -n "${SWIFT_VER}" ] && SWIFT_OK=1
    fi
    bool_row "Swift" "${SWIFT_OK}" "${SWIFT_VER}" "not found"
else
    row "Xcode" "${NA}" "N/A on ${OS_PRETTY}"
    row "Swift" "${NA}" "N/A on ${OS_PRETTY}"
fi

can_kotlin_sdk()      { [ -n "${ANDROID_SDK}" ] && [ -n "${ANDROID_NDK}" ] && [ "${JAVA_OK}" = "1" ]; }
can_android_example() { can_kotlin_sdk; }
can_web_sdk()         { [ "${NODE_OK}" = "1" ] && [ "${YARN_OK}" = "1" ]; }
can_rn_sdk()          { [ "${NODE_OK}" = "1" ] && [ "${YARN_OK}" = "1" ] && [ -n "${ANDROID_SDK}" ]; }
can_flutter_sdk()     { [ "${FLUTTER_OK}" = "1" ] && [ "${DART_OK}" = "1" ]; }
can_native_android()  { [ "${CMAKE_OK}" = "1" ] && [ "${NINJA_OK}" = "1" ] && [ -n "${ANDROID_NDK}" ]; }
can_native_linux()    { [ "${OS}" = "linux" ] && [ "${CMAKE_OK}" = "1" ] && [ "${CC_OK}" = "1" ]; }
can_ios_anything()    { [ "${OS}" = "macos" ] && [ "${XCODE_OK}" = "1" ]; }

build_row() {
    local label="$1" can="$2" missing="$3"
    if [ "${can}" = "1" ]; then
        row "${label}" "${OK}" ""
    else
        row "${label}" "${BAD}" "${missing}"
    fi
}

echo
echo "${C_BOLD}What you can build${C_RESET}"

if can_kotlin_sdk; then
    build_row "Kotlin SDK" 1 ""
else
    miss=""
    [ -z "${ANDROID_SDK}" ] && miss="${miss} Android SDK"
    [ -z "${ANDROID_NDK}" ] && miss="${miss} Android NDK"
    [ "${JAVA_OK}" != "1" ] && miss="${miss} JDK17+"
    build_row "Kotlin SDK" 0 "missing:${miss}"
fi

can_android_example && build_row "Android example app" 1 "" || build_row "Android example app" 0 "needs Kotlin SDK toolchain"
can_web_sdk         && build_row "Web SDK"             1 "" || build_row "Web SDK"             0 "missing: Node ≥20 + Yarn"
can_rn_sdk          && build_row "React Native SDK"    1 "" || build_row "React Native SDK"    0 "missing: Node + Yarn + Android SDK"
can_flutter_sdk     && build_row "Flutter SDK"         1 "" || build_row "Flutter SDK"         0 "missing: flutter, dart"
can_native_android  && build_row "Native C++ (Android)" 1 "" || build_row "Native C++ (Android)" 0 "missing: cmake + ninja + NDK"

if [ "${OS}" = "linux" ]; then
    can_native_linux && build_row "Native C++ (Linux)" 1 "" || build_row "Native C++ (Linux)" 0 "missing: cmake + gcc/clang"
else
    row "Native C++ (Linux)" "${NA}" "Linux only"
fi

if [ "${OS}" = "macos" ]; then
    can_ios_anything && build_row "Swift / iOS SDK"  1 "" || build_row "Swift / iOS SDK"  0 "install Xcode"
    can_ios_anything && build_row "iOS example app"  1 "" || build_row "iOS example app"  0 "install Xcode"
    can_ios_anything && build_row "Native C++ (iOS)" 1 "" || build_row "Native C++ (iOS)" 0 "install Xcode"
else
    row "Swift / iOS SDK"   "${NA}" "requires macOS + Xcode"
    row "iOS example app"   "${NA}" "requires macOS + Xcode"
    row "Native C++ (iOS)"  "${NA}" "requires macOS + Xcode"
fi

echo
echo "Run ${C_BOLD}./run setup${C_RESET} to provision build files for everything you can build."

if [ "${VERBOSE}" = "1" ]; then
    echo
    echo "${C_BOLD}Verbose detail${C_RESET}"
    echo "  ANDROID_HOME       = ${ANDROID_HOME:-}"
    echo "  ANDROID_SDK_ROOT   = ${ANDROID_SDK_ROOT:-}"
    echo "  ANDROID_NDK_HOME   = ${ANDROID_NDK_HOME:-}"
    echo "  PATH (head)        = $(echo "${PATH}" | tr ':' '\n' | head -5 | paste -sd: -)"
fi

exit 0
