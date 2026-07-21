# RunAnywhere Web SDK — AGENTS.md

## Overview

The Web SDK is a Swift-aligned TypeScript facade over the RACommons C/C++ core. It is split across three npm packages, each owning its own self-contained Emscripten WASM artifact (commons code is embedded in every backend WASM; no cross-WASM symbol sharing). Apps load only the WASMs they need.

- `@runanywhere/web`: public Swift-shaped core facade, generated proto types, and the **commons-only** WASM (`racommons.{js,wasm}`) used during `RunAnywhere.initialize()`.
- `@runanywhere/web/backend`: the narrow, typed backend integration contract for module installation, capability routing, lifecycle hooks, and safe logging.
- `@runanywhere/web/internal`: broader core-internal implementation exports; neither applications nor backend packages may depend on this entrypoint.
- `@runanywhere/web/browser`: browser-only helpers such as audio capture/playback, video capture, and capability detection.
- `@runanywhere/web-llamacpp`: LLM + VLM + LoRA + tool-calling + structured-output backend. Ships **two execution-mode variants**: `racommons-llamacpp.{js,wasm}` (CPU) and `racommons-llamacpp-webgpu.{js,wasm}` (WebGPU + Asyncify). Both carry the unified llama.cpp vtable (LLM and VLM are modalities of the same engine).
- `@runanywhere/web-onnx`: embeddings + STT + TTS + VAD backend backed by `racommons-onnx-sherpa.{js,wasm}` — one WASM that registers two vtables (`onnx`, `sherpa`) bundled because they share ONNX Runtime. Core composes its embeddings with llama.cpp generation for cross-WASM RAG.

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

- Never log API keys, bearer tokens, authorization headers, request bodies
  containing credentials, or secret-bearing URLs. Do not store API keys in
  localStorage, OPFS, IndexedDB, screenshots, traces, or committed `.env`
  files. `VITE_*` values are browser-visible client configuration, never
  server secrets.
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

Run from `sdk/runanywhere-web/` unless noted.

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
npm run build:wasm:all                    # all four artifacts (CPU and WebGPU use separate configs)
npm run build:wasm:debug
npm run clean:wasm                       # remove all WASM build dirs and generated glue/binaries
npm run build:wasm:clean

./scripts/package-sdk.sh
```

Example app:

```bash
cd ../../examples/web/RunAnywhereAI
npm run lint
npm run typecheck
npm run build
npm run dev -- --host 127.0.0.1
```

## Public Surface

The root package intentionally exports a small Swift-shaped surface:

```ts
import { RunAnywhere, SDKEnvironment } from '@runanywhere/web';
import { LlamaCPP } from '@runanywhere/web-llamacpp';

await RunAnywhere.initialize({
  environment: SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT,
});
await LlamaCPP.register({ acceleration: 'auto' });

const stream = await RunAnywhere.generateStream({
  prompt: 'Write a haiku about local AI.',
  maxTokens: 128,
});

for await (const token of stream.stream) {
  console.log(token);
}
```

Prefer Swift-shaped flat APIs at the root when Swift exposes a flat method:

- Model lifecycle/registry: `RunAnywhere.loadModel`, `unloadModel`, `currentModel`, `componentLifecycleSnapshot`, `listModels`, `queryModels`, `getModel`, `downloadedModels`, `downloadModel`, `importModel`.
- LLM/structured/tool calling: `RunAnywhere.generate`, `generateStream`, `cancelGeneration`, `generateStructured`, `generateStructuredStream`, `extractStructuredOutput`, `generateWithTools`.
- Speech/VLM/VoiceAgent/RAG: `RunAnywhere.transcribe`, `transcribeStream`, `synthesize`, `synthesizeStream`, `speak`, `stopSynthesis`, `stopSpeaking`, `detectVoiceActivity`, `streamVAD`, `resetVAD`, `processImage`, `processImageStream`, `cancelVLMGeneration`, `initializeVoiceAgent`, `processVoiceTurn`, `streamVoiceAgent`, `ragCreatePipeline`, `ragIngest`, `ragQuery`, etc.

Keep namespaces when Swift has namespace properties (`RunAnywhere.solutions`, `RunAnywhere.pluginLoader`) or when backend/package internals need lower-level handles. Example app code should prefer root Swift-shaped methods and avoid `@runanywhere/web/internal`.

## Package Structure

```text
sdk/runanywhere-web/
├── package.json
├── scripts/
│   └── package-sdk.sh
├── wasm/
│   ├── CMakeLists.txt        # 4 artifacts: core / llama CPU / llama WebGPU / ONNX
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
    │   ├── src/Infrastructure/LifecycleVLMProvider.ts
    │   └── wasm/              # racommons-llamacpp.{js,wasm} + racommons-llamacpp-webgpu.{js,wasm}
    └── onnx/
        ├── src/ONNX.ts
        ├── src/Foundation/SherpaONNXBridge.ts
        └── wasm/              # racommons-onnx-sherpa.{js,wasm}
```

There is no longer a `packages/onnx/wasm/sherpa/` standalone artifact, and no `StandaloneSherpa*` provider in `packages/onnx/src/Foundation/`. The proto-byte STT/TTS/VAD path through `racommons-onnx-sherpa.wasm` is the only Sherpa surface.

## Initialization Flow

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

`RunAnywhere.initialize()` loads `racommons.wasm` (commons only) and records core SDK state. Each backend `register()` call loads its own dedicated WASM, calls `rac_init()` against that module, registers the backend vtable(s) with the plugin registry, and installs the module on the core proto-byte adapters so subsequent operations route correctly.

`ONNX.register()` accepts an optional `wasmUrl` override. The previous `skipProtoBytePlugins` / `skipStandaloneSpeech` options have been removed — the proto-byte path is the only path.

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
- Diffusion is exposed through `@runanywhere/web` core (Swift/Kotlin parity); there is no separate `@runanywhere/web-diffusion` package
  until it ships a WASM artifact. Do not claim or package diffusion alongside
  the four current canonical JS/WASM pairs.
- Hybrid STT registers `Cloud.registerBackend()` only after `ONNX.register()`;
  a missing optional cloud engine must not make local ONNX/Sherpa unavailable.

## Build Artifacts

Expected publish-time artifacts:

- `packages/core/dist/**`
- `packages/core/wasm/racommons.{js,wasm}`
- `packages/llamacpp/dist/**`
- `packages/llamacpp/wasm/racommons-llamacpp.{js,wasm}`
- `packages/llamacpp/wasm/racommons-llamacpp-webgpu.{js,wasm}`
- `packages/onnx/dist/**`
- `packages/onnx/wasm/racommons-onnx-sherpa.{js,wasm}`
- `../shared/proto-ts/dist/**`

`packages/onnx` must not publish `wasm/sherpa/**` (the directory no longer exists).

Every canonical `.js` file is mandatory Emscripten runtime glue. A bundler may
hash the main-thread import, while pthread-enabled CPU/ONNX modules can also
request their canonical self-name from workers. The WebGPU release variant is
deliberately non-threaded because its asynchronous waits use Asyncify, but its
canonical glue remains required. Package and deployment gates must verify all
four canonical JS/WASM pairs are non-empty, syntactically valid, served as
JavaScript/`application/wasm`, and never answered by an SPA HTML fallback.

## Validation

Build/install/launch is smoke validation only. Full Web validation needs:

1. Fresh browser context.
2. Example app served with COOP/COEP headers.
3. Model download.
4. Model load.
5. Real browser inference for the target modality.
6. Logs/screenshots reviewed.

The maintained browser suites and support code live under `tests/browser/` and
run through `playwright.config.ts`; keep release assertions there.

### Required release gates

Run all static gates before browser validation:

```bash
cd sdk/runanywhere-web
npm run typecheck
npm run lint
npm run test
npm run build
npm run test:browser
npm run test:browser:release

cd ../../examples/web/RunAnywhereAI
npm run lint
npm run typecheck
npm run build
```

Then launch the built application in a real browser with COOP/COEP enabled.
For every claimed modality, verify model download, model load, real inference,
visible output, cancellation/retry where supported, and reviewed console/page/
network errors. A release that claims the full demo must exercise LLM, VLM,
STT batch + streaming, TTS playback, VAD, Voice Agent, RAG/Documents, model
storage/persistence, Settings reinitialization, CPU fallback, and WebGPU when
the browser supports it. Production verification repeats the header, asset,
backend-registration, and representative inference checks against the deployed
origin.
