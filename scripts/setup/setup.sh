#!/usr/bin/env bash
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if [ -t 1 ] && [ "${NO_COLOR:-}" = "" ]; then
    C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
    C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_BAD=$'\033[31m'
else
    C_RESET=''; C_BOLD=''; C_DIM=''; C_OK=''; C_WARN=''; C_BAD=''
fi

usage() {
    cat <<EOF
Usage: $0 [TARGET ...]

Provision environment (local.properties, deps) for the SDKs. Does not build artifacts.

TARGETS:
  all       (default) every host-buildable target
  android   write local.properties for Kotlin SDK + Android example
  flutter   flutter pub get for Flutter SDK + examples
  rn        yarn install for React Native SDK
  ios       swift package resolve + pod install (macOS only)
  web       yarn install for Web SDK + examples

Build commands live under ./run sdk <name> <action> and ./run example <platform> <action>.

Examples:
  $0
  $0 android web
EOF
}

OS=$(uname -s)
case "${OS}" in
    Linux*)  OS=linux ;;
    Darwin*) OS=macos ;;
    *)       OS=other ;;
esac

NDK_VERSION=$(grep -E '^racNdkVersion=' "${REPO_ROOT}/sdk/runanywhere-kotlin/gradle.properties" 2>/dev/null | cut -d= -f2 | tr -d ' \r' || true)
NDK_VERSION="${NDK_VERSION:-27.0.12077973}"

have() { command -v "$1" >/dev/null 2>&1; }

note() { printf "  ${C_DIM}%s${C_RESET}\n" "$*"; }
ok()   { printf "  ${C_OK}✓${C_RESET} %s\n" "$*"; }
warn() { printf "  ${C_WARN}!${C_RESET} %s\n" "$*"; }
err()  { printf "  ${C_BAD}✗${C_RESET} %s\n" "$*" >&2; }

heading() { echo; printf "${C_BOLD}== %s ==${C_RESET}\n" "$*"; }

# Repo-wide, not target-specific: make sure every AGENTS.md has its CLAUDE.md
# symlink beside it. Committed symlinks already materialize on clone for
# macOS/Linux; this covers Windows checkouts and any clobbered link.
ensure_doc_symlinks() {
    heading "AGENTS.md / CLAUDE.md symlinks"
    if bash "${REPO_ROOT}/scripts/validation/gates/check_agents_claude_sync.sh" --fix; then
        ok "CLAUDE.md symlinks ready"
    else
        warn "could not create CLAUDE.md symlinks (see above)"
    fi
}

resolve_android_sdk() {
    for c in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$HOME/Android/Sdk" "$HOME/Library/Android/sdk"; do
        [ -n "${c}" ] && [ -d "${c}" ] && { echo "${c}"; return 0; }
    done
    return 1
}

resolve_android_ndk() {
    local sdk="$1"
    if [ -n "${ANDROID_NDK_HOME:-}" ] && [ -d "${ANDROID_NDK_HOME}" ]; then
        echo "${ANDROID_NDK_HOME}"; return 0
    fi
    [ -d "${sdk}/ndk/${NDK_VERSION}" ] && { echo "${sdk}/ndk/${NDK_VERSION}"; return 0; }
    return 1
}

ensure_local_props() {
    local dir="$1" sdk="$2" ndk="${3:-}"
    local props="${dir}/local.properties"
    if [ -f "${props}" ]; then
        note "exists: ${props#${REPO_ROOT}/}"
        return 0
    fi
    {
        echo "sdk.dir=${sdk}"
        [ -n "${ndk}" ] && echo "ndk.dir=${ndk}"
    } > "${props}"
    ok "wrote ${props#${REPO_ROOT}/}"
}

setup_android() {
    heading "Android (Kotlin SDK + example)"
    local sdk
    if ! sdk=$(resolve_android_sdk); then
        err "Android SDK not found (set ANDROID_HOME or install)"
        return 1
    fi
    note "Android SDK: ${sdk}"
    local ndk=""
    if ndk=$(resolve_android_ndk "${sdk}"); then
        note "Android NDK: ${ndk}"
    else
        warn "Android NDK ${NDK_VERSION} not found — install it before running ./run sdk commons build-android"
    fi
    ensure_local_props "${REPO_ROOT}/sdk/runanywhere-kotlin" "${sdk}" "${ndk}"
    ensure_local_props "${REPO_ROOT}/examples/android/RunAnywhereAI" "${sdk}" "${ndk}"
}

setup_flutter() {
    heading "Flutter"
    if ! have flutter; then err "flutter not found"; return 1; fi
    if [ -d "${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere" ]; then
        (cd "${REPO_ROOT}/sdk/runanywhere-flutter/packages/runanywhere" && flutter pub get </dev/null) && ok "sdk pub get"
    fi
    for ex in "${REPO_ROOT}"/examples/flutter/*/; do
        [ -d "${ex}" ] && [ -f "${ex}/pubspec.yaml" ] && (cd "${ex}" && flutter pub get </dev/null) && ok "$(basename "${ex}") pub get"
    done
}

setup_rn() {
    heading "React Native"
    if ! have yarn && ! have npm; then err "yarn/npm not found"; return 1; fi
    if [ -d "${REPO_ROOT}/sdk/runanywhere-react-native" ]; then
        cd "${REPO_ROOT}/sdk/runanywhere-react-native"
        if have yarn; then yarn install && ok "yarn install"; else npm install && ok "npm install"; fi
    fi
}

setup_ios() {
    heading "iOS / Swift"
    if [ "${OS}" != "macos" ]; then
        warn "iOS targets require macOS — skipping"
        return 0
    fi
    if ! have swift; then err "swift not found (install Xcode)"; return 1; fi
    if [ -d "${REPO_ROOT}/sdk/runanywhere-swift" ]; then
        (cd "${REPO_ROOT}/sdk/runanywhere-swift" && RUNANYWHERE_USE_LOCAL_NATIVES=1 swift package resolve) && ok "swift package resolve"
    fi
    for ex in "${REPO_ROOT}"/examples/ios/*/; do
        if [ -f "${ex}/Podfile" ] && have pod; then
            (cd "${ex}" && pod install) && ok "$(basename "${ex}") pod install"
        fi
    done
}

setup_web() {
    heading "Web"
    if ! have yarn && ! have npm; then err "yarn/npm not found"; return 1; fi
    if [ -d "${REPO_ROOT}/sdk/runanywhere-web" ]; then
        cd "${REPO_ROOT}/sdk/runanywhere-web"
        if have yarn; then yarn install && ok "sdk yarn install"; else npm install && ok "sdk npm install"; fi
    fi
    for ex in "${REPO_ROOT}"/examples/web/*/; do
        if [ -f "${ex}/package.json" ]; then
            cd "${ex}"
            if have yarn; then yarn install && ok "$(basename "${ex}") yarn install"; else npm install && ok "$(basename "${ex}") npm install"; fi
        fi
    done
}

setup_all() {
    local rc=0
    setup_android  || rc=1
    setup_web      || rc=1
    setup_rn       || rc=1
    setup_flutter  || rc=1
    [ "${OS}" = "macos" ] && { setup_ios || rc=1; }
    return ${rc}
}

if [ "${1:-help}" = "-h" ] || [ "${1:-help}" = "--help" ]; then
    usage; exit 0
fi

TARGETS=("$@")
[ "${#TARGETS[@]}" -eq 0 ] && TARGETS=(all)

ensure_doc_symlinks

EXIT=0
for t in "${TARGETS[@]}"; do
    case "${t}" in
        all)      setup_all     || EXIT=1 ;;
        android)  setup_android || EXIT=1 ;;
        flutter)  setup_flutter || EXIT=1 ;;
        rn)       setup_rn      || EXIT=1 ;;
        ios)      setup_ios     || EXIT=1 ;;
        web)      setup_web     || EXIT=1 ;;
        help|-h|--help) usage; exit 0 ;;
        *) err "unknown target: ${t}"; usage; exit 2 ;;
    esac
done

echo
if [ "${EXIT}" = "0" ]; then
    ok "environment ready — run './run help' to see commands"
else
    warn "setup finished with some failures (see above)"
fi
exit ${EXIT}
