---
name: no-hardcoded-model-names
description: "Detect model capabilities from artifact evidence, never from a model name or family list."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 16bc371b-e60e-4d76-b083-037c3d930444
  modified: 2026-07-27T09:31:23.888Z
---

Never branch on a model id, name, or family string to decide what a model can do.
Derive capability from the artifact itself.

**Why:** while fixing the thinking-mode toggle I added a check for `contains(id,
"lfm2")`. The user cut it off: some LFM models *are* thinking models, so a family
name predicts nothing. The same applies to any substring matcher over model ids
(`qwen3`, `deepseek-r1`, `gpt-oss`, `glm-4`) — vendors ship reasoning and
non-reasoning checkpoints under one prefix.

**How to apply:** read the artifact. For GGUF that means the chat template
(whether it honors `enable_thinking`, whether it prefills the open tag). For
QHexRT it is the bundle catalog flag; for MLX, `tokenizer_config.json`. When the
evidence is inconclusive, report unknown and fall through — do not guess from the
name.
