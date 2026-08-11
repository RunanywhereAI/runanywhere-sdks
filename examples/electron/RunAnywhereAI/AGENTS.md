# AGENTS.md

RunAnywhere AI — the Electron desktop example app. `CLAUDE.md` is a symlink to this file.

Everything runs **on-device**: chat, reasoning, your own knowledge base, voice, and vision. No
prompt, document, or audio leaves the machine.

---

## The two rules that govern this app

### 1. TypeScript only, strictly typed

**Every authored file in this app is TypeScript.** Main process, preload, renderer, shared
modules, build config, tests. There is no JavaScript in source. The conventions are the same as
`examples/web/RunAnywhereAI` and `sdk/runanywhere-electron`, so one habit set covers all three.

- **`strict: true`** in all three tsconfigs (`main`, `preload`, `renderer`), never weakened
  per-file.
- **No `any`.** `@typescript-eslint/no-explicit-any` is an error. Use `unknown` and narrow.
- **No `@ts-ignore` / `@ts-expect-error`** to silence a real error, and no non-null `!` to paper
  over a maybe — narrow it or handle the absence.
- **No raw JSON assumptions.** Anything read from disk, IPC, or the network is decoded into a
  declared type first. The IPC contract lives in exactly one place — `src/shared/ipc-contract.ts`
  — and both sides import it, so a channel can never drift between main and renderer.
- **`consistent-type-imports`**, **`no-floating-promises`**, **`no-misused-promises`**, unused
  vars are errors (`^_` to opt out), **`no-console`** (use the app logger, which routes to a
  main-side file log).
- **Proto types are the source of truth.** Model categories, error codes, stream event shapes,
  audio formats, voice events — all come from the SDK's re-exported generated types. Never
  hand-write an enum or string union the IDL already defines.
- **Discriminated unions for state**, `readonly` for anything the caller must not mutate,
  `as const` for literal tables, exhaustive `switch` with a `never` fallthrough.
- **The renderer may not import `electron`.** Enforced by `no-restricted-imports`. Everything the
  renderer needs arrives through the typed `window.runanywhere` / `window.appStore` bridges.

Output format differs by target even though the source language does not: main and preload emit
**CommonJS** (Electron loads them that way), the renderer emits an **ESM** bundle, and the model
catalog additionally emits a CommonJS `.js` on disk because the SDK's utility host `require()`s it
by path.

```bash
npm run typecheck   # all three projects
npm run lint        # --max-warnings 0
npm run build       # production bundle
npm test            # unit + Electron smoke
```

### 2. Almost no logic lives here

Per the root `AGENTS.md`, **logic belongs at the lowest layer that can serve all consumers**:

```text
C++ commons  ->  owns ALL AI logic (inference, lifecycle, registry, download, RAG, routing)
     SDK     ->  thin bridge: platform I/O, process plumbing, typed API
   this app  ->  UI rendering, navigation, copy, thin SDK calls.  That is all.
```

**iOS/macOS Swift is the canonical reference.** When behaviour is ambiguous, read the Swift app
and copy its logic exactly, adapting syntax only. This app must be visually and functionally
indistinguishable from the macOS target of `examples/ios/RunAnywhereAI`.

If you find yourself writing any of the following, **stop — it is a bug one layer down**:

- a multi-step bootstrap sequence before a feature works
- a hardcoded model id, framework, or filesystem path pattern
- post-processing of model output
- a workaround for an SDK or commons defect
- a re-implementation of something the SDK already does privately
- a hand-maintained copy of an SDK-internal mapping

Fix it in the SDK, or in commons if it is cross-platform, and let all six SDKs benefit. The
running list of things that were pushed down out of this app is in
`thoughts/shared/plans/electron_app_parity.md` §5a.

**What legitimately belongs here:** the model catalog table (every platform owns its own —
`ModelCatalogBootstrap.swift`, `ModelCatalog.kt`, `model-catalog.ts`), copy strings and prompt
suggestions, the local JSON store for conversations/settings, the demo tool implementations,
cosine similarity in the embeddings demo, and pure presentation helpers like the segmentation
mask painter.

---

## Design parity is a gate

The app must be **indistinguishable** from the macOS SwiftUI app. Tokens are transcribed from
`examples/ios/RunAnywhereAI/RunAnywhereAI/Core/DesignSystem/` (the macOS branch of every
`#if os(macOS)`) into `src/renderer/design/tokens.css`, which is the **one** theme file — no
component invents a value.

Two things are easy to get wrong:

1. **Use the Swift cool blue-ink neutrals** (`#FBFAF8` / `#0C0E17` / `#131620` / `#10182B`), which
   match `examples/DESIGN_GUIDELINE.md §2`. The Web example ships *warm* neutrals that appear in
   neither the guideline nor the Swift app — do not copy them.
2. **Use the macOS column** wherever iOS and macOS differ (e.g. composer radius is **16**, not the
   iOS 28; `hitTarget` is 28, not 44).

Parity is verified by driving both apps and comparing screenshots per screen, in light and dark —
not by reading code. Motion is asserted from computed styles against the Motion table, and
`prefers-reduced-motion` must produce a 150 ms crossfade (not a 0 ms blink) with ambient loops
stopped. See workstream K in the plan.

---

## Architecture

Three processes. Inference never runs in main or renderer.

```text
MAIN (CJS)                      forks
  ├─ window, menu, security, theme, store, .env, native resolution
  ├─ SDK bootstrap ──────────────────────►  UTILITY HOST ── native addon ── C++ commons
  └─ brokers a MessagePort main never reads
        │
     RENDERER (ESM bundle)  ── preload (CJS) ──►  window.runanywhere / window.appStore
```

Streaming: an `AsyncIterable` **cannot** cross `contextBridge`. Streams arrive on a per-request
channel and a renderer-side adapter re-exposes an `AsyncIterable` whose `return()` sends a cancel
— which keeps `iterator.return?.()` working as the Stop button at every call site.

---

## Non-negotiables

- `app.setName('RunAnywhere AI')` **before** any `app.getPath('userData')`.
- The catalog is registered **before** the SDK preload is required (registration is per-process).
- `contextIsolation: true`, `nodeIntegration: false`, `sandbox: false` (the preload requires SDK
  modules).
- All four security handlers: permission allowlist (`media`/`audioCapture` only),
  `setWindowOpenHandler`, `will-navigate`, `will-attach-webview`.
- The menu is **replaced, not hidden** — hiding it leaves DevTools accelerators live in a shipped
  build. On macOS `{ role: 'appMenu' }` must be first, or there is no ⌘Q/About/Preferences.
- Test IPC channels are registered **only** under `RA_SELFTEST=1` (one of them calls `app.exit`).
- Store writes stay atomic (temp + `fsync` + rename) with corrupt-file backup; conversations
  capped at 200.
- Settings saves **merge**, never replace — per-modality model choices live in the same object.
- Removing a custom model clears any `settings.models[type]` pointing at it.
- `webUtils.getPathForFile` is the only `File` → path route (Electron removed `File.path`).
- **CSP forbids `eval`/`new Function`** — this is why the demo calculator has a hand-written
  arithmetic parser.
- Leaving Voice or Diarization closes the microphone.
- One generation / one RAG query / one VAD window at a time.
- Model residency is the **SDK's** decision — never reintroduce an app-side unload policy.

## Windows

macOS parity is the design target; Windows is a shipping target and must not regress. The `.cmd`
launchers (which clear `ELECTRON_RUN_AS_NODE`), `%APPDATA%` paths, DPAPI secure storage, the CUDA
prebuild opt-in (`--gpu` / `RA_GPU=1`, never the silent default), and the `.ico` icon all stay.
Platform-specific copy must be platform-conditional — never show "Windows DPAPI" or a `.cmd`
filename on macOS.
