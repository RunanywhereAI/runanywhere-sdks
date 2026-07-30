---
name: use-gh-for-github
description: Use the gh CLI for every GitHub interaction
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 16bc371b-e60e-4d76-b083-037c3d930444
  modified: 2026-07-26T11:37:56.383Z
---

Use the `gh` CLI for all GitHub access — PRs, issues, reviews, releases, CI runs, repo/API lookups (`gh api`). Don't reach for raw web fetches or the git remote when `gh` covers it.

**Why:** `gh` is already authenticated in this environment and returns structured output.

**How to apply:** `gh pr view/create`, `gh run list`, `gh api <endpoint> --jq ...`. Note: zsh needs quoted URLs when they contain `?` (e.g. `gh api "repos/o/r/git/trees/HEAD?recursive=1"`). Creating or pushing anything still waits on [[no-commit-without-approval]].
