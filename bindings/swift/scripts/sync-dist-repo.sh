#!/usr/bin/env bash
# =============================================================================
# sync-dist-repo.sh
# =============================================================================
# Refreshes a checkout of the standalone Swift distribution repo
#   https://github.com/RunanywhereAI/runanywhere-swift
# from this monorepo, so it can be committed and tagged at the current release.
#
# WHY THAT REPO EXISTS
#   `.package(url: ".../runanywhere-sdks", from: "…")` makes SwiftPM clone the
#   entire monorepo (~340 MB) to build a Swift package that needs only Sources/
#   plus remote binaryTargets. runanywhere-swift carries the Swift surface and
#   nothing else (~3 MB) and points at the SAME release assets with the SAME
#   checksums — the XCFrameworks are never re-uploaded.
#
# WHAT THIS SCRIPT OWNS
#   Sources/      regenerated from `git ls-files bindings/swift/Sources`, minus
#                 the packaging-only targets that must not ship to consumers.
#   Package.swift `let sdkVersion` bumped to core/VERSION. The rest of that
#                 manifest is hand-authored in the distribution repo (its own
#                 products, its own MLX dependency mirroring) and is carried
#                 forward untouched — this script never regenerates it.
#   README.md     version references retargeted at the new release.
#   LICENSE       copied from the monorepo root.
#
# WHAT THIS SCRIPT DOES NOT OWN
#   Checksums. bindings/swift/scripts/sync-checksums.sh already updates both
#   manifests in one pass; pass --zips to chain it here.
#
# Usage:
#   bindings/swift/scripts/sync-dist-repo.sh [options] DIST_REPO_PATH
#
# Options:
#   --check         Report what would change; write nothing. Exit 1 on drift.
#   --zips DIR      After syncing, run sync-checksums.sh against DIR so the
#                   distribution manifest gets this release's checksums too.
#   --commit        Commit the result in DIST_REPO_PATH.
#   --tag           Create the <version> tag (no 'v' prefix). Implies --commit.
#
# Never pushes. Review, then push the distribution repo yourself.
#
# Example — full cut once the Apple archives exist:
#   git clone https://github.com/RunanywhereAI/runanywhere-swift.git /tmp/ra-swift
#   bindings/swift/scripts/sync-dist-repo.sh \
#       --zips release-artifacts/native-ios-macos --tag /tmp/ra-swift
#   git -C /tmp/ra-swift push origin main --follow-tags
#
# Verify at any time with:
#   RUNANYWHERE_SWIFT_DIST_REPO=/tmp/ra-swift \
#     scripts/validation/gates/check_swift_dist_repo_sync.sh
# =============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

MODE="update"
ZIP_DIR=""
DO_COMMIT=0
DO_TAG=0
DIST_REPO=""

while [ $# -gt 0 ]; do
    case "$1" in
        --check)  MODE="check"; shift ;;
        --zips)   ZIP_DIR="${2:-}"; shift 2 ;;
        --commit) DO_COMMIT=1; shift ;;
        --tag)    DO_TAG=1; DO_COMMIT=1; shift ;;
        -h|--help)
            sed -n '2,50p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        -*)
            echo "ERROR: unknown option: $1" >&2
            exit 1 ;;
        *)
            if [ -n "$DIST_REPO" ]; then
                echo "ERROR: unexpected extra argument: $1" >&2
                exit 1
            fi
            DIST_REPO="$1"; shift ;;
    esac
done

if [ -z "$DIST_REPO" ]; then
    echo "usage: $0 [--check] [--zips DIR] [--commit] [--tag] DIST_REPO_PATH" >&2
    exit 1
fi
if [ "$MODE" = "check" ] && { [ "$DO_COMMIT" -eq 1 ] || [ -n "$ZIP_DIR" ]; }; then
    echo "ERROR: --check cannot be combined with --zips/--commit/--tag" >&2
    exit 1
fi

DIST_REPO="${DIST_REPO%/}"
if [ ! -d "$DIST_REPO/.git" ]; then
    echo "ERROR: not a git checkout: $DIST_REPO" >&2
    echo "       git clone https://github.com/RunanywhereAI/runanywhere-swift.git $DIST_REPO" >&2
    exit 1
fi

DIST_MANIFEST="$DIST_REPO/Package.swift"
if [ ! -f "$DIST_MANIFEST" ]; then
    echo "ERROR: no Package.swift in $DIST_REPO — is this the runanywhere-swift repo?" >&2
    exit 1
fi
if ! grep -q '^let sdkVersion = "' "$DIST_MANIFEST"; then
    echo "ERROR: $DIST_MANIFEST has no 'let sdkVersion' line" >&2
    exit 1
fi

VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/core/VERSION")"
if ! [[ "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?$ ]]; then
    echo "ERROR: invalid canonical release version: ${VERSION}" >&2
    exit 1
fi
OLD_VERSION="$(awk -F'"' '/^let sdkVersion = "/ { print $2; exit }' "$DIST_MANIFEST")"

# Packaging-only Swift targets that exist for CocoaPods/CLI packaging inside the
# monorepo and are deliberately absent from the consumer-facing package.
EXCLUDED_TARGETS_RE='^Sources/(MLXRuntimeDistribution|RunAnywhereMLXCLI)/'

echo ">> runanywhere-swift distribution sync"
echo ">> monorepo:     ${REPO_ROOT}"
echo ">> distribution: ${DIST_REPO}"
echo ">> version:      ${OLD_VERSION:-<none>} -> ${VERSION}"
if [ "$MODE" = "check" ]; then
    echo ">> mode:         check (no writes)"
fi
echo ""

# --- 1. Sources/ -----------------------------------------------------------
# git ls-files is the source of truth: it tracks exactly what is committed and
# silently skips build detritus, so a dirty bindings/swift cannot leak.
# Built with a read loop rather than `mapfile`: macOS ships bash 3.2, which has
# no mapfile, and this script must run on a stock macOS release runner.
SOURCE_FILES=()
while IFS= read -r rel; do
    [ -z "$rel" ] && continue
    SOURCE_FILES+=("$rel")
done < <(
    git -C "${REPO_ROOT}" ls-files bindings/swift/Sources \
        | sed 's|^bindings/swift/||' \
        | grep -vE "${EXCLUDED_TARGETS_RE}" \
        | sort
)
if [ "${#SOURCE_FILES[@]}" -eq 0 ]; then
    echo "ERROR: no tracked files under bindings/swift/Sources" >&2
    exit 1
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
for rel in "${SOURCE_FILES[@]}"; do
    mkdir -p "$STAGE/$(dirname "$rel")"
    cp "${REPO_ROOT}/bindings/swift/$rel" "$STAGE/$rel"
done

added=0; changed=0; removed=0
for rel in "${SOURCE_FILES[@]}"; do
    if [ ! -f "$DIST_REPO/$rel" ]; then
        added=$((added + 1))
        [ "$MODE" = "check" ] && echo "  + $rel"
    elif ! cmp -s "$STAGE/$rel" "$DIST_REPO/$rel"; then
        changed=$((changed + 1))
        [ "$MODE" = "check" ] && echo "  ~ $rel"
    fi
done
# Scan the filesystem, not `git ls-files`: update mode replaces Sources/
# wholesale, so an untracked stray downstream is deleted too and --check must
# predict that rather than quietly ignoring it.
if [ -d "$DIST_REPO/Sources" ]; then
    while IFS= read -r abs; do
        [ -z "$abs" ] && continue
        rel="${abs#"$DIST_REPO"/}"
        if [ ! -f "$STAGE/$rel" ]; then
            removed=$((removed + 1))
            [ "$MODE" = "check" ] && echo "  - $rel"
        fi
    done < <(find "$DIST_REPO/Sources" -type f)
fi

if [ "$MODE" = "update" ]; then
    # Replace wholesale so a target deleted upstream cannot linger downstream.
    rm -rf "${DIST_REPO:?}/Sources"
    cp -R "$STAGE/Sources" "$DIST_REPO/Sources"
fi
echo "  Sources/: ${#SOURCE_FILES[@]} files (${added} added, ${changed} changed, ${removed} removed)"

# --- 2. Package.swift sdkVersion -------------------------------------------
manifest_drift=0
if [ "$OLD_VERSION" != "$VERSION" ]; then
    manifest_drift=1
    if [ "$MODE" = "update" ]; then
        python3 - "$DIST_MANIFEST" "$VERSION" <<'PY'
import re, sys
path, version = sys.argv[1:]
with open(path) as f:
    src = f.read()
new, n = re.subn(r'^let sdkVersion = "[^"]+"$',
                 f'let sdkVersion = "{version}"', src, count=1, flags=re.M)
if n != 1:
    sys.exit("ERROR: could not rewrite sdkVersion")
with open(path, "w") as f:
    f.write(new)
PY
        echo "  Package.swift: sdkVersion -> ${VERSION}"
    else
        echo "  ~ Package.swift: sdkVersion ${OLD_VERSION} -> ${VERSION}"
    fi
else
    echo "  Package.swift: sdkVersion already ${VERSION}"
fi

# --- 3. README.md version references ---------------------------------------
DIST_README="$DIST_REPO/README.md"
if [ -f "$DIST_README" ] && [ -n "$OLD_VERSION" ] && [ "$OLD_VERSION" != "$VERSION" ]; then
    hits="$(grep -Fc -- "$OLD_VERSION" "$DIST_README" || true)"
    if [ "$hits" -gt 0 ]; then
        manifest_drift=1
        if [ "$MODE" = "update" ]; then
            python3 - "$DIST_README" "$OLD_VERSION" "$VERSION" <<'PY'
import sys
path, old, new = sys.argv[1:]
with open(path) as f:
    src = f.read()
with open(path, "w") as f:
    f.write(src.replace(old, new))
PY
            echo "  README.md: ${hits} version reference(s) -> ${VERSION}"
        else
            echo "  ~ README.md: ${hits} reference(s) still at ${OLD_VERSION}"
        fi
    fi
fi

# --- 4. LICENSE -------------------------------------------------------------
if ! cmp -s "${REPO_ROOT}/LICENSE" "$DIST_REPO/LICENSE"; then
    manifest_drift=1
    if [ "$MODE" = "update" ]; then
        cp "${REPO_ROOT}/LICENSE" "$DIST_REPO/LICENSE"
        echo "  LICENSE: refreshed from monorepo root"
    else
        echo "  ~ LICENSE: differs from monorepo root"
    fi
fi

if [ "$MODE" = "check" ]; then
    echo ""
    if [ "$((added + changed + removed))" -eq 0 ] && [ "$manifest_drift" -eq 0 ]; then
        echo ">> In sync at ${VERSION}."
        exit 0
    fi
    echo "ERROR: distribution repo is out of sync with the monorepo" >&2
    echo "       Run: $0 ${DIST_REPO}" >&2
    exit 1
fi

# --- 5. Checksums (delegated) ----------------------------------------------
if [ -n "$ZIP_DIR" ]; then
    echo ""
    RUNANYWHERE_SWIFT_DIST_REPO="$DIST_REPO" \
        "${REPO_ROOT}/bindings/swift/scripts/sync-checksums.sh" "$ZIP_DIR"
fi

# --- 6. Commit / tag --------------------------------------------------------
if [ "$DO_COMMIT" -eq 1 ]; then
    echo ""
    if [ -z "$(git -C "$DIST_REPO" status --porcelain)" ]; then
        echo ">> Nothing to commit; distribution repo already matches ${VERSION}."
    else
        git -C "$DIST_REPO" add -A
        git -C "$DIST_REPO" commit -q -m "chore: sync RunAnywhere Swift SDK to ${VERSION}

Generated from RunanywhereAI/runanywhere-sdks by
bindings/swift/scripts/sync-dist-repo.sh. Do not hand-edit."
        echo ">> Committed: $(git -C "$DIST_REPO" log --oneline -1)"
    fi
fi

if [ "$DO_TAG" -eq 1 ]; then
    if git -C "$DIST_REPO" rev-parse -q --verify "refs/tags/${VERSION}" >/dev/null 2>&1; then
        echo ">> Tag ${VERSION} already exists in ${DIST_REPO}; leaving it alone."
    else
        # No 'v' prefix: SwiftPM `from: "x.y.z"` resolves bare semver tags.
        git -C "$DIST_REPO" tag -a "${VERSION}" -m "RunAnywhere Swift SDK ${VERSION}"
        echo ">> Tagged ${VERSION}"
    fi
fi

echo ""
echo ">> Done."
if [ -z "$ZIP_DIR" ]; then
    echo ">> Checksums NOT synced. Once the Apple archives exist, run:"
    echo "     RUNANYWHERE_SWIFT_DIST_REPO=${DIST_REPO} \\"
    echo "       bindings/swift/scripts/sync-checksums.sh <zip_dir>"
fi
if [ "$DO_TAG" -eq 0 ]; then
    echo ">> Then commit and tag ${VERSION} (no 'v' prefix):"
    echo "     $0 --tag ${DIST_REPO}"
fi
echo ">> Verify before pushing:"
echo "     RUNANYWHERE_SWIFT_DIST_REPO=${DIST_REPO} \\"
echo "       scripts/validation/gates/check_swift_dist_repo_sync.sh"
echo ">> Then: git -C ${DIST_REPO} push origin main --follow-tags"
