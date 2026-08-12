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
#   Sources/      regenerated from `git ls-files bindings/swift/Sources` PLUS
#                 everything on disk under Sources/RunAnywhere/Generated, minus
#                 the packaging-only targets that must not ship to consumers.
#
#                 That union is load-bearing. Sources/RunAnywhere/Generated is
#                 IDL codegen output and is gitignored, so `git ls-files` alone
#                 returns exactly one file from it (Versions.swift) — this
#                 script would copy 41 fewer files, commit, and tag a
#                 distribution repo that does not compile, with no error
#                 anywhere. SwiftPM has no build hook and no packaging step: it
#                 clones the tag and compiles what is there, so this script IS
#                 the Swift packaging step. It therefore runs codegen itself
#                 (step 0) and hard-fails if the generated tree is missing or
#                 implausibly small.
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
#   --check         Report what would change; write nothing to DIST_REPO_PATH.
#                   Still runs codegen in the monorepo — comparing against an
#                   absent Generated/ would report 41 phantom deletions.
#   --no-codegen    Skip the codegen step (the generated tree must already be
#                   present; it is still verified). For a release job that ran
#                   idl/codegen/generate_all.sh once for all five SDKs.
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
RUN_CODEGEN=1

while [ $# -gt 0 ]; do
    case "$1" in
        --check)  MODE="check"; shift ;;
        --no-codegen) RUN_CODEGEN=0; shift ;;
        --zips)   ZIP_DIR="${2:-}"; shift 2 ;;
        --commit) DO_COMMIT=1; shift ;;
        --tag)    DO_TAG=1; DO_COMMIT=1; shift ;;
        -h|--help)
            sed -n '2,70p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
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
    echo "usage: $0 [--check] [--no-codegen] [--zips DIR] [--commit] [--tag] DIST_REPO_PATH" >&2
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

# The IDL codegen output that `git ls-files` cannot see, relative to
# bindings/swift/. Mirrors the `tree` entry in idl/codegen/generated_trees.txt.
GENERATED_SUBDIR='Sources/RunAnywhere/Generated'
# Floor, not an exact count: adding a .proto legitimately raises it. This exists
# to catch "codegen produced nothing", which is the failure that would otherwise
# ship a distribution tag that does not compile.
GENERATED_MIN_FILES=40

echo ">> runanywhere-swift distribution sync"
echo ">> monorepo:     ${REPO_ROOT}"
echo ">> distribution: ${DIST_REPO}"
echo ">> version:      ${OLD_VERSION:-<none>} -> ${VERSION}"
if [ "$MODE" = "check" ]; then
    echo ">> mode:         check (no writes)"
fi
echo ""

# --- 0. IDL codegen ---------------------------------------------------------
# Must precede the file enumeration below: Sources/RunAnywhere/Generated is
# gitignored, so it may simply not exist in a fresh clone.
if [ "$RUN_CODEGEN" -eq 1 ]; then
    echo ">> generating IDL bindings first (Sources/RunAnywhere/Generated is not tracked)"
    "${REPO_ROOT}/idl/codegen/ensure_generated.sh" --only swift
    echo ""
else
    echo ">> --no-codegen: verifying the generated tree is already present"
    "${REPO_ROOT}/idl/codegen/check_generated_trees.sh" --only swift >/dev/null
    echo ""
fi

# --- 1. Sources/ -----------------------------------------------------------
# Two sources, unioned:
#   a) `git ls-files` for the hand-written Swift — it tracks exactly what is
#      committed and silently skips build detritus, so a dirty bindings/swift
#      cannot leak.
#   b) `find` over Sources/RunAnywhere/Generated — codegen output, gitignored,
#      therefore invisible to (a). Without this the distribution repo ships a
#      Swift package with no proto types and no error is raised anywhere.
# Built with read loops rather than `mapfile`: macOS ships bash 3.2, which has
# no mapfile, and this script must run on a stock macOS release runner.
GENERATED_ABS="${REPO_ROOT}/bindings/swift/${GENERATED_SUBDIR}"
if [ ! -d "${GENERATED_ABS}" ]; then
    echo "ERROR: ${GENERATED_SUBDIR} does not exist under bindings/swift/." >&2
    echo "       It is IDL codegen output and is not tracked by git. Run:" >&2
    echo "         ./idl/codegen/generate_all.sh" >&2
    exit 1
fi

# Each producer runs separately with its exit status checked. `set -e` and
# pipefail do NOT reach inside a process substitution: a failing `git ls-files`
# or a `find` over a missing Generated/ is invisible there — the loop just reads
# fewer lines — and the count guards below would then pass on a plausible but
# incomplete list, which is the exact failure this section exists to prevent.
# No EXIT trap here: one is installed further down for $STAGE and a second
# would replace it. The file is removed inline once it has been read.
SOURCE_LIST="$(mktemp)"

if ! git -C "${REPO_ROOT}" ls-files bindings/swift/Sources \
        | sed 's|^bindings/swift/||' > "${SOURCE_LIST}"; then
    echo "ERROR: git ls-files bindings/swift/Sources failed" >&2
    exit 1
fi
if ! find "${GENERATED_ABS}" -type f ! -name '.*' \
        | sed "s|^${REPO_ROOT}/bindings/swift/||" >> "${SOURCE_LIST}"; then
    echo "ERROR: could not enumerate ${GENERATED_ABS}." >&2
    echo "       Run ./idl/codegen/generate_all.sh --only swift first." >&2
    exit 1
fi

SOURCE_FILES=()
while IFS= read -r rel; do
    [ -z "$rel" ] && continue
    SOURCE_FILES+=("$rel")
done < <(grep -vE "${EXCLUDED_TARGETS_RE}" "${SOURCE_LIST}" | LC_ALL=C sort -u)
rm -f "${SOURCE_LIST}"
if [ "${#SOURCE_FILES[@]}" -eq 0 ]; then
    echo "ERROR: no files under bindings/swift/Sources" >&2
    exit 1
fi

# Prove the generated payload is actually in the list. `git ls-files` returns
# exactly one file from Generated/ (the hand-written Versions.swift), so a
# regression that drops the find(1) branch would still yield a plausible-looking
# ~250-file list and a distribution repo that fails to compile at the tag.
generated_count=0
for rel in "${SOURCE_FILES[@]}"; do
    case "$rel" in
        "${GENERATED_SUBDIR}"/*) generated_count=$((generated_count + 1)) ;;
    esac
done
if [ "${generated_count}" -lt "${GENERATED_MIN_FILES}" ]; then
    echo "ERROR: only ${generated_count} file(s) under ${GENERATED_SUBDIR}; expected >= ${GENERATED_MIN_FILES}." >&2
    echo "       The Swift proto bindings are IDL codegen output and are gitignored." >&2
    echo "       Shipping this would tag a runanywhere-swift that does not compile." >&2
    echo "       Run ./idl/codegen/generate_all.sh and retry." >&2
    exit 1
fi
echo "  codegen: ${generated_count} files under ${GENERATED_SUBDIR}"

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
