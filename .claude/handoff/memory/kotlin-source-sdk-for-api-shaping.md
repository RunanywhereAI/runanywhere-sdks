---
name: kotlin-source-sdk-for-api-shaping
description: "For the API-shaping/DX task (task 22+), Kotlin is the source SDK — overrides the repo's iOS-as-source-of-truth rule"
metadata: 
  node_type: memory
  type: project
  originSessionId: 16bc371b-e60e-4d76-b083-037c3d930444
  modified: 2026-07-29T10:40:36.578Z
---

For the public-API shaping work started 2026-07-29 (industry-standard API alignment: OpenAI, LiveKit, Cactus Compute references), Siddhesh decided **Kotlin is the source SDK**: the new API shape is designed and landed in `sdk/runanywhere-kotlin` first, and the other seven SDKs mirror it.

**Why:** stated directly ("we will take kt as our source sdk") while commissioning Cactus Compute Kotlin API research; Cactus's Kotlin SDK is the competitor benchmark.

**How to apply:** this overrides the repo AGENTS.md "iOS SDK is source of truth" rule *for facade/API-shape decisions in this workstream only*. Business-logic behavior questions still defer to iOS/commons. When shaping or reviewing public API surface, compare against Kotlin first.
