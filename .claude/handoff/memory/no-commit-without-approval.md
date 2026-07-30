---
name: no-commit-without-approval
description: Never run git commit or git push until the user explicitly says to
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 16bc371b-e60e-4d76-b083-037c3d930444
  modified: 2026-07-26T11:37:26.819Z
---

Never `git commit` or `git push` until the user explicitly asks for it. Stage/edit freely, then stop and report what's ready.

**Why:** The user wants to review every change before it enters history or the remote.

**How to apply:** Finish the work, summarize the diff, and wait. Treat "looks good" on code as approval of the code, not of committing. See [[one-line-commit-messages]] and [[use-gh-for-github]].
