# RunAnywhere Web SDK — AGENTS.md

## Overview

The Web SDK is a Swift-aligned TypeScript facade over the RACommons C/C++ core. It is split across three npm packages, each owning its own self-contained Emscripten WASM artifact (commons code is embedded in every backend WASM; no cross-WASM symbol sharing). Apps load only the WASMs they need.

- `@runanywhere/web`: public Swift-shaped core facade, generated proto types, and the **commons-only** WASM (`racommons.{js,wasm}`) used during `RunAnywhere.initialize()`.
- `@runanywhere/web/internal`: backend-only plumbing such as WASM module installation, proto adapters, stream adapters, provider hooks, and logging.
- `@runanywhere/web/browser`: browser-only helpers such as audio capture/playback, video capture, and capability detection.
- `@runanywhere/web-llamacpp`: LLM + VLM + embeddings + tool-calling + structured-output backend. Ships **two execution-mode variants**: `racommons-llamacpp.{js,wasm}` (CPU) and `racommons-llamacpp-webgpu.{js,wasm}` (WebGPU + JSPI). Both carry the unified llama.cpp vtable (LLM and VLM are modalities of the same engine).
- `@runanywhere/web-onnx`: STT + TTS + VAD backend backed by `racommons-onnx-sherpa.{js,wasm}` — one WASM that registers two vtables (`onnx`, `sherpa`) bundled because they share ONNX Runtime.

Keep app code on the root `RunAnywhere` facade. Backend packages may import from `@runanywhere/web/internal`; browser apps may import UI/device helpers from `@runanywhere/web/browser`.

## Commands

Run from `sdk/runanywhere-web/` unless noted.

```bash
npm run typecheck
npm run build
npm run lint
npm run test
npm run test:browser

# WASM builds — each flag emits ONE artifact to its owning package
npm run build:wasm -- --core             # packages/core/wasm/racommons.{js,wasm}
npm run build:wasm -- --llamacpp         # packages/llamacpp/wasm/racommons-llamacpp.{js,wasm} (CPU)
npm run build:wasm -- --llamacpp --webgpu  # packages/llamacpp/wasm/racommons-llamacpp-webgpu.{js,wasm}
npm run build:wasm -- --onnx             # packages/onnx/wasm/racommons-onnx-sherpa.{js,wasm}
npm run build:wasm -- --all              # all four artifacts
npm run build:wasm:debug
npm run build:wasm:clean

./scripts/package-sdk.sh
```

The `--vlm` flag has been removed — the llamacpp WASM always includes VLM (mtmd is unconditionally compiled into the unified llama.cpp engine).

Example app:

```bash
cd ../../examples/web/RunAnywhereAI
npm run typecheck
npm run build
npm run dev -- --host 127.0.0.1
```

## Public Surface

The root package intentionally exports a small Swift-shaped surface:

```ts
import { RunAnywhere } from '@runanywhere/web';
import { LlamaCPP } from '@runanywhere/web-llamacpp';

await RunAnywhere.initialize({ environment: 'development' });
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
│   ├── CMakeLists.txt        # 3 Emscripten executable targets (core / llamacpp / onnx)
│   └── scripts/build.sh
└── packages/
    ├── core/
    │   ├── src/index.ts       # public facade
    │   ├── src/internal.ts    # backend-only entrypoint
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
await RunAnywhere.initialize({ environment: 'development' });
await LlamaCPP.register({ acceleration: 'auto' });   // loads racommons-llamacpp.wasm
await ONNX.register();                                // loads racommons-onnx-sherpa.wasm
await RunAnywhere.completeServicesInitialization();
```

`RunAnywhere.initialize()` loads `racommons.wasm` (commons only) and records core SDK state. Each backend `register()` call loads its own dedicated WASM, calls `rac_init()` against that module, registers the backend vtable(s) with the plugin registry, and installs the module on the core proto-byte adapters so subsequent operations route correctly.

`ONNX.register()` accepts an optional `wasmUrl` override. The previous `skipProtoBytePlugins` / `skipStandaloneSpeech` options have been removed — the proto-byte path is the only path.

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

## Validation

Build/install/launch is smoke validation only. Full Web validation needs:

1. Fresh browser context.
2. Example app served with COOP/COEP headers.
3. Model download.
4. Model load.
5. Real browser inference for the target modality.
6. Logs/screenshots reviewed.

Use `test_workflows/instructions/web/` for the canonical browser workflow.
