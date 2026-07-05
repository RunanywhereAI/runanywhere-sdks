# RunAnywhere Web SDK (web-next)

## Info

Worker-first rewrite of the Web SDK: every `rac_*` call runs inside a Web Worker so the main thread never blocks. npm workspaces root (`@runanywhere/web-next-root`) over three packages plus the shared proto workspace. Global rules: see repo-root AGENTS.md.

- `packages/core` — `@runanywhere/web`: `RunAnywhere` facade, worker runtime, adapters, infrastructure (also exports `@runanywhere/web/internal`)
- `packages/llamacpp` — `@runanywhere/web-llamacpp`: LLM/VLM backend worker (llama.cpp WASM)
- `packages/onnx` — `@runanywhere/web-onnx`: STT/TTS/VAD/embeddings/RAG backend worker (Sherpa/ORT WASM)
- Workspace dep: `../shared/proto-ts` (`@runanywhere/proto-ts`) — generated protobuf TS types
- `wasm/` — in-tree Emscripten toolchain (CMakeLists, platform glue, patches); artifacts emit into each package's `wasm/` dir so `new URL('../wasm/…', import.meta.url)` resolves

Usage contract: `RunAnywhere.initialize()` then `LlamaCPP.register()` / `ONNX.register()` spawn the backend workers and register vtables. Cross-origin isolation (COOP + COEP) is required for `SharedArrayBuffer`; Safari needs the `coi-serviceworker.js` polyfill. TypeScript never hard-codes C struct offsets — read them at runtime via the exported offset functions.

## Build Info

```bash
# From sdk/runanywhere-web-next/
npm install
npm run vendor:wasm:speech   # download sherpa-onnx + ORT WASM static libs (needed for onnx backend)
npm run build:wasm           # Emscripten build → packages/*/wasm (scripts/build/wasm/bundle.sh; needs EMSDK)
npm run typecheck            # proto-ts + core (+ core build) + backends
npm run build                # compile all packages to dist/
npm run lint
npm run clean

# From repo root (dev entry point)
./run sdk web build          # npm install + typecheck + build
./run sdk web typecheck
./run sdk web build-wasm     # npm run build:wasm
./run sdk web vendor         # npm run vendor:wasm:speech
./run sdk web clean

# Proto codegen (repo root)
./run codegen ts             # scripts/codegen/generate_ts.sh → sdk/shared/proto-ts

# Release packaging (repo root)
scripts/release/package-web.sh
```

Requirements: Node 18+, Emscripten SDK for WASM builds. The example app (`examples/web-next/RunAnywhereAI/`) aliases imports to this SDK's `packages/*/dist` — run `npm run build` here before the example can run.

## Work Ground

Short dated notes for other agents. Add gotchas here; prune stale ones.

- 2026-07-05: `./run sdk web stage` invokes `npm run stage:wasm`, but no `stage:wasm` script exists in the root package.json — currently broken; use `build-wasm`/`vendor` instead.
- 2026-07-05: `vendor:wasm:speech` pulls static libs from the `Siddhesh2377/sherpa-onnx-rac` release into `sdk/runanywhere-commons/third_party/{sherpa-onnx-wasm,onnxruntime-wasm}`.
