---
name: one-line-commit-messages
description: "Commit messages must be a single meaningful line — no body, no bullet lists"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 16bc371b-e60e-4d76-b083-037c3d930444
  modified: 2026-07-26T11:37:33.170Z
---

Commit messages are one line, and that line must say what actually changed (scope prefix + concrete change, matching this repo's history, e.g. `npu: add Magpie-TTS Multilingual 357M (Hexagon v75 + v81)`). No multi-paragraph body, no bullet summaries.

**Why:** The user reads history as a scannable list; padding hides the real change.

**How to apply:** Write the subject only. If the change feels too big for one line, that's a signal to split the commit. Only commit when [[no-commit-without-approval]] is satisfied.
