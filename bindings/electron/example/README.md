# runanywhere-minimal (Electron)

The smallest app that proves the Electron SDK works: one prompt box, one
Generate button, one streamed answer. Plain DOM, no framework, no design system,
no bundler. It is the contributor test harness — *"does my C++/SDK change still
work?"* — not a showcase app. The full desktop app lives in
[RunanywhereAI/runanywhere-electron](https://github.com/RunanywhereAI/runanywhere-electron).

## How it consumes the SDK

From **local source in this monorepo**, never from npm:

```jsonc
"dependencies": {
  "@runanywhere/electron": "file:..",
  "@runanywhere/electron-llamacpp": "file:../packages/llamacpp"
}
```

`.npmrc` pins `install-links=false`, so npm symlinks those two rather than
copying them. Rebuild `bindings/electron` and the next launch picks the change
up — there is no restage step. (The SDK's own `.npmrc` sets `install-links=true`
for its own dependency; that setting is per project and does not reach here.)

## Prerequisites

The SDK must be built, and the native addon must exist:

```bash
# From bindings/electron — TypeScript facade + backend package.
npm install && npm run build
(cd packages/llamacpp && npm install && npm run build)
```

The addon is found automatically, in this order: `RUNANYWHERE_NATIVE_PATH`,
`bindings/electron/prebuilds/<platform>-<arch>/runanywhere_native.node`, then
the repo's CMake build dirs (`build/electron-macos/...`, `build/windows-release/...`).
If none exists, build one with the `electron-macos` / `windows-release` preset —
it takes a while. Nothing in this app hardcodes a path.

## Run

```bash
cd bindings/electron/example
npm install
npm run typecheck   # both projects: node (CJS) + renderer (ESM)
npm start           # build, then launch Electron
```

Or `./run example electron {build|start|clean}` from the repo root.

Click **Generate**. The first run downloads SmolLM2 360M (~386 MB) into
`~/.runanywhere`, so give it a minute; later runs start generating immediately.

## What it exercises

| Step | API |
|------|-----|
| Backend registration (main) | `LlamaCPP.register()` |
| Utility-host fork + port broker | `new RunAnywhereMain({ catalogPath }).connect(webContents)` |
| Catalog entry (preload) | `registerCatalog(CATALOG)` |
| SDK bring-up (renderer) | `window.runanywhere.initialize()` |
| Streaming generation | `window.runanywhere.llm.generateStream(prompt, { model })` |

**Download and load are automatic** — passing `options.model` is enough. The
catalog is *not* auto-seeded, though: the SDK ships no built-in table, so the one
row in `src/catalog.ts` is required. To try a different model, edit that file.

## The four files, and why each exists

Electron runs this app in three processes plus the SDK's utility host, and the
split below is the whole reason this example is four files instead of one:

- **`src/main.ts`** — main process. Records the backend plugin (main-process
  only: paths reach the host through `RUNANYWHERE_PLUGIN_PATHS` at fork time,
  never over renderer RPC), forks the utility host, brokers its `MessagePort`
  into the window.
- **`src/preload.ts`** — stages the catalog **before** importing
  `@runanywhere/electron/preload`. That order is load-bearing; the comment in the
  file says why. The SDK's preload publishes `window.runanywhere`.
- **`src/catalog.ts`** — this app's one-row model table. Loaded by the utility
  host through a raw `require()`, which is why it imports types only.
- **`src/renderer.ts`** — the page. Drives `next()` by hand because
  contextBridge's structured clone drops symbol keys, so `for await` cannot
  iterate a bridged stream.

Inference never runs in main or the renderer — only in the utility host that
owns the native addon.

## Emit targets

Main, preload, and the catalog compile to **CommonJS** (`tsconfig.json`);
the renderer compiles to **ESM** (`tsconfig.renderer.json`) and the page loads it
with `<script type="module">`. That split is the SDK's documented contract — see
`bindings/electron/AGENTS.md`, "Emit targets". The renderer imports nothing at
runtime (only `import type`, which erases), so no bundler is needed.

Deliberately absent: VLM, STT, TTS, voice, RAG, model pickers, settings,
packaging, theming. Those either live in the SDK already or belong in the full
app.
