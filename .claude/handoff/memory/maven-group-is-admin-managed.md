---
name: maven-group-is-admin-managed
description: "Never change the Maven group, package ids, or publishing coordinates — admins own them."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 16bc371b-e60e-4d76-b083-037c3d930444
  modified: 2026-07-27T09:31:14.893Z
---

Do not touch the Maven group (`io.github.sanchitmonga22`), npm scopes, pub.dev
package names, or any publishing coordinate. Admins manage them out of band.

**Why:** an agent renamed the group to `io.github.runanywhereai` across 7 files
during a "remove hardcoded values" sweep. The user's reaction was immediate and
emphatic: coordinates are handled by the admins, revert now. A coordinate change
silently breaks every downstream consumer and cannot be undone by a later patch.

**How to apply:** treat coordinates as data, not code smell, even when they look
like a personal account hardcoded in a company repo. If a task seems to require
changing one, stop and ask. Related: [[no-commit-without-approval]].
