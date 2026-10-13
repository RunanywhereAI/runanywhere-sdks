#!/bin/bash
# Skill trees: ONE canonical source, one generated mirror (DRY).
#
# `.claude/skills/` is the CANONICAL, human-edited skill tree (Claude Code reads it directly).
# `.agents/skills/` is a GENERATED MIRROR for non-Claude agent tooling (e.g. Codex, which has no native
# "skills" mechanism but can be pointed at plain markdown runbooks from AGENTS.md) — never hand-edit it.
# This script regenerates the mirror; `--check` verifies they are in sync.
#
# Why a copy and not a symlink: a checkout without core.symlinks=true (common on Windows) materializes
# git symlinks as text files, which would break Codex's reads. A generated copy + a drift check is portable.
#
# BOTH trees are TRACKED (see .gitignore: `.claude/*` / `.agents/*` are ignored except for the
# `!.claude/skills/`, `!.claude/commands/`, `!.agents/skills/` negations). Because the mirror is
# committed, a stale mirror is a wrong file published to a PUBLIC repo, not just local confusion —
# so `--check` runs in CI as a required gate (.github/workflows/agent-skills-gate.yml), alongside a
# scan that keeps private hostnames/credentials out of both trees.
#
# Usage:
#   scripts/setup/sync-skills.sh            # regenerate .agents/skills from .claude/skills
#   scripts/setup/sync-skills.sh --check    # exit non-zero if the mirror is stale
set -euo pipefail

# Repo root by WALKING UP to a marker, not by counting parent hops — a hardcoded ../.. breaks the moment
# this script moves. Depth-independent on purpose.
_walk_up_to_repo_root() {
  local d; d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  while [ "$d" != "/" ]; do
    if [ -f "$d/CMakeLists.txt" ] && [ -f "$d/package.json" ]; then printf '%s\n' "$d"; return 0; fi
    d="$(dirname "$d")"
  done
  echo "FATAL: no repo root above ${BASH_SOURCE[0]} (looked for CMakeLists.txt + package.json)" >&2
  return 1
}
REPO="$(_walk_up_to_repo_root)" || exit 1
SRC="$REPO/.claude/skills"
DST="$REPO/.agents/skills"

if [[ ! -d "$SRC" ]]; then
  echo "No .claude/skills/ yet — nothing to mirror." >&2
  exit 0
fi

if [[ "${1:-}" == "--check" ]]; then
  if diff -rq "$SRC" "$DST" >/dev/null 2>&1; then
    echo "skills in sync: .agents/skills mirrors .claude/skills"
    exit 0
  fi
  echo "ERROR: .agents/skills is STALE. Run scripts/setup/sync-skills.sh (edit .claude/skills, never .agents/skills)." >&2
  diff -rq "$SRC" "$DST" || true
  exit 1
fi

rm -rf "$DST"
mkdir -p "$(dirname "$DST")"
cp -R "$SRC" "$DST"
echo "regenerated .agents/skills from .claude/skills"
