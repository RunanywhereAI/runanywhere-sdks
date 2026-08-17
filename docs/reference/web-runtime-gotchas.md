# Web SDK runtime gotchas

Linked from `AGENTS.md`. Hard-won WASM/browser-runtime bugs and workarounds that aren't
obvious from reading the TypeScript alone. See `bindings/web/AGENTS.md` for the SDK's
general architecture and build/test commands.

- **Cross-origin isolation.** `SharedArrayBuffer` requires COOP/COEP headers (the minimal
  example's `vite.config.ts` sets these). Safari additionally needs the
  `coi-serviceworker.js` polyfill.
- **VLM Worker crash recovery.** If `rac_vlm_component_process` causes a WASM OOM
  (`"memory access out of bounds"`), the Worker auto-recovers by creating a fresh WASM
  instance on the next `process()` call rather than staying wedged.
- **Qwen2-VL WebGPU workaround.** Qwen2-VL models produce NaN logits on WebGPU due to f16
  M-RoPE overflow. The VLM Worker forces CPU WASM for Qwen2-VL even when WebGPU is
  otherwise active for the session.
- **Struct offsets are never hard-coded.** TypeScript never bakes in C struct field
  offsets. `wasm_exports.cpp` exposes `EMSCRIPTEN_KEEPALIVE` offset functions, and the
  `Offsets` proxy reads them at runtime from the WASM module — so a C struct layout change
  can't silently desync from the TS side.
