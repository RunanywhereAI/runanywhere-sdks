#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

requested_mode="${VALIDATION_IDL_DRIFT_BASELINE:-auto}"
resolved_mode="${requested_mode}"

if [[ "${requested_mode}" == "auto" ]]; then
  resolved_mode="current-worktree"
  if [[ -n "${CI:-}" && "${CI}" != "0" && "${CI}" != "false" ]]; then
    resolved_mode="committed"
  fi
  if [[ -n "${GITHUB_ACTIONS:-}" && "${GITHUB_ACTIONS}" != "0" && "${GITHUB_ACTIONS}" != "false" ]]; then
    resolved_mode="committed"
  fi
fi

case "${resolved_mode}" in
  committed|strict|ci)
    printf "IDL drift baseline mode: committed Git index (strict CI)\n"
    exec "${REPO_ROOT}/idl/codegen/ci-drift-check.sh"
    ;;
  current-worktree|dirty-worktree)
    ;;
  *)
    printf "error: unsupported VALIDATION_IDL_DRIFT_BASELINE=%q\n" "${requested_mode}" >&2
    printf "supported modes: auto, current-worktree, committed\n" >&2
    exit 2
    ;;
esac

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/runanywhere-idl-drift.XXXXXX")"
cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

baseline_index="${tmp_dir}/index"
diff_stat="${tmp_dir}/diff.stat"
diff_names="${tmp_dir}/diff.name-status"
untracked_names="${tmp_dir}/untracked.txt"

cd "${REPO_ROOT}"

printf "IDL drift baseline mode: current worktree (isolated Git index)\n"
printf "Baseline index: %s\n" "${baseline_index}"
printf "Seeding baseline from current tracked and untracked worktree files...\n"

export GIT_INDEX_FILE="${baseline_index}"
git add -A -- .
printf "Baseline paths indexed: %s\n\n" "$(git ls-files | wc -l | tr -d ' ')"

"${REPO_ROOT}/idl/codegen/generate_all.sh"

git diff --stat -- . > "${diff_stat}"
git diff --name-status -- . > "${diff_names}"
git ls-files --others --exclude-standard -- . > "${untracked_names}"

if [[ -s "${diff_names}" || -s "${untracked_names}" ]]; then
  printf "\n" >&2
  printf "::error::IDL codegen is not idempotent against the current worktree baseline.\n" >&2
  printf "\n" >&2

  if [[ -s "${diff_stat}" ]]; then
    printf "Diff stat relative to baseline:\n" >&2
    cat "${diff_stat}" >&2
    printf "\n" >&2
  fi

  if [[ -s "${diff_names}" ]]; then
    printf "Changed tracked or baselined paths:\n" >&2
    cat "${diff_names}" >&2
    printf "\n" >&2
  fi

  if [[ -s "${untracked_names}" ]]; then
    printf "New untracked paths:\n" >&2
    sed 's/^/?? /' "${untracked_names}" >&2
    printf "\n" >&2
  fi

  printf "Run ./idl/codegen/generate_all.sh locally and review the paths above.\n" >&2
  exit 1
fi

printf "✓ No drift detected — generated files match the current worktree baseline.\n"
