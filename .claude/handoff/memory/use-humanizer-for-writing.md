---
name: use-humanizer-for-writing
description: Invoke the humanizer skill for all non-code writing work
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 16bc371b-e60e-4d76-b083-037c3d930444
  modified: 2026-07-26T11:37:49.978Z
---

For any non-code writing — docs, READMEs, plan documents, PR descriptions, issue text, release notes, messages — invoke the `humanizer` skill and apply it to the prose.

**Why:** The user does not want AI-tell writing patterns in anything textual that ships.

**How to apply:** Installed at `/home/home/.claude/skills/humanizer` (git clone of `blader/humanizer`, MIT, updatable with `git pull`). Call `Skill(humanizer)` before finalizing prose. Does not apply to code or to short conversational replies. Related: [[no-ai-slop-comments]].
