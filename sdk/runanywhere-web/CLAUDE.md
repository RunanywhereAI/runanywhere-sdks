# RunAnywhere Web SDK — CLAUDE.md

## Overview

The Web SDK is a Swift-aligned TypeScript facade over RACommons WASM:

- `@runanywhere/web`: public Swift-shaped core facade, generated-proto public types, and no bundled WASM.
- `@runanywhere/web/internal`: backend-only plumbing such as WASM module installation, proto adapters, stream adapters, provider hooks, and logging.
- `@runanywhere/web/browser`: browser-only helpers such as audio capture/playback, video capture, and capability detection.
- `@runanywhere/web-llamacpp`: LLM/VLM/embeddings/tool-calling/structured-output backend package.
- `@runanywhere/web-onnx`: STT/TTS/VAD backend package backed by the unified RACommons WASM module.

Keep app code on the root `RunAnywhere` facade. Backend packages may import from `@runanywhere/web/internal`; browser apps may import UI/device helpers from `@runanywhere/web/browser`.

## Commands

Run from `sdk/runanywhere-web/` unless noted.

```bash
npm run typecheck
npm run build
npm run lint
npm run test
npm run test:browser

npm run build:wasm -- --llamacpp
npm run build:wasm -- --llamacpp --onnx
npm run build:wasm -- --llamacpp --vlm --webgpu
npm run build:wasm:debug
npm run build:wasm:clean

./scripts/package-sdk.sh
```

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
│   ├── CMakeLists.txt
│   └── scripts/build.sh
└── packages/
    ├── core/
    │   ├── src/index.ts       # public facade
    │   ├── src/internal.ts    # backend-only entrypoint
    │   ├── src/browser.ts     # browser helper entrypoint
    │   └── src/Public/
    ├── llamacpp/
    │   ├── src/LlamaCPP.ts
    │   ├── src/Foundation/
    │   ├── src/Infrastructure/LifecycleVLMProvider.ts
    │   └── wasm/
    └── onnx/
        └── src/ONNX.ts
```

The old `packages/onnx/wasm/sherpa/` publish artifact is intentionally deleted. ONNX registration now uses the unified RACommons WASM module built with `RAC_WASM_ONNX=ON` through `npm run build:wasm -- --llamacpp --onnx`, but real STT/TTS/VAD is still blocked until `sdk/runanywhere-commons/third_party/onnxruntime-wasm` and `sdk/runanywhere-commons/third_party/sherpa-onnx-wasm` contain usable static archives and headers.

## Initialization Flow

```ts
await RunAnywhere.initialize({ environment: 'development' });
await LlamaCPP.register({ acceleration: 'auto' });
await ONNX.register();
await RunAnywhere.completeServicesInitialization();
```

`RunAnywhere.initialize()` restores browser storage and records core SDK state. Backend registration installs the RACommons Emscripten module, completes native Phase 1, registers backend vtables, and then lets deferred Phase 2 service initialization run.

## Build Artifacts

Expected publish-time artifacts:

- `packages/core/dist/**`
- `packages/llamacpp/dist/**`
- `packages/llamacpp/wasm/racommons-llamacpp.{js,wasm}`
- `packages/llamacpp/wasm/racommons-llamacpp-webgpu.{js,wasm}`
- `packages/onnx/dist/**`
- `../shared/proto-ts/dist/**`

`packages/onnx` must not publish `wasm/sherpa/**`.

## Validation

Build/install/launch is smoke validation only. Full Web validation needs:

1. Fresh browser context.
2. Example app served with COOP/COEP headers.
3. Model download.
4. Model load.
5. Real browser inference for the target modality.
6. Logs/screenshots reviewed.

Use `test_workflows/instructions/web/` for the canonical browser workflow.
