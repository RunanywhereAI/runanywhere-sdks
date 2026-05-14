# Web Swift-Alignment Validation Report

Date: 2026-05-14
Branch: `feat/v2-architecture`
Scope: `sdk/runanywhere-web`, `examples/web/RunAnywhereAI`, Web WASM packaging, and the shared C++ pieces required by Web.
Source of truth: `sdk/runanywhere-swift/ARCHITECTURE.md`

## Summary

The Web SDK has been aligned further toward the Swift public facade:

- The root `RunAnywhere` surface exposes flat Swift-shaped methods for initialization, lifecycle, registry, downloads, LLM, structured output, tool calling, STT, TTS, VAD, VLM, RAG, VoiceAgent, storage analyzer wrappers, hardware, logging, solutions, and plugin loading.
- The Web example app consumes the root facade for model download/load, chat generation, VLM analysis, and RAG document/query actions where root methods exist.
- VLM is wired through lifecycle-resolved C++/WASM artifacts with primary GGUF plus mmproj sidecar metadata and exported VLM proto symbols.
- LLM browser E2E passes with real model download/load/generation.
- Full all-modality PASS is still blocked by missing ONNX/Sherpa/RAG Web artifacts and a current WebGPU VLM runtime abort.

## Validation

| Check | Result | Evidence |
| --- | --- | --- |
| Web lint | PASS | `npm run lint` in `sdk/runanywhere-web` |
| Web typecheck | PASS | `npm run typecheck` in `sdk/runanywhere-web` |
| Web package build | PASS | `npm run build` in `sdk/runanywhere-web` |
| Web unit tests | PASS | `npm run test` in `sdk/runanywhere-web`: 5 files, 24 tests |
| Example typecheck | PASS | `npm run typecheck` in `examples/web/RunAnywhereAI` |
| Example production build | PASS | `npm run build` in `examples/web/RunAnywhereAI` |
| Browser smoke | PASS | `npm run test:browser`: 1 passed, opt-in LLM/VLM tests skipped |
| LLM browser E2E | PASS | `RA_RUN_LLM_E2E=1 npm run test:browser -- tests/browser/llm-generate.spec.ts`: 1 passed in 13.0s |
| VLM browser E2E | BLOCKED | `RA_RUN_VLM_E2E=1 npm run test:browser -- tests/browser/vlm-generate.spec.ts`: fails during `RunAnywhere.loadModel(...)` with `RuntimeError: unreachable` in `racommons-llamacpp-webgpu.wasm` |
| Whitespace check | PASS | `git diff --check` |
| MCP/Puppeteer browser launch | PASS for app readiness | Opened `http://127.0.0.1:5174/`; verified app shell, WebGPU badge, `crossOriginIsolated`, `SharedArrayBuffer`, WebGPU adapter, JSPI (`WebAssembly.promising`, `WebAssembly.Suspending`) |

## WASM Symbol Inspection

`sdk/runanywhere-web/packages/llamacpp/wasm/racommons-llamacpp.js`

- present: `_rac_backend_llamacpp_register`
- present: `_rac_backend_llamacpp_vlm_register`
- present: `_rac_vlm_process_proto`
- present: `_rac_vlm_process_stream_proto`
- missing: `_rac_backend_onnx_register`
- missing: `_rac_backend_sherpa_register`
- missing: `_rac_rag_session_create_proto`
- missing: `_rac_rag_query_proto`

`sdk/runanywhere-web/packages/llamacpp/wasm/racommons-llamacpp-webgpu.js`

- present: `_rac_backend_llamacpp_register`
- present: `_rac_backend_llamacpp_vlm_register`
- present: `_rac_vlm_process_proto`
- present: `_rac_vlm_process_stream_proto`
- missing: `_rac_backend_onnx_register`
- missing: `_rac_backend_sherpa_register`
- missing: `_rac_rag_session_create_proto`
- missing: `_rac_rag_query_proto`

## Current Blockers

1. STT, TTS, and model-backed VAD cannot pass until ONNX Runtime WASM and Sherpa/Piper/eSpeak WASM static archives are present and linked into the Web artifact.
2. RAG cannot pass until ONNX embeddings are available and `rac_rag_*` proto exports are emitted.
3. VoiceAgent cannot pass until STT, VAD, LLM, and TTS all load and run in the browser.
4. VLM currently exports the expected llama/VLM symbols, but WebGPU E2E aborts during lifecycle `loadModel(...)` with `RuntimeError: unreachable`.
5. Tool-calling, structured output, LoRA, Solutions, and PluginLoader still need real browser E2E proof beyond surface/export checks.

## Artifacts

- Screenshot: `runanywhere-web-swift-alignment-ready` captured through Puppeteer.
- VLM failure trace: `sdk/runanywhere-web/test-results/vlm-generate-Web-SDK-VLM-e-1670b-proj-and-processes-an-image-chromium/trace.zip`
- VLM error context: `sdk/runanywhere-web/test-results/vlm-generate-Web-SDK-VLM-e-1670b-proj-and-processes-an-image-chromium/error-context.md`
