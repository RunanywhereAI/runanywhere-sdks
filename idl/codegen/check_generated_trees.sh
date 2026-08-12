#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# check_generated_trees.sh — assert the un-committed codegen output is present
# =============================================================================
# THE FAILURE THIS PREVENTS
#   The bindings listed in idl/codegen/generated_trees.txt are gitignored. Five
#   of those trees ship *inside* a published artifact (SwiftPM tag, npm tarball,
#   pub package, Python sdist/wheel). If a packaging run forgets to generate
#   them first, nothing errors: `npm pack` happily packs an empty dist/,
#   `flutter pub publish --dry-run` happily validates a package with no
#   lib/generated/, and the breakage surfaces as an ImportError or TS2307 in a
#   consumer's project days later.
#
#   So every publish path calls idl/codegen/ensure_generated.sh, and this script
#   is the assertion at the end of it: the trees exist, they are not empty, and
#   the hand-written files that live inside them survived the wipe.
#
# It also verifies the `keep` entries are still TRACKED, which is the direct
# test of the .gitignore negations: get one wrong and a hand-written file
# silently becomes untracked and then silently disappears from the next clone.
#
# Usage:
#   idl/codegen/check_generated_trees.sh          codegen output only
#   idl/codegen/check_generated_trees.sh --only ts
#                                                 restrict to one language's
#                                                 output, so a Web packaging run
#                                                 is not failed by the absence of
#                                                 Dart or Swift bindings it does
#                                                 not ship
#   idl/codegen/check_generated_trees.sh --with-built
#                                                 also require the `built`
#                                                 entries (proto-ts/dist), i.e.
#                                                 the caller already ran tsc
#   idl/codegen/check_generated_trees.sh --files-only
#                                                 skip the `git ls-files` part
#                                                 (for use outside a checkout,
#                                                 e.g. inside an unpacked sdist)
# =============================================================================
set -uo pipefail

export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
MANIFEST="${SCRIPT_DIR}/generated_trees.txt"

FILES_ONLY=0
WITH_BUILT=0
ONLY_LANGS=""
while [ $# -gt 0 ]; do
    case "$1" in
        --files-only) FILES_ONLY=1; shift ;;
        --with-built) WITH_BUILT=1; shift ;;
        # This script does not run under `set -e`, so a bare `shift 2` with one
        # argument left leaves $# unchanged and the loop spins forever.
        --only)
            if [ $# -lt 2 ] || [ -z "${2}" ]; then
                echo "check_generated_trees.sh: --only requires a language list" >&2
                exit 2
            fi
            ONLY_LANGS="$(printf '%s' "${2}" | tr ',' ' ')"
            shift 2
            ;;
        --only=*) ONLY_LANGS="$(printf '%s' "${1#--only=}" | tr ',' ' ')"; shift ;;
        -h|--help) sed -n '2,45p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "check_generated_trees.sh: unknown flag: $1" >&2; exit 2 ;;
    esac
done

# Empty ONLY_LANGS means "every language".
want_lang() {
    [ -z "${ONLY_LANGS}" ] && return 0
    case " ${ONLY_LANGS} " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

[ -f "${MANIFEST}" ] || { echo "check_generated_trees.sh: missing ${MANIFEST}" >&2; exit 2; }

FAILURES=0
CHECKED=0

fail() { echo "  ✗ $*" >&2; FAILURES=$((FAILURES + 1)); }
pass() { echo "  ✓ $*"; }

# `git ls-files --error-unmatch` is the only reliable "is this tracked?" probe:
# it ignores the working tree and answers from the index, so an ignored-but-
# present file is correctly reported as untracked.
is_tracked() {
    git -C "${REPO_ROOT}" ls-files --error-unmatch -- "$1" >/dev/null 2>&1
}

in_git_checkout() {
    git -C "${REPO_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

echo ">> verifying generated trees under ${REPO_ROOT}"

while IFS=$'\t' read -r kind lang path minfiles note; do
    case "${kind}" in
        ''|'#'*) continue ;;
    esac
    [ -n "${path:-}" ] || continue
    want_lang "${lang}" || continue
    if [ "${kind}" = "built" ] && [ "${WITH_BUILT}" -eq 0 ]; then
        continue
    fi
    CHECKED=$((CHECKED + 1))
    abs="${REPO_ROOT}/${path}"

    case "${kind}" in
        tree|built)
            if [ ! -d "${abs}" ]; then
                fail "${path}: directory missing — codegen did not run"
                continue
            fi
            n="$(find "${abs}" -type f ! -name '.*' | wc -l | tr -d ' ')"
            if [ "${n}" -lt "${minfiles}" ]; then
                fail "${path}: ${n} files, expected >= ${minfiles} (${note})"
            else
                pass "${path}: ${n} files"
            fi
            ;;
        file)
            if [ ! -f "${abs}" ]; then
                fail "${path}: missing — codegen did not run (${note})"
            else
                pass "${path}"
            fi
            ;;
        keep)
            if [ ! -f "${abs}" ]; then
                fail "${path}: MISSING — a hand-written file was destroyed by a codegen wipe (${note})"
                continue
            fi
            if [ "${FILES_ONLY}" -eq 0 ] && in_git_checkout && ! is_tracked "${path}"; then
                fail "${path}: present but NOT TRACKED — a .gitignore rule is swallowing a hand-written file (${note})"
                continue
            fi
            pass "${path} (tracked, hand-written)"
            ;;
        *)
            fail "unknown manifest kind '${kind}' for ${path}"
            ;;
    esac
done < "${MANIFEST}"

# The inverse assertion: nothing generated may be TRACKED. A `git add -f`, or a
# .gitignore edit that loses a rule, would re-commit hundreds of machine files
# and quietly undo the whole arrangement — and unlike a missing tree, that
# failure produces no symptom at all until the next 600-file diff.
if [ "${FILES_ONLY}" -eq 0 ] && in_git_checkout; then
    while IFS=$'\t' read -r kind lang path minfiles note; do
        case "${kind}" in tree|built|file) ;; *) continue ;; esac
        [ -n "${path:-}" ] || continue
        want_lang "${lang}" || continue
        # `keep` paths are legitimately tracked; subtract them.
        leaked="$(git -C "${REPO_ROOT}" ls-files -- "${path}" \
            | grep -vxF -f <(awk -F'\t' '$1=="keep"{print $3}' "${MANIFEST}") || true)"
        if [ -n "${leaked}" ]; then
            fail "${path}: generated files are TRACKED — the .gitignore rule is not taking effect:"
            printf '%s\n' "${leaked}" | head -5 | sed 's/^/       /' >&2
            n="$(printf '%s\n' "${leaked}" | wc -l | tr -d ' ')"
            [ "${n}" -gt 5 ] && echo "       ... and $((n - 5)) more" >&2
        fi
    done < "${MANIFEST}"
fi

if [ "${CHECKED}" -eq 0 ]; then
    echo "check_generated_trees.sh: manifest parsed to zero entries — is ${MANIFEST} tab-separated?" >&2
    exit 2
fi

if [ "${FAILURES}" -ne 0 ]; then
    echo "" >&2
    echo "::error::${FAILURES} generated-code problem(s). Run ./idl/codegen/generate_all.sh" >&2
    echo "         (and, for bindings/proto-ts/dist, 'npm run build' in bindings/proto-ts)." >&2
    exit 1
fi

echo "✓ all ${CHECKED} generated-code entries present"
