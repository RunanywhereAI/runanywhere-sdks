# RunAnywhere Web SDK — Minimal Example

The smallest app that proves the Web SDK works: one prompt box, one Generate
button, one streamed answer (`index.html` + `src/main.ts`, plain DOM, no
framework). It is both the in-repo contributor harness (edit the SDK, see it
here with no publish step) and the default target Playwright drives for
`bindings/web/tests/browser/*` (`RA_E2E_APP_DIR` points those specs at a
different app instead).

By default it builds against **local SDK source**: `vite.config.ts` aliases +
`tsconfig.json` paths resolve `@runanywhere/web`, `@runanywhere/web-llamacpp`,
and `@runanywhere/proto-ts` straight into `bindings/web/packages/*/src` and
`bindings/proto-ts/src`. Every alias must point at the same source modules —
letting one resolve to `dist/` instead creates a second SDK singleton.

## Commands

```bash
npm install
npm run typecheck
npm run build      # production bundle in dist/
npm run preview    # serves dist/ on http://localhost:3000
npm run dev        # http://localhost:3000
```

`npm run build` requires the four canonical WASM pairs (`racommons`,
`racommons-llamacpp`, `racommons-llamacpp-webgpu`, `racommons-onnx-sherpa`) to
already exist under `bindings/web/packages/*/wasm`. Build them first with
`npm run build:wasm:all` from `bindings/web/` — the Vite plugin fails the
build listing the missing filenames rather than shipping a bundle that only
breaks in the browser.

`RAC_USE_INSTALLED_SDK=1` switches both module resolution and the WASM
source directories to the installed `@runanywhere/*` packages in
`node_modules` — this is the mode the release consumer gate uses after
installing release-candidate tarballs. Pair it with `npm run
typecheck:installed`, which drops the local-source path mapping so it
type-checks against what actually got installed.

## What the app does

`src/main.ts` is the entire app. Boot order matters — it mirrors the SDK's
documented two-phase init:

```ts
await RunAnywhere.initialize({ environment: 'development' });  // loads racommons.wasm
await LlamaCPP.register({ acceleration: 'auto' });             // loads racommons-llamacpp[-webgpu].wasm
await RunAnywhere.completeServicesInitialization();            // deprecated no-op; initialize() folds both phases
RunAnywhere.models.register({ id: 'smollm2-360m-q8_0', ... }); // the catalog is app-owned
```

then streams a completion:

```ts
for await (const event of RunAnywhere.llm.generateStream(prompt, { model: MODEL_ID })) {
  // 'textDelta' | 'reasoningDelta' | 'completed' | 'failed' | 'cancelled'
}
```

Naming `options.model` is enough — the SDK downloads and loads that model on
first use; the app never sequences download/load itself. It does call
`models.register` once at boot, because the browser SDK ships no built-in
catalog and `generateStream` can only resolve ids the registry already knows.

## Browser requirements (`vite.config.ts`)

`SharedArrayBuffer` — and therefore the pthread CPU WASM build — needs
cross-origin isolation, so both the dev and preview servers set
`Cross-Origin-Opener-Policy: same-origin` / `Cross-Origin-Embedder-Policy:
credentialless`. The production build target is pinned to `chrome86` (the
Web SDK's documented floor) so a future Vite major can't silently raise it.

The build also copies the four canonical Emscripten `.js`/`.wasm` pairs into
`dist/assets/` **under their original filenames** — Emscripten glue resolves
its own binary via `new URL("x.wasm", import.meta.url)`, and each
pthread-enabled module spawns workers that request that exact filename. A
Vite-hashed copy alone breaks the worker handshake and the CPU build hangs
waiting for its pthread pool forever.

## Readiness contract for the browser gates

`src/readiness.ts` publishes two globals that the Playwright specs read
instead of scraping DOM layout, so the gates survive an app rewrite:

| Global | What it carries |
| --- | --- |
| `window.__RUNANYWHERE_AI_READY__` | boot progress (`state`, `backend`, `step`, `reason`, `shellReady`) |
| `window.__RUNANYWHERE_SDK__` | the imported SDK singleton, for public-surface probes |

The root `<html>` element mirrors backend state as
`data-runanywhere-ai-backend`. `npm run test:browser:smoke` (from
`bindings/web/`) boots this app by default.

## Validation

Build and typecheck are smoke checks only. Real validation is a browser
launch with a model download, a model load, and a streamed answer — last
verified for this app against `npm run preview` (COOP/COEP live, all four
canonical pairs served as JavaScript / `application/wasm`,
`smollm2-360m-q8_0` downloaded, loaded, and generated on the WebGPU
llama.cpp path).
