#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# =============================================================================
# ci-drift-check.sh — the IDL gate
# =============================================================================
# WHAT CHANGED AND WHY
#   This used to be "regenerate, then `git diff --exit-code` must be empty".
#   That check is now meaningless for most of the output: the Swift, TypeScript,
#   Dart, React Native and Python bindings are gitignored, so regenerating them
#   can never move `git status`. A gate that cannot fail is worse than no gate,
#   because it reads green.
#
#   The replacement has four parts, in order of what each can catch:
#
#   1. SCHEMA LOCK — idl/SCHEMA_LOCK is tracked and generate_all.sh refreshes it
#      from the .proto digest. Edit a schema without running codegen and the
#      committed lock no longer matches: that is now the drift signal.
#
#   2. PRESENCE — check_generated_trees.sh asserts every tree was actually
#      written, and that none of them came back TRACKED. Nothing generated is
#      committed any more, so "regenerate and diff" is gone entirely; the
#      inverse assertion (no generated file is in the index) took its place.
#
#   3. COMPILE — the generated TypeScript is fed to tsc and the generated Python
#      is imported. Those are the two languages where a bad generator produces
#      output that looks fine and fails only downstream. The C/C++ and Kotlin
#      trees are compiled by the native and kotlin-android jobs in pr-build.yml,
#      which now generate before they build.
#
# Run locally:
#   ./idl/codegen/ci-drift-check.sh                  parts 1-3 + 5
#   ./idl/codegen/ci-drift-check.sh --with-compile   ...and part 4 (needs npm)
#
# Run in CI:
#   .github/workflows/idl-drift-check.yml            always --with-compile
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

WITH_COMPILE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --with-compile) WITH_COMPILE=1; shift ;;
        -h|--help) sed -n '2,45p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "ci-drift-check.sh: unknown flag: $1" >&2; exit 2 ;;
    esac
done

cd "${REPO_ROOT}"

DRIFT=0
step() { echo ""; echo "── $* ──"; }

# --- 1. Regenerate every language ------------------------------------------
# Snapshot the working tree first. The old gate could assert "git status is
# empty" afterwards; with most output ignored, the meaningful question is
# narrower — did this run change anything it did not declare? — and that is a
# before/after comparison, not an absolute one.
BEFORE_STATUS="$(mktemp)"; AFTER_STATUS="$(mktemp)"
trap 'rm -f "${BEFORE_STATUS}" "${AFTER_STATUS}"' EXIT
git status --porcelain --untracked-files=all | LC_ALL=C sort > "${BEFORE_STATUS}"

step "regenerating every binding"
if ! "${SCRIPT_DIR}/generate_all.sh"; then
    echo "::error::generate_all.sh failed" >&2
    exit 1
fi

# --- 2. Schema lock ---------------------------------------------------------
step "schema lock"
if ! "${SCRIPT_DIR}/schema_lock.sh" --check; then
    DRIFT=1
fi
# generate_all.sh refreshes the lock; if that left the working tree dirty, the
# committed lock was stale, i.e. someone edited a .proto without regenerating.
if ! git diff --exit-code --quiet -- idl/SCHEMA_LOCK; then
    echo "::error::idl/SCHEMA_LOCK moved during this run — it was committed stale." >&2
    git --no-pager diff -- idl/SCHEMA_LOCK >&2
    DRIFT=1
fi

# --- 3. Presence of the untracked trees ------------------------------------
step "generated trees present"
if ! "${SCRIPT_DIR}/check_generated_trees.sh"; then
    DRIFT=1
fi

# --- 4. Case-collisions in the generated names ------------------------------
# Two generated files whose names differ only in case are one file on macOS and
# two on Linux, so the tree that compiles here is not the tree that compiles
# there. De-committing removed the index side of this hazard but not this half.
step "case-distinct filenames"
if ! "${SCRIPT_DIR}/check_generated_filenames.sh"; then
    DRIFT=1
fi

# --- 4b. Compile the generated code -----------------------------------------
# The trees can no longer be reviewed in a diff, so "it was generated" has to be
# backed by "and it builds". TypeScript and Python are the two where a bad
# generator emits output that looks plausible and only fails downstream — tsc
# catches the first, `import` catches the second.
if [ "${WITH_COMPILE}" -eq 1 ]; then
    step "compiling the generated TypeScript (tsc -> bindings/proto-ts/dist)"
    if (cd bindings/proto-ts \
            && npm install --package-lock=false --workspaces=false --no-audit --no-fund \
            && npm run build); then
        if ! "${SCRIPT_DIR}/check_generated_trees.sh" --with-built >/dev/null; then
            echo "::error::tsc succeeded but bindings/proto-ts/dist is missing or short." >&2
            DRIFT=1
        fi
    else
        echo "::error::the generated TypeScript does not compile." >&2
        DRIFT=1
    fi

    step "importing the generated Python"
    if ! (cd bindings/python && python3 -c '
import importlib, pathlib, sys, types
sys.path.insert(0, ".")
# Stand `runanywhere` up as a bare namespace package pointing at the real
# directory, so importing its generated submodules does NOT execute
# runanywhere/__init__.py. That module imports .inputs -> numpy and, further
# down, the native _core — neither of which this job builds or installs, and
# neither of which says anything about whether the generated code is valid.
# The generated *_pb2 modules import each other absolutely
# ("from runanywhere._proto import errors_pb2"), so the name has to resolve;
# it just must not run the package body.
_shim = types.ModuleType("runanywhere")
_shim.__path__ = [str(pathlib.Path("runanywhere").resolve())]
sys.modules["runanywhere"] = _shim
import runanywhere._generated_errors as e
import runanywhere._generated_defaults as d
assert e.ErrorCode, "ErrorCode enum is empty"
n = 0
for p in sorted(pathlib.Path("runanywhere/_proto").glob("*_pb2.py")):
    importlib.import_module("runanywhere._proto." + p.stem)
    n += 1
assert n >= 15, f"only {n} generated protobuf modules"
print(f"  ok: {n} protobuf modules, {len(e.ErrorCode.__members__)} error codes")
'); then
        echo "::error::the generated Python does not import." >&2
        DRIFT=1
    fi
fi

# --- 5. Anything else the run changed --------------------------------------
# Catches a generator that starts writing somewhere nobody declared: a path that
# is neither ignored (so it shows up as untracked) nor part of a committed tree
# already covered above. Compared against the pre-run snapshot so a working tree
# that was already dirty for unrelated reasons does not fail the gate.
step "no stray files outside the declared trees"
git status --porcelain --untracked-files=all | LC_ALL=C sort > "${AFTER_STATUS}"
STRAY="$(comm -13 "${BEFORE_STATUS}" "${AFTER_STATUS}" | grep -v ' idl/SCHEMA_LOCK$' || true)"
if [ -n "${STRAY}" ]; then
    echo "::error::codegen changed files outside the declared generated trees:" >&2
    printf '%s\n' "${STRAY}" | sed 's/^/  /' >&2
    DRIFT=1
fi

if [ "${DRIFT}" -ne 0 ]; then
    echo "" >&2
    echo "::error::IDL gate failed." >&2
    echo "" >&2
    echo "To fix locally:" >&2
    echo "  ./idl/codegen/generate_all.sh" >&2
    echo "  git add idl/SCHEMA_LOCK        # the only tracked output of a codegen run" >&2
    exit 1
fi

echo ""
echo "✓ IDL gate passed."
