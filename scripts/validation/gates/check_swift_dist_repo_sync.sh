#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# check_swift_dist_repo_sync.sh
# =============================================================================
# RunanywhereAI/runanywhere-swift is a generated, Swift-only distribution repo
# (Package.swift + Sources/ + LICENSE + README.md) that exists so SwiftPM
# consumers clone ~3 MB instead of the ~340 MB monorepo. Its manifest declares
# the SAME remote binaryTargets, against the SAME release assets on
# runanywhere-sdks, with the SAME checksums — the XCFrameworks are never
# re-uploaded.
#
# THE FAILURE THIS PREVENTS
#   Nothing else in the release path knows that repo exists. Publish v0.20.18
#   here, forget to cut the split repo, and it stays at 0.20.17 — so
#   `from: "0.20.18"` resolves to nothing for every Swift consumer, silently,
#   until someone files a bug. A line in a runbook does not prevent that.
#
# THE TRIGGER
#   Enforcement keys off "has this version actually been released?", i.e. does
#   the monorepo tag v${VERSION} exist. That is the only point at which the
#   split repo *can* be tagged (its manifest points at that release's assets)
#   and therefore the only point at which being untagged is a real defect.
#
#     - VERSION not yet tagged (an in-flight release PR, a version bump under
#       review) -> nothing to compare, SKIP. A normal PR is never failed by
#       this gate for work unrelated to releasing.
#     - VERSION tagged -> runanywhere-swift MUST carry the matching tag.
#
#   So the moment v0.20.18 is pushed here, every subsequent CI run fails until
#   runanywhere-swift is cut at 0.20.18. Forgetting stops being possible; it
#   becomes a red build on the next PR that touches anything.
#
# OFFLINE / AIR-GAPPED
#   The tag probe needs the network. If it cannot reach the remote the gate
#   SKIPs rather than failing, so local runs and offline CI stay green.
#   RAC_SKIP_SWIFT_DIST_REPO_CHECK=1 opts out explicitly.
#
# LOCAL PRE-TAG VERIFICATION
#   Export RUNANYWHERE_SWIFT_DIST_REPO=/path/to/runanywhere-swift (the same
#   variable bindings/swift/scripts/sync-checksums.sh uses) and this gate also
#   cross-checks that working copy fully offline: its sdkVersion must equal
#   this repo's, and all six binaryTarget checksums must match the root
#   manifest byte for byte. That is what you run *before* tagging.
#
# Cut the split repo with:
#   bindings/swift/scripts/sync-dist-repo.sh <checkout>
#
# Usage:
#   scripts/validation/gates/check_swift_dist_repo_sync.sh      (no arguments)
#
# Environment:
#   RUNANYWHERE_SWIFT_DIST_REPO      optional checkout to cross-check offline
#   RAC_SKIP_SWIFT_DIST_REPO_CHECK=1 skip entirely
#
# Exit codes:
#   0  in sync, or legitimately skipped (unreleased version / offline)
#   1  drift: the released version has no matching runanywhere-swift tag, or a
#      provided checkout disagrees with this repo
#   2  tooling error (a required program is missing)
# =============================================================================

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/core/VERSION")"
PACKAGE_SWIFT="${REPO_ROOT}/Package.swift"
DIST_REPO_URL="https://github.com/RunanywhereAI/runanywhere-swift.git"
FAILURES=0

if ! [[ "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?$ ]]; then
  echo "[FAIL] invalid canonical release version: ${VERSION}" >&2
  exit 1
fi

if [ "${RAC_SKIP_SWIFT_DIST_REPO_CHECK:-0}" = "1" ]; then
  echo "[SKIP] runanywhere-swift sync check disabled via RAC_SKIP_SWIFT_DIST_REPO_CHECK"
  exit 0
fi

command -v git >/dev/null 2>&1 || { echo "[FAIL] git not found on PATH." >&2; exit 2; }
if [ -n "${RUNANYWHERE_SWIFT_DIST_REPO:-}" ]; then
  command -v python3 >/dev/null 2>&1 || {
    echo "[FAIL] python3 not found on PATH; required to read manifest checksums." >&2
    exit 2
  }
fi

# The six remote binaryTargets shared by both manifests. Names are byte
# identical across repos, which is what lets one regex serve both.
BINARY_TARGETS=(
  RACommonsBinary
  RABackendLlamaCPPBinary
  RABackendONNXBinary
  RABackendSherpaBinary
  RABackendNeuRTBinary
  RABackendMLXBinary
)

# Reads the checksum of a remote binaryTarget. Requires `url:` between the name
# and the checksum so the local-development entry (which uses `path:` and has no
# checksum) can never be picked up by accident.
read_binary_checksum() {
  local manifest="$1"
  local binary_name="$2"
  python3 - "$manifest" "$binary_name" <<'PY'
import re, sys

path, binary_name = sys.argv[1:]
with open(path) as f:
    src = f.read()
pattern = re.compile(
    r'name:\s*"' + re.escape(binary_name)
    + r'"\s*,\s*url:\s*"[^"]+"\s*,\s*checksum:\s*"([0-9a-f]{64})"',
    re.DOTALL,
)
m = pattern.search(src)
print(m.group(1) if m else "")
PY
}

# ---------------------------------------------------------------------------
# Offline cross-check of a local distribution-repo checkout, when one is given.
# ---------------------------------------------------------------------------
verify_dist_checkout() {
  local checkout="${RUNANYWHERE_SWIFT_DIST_REPO%/}"
  local dist_manifest="${checkout}/Package.swift"

  if [ ! -f "${dist_manifest}" ]; then
    echo "[FAIL] RUNANYWHERE_SWIFT_DIST_REPO is set but no Package.swift at ${dist_manifest}" >&2
    FAILURES=$((FAILURES + 1))
    return
  fi

  local dist_version
  dist_version="$(awk -F'"' '/^let sdkVersion = "/ { print $2; exit }' "${dist_manifest}")"
  if [ "${dist_version}" != "${VERSION}" ]; then
    echo "[FAIL] ${dist_manifest}: sdkVersion '${dist_version:-<missing>}' != canonical '${VERSION}'" >&2
    echo "       Run: bindings/swift/scripts/sync-dist-repo.sh ${checkout}" >&2
    FAILURES=$((FAILURES + 1))
    return
  fi

  local mismatches=0
  local target root_sum dist_sum
  for target in "${BINARY_TARGETS[@]}"; do
    root_sum="$(read_binary_checksum "${PACKAGE_SWIFT}" "${target}")"
    dist_sum="$(read_binary_checksum "${dist_manifest}" "${target}")"
    if [ -z "${root_sum}" ]; then
      echo "[FAIL] Package.swift: no remote binaryTarget '${target}'" >&2
      mismatches=$((mismatches + 1))
      continue
    fi
    if [ -z "${dist_sum}" ]; then
      echo "[FAIL] ${dist_manifest}: no remote binaryTarget '${target}'" >&2
      mismatches=$((mismatches + 1))
      continue
    fi
    if [ "${root_sum}" != "${dist_sum}" ]; then
      echo "[FAIL] ${target}: checksum drift between manifests" >&2
      echo "       Package.swift:              ${root_sum}" >&2
      echo "       runanywhere-swift manifest: ${dist_sum}" >&2
      mismatches=$((mismatches + 1))
    fi
  done

  if [ "${mismatches}" -ne 0 ]; then
    echo "       Re-run: RUNANYWHERE_SWIFT_DIST_REPO=${checkout} \\" >&2
    echo "                 bindings/swift/scripts/sync-checksums.sh <zip_dir>" >&2
    FAILURES=$((FAILURES + mismatches))
    return
  fi

  echo "[OK] runanywhere-swift checkout matches: sdkVersion ${VERSION}, all ${#BINARY_TARGETS[@]} checksums"
}

if [ -n "${RUNANYWHERE_SWIFT_DIST_REPO:-}" ]; then
  verify_dist_checkout
fi

# ---------------------------------------------------------------------------
# Is this version actually released? Only then must the split repo carry a tag.
# ---------------------------------------------------------------------------
# actions/checkout fetches no tags by default, so a local-only probe finds
# nothing on CI even when the tag exists. Ask the remote as a fallback, exactly
# as check_release_version_coherence.sh does.
monorepo_tag_exists() {
  if git -C "${REPO_ROOT}" rev-parse -q --verify "refs/tags/v${VERSION}" >/dev/null 2>&1; then
    return 0
  fi
  if git -C "${REPO_ROOT}" ls-remote --exit-code --tags origin "refs/tags/v${VERSION}" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

# Never let a credential prompt or a dead network hang CI on this gate.
export GIT_TERMINAL_PROMPT=0
run_with_timeout() {
  if command -v timeout >/dev/null 2>&1; then
    timeout 30 "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout 30 "$@"
  else
    "$@"
  fi
}

if ! monorepo_tag_exists; then
  echo "[SKIP] v${VERSION} is not tagged yet; runanywhere-swift is cut after the release is published"
  if [ "${FAILURES}" -ne 0 ]; then
    echo "[FAIL] runanywhere-swift distribution sync: ${FAILURES} problem(s)" >&2
    exit 1
  fi
  exit 0
fi

DIST_TAGS=""
if ! DIST_TAGS="$(run_with_timeout git ls-remote --tags "${DIST_REPO_URL}" 2>/dev/null)"; then
  echo "[SKIP] cannot reach ${DIST_REPO_URL}; skipping the released-tag check (offline)"
  if [ "${FAILURES}" -ne 0 ]; then
    echo "[FAIL] runanywhere-swift distribution sync: ${FAILURES} problem(s)" >&2
    exit 1
  fi
  exit 0
fi

# The split repo tags WITHOUT a leading `v` (SwiftPM `from:` resolves bare
# semver), while the monorepo tags v-prefixed. That asymmetry is deliberate.
if grep -qE "refs/tags/${VERSION}(\^\{\})?$" <<< "${DIST_TAGS}"; then
  echo "[OK] runanywhere-swift is released at ${VERSION}, matching monorepo v${VERSION}"
else
  LATEST_DIST_TAG="$(
    sed -nE 's@^.*refs/tags/([0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?)$@\1@p' <<< "${DIST_TAGS}" \
      | sort -V | tail -1
  )"
  echo "[FAIL] runanywhere-swift has no ${VERSION} tag (latest: ${LATEST_DIST_TAG:-<none>})" >&2
  echo "       v${VERSION} is published here, so 'from: \"${VERSION}\"' is broken for every" >&2
  echo "       SwiftPM consumer of ${DIST_REPO_URL}" >&2
  echo "       Cut it with:" >&2
  echo "         git clone ${DIST_REPO_URL} /tmp/ra-swift" >&2
  echo "         bindings/swift/scripts/sync-dist-repo.sh /tmp/ra-swift" >&2
  echo "       then sync checksums, push, and tag ${VERSION} (no 'v' prefix)." >&2
  FAILURES=$((FAILURES + 1))
fi

if [ "${FAILURES}" -ne 0 ]; then
  echo "[FAIL] runanywhere-swift distribution sync: ${FAILURES} problem(s)" >&2
  exit 1
fi

echo "[OK] runanywhere-swift distribution sync: ${VERSION}"
