---
name: use-edit-tool-for-file-changes
description: "Edit files with the Edit/Write tools, not sed/python heredocs in the shell"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 16bc371b-e60e-4d76-b083-037c3d930444
  modified: 2026-07-29T07:29:33.602Z
---

Use the Edit/Write tools for file modifications. Don't reach for `sed -i` or python heredoc scripts in Bash to edit files; shell is for builds, greps, and running things.

**Why:** Siddhesh asked for this directly (2026-07-29) — tool edits are reviewable in the client UI and diffable; shell edits are opaque and bit me twice with over-broad replaces (AgentLoopConfig, duplicate include).

**How to apply:** Batch renames across a file are fine as multiple Edit calls or one Edit with replace_all. Only fall back to a script when the edit is genuinely programmatic (e.g. splitting agent output into files), and say so.
