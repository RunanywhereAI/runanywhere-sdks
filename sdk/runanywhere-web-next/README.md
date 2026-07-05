# @runanywhere/web (rewrite)

Blank-slate, worker-first rewrite of the Web SDK. Every `rac_*` call runs inside a
Web Worker, so the main thread never blocks. Three packages over the shared
`@runanywhere/proto-ts`:

- `@runanywhere/web` (core) — facade, worker runtime, adapters, infrastructure
- `@runanywhere/web-llamacpp` — LLM / VLM backend worker
- `@runanywhere/web-onnx` — STT / TTS / VAD / embeddings / RAG backend worker

Plan: `thoughts/shared/plans/web_sdk_next_build_plan.md`. Acceptance gate:
`WEB_REWRITE_CHECKLIST.md`.

## Build & run

```bash
cd sdk/runanywhere-web-next

npm install
npm run vendor:wasm:speech   # pull prebuilt sherpa-onnx + ORT static libs (needed for --onnx)
npm run build:wasm           # build the Emscripten artifacts into packages/*/wasm
npm run typecheck            # proto-ts + core (+ build) + backends
npm run build                # compile all packages to dist
```

`vendor:wasm:speech` downloads the matched sherpa-onnx + ONNX Runtime WASM static
libraries (`libsherpa-onnx-c-api.a`, `libonnxruntime.a`) from the
`Siddhesh2377/sherpa-onnx-rac` release into
`sdk/runanywhere-commons/third_party/{sherpa-onnx-wasm,onnxruntime-wasm}`; the onnx
WASM build links them in statically. `build:wasm` runs the in-tree Emscripten
toolchain under `wasm/` (Emscripten required) and emits `.wasm`/`.js` directly into
each package's `wasm/` dir so `new URL('../wasm/…', import.meta.url)` resolves.

## Usage

```ts
import { RunAnywhere } from '@runanywhere/web';
import { LlamaCPP } from '@runanywhere/web-llamacpp';
import { ONNX } from '@runanywhere/web-onnx';

await RunAnywhere.initialize({ environment, apiKey });
await LlamaCPP.register();   // spawns the llamacpp worker, registers llm/vlm
await ONNX.register();       // spawns the onnx worker, registers stt/tts/vad/embedding/rag

const result = await RunAnywhere.generate(request);
for await (const event of RunAnywhere.generateStream(request)) { /* … */ }
```

Cross-origin isolation (COOP + COEP) is required for `SharedArrayBuffer`; Safari
needs the `coi-serviceworker.js` polyfill.

## Via the root runner

```bash
./run sdk web-next stage      # stage WASM artifacts
./run sdk web-next build      # install + typecheck + build
./run sdk web-next typecheck  # typecheck only
./run sdk web-next clean      # remove dist
```
