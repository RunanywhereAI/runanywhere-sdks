---
name: no-ai-slop-comments
description: "No filler comments, no ASCII art/banners, no change narration — keep the codebase clean"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 16bc371b-e60e-4d76-b083-037c3d930444
  modified: 2026-07-29T06:07:59.159Z
---

Never write AI-slop in the codebase: comments that restate the line below them, decorative section banners or ASCII-art dividers (`// ====== SECTION ======`, box-drawing diagrams in code), `// Step 1:` scaffolding, or narration of the edit ("now we also handle X", "removed the old path", "N was field X — retired"). Comment only where a reader would otherwise be misled — a non-obvious invariant, a workaround with its reason, an ABI/wire constraint. Applies to everything checked in: code, protos, headers, build files.

**Why:** Siddhesh treats filler as noise that makes real comments invisible; reinforced on 2026-07-29 ("no ai slop anywhere... comments and ascii art, keep the codebase clean").

**How to apply:** Match the comment density and style of the surrounding file — but don't add new banners even where a legacy file has them. A `reserved` proto field gets at most a terse one-liner naming what it was, not a paragraph. If a comment could be deleted with no information lost, don't write it. Same for prose in code: no padding.
