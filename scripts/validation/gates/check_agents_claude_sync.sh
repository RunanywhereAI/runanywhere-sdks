#!/usr/bin/env bash
#
# check_agents_claude_sync.sh — keep AGENTS.md and CLAUDE.md identical, the simple way.
#
# CLAUDE.md is a symlink to the AGENTS.md sitting beside it. AGENTS.md is the real
# file; because CLAUDE.md just points at it, editing either name edits the same
# bytes and the two can never drift. Every first-party directory (git-tracked, so
# vendored / .build copies are skipped automatically) that has an AGENTS.md must
# have a committed CLAUDE.md -> AGENTS.md symlink beside it.
#
# The symlinks are committed, so `git clone` / `git checkout` recreates them for
# free on macOS/Linux. --fix (run by setup.sh and the post-checkout/post-merge
# pre-commit hooks) re-creates any that are missing — e.g. on a Windows checkout
# or a clobbered link. --fix only touches the filesystem; it never stages.
#
# Usage:
#   check_agents_claude_sync.sh          check (CI / pre-commit); exit 1 on any missing/wrong/untracked link
#   check_agents_claude_sync.sh --fix    create or repair the symlinks
#   check_agents_claude_sync.sh --help
#
# Exit codes: 0 ok/fixed | 1 drift (check mode) | 2 tooling error

set -euo pipefail

CANON="AGENTS.md"
COPY="CLAUDE.md"
TARGET="AGENTS.md"   # relative symlink target — CLAUDE.md and AGENTS.md are siblings

usage() {
  cat <<'EOF'
check_agents_claude_sync.sh — keep AGENTS.md and CLAUDE.md identical via a symlink.

CLAUDE.md is a symlink to the sibling AGENTS.md, so editing either edits the same
file and they can never drift. The symlinks are committed, so a fresh clone /
checkout recreates them automatically on macOS/Linux. Every git-tracked AGENTS.md
must have a committed CLAUDE.md -> AGENTS.md symlink beside it. "First-party" ==
tracked by git, so vendored / build-output copies (.build/, wasm/_deps,
third_party/, ...) are skipped automatically.

  check_agents_claude_sync.sh          check (CI / pre-commit): fail on any
                                       missing / wrong / untracked symlink
  check_agents_claude_sync.sh --fix    (re)create the symlinks on disk (no staging)
  check_agents_claude_sync.sh --help   this message

Exit codes: 0 ok/fixed | 1 drift (check mode) | 2 tooling error
EOF
}

MODE=check
case "${1:-}" in
  ""|--check) MODE=check ;;
  --fix)      MODE=fix ;;
  -h|--help)  usage; exit 0 ;;
  *) printf '::error::unknown argument: %s (expected --fix, --check, or --help)\n' "$1" >&2; exit 2 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

command -v git >/dev/null 2>&1 || { printf '::error::git not found on PATH.\n' >&2; exit 2; }
git -C "${REPO_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || { printf '::error::%s is not a git work tree.\n' "${REPO_ROOT}" >&2; exit 2; }

# -z keeps paths raw (no octal-quoting of non-ASCII/space/quote names), so the
# NUL-delimited read loops below match and operate on the true filesystem path.
git_ls()     { git -C "${REPO_ROOT}" ls-files -z -- "$@"; }
is_tracked() { git -C "${REPO_ROOT}" ls-files --error-unmatch -- "$1" >/dev/null 2>&1; }
sibling()    { local d; d="$(dirname "$1")"; [ "${d}" = "." ] && printf '%s' "$2" || printf '%s/%s' "${d}" "$2"; }

status=0
changed=0
pairs=0

# Pass 1 — every tracked AGENTS.md needs a tracked sibling CLAUDE.md -> AGENTS.md symlink.
while IFS= read -r -d '' a; do
  case "${a}" in "${CANON}"|*/"${CANON}") ;; *) continue ;; esac   # exact basename only
  a_abs="${REPO_ROOT}/${a}"
  [ -f "${a_abs}" ] || continue   # index entry not materialized on disk (sparse-checkout) — nothing to link from
  pairs=$((pairs + 1))
  c="$(sibling "${a}" "${COPY}")"
  c_abs="${REPO_ROOT}/${c}"

  if [ -L "${c_abs}" ] && [ "$(readlink "${c_abs}")" = "${TARGET}" ]; then
    # Correct symlink on disk. In check mode it must also be committed (a clean CI
    # checkout only has tracked files); --fix just needs the file to exist.
    if [ "${MODE}" = fix ] || is_tracked "${c}"; then
      continue
    fi
    printf '::error file=%s::%s is a correct symlink but untracked — `git add %s`\n' "${c}" "${c}" "${c}" >&2
    status=1
    continue
  fi

  if [ "${MODE}" = fix ]; then
    rm -f "${c_abs}"
    ( cd "${REPO_ROOT}/$(dirname "${a}")" && ln -s "${TARGET}" "${COPY}" )
    printf '  linked   %-52s -> %s\n' "${c}" "${TARGET}"
    changed=$((changed + 1))
  elif [ ! -L "${c_abs}" ] && [ ! -e "${c_abs}" ]; then
    printf '::error file=%s::missing %s (should be a symlink -> %s; run --fix)\n' "${c}" "${c}" "${TARGET}" >&2
    status=1
  elif [ ! -L "${c_abs}" ]; then
    printf '::error file=%s::%s is a regular file, not a symlink -> %s (run --fix)\n' "${c}" "${c}" "${TARGET}" >&2
    status=1
  else
    printf '::error file=%s::%s points to %s, expected %s (run --fix)\n' "${c}" "${c}" "$(readlink "${c_abs}")" "${TARGET}" >&2
    status=1
  fi
done < <(git_ls '*AGENTS.md')

# Pass 2 — orphan guard: a tracked CLAUDE.md with no AGENTS.md sibling. Promote its
# content to AGENTS.md in --fix (never lose it), fail in check mode.
while IFS= read -r -d '' c; do
  case "${c}" in "${COPY}"|*/"${COPY}") ;; *) continue ;; esac
  c_abs="${REPO_ROOT}/${c}"
  a="$(sibling "${c}" "${CANON}")"
  a_abs="${REPO_ROOT}/${a}"
  [ -e "${a_abs}" ] && continue       # AGENTS.md present → handled by pass 1
  is_tracked "${a}" && continue       # AGENTS.md tracked but not materialized (sparse) → skip

  if [ "${MODE}" = fix ] && [ -f "${c_abs}" ] && [ ! -L "${c_abs}" ]; then
    mv "${c_abs}" "${a_abs}"
    ( cd "${REPO_ROOT}/$(dirname "${c}")" && ln -s "${TARGET}" "${COPY}" )
    printf '  promoted %-52s -> %s (orphan had no %s)\n' "${c}" "${TARGET}" "${CANON}"
    changed=$((changed + 1))
  else
    printf '::error file=%s::%s has no sibling %s (run --fix)\n' "${c}" "${c}" "${a}" >&2
    status=1
  fi
done < <(git_ls '*CLAUDE.md')

if [ "${MODE}" = fix ]; then
  if [ "${changed}" -eq 0 ]; then
    printf 'All %s CLAUDE.md symlink(s) already correct.\n' "${pairs}"
  else
    printf '\nCreated/updated %s symlink(s). `git add` any new ones to commit them.\n' "${changed}"
  fi
  exit 0
fi

if [ "${status}" -ne 0 ]; then
  {
    printf '\n::error::CLAUDE.md symlinks are missing / wrong / untracked.\n'
    printf 'Fix locally with:\n'
    printf '  bash scripts/validation/gates/check_agents_claude_sync.sh --fix\n'
  } >&2
  exit 1
fi

printf 'All %s CLAUDE.md -> AGENTS.md symlink(s) present and tracked.\n' "${pairs}"
