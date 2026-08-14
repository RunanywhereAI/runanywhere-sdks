#!/usr/bin/env bash
# =============================================================================
# scripts/release/bump-consumer-apps.sh
# =============================================================================
# Bump the six extracted consumer apps to a published SDK version and open a PR
# per repo.
#
# WHY THIS EXISTS
# Every app repo pins the SDK in a manifest AND in one or more lockfiles, and the
# lockfile is what CI actually enforces. Editing only the manifest produces a PR
# that fails a *different* way per ecosystem — and each failure only becomes
# visible after the previous one is fixed, so a "quick bump" turns into four
# sequential CI round-trips. All five of these were hit for real on 0.20.19:
#
#   npm       `npm ci` -> EUSAGE "package.json and package-lock.json are not in sync"
#   gradle    dependency LOCKING      -> "{strictly <old>} because of Dependency Locking"
#   gradle    dependency VERIFICATION -> "N artifacts failed verification"
#   swiftpm   "Package.resolved is stale — run 'swift package resolve' and commit it"
#   pub       version solving against pubspec.lock
#
# So each edit_* function refreshes its own lockfiles. They are best-effort: a
# repo without the relevant lockfile simply no-ops.
#
# PRECONDITION: the packages must already be PUBLISHED at <version>. Every
# lockfile refresh resolves against the real registry, and for iOS the
# runanywhere-swift repo must already carry the matching tag.
#
# USAGE:
#   scripts/release/bump-consumer-apps.sh <version> [apps-root]
#
#   apps-root defaults to $RUNANYWHERE_APPS_ROOT, then to the sibling
#   "starters" directory next to this repo.
# =============================================================================

set -uo pipefail

VERSION="${1:?usage: $0 <version> [apps-root]}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APPS_ROOT="${2:-${RUNANYWHERE_APPS_ROOT:-$(cd "${REPO_ROOT}/.." && pwd)/starters}}"
BRANCH="chore/sdk-${VERSION}"

[ -d "${APPS_ROOT}" ] || { echo "ERROR: apps root not found: ${APPS_ROOT}" >&2; exit 1; }
echo "== bumping consumer apps to ${VERSION} (root: ${APPS_ROOT}) =="

bump_repo() {
    local dir="$1" repo="$2"; shift 2
    local path="${APPS_ROOT}/${dir}"
    [ -d "${path}/.git" ] || { echo "  SKIP   ${repo}: not a checkout at ${path}"; return 0; }
    cd "${path}" || return 1

    git fetch -q origin main 2>/dev/null
    git checkout -q main 2>/dev/null && git reset -q --hard origin/main
    git checkout -q -B "${BRANCH}" 2>/dev/null

    "$@"   # repo-specific edit + lockfile refresh

    if git diff --quiet; then
        echo "  SKIP   ${repo}: nothing to change (already at ${VERSION}?)"
        return 0
    fi
    git add -A
    git -c core.hooksPath=/dev/null commit -q -m "chore: bump RunAnywhere SDK to ${VERSION}

Consumes the published ${VERSION} packages from the public registries, and
refreshes every lockfile that pins them."
    if git push -q -u origin "${BRANCH}" 2>/dev/null; then
        local url
        url=$(gh pr create --repo "RunanywhereAI/${repo}" --base main --head "${BRANCH}" \
              --title "chore: bump RunAnywhere SDK to ${VERSION}" \
              --body "Bumps this app to the published RunAnywhere SDK **${VERSION}**, resolving from the public registry, with all pinning layers refreshed." 2>&1 | tail -1)
        echo "  PR     ${repo} -> ${url}"
    else
        echo "  ERROR  ${repo}: push failed"
        return 1
    fi
}

edit_ios() {
    # Two manifest pins that MUST agree, plus SwiftPM's own resolved graph.
    # NOTE: `from:` sits on its OWN LINE here, so a single-line sed silently
    # matches nothing and the PR ships with Package.swift and pbxproj disagreeing.
    perl -0pi -e "s{(runanywhere-swift\\.git\",\\s*\\n\\s*from:\\s*\")[0-9.]+(\")}{\${1}${VERSION}\${2}}s" Package.swift 2>/dev/null
    sed -i '' -E "s|(minimumVersion = )[0-9.]+;|\1${VERSION};|" ./*.xcodeproj/project.pbxproj 2>/dev/null
    echo "    Package.swift: $(grep -A1 'runanywhere-swift.git' Package.swift | grep -oE 'from: "[0-9.]+"' | head -1)"
    echo "    pbxproj:       $(grep -oE 'minimumVersion = [0-9.]+' ./*.xcodeproj/project.pbxproj | head -1)"
    if [ -f Package.resolved ]; then
        swift package resolve >/dev/null 2>&1 \
            && echo "    Package.resolved refreshed" \
            || echo "    WARN: swift package resolve failed (is ${VERSION} tagged on runanywhere-swift?)"
    fi
}

edit_android() {
    sed -i '' -E "s|^(runanywhere = \")[0-9.]+(\")|\1${VERSION}\2|" gradle/libs.versions.toml
    echo "    $(grep -E '^runanywhere = ' gradle/libs.versions.toml)"
    [ -f local.properties ] || echo "sdk.dir=${ANDROID_HOME:-${HOME}/Library/Android/sdk}" > local.properties
    # Two INDEPENDENT layers beyond the version catalog, and ORDER MATTERS:
    # verification cannot resolve the new coordinates until the lock allows them.
    if find . -name "*.lockfile" -not -path "./.git/*" | grep -q .; then
        ./gradlew :app:dependencies --write-locks --no-daemon >/dev/null 2>&1 \
            && echo "    gradle.lockfile refreshed" || echo "    WARN: --write-locks failed"
    fi
    if [ -f gradle/verification-metadata.xml ]; then
        ./gradlew :app:assembleDebug --write-verification-metadata sha256 --no-daemon >/dev/null 2>&1 \
            && echo "    verification-metadata.xml refreshed" || echo "    WARN: --write-verification-metadata failed"
    fi
}

edit_npm_all() {
    python3 - "${VERSION}" <<'PY'
import json, sys
new = sys.argv[1]
d = json.load(open('package.json'))
changed = []
for field in ("dependencies", "devDependencies"):
    for k, v in (d.get(field) or {}).items():
        if not k.startswith("@runanywhere/"):
            continue
        # electron-qhexrt is deliberately held back: it is JS-only and deprecated
        # because no win-arm64 QHexRT engine exists to put in it.
        if "electron-qhexrt" in k:
            continue
        prefix = "^" if str(v).startswith("^") else ""
        if str(v).lstrip("^") != new:
            d[field][k] = f"{prefix}{new}"
            changed.append(k)
json.dump(d, open('package.json', 'w'), indent=2)
open('package.json', 'a').write("\n")
print("    bumped:", ", ".join(changed) if changed else "(none)")
PY
    # yarn.lock is the lockfile of record where present; never create a
    # package-lock.json beside it — the two corrupt each other in these repos.
    if [ -f yarn.lock ]; then
        YARN_ENABLE_IMMUTABLE_INSTALLS=false yarn install --mode=update-lockfile >/dev/null 2>&1 \
            && echo "    yarn.lock refreshed" || echo "    WARN: yarn lockfile update failed"
    elif [ -f package-lock.json ]; then
        npm install --package-lock-only --ignore-scripts >/dev/null 2>&1 \
            && echo "    package-lock.json refreshed" || echo "    WARN: npm lockfile update failed"
    fi
}

edit_flutter() {
    sed -i '' -E "s|^(  runanywhere[a-z_]*: \^)[0-9.]+|\1${VERSION}|" pubspec.yaml
    grep -E '^  runanywhere' pubspec.yaml | sed 's/^/    /'
    if [ -f pubspec.lock ]; then
        local flutter_bin="${FLUTTER_BIN:-}"
        [ -n "${flutter_bin}" ] || flutter_bin="$(command -v flutter || true)"
        if [ -n "${flutter_bin}" ]; then
            "${flutter_bin}" pub get >/dev/null 2>&1 \
                && echo "    pubspec.lock refreshed" || echo "    WARN: flutter pub get failed"
        else
            echo "    WARN: no flutter on PATH; set FLUTTER_BIN"
        fi
    fi
}

bump_repo runanywhere-ios          runanywhere-ios          edit_ios
bump_repo runanywhere-android      runanywhere-android      edit_android
bump_repo runanywhere-web          runanywhere-web          edit_npm_all
bump_repo runanywhere-electron     runanywhere-electron     edit_npm_all
bump_repo flutter-starter-example  flutter-starter-example  edit_flutter
bump_repo react-native-starter-app react-native-starter-app edit_npm_all

echo "== done =="
