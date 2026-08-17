# RunAnywhere Web SDK — AGENTS.md

## Overview

The Web SDK is a Swift-aligned TypeScript facade over the RACommons C/C++ core. It is split across three npm packages, each owning its own self-contained Emscripten WASM artifact (commons code is embedded in every backend WASM; no cross-WASM symbol sharing). Apps load only the WASMs they need.

- `@runanywhere/web`: public Swift-shaped core facade, generated proto types, and the **commons-only** WASM (`racommons.{js,wasm}`) used during `RunAnywhere.initialize()`.
- `@runanywhere/web/backend`: the narrow, typed backend integration contract for module installation, capability routing, lifecycle hooks, and safe logging.
- `@runanywhere/web/internal`: broader core-internal implementation exports; neither applications nor backend packages may depend on this entrypoint.
- `@runanywhere/web/browser`: browser-only helpers such as audio capture/playback, video capture, and capability detection.
- `@runanywhere/web-llamacpp`: LLM + GGUF text embeddings + VLM + LoRA + tool-calling + structured-output backend. Ships **two execution-mode variants**: `racommons-llamacpp.{js,wasm}` (CPU) and `racommons-llamacpp-webgpu.{js,wasm}` (WebGPU + Asyncify). Both carry the unified llama.cpp vtable; model-framework routing lets its embedding primitive coexist with ONNX.
- `@runanywhere/web-onnx`: ONNX embeddings + STT + TTS + VAD backend backed by `racommons-onnx-sherpa.{js,wasm}` (CPU/pthread) and `racommons-onnx-sherpa-webgpu.{js,wasm}` (ORT WebGPU EP) — registers two vtables (`onnx`, `sherpa`) because they share ONNX Runtime. Speech acceleration is **separate** from LLM WebGPU (`ONNX.register({ acceleration, threads })`, `RunAnywhere.runtime.speech`). Fail-closed BackendWorker by default in browsers. See [`docs/ONNX_WEBGPU.md`](docs/ONNX_WEBGPU.md) and [`docs/WASM_AND_WEBGPU.md`](docs/WASM_AND_WEBGPU.md) for why both WASM and WebGPU exist.

Keep app code on the root `RunAnywhere` facade. Backend packages integrate only through `@runanywhere/web/backend`; browser apps may import UI/device helpers from `@runanywhere/web/browser`.

## Commons-First, Thin TypeScript

**Commons owns business and model logic.** Validation, modality pipelines, tool/structured/LoRA/RAG/hybrid/voice-agent session rules, and streaming state machines live in `runanywhere-commons` and are consumed only through the generated-proto C ABI (`rac_*_proto`, lifecycle, events) inside each backend WASM.

**TypeScript stays thin.** The Web SDK may only:
- Encode/decode proto bytes and invoke `rac_*` via `ccall` / BackendWorker RPC
- Own browser I/O (mic, speaker, permissions, DOM, fetch, OPFS/IndexedDB coordination)
- Host BackendWorkers and route requests to the module that owns the model
- Expose Swift/Kotlin-shaped `RunAnywhere.*` facades

**Do not reimplement commons pipelines in TS** when a commons export exists. Prefer native session ABIs; CrossWasm/TS fallbacks are degraded-only and must not become the production path.

**Off the UI thread.** All commons/WASM inference and model mutation runs in a BackendWorker. Main thread is I/O + thin facade only. Acceleration is WebGPU-first when the engine and device support it (`navigator.gpu` + `shader-f16`); otherwise CPU worker. Never silently fall back to main-thread inference when a required worker fails.

## Package Boundaries and Dependency Direction

There are exactly three publishable Web packages. `@runanywhere/web/backend`,
`@runanywhere/web/internal`, and `@runanywhere/web/browser` are entrypoints of
the core package, not extra packages.

```text
browser app
  -> @runanywhere/web
  -> @runanywhere/web/browser
  -> @runanywhere/web-llamacpp and/or @runanywhere/web-onnx

@runanywhere/web-llamacpp -> @runanywhere/web/backend
@runanywhere/web-onnx     -> @runanywhere/web/backend
@runanywhere/web          -> @runanywhere/proto-ts + backend-neutral commons
```

- Core must never import a backend package or contain llama.cpp, ONNX Runtime,
  Sherpa, or WebGPU implementation decisions. It owns contracts, lifecycle,
  routing hooks, generated-wire adapters, and browser-neutral infrastructure.
- Backend packages implement and register only the capabilities their own WASM
  serves. They may use only the documented core `backend` entrypoint; they must
  not import `internal`, one another, or deep-import package source files.
- Example/application code uses public package roots. It must not import
  `@runanywhere/web/internal` or recreate SDK business rules in views.

## Type, Validation, and Error Rules

- TypeScript remains strict. Do not introduce `any`, `@ts-ignore`, unchecked
  JSON casts, or duplicate hand-written wire DTOs. Start external data as
  `unknown`, validate it, and narrow it deliberately.
- These packages publish ESM. Relative TypeScript imports/exports must name the
  emitted `.js` path (for example `./runtime/EmscriptenModule.js`), including
  dynamic imports and barrel exports. Bundler-only extension inference hides
  broken NodeNext declarations and runtime entrypoints; keep
  `npm run check:esm-specifiers` and `npm run verify:nodenext` green.
- Model, lifecycle, storage, event, modality, environment, and error types come
  from generated `@runanywhere/proto-ts` modules. Local types are appropriate
  only for Web-specific call-site options or discriminated UI/runtime state
  that does not exist in the IDL.
- Validate every external boundary before crossing into WASM: URLs,
  credentials, model metadata, downloaded bytes, JSON, browser media, and
  persisted state. Throw/return the SDK's structured error shape with an
  actionable field or operation; do not leak a stack trace as a user message.
- Keep components and views focused on rendering and orchestration. Reusable
  model routing, lifecycle, storage, audio, and inference behavior belongs in
  the lowest applicable SDK layer.

## Security and Honest Runtime State

- Never log or persist API keys, bearer tokens, authorization headers, request
  bodies containing credentials, or secret-bearing URLs (localStorage, OPFS,
  IndexedDB, screenshots, traces, `.env` files included). `VITE_*` values are
  public browser-bundle configuration, never server secrets — see
  [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md) for the full deployment contract.
- Browser control-plane access must be same-origin when an upstream does not
  publish CORS. Keep relay destinations fixed and allowlisted; never turn a
  URL from Settings, query parameters, or request bodies into a proxy target.
- UI and readiness probes must report real registered/loaded/inference state.
  A missing backend, unavailable WebGPU path, failed model load, or failed
  modality is an explicit unavailable/error state, not a fake toggle, silent
  fallback, placeholder success, or downloaded-only pass.
- Dynamic flows expose distinct idle/loading/ready/success/error/cancelled
  states with typed unions or generated enums. Errors must leave a retry or
  recovery path.

## Commands

Run from `bindings/web/` unless noted.

```bash
npm run typecheck
npm run build
npm run lint
npm run test
npm run check:esm-specifiers
npm run verify:nodenext                 # published declarations + Node ESM entrypoints
npm run test:browser
npm run test:browser:release             # opt-in full real-model release journey

# WASM builds — each flag emits ONE artifact to its owning package
npm run build:wasm -- --core             # packages/core/wasm/racommons.{js,wasm}
npm run build:wasm -- --llamacpp         # packages/llamacpp/wasm/racommons-llamacpp.{js,wasm} (CPU)
npm run build:wasm -- --webgpu           # packages/llamacpp/wasm/racommons-llamacpp-webgpu.{js,wasm}
npm run build:wasm -- --onnx             # packages/onnx/wasm/racommons-onnx-sherpa.{js,wasm}
npm run build:wasm -- --onnx-webgpu      # packages/onnx/wasm/racommons-onnx-sherpa-webgpu.{js,wasm}
npm run build:wasm:all                    # core + llama CPU/WebGPU + onnx CPU/WebGPU
npm run vendor:wasm:speech                # CPU ORT + WebGPU ORT + Sherpa (required before release)
npm run build:wasm:debug
npm run clean:wasm                       # remove all WASM build dirs and generated glue/binaries
npm run build:wasm:clean

./scripts/package-sdk.sh
```

Minimal example (the in-repo harness — the full demo app lives in
[RunanywhereAI/runanywhere-web](https://github.com/RunanywhereAI/runanywhere-web)):

```bash
cd example
npm install
npm run typecheck
npm run build
npm run dev
```

Full release-gate sequencing, package-verification, and browser-validation
runbooks live in [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md).

## Package Structure

```text
bindings/web/
├── package.json
├── scripts/
│   └── package-sdk.sh
├── wasm/
│   ├── CMakeLists.txt        # 5 artifacts: core / llama CPU|WebGPU / onnx CPU|WebGPU
│   └── scripts/build.sh
└── packages/
    ├── core/
    │   ├── src/index.ts       # public facade
    │   ├── src/internal.ts    # core-private implementation entrypoint
    │   ├── src/backend.ts     # narrow backend integration entrypoint
    │   ├── src/browser.ts     # browser helper entrypoint
    │   ├── src/Public/
    │   └── wasm/              # racommons.{js,wasm} (commons-only)
    ├── llamacpp/
    │   ├── src/LlamaCPP.ts
    │   ├── src/Foundation/LlamaCppBridge.ts
    │   └── wasm/              # racommons-llamacpp.{js,wasm} + racommons-llamacpp-webgpu.{js,wasm}
    └── onnx/
        ├── src/ONNX.ts
        ├── src/Foundation/SherpaONNXBridge.ts
        └── wasm/              # racommons-onnx-sherpa.{js,wasm} (+ optional -webgpu twin)
```

## Initialization & Public Surface

```ts
import { RunAnywhere, SDKEnvironment } from '@runanywhere/web';
import { LlamaCPP } from '@runanywhere/web-llamacpp';
import { ONNX } from '@runanywhere/web-onnx';

await RunAnywhere.initialize({
  environment: SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT,
});
await LlamaCPP.register({ acceleration: 'auto' });   // loads racommons-llamacpp.wasm
await ONNX.register();                                // loads racommons-onnx-sherpa.wasm
await RunAnywhere.completeServicesInitialization();
```

`RunAnywhere.initialize()` loads `racommons.wasm` (commons only) and records core SDK
state. Each backend's `register()` loads its own dedicated WASM, calls `rac_init()`
against that module, registers its vtable(s) with the plugin registry, and installs
itself on the core proto-byte adapters so subsequent operations route correctly.
`ONNX.register()` accepts an optional `wasmUrl` override; the previous
`skipProtoBytePlugins` / `skipStandaloneSpeech` options were removed — proto-byte is
the only path.

The root facade is intentionally small and Swift-shaped
(`RunAnywhere.loadModel`, `generateStream`, `transcribeStream`, `ragQuery`, …).
See [`docs/reference/PUBLIC_API_SURFACE.md`](docs/reference/PUBLIC_API_SURFACE.md)
for the full method inventory. Keep namespaces only where Swift has them
(`RunAnywhere.solutions`, `RunAnywhere.pluginLoader`); example/app code should
prefer root methods and avoid `@runanywhere/web/internal`.

### Demo boot and runtime honesty

- The example boots in this order: `RunAnywhere.initialize()` → backend
  registration → `completeServicesInitialization()` (Phase 2) → model catalog
  registration/hydration. Production identity is asynchronous after this path
  and must never block local shell readiness.
- `BackendWorkerHost` is the production LlamaCPP inference path when
  `Worker` is available: `LlamaCPP.register()` installs `backendWorker.ts`,
  loads models in the worker (preferring the no-pthread WebGPU WASM), and
  sets `RunAnywhere.runtime.executionContext` to `'worker'`. On handshake
  failure, `runtime.degradedReason` explains the main-thread fallback.
  Nesting the pthread CPU artifact in a DedicatedWorker requires
  `mainScriptUrlOrBlob` so `em-pthread` children can boot.
- Diffusion is exposed through `@runanywhere/web` core (Swift/Kotlin parity); there
  is no separate `@runanywhere/web-diffusion` package until it ships a WASM
  artifact — don't claim or package it alongside the four canonical JS/WASM pairs.
- Hybrid STT registers `Cloud.registerBackend()` only after `ONNX.register()`;
  a missing optional cloud engine must not make local ONNX/Sherpa unavailable.

## Build, Artifacts & Release Validation

Canonical publish-time WASM/JS artifact pairs, the `prepack`/`verify:package`
gates, and the browser-validation runbook (COOP/COEP, per-modality
download→load→inference→output proof) are documented in
[`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md); the production deployment
contract (headers, CSP, static-asset serving, storage/memory budgets) is in
[`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md). Read both before cutting a release
or touching headers/CSP — do not re-derive them here.

Two invariants worth restating because they are easy to violate by accident:

- `packages/onnx` must never publish `wasm/sherpa/**` — that standalone
  artifact was removed; the proto-byte path through `racommons-onnx-sherpa.wasm`
  is the only Sherpa surface.
- A green `typecheck`/`lint`/`build` is smoke validation only. Claiming a
  release covers a modality (LLM, VLM, STT, TTS, VAD, Voice Agent, RAG, …)
  requires driving it in a real, COOP/COEP-enabled browser end to end — see
  `npm run test:browser:release` and `tests/browser/release-app.e2e.spec.ts`.
