# Web SDK rewrite — acceptance checklist

Living doc. Every item is a thing that must hold before cutover. `[ ]` open, `[x]` done.
Plan: `thoughts/shared/plans/web_sdk_rewrite.md`.

## Hard gates (non-negotiable)

- [ ] Every backend + every feature actually WORKS in-browser — not just typechecks/wires.
      LLM, VLM, STT, TTS, VAD, Embeddings, RAG, Structured Output, Voice agent.
- [ ] ONNX path works. Old SDK: ONNX wired but non-functional. Find root cause before P4; do not reproduce.
- [ ] RAG works end to end (embed → retrieve → generate). Old SDK: broken. Fix, don't copy.
- [ ] Non-freezing UX in every browser (Chrome, Safari, Firefox). Main thread never blocks.
- [ ] All heavy inference runs off-thread (Web Worker / OffscreenRuntimeBridge / StreamWorker).
- [ ] Thread + resource management: correct PTHREAD_POOL_SIZE, no worker starvation, clean teardown.

## Layering (from AGENTS.md)

- [ ] Thin bridge over commons — no AI/business logic in TS.
- [ ] Public API mirrors iOS Swift shape + behavior.
- [ ] Proto types are canonical; no hand-written enums.
- [ ] Generated proto TS and WASM build scripts reused, not rewritten.

## Do-not-regress (encoded fixes from the old tree)

- [ ] COOP/COEP cross-origin isolation for SharedArrayBuffer; Safari `coi-serviceworker.js`.
- [ ] WASM struct offsets read at runtime via `Offsets` proxy — never hard-coded.
- [ ] VLM worker OOM auto-recovery on `memory access out of bounds`.
- [ ] Qwen2-VL forced to CPU WASM under WebGPU (f16 M-RoPE NaN logits).
- [ ] VLM pthread-pool deadlock avoided (`PTHREAD_POOL_SIZE=8` in wasm CMake).
- [ ] Async `http_download` slot (fetch + ReadableStream → MEMFS, HTTP 416 = complete) + event-driven C++ download driver → live progress.
- [ ] Model discovery / OPFS↔MEMFS hydration: `frameworkOPFSDir()`, `hydrateModelRegistry()`, `models.hydrated` event, `model_folder_is_complete` size check, framework helper exports.
- [ ] Streaming fan-out: one commons callback per handle → `HandleFanOut` → many AsyncIterable subscribers.
- [ ] Telemetry via TelemetryBridge; prod needs `rac_auth_get_access_token` WASM export (follow-up).
- [ ] emcc pinned 5.0.6 (5.0.0 produced broken onnx).
- [ ] `RAC_EXPORTED_FUNCTIONS_BASE` lists every `rac_*` the TS calls.
- [ ] Vendored prebuilt ONNX/sherpa WASM via vendor scripts.
- [ ] Hybrid STT (offline sherpa ↔ cloud) routing in commons; Sarvam is the only cloud STT tested.

## Reference

- Known-good checkout: `/home/home/Projects/runanywhere-sdks` (branch `siddhesh/web-sdk-fixes`).
- Old SDK: `sdk/runanywhere-web/`. Lift logic per-item; don't guess.
