# Web SDK - PR Review Checklist

Updated: 2026-05-14
Source of truth: `sdk/runanywhere-swift/ARCHITECTURE.md`
Reference implementation: `sdk/runanywhere-react-native`
Scope: Web SDK Swift-alignment pass only.

## Review stance

Approve only when the Web SDK is a thin browser/platform facade over proto/C++ business logic and the public API mirrors the Swift SDK shape. Browser-native code is allowed for Web storage, Fetch/Emscripten transport, media capture/playback, WebGPU/JSPI selection, Web Workers, and example UI state. Historical/resolved findings stay out of this file.

## Required architecture checks

- `@runanywhere/web` root exports the public facade and public proto-derived types only.
- Backend/runtime plumbing is private or exported only from `@runanywhere/web/internal` for backend packages.
- Shared data types come from `@runanywhere/proto-ts`; local duplicate enums/types are deleted unless they are browser UI state.
- The shared generated TS package remains `sdk/shared/proto-ts` and publishes as `@runanywhere/proto-ts`; it should not move under Web.
- Root flat methods exist for Swift-flat APIs: lifecycle, registry, download/import/storage, LLM, structured output, tool calling, STT, TTS, VAD, VLM, VoiceAgent, and RAG.
- `RunAnywhere.solutions` and `RunAnywhere.pluginLoader` remain namespace properties because Swift exposes them that way.
- TypeScript owns only browser resources, proto marshaling, WASM module lifetime, and JS callback trampolines.
- C++ owns model lifecycle, downloads, registry, routing, modality inference, structured output, tool-call parsing/run-loop, RAG, LoRA, solutions, SDK events, telemetry, and plugin loading.

## Required backend/export checks

- LLM artifact exports `_rac_backend_llamacpp_register`.
- VLM-capable artifacts export `_rac_backend_llamacpp_vlm_register`, `_rac_vlm_process_proto`, and `_rac_vlm_process_stream_proto`.
- WebGPU artifact JSPI exports include model lifecycle load/unload and LLM/VLM proto generation/process symbols.
- ONNX-capable artifact exports `_rac_backend_onnx_register`.
- Sherpa-capable artifact exports `_rac_backend_sherpa_register`.
- STT artifact exports component lifecycle and proto transcription symbols.
- TTS artifact exports component lifecycle and proto synthesis/list-voice symbols.
- VAD artifact exports component lifecycle, model-load/is-loaded, and proto process/stat/event symbols.
- RAG artifact exports `rac_rag_session_create_proto`, `rac_rag_ingest_proto`, `rac_rag_query_proto`, `rac_rag_stats_proto`, `rac_rag_clear_proto`, and destroy symbols.
- Missing exports are reported as `BLOCKED` with artifact paths, not treated as PASS.

## Required deletion checks

- No example view imports `@runanywhere/web/internal`.
- No example view imports proto adapters directly.
- No example view imports VLM worker bridge internals directly.
- No app-facing root exports expose provider registration hooks after backend packages own registration.
- No stale standalone Sherpa assets remain after unified ONNX/Sherpa backend registration is proven.
- No stale Web docs claim full STT/TTS/VAD/RAG/VoiceAgent support without browser inference evidence.
- No stale browser test checklist describes UI that no longer exists.

## Required modality checks

| Area | Review requirement |
| --- | --- |
| LLM | Download, load, and real browser generation through the example app or equivalent browser workflow. |
| Model lifecycle | Download/load/unload/current model flow works through Swift-shaped public APIs. |
| STT | ONNX/Sherpa exports present, model downloaded/loaded, fixture audio transcribed with expected keywords. |
| TTS | ONNX/Sherpa/Piper exports present, voice downloaded/loaded, synthesized audio bytes and duration verified. |
| VAD | Silero/model-backed path verified, not energy fallback, with speech/silence fixture transitions. |
| VLM | Primary GGUF plus mmproj sidecar downloaded/loaded, lifecycle provider resolves artifacts internally, fixture image returns text. |
| RAG | Embedding and LLM models loaded, pipeline created, document ingested, query returns retrieved evidence and answer. |
| VoiceAgent | STT, VAD, LLM, and TTS loaded, one full voice turn returns transcript, response, and audio. |
| Tool calling | C++ run-loop ABI used where present; JS executes registered tool callbacks only; browser test proves one deterministic tool. |
| Structured output | C++ prompt/schema path used where present; browser test proves schema-valid JSON. |
| LoRA | Public API works or is marked blocked with missing export/artifact proof. |
| Solutions | Public namespace works or is marked blocked with exact proof. |
| PluginLoader | Public namespace works or is marked blocked with exact missing host/plugin ABI proof. |
| Storage | Browser storage is tested with clean state, download persistence, and reload behavior. |
| Events/logging/hardware | Public APIs are verified after facade changes. |

## Required packaging checks

- `@runanywhere/proto-ts` builds before Web packages.
- Core, llamacpp, and onnx packages declare publishable dependencies/peers for external consumers.
- Package `files` and `exports` include only intended public artifacts.
- Backend package artifact checks fail if required `.js`, `.wasm`, worker, or symbol exports are missing.
- `@runanywhere/web-onnx` does not publish an empty backend story as if STT/TTS/VAD are usable.
- Package dry-run or pack checks run in dependency order.
- Browser app aliases used for local development do not hide missing published package dependencies.

## Required validation checks

- Run the lint workflow from `.claude/commands/run_and_fix_lints.md` for the Web lane.
- Run `npm run lint` from `sdk/runanywhere-web`.
- Run `npm run typecheck` from `sdk/runanywhere-web`.
- Run `npm run build` from `sdk/runanywhere-web`.
- Run `npm run test` from `sdk/runanywhere-web`.
- Run `npm run test:browser` from `sdk/runanywhere-web`.
- Run opt-in LLM browser E2E.
- Run opt-in VLM browser E2E after WebGPU/JSPI rebuild and keep the failure trace if it aborts.
- Run example app typecheck.
- Run example app production build.
- Run `git diff --check`.
- Inspect Web WASM exports for init, model-path, backend registration, VLM, ONNX/Sherpa, and RAG symbols.
- Start the Web example with captured Vite logs and verify via MCP/Puppeteer or equivalent browser automation.
- Store evidence under `test_workflows/logs/<timestamp>-web-swift-alignment/REPORT.md`.

## Current review blockers

Current evidence report: `test_workflows/logs/20260514-160224-web-swift-alignment/REPORT.md`.

- ONNX/Sherpa WASM static archives are absent, so STT/TTS/model-backed VAD cannot pass.
- RAG exports are absent and embeddings depend on ONNX Runtime WASM.
- VoiceAgent remains blocked behind STT/VAD/TTS runtime readiness.
- VLM currently fails Chrome/WebGPU browser E2E after successful primary+mmproj load: `RunAnywhere.processImage(...)` reaches CLIP `encoding image slice...` and does not resolve within the 60s generation timeout. Trace: `sdk/runanywhere-web/test-results/vlm-generate-Web-SDK-VLM-e-e4e42-proj-and-processes-an-image-chromium/trace.zip`.
- Tool-calling and structured-output C++ ownership need browser E2E proof.
- Browser E2E evidence is current and passing for LLM only; it is not complete for all exposed modalities.
- Package dry-run/symbol checks are not yet part of the Web validation gate.
