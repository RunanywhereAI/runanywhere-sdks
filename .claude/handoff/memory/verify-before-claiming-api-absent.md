---
name: verify-before-claiming-api-absent
description: "Before reporting an API as missing, search the whole facade including spread and extension files."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 16bc371b-e60e-4d76-b083-037c3d930444
  modified: 2026-07-27T09:31:33.627Z
---

Do not report a public API as nonexistent based on grepping the file that
declares the facade object. Search the extension directory too.

**Why:** auditing the docs branch I claimed `RunAnywhere.transcribe` and `.speak`
did not exist on the Web SDK, because my pattern was anchored to
`packages/core/src/Public/RunAnywhere.ts`. Both are real: `transcribe` lives in
`Public/Extensions/RunAnywhere+FlatFacade.ts` and reaches the object through a
`...flatFacade` spread, and `speak` is defined further down the file than I
looked. I reported a false defect in a written audit the user acted on.

**How to apply:** these SDKs compose their surface from many files (Swift
`RunAnywhere+*.swift`, Kotlin `public/extensions/**`, Web/RN `Public/Extensions/**`
plus spreads, Flutter `public/capabilities/**`). Grep the whole tree for the bare
symbol, check for `...spread` and `Object.assign`, and only then call it absent.
An absence claim is a strong claim — verify it like one.
