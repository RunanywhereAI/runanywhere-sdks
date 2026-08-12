# RunAnywhere Web SDK — Minimal Example

The smallest app that proves the Web SDK works: one prompt box, one Generate
button, one streamed answer. Plain DOM, no framework, no design system.

This is the in-repo contributor harness and the release consumer gate target —
it builds against the **local SDK source** by default (Vite aliases +
`tsconfig.json` paths into `bindings/web/packages/*/src` and
`bindings/proto-ts/src`), so an SDK edit shows up here without a publish step.

## Commands

```bash
npm install
npm run typecheck
npm run build      # production bundle in dist/
npm run preview    # serves dist/ on http://localhost:3000
npm run dev        # http://localhost:3000
```

`npm run build` requires the four canonical WASM pairs to exist. Build them with
`npm run build:wasm:all` from `bindings/web/` first; the build fails with
the missing filenames rather than emitting a bundle that only breaks in the
browser.

Setting `RAC_USE_INSTALLED_SDK=1` switches both the module resolution and the
WASM sources to installed `@runanywhere/*` packages in `node_modules` — the mode
the release workflow uses after installing release-candidate tarballs. Pair it
with `npm run typecheck:installed`, which drops the local-source path mapping.

## What the app does

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
first use. The app never sequences download/load itself. It does have to
`models.register` the entry once, because the browser SDK ships no built-in
catalog: `llm.generateStream` can only resolve ids the registry already knows.

## Browser requirements

`SharedArrayBuffer` — and therefore the pthread CPU WASM build — needs
cross-origin isolation, so `vite.config.ts` sets COOP/COEP headers on both the
dev and the preview server. The build copies the canonical Emscripten
`.js`/`.wasm` pairs into `dist/assets/` under their original filenames, which
pthread workers request by name; a hashed copy alone is not enough.

## Readiness contract for the browser gates

`src/readiness.ts` publishes two globals the SDK's Playwright specs
(`bindings/web/tests/browser/`) probe instead of a DOM layout:

| Global | What it carries |
| --- | --- |
| `window.__RUNANYWHERE_AI_READY__` | boot progress (`state`, `backend`, `step`, `reason`, `shellReady`) |
| `window.__RUNANYWHERE_SDK__` | the imported SDK singleton, for public-surface probes |

The root element mirrors the backend state as `data-runanywhere-ai-backend`.
`npm run test:browser:smoke` (from `bindings/web/`) boots this app by
default; `RA_E2E_APP_DIR` points the same specs at a different app.

## Validation

Build and typecheck are smoke checks. Real validation is a browser launch with
a model download, a model load, and a streamed answer — verified for this app
against `npm run preview` (COOP/COEP live, all four canonical pairs served as
JavaScript / `application/wasm`, `smollm2-360m-q8_0` downloaded, loaded, and
generated on the WebGPU llama.cpp path).
