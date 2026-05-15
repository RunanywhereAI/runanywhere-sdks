# Web SDK - Current Inconsistencies

Updated: 2026-05-15
Source of truth: `sdk/runanywhere-swift/ARCHITECTURE.md`
Reference implementation for Web-facing TypeScript bridge shape: `sdk/runanywhere-react-native`
Scope: `sdk/runanywhere-web`, `examples/web/RunAnywhereAI`, Web WASM packaging, and Web validation only.

## Alignment rule

Swift is the canonical API, naming, folder, bridge, and business-logic shape. Web may keep browser-native code only for browser storage, Fetch/Emscripten transport, media capture/playback, WebGPU/JSPI selection, browser persistence, workers, and UI state. Everything else should be proto/C++ owned or match Swift's public facade.

No backwards compatibility is required. Prefer deletion over deprecated aliases.

## Current truth

- Current evidence report: `test_workflows/logs/20260514-2154-web-full-parity/REPORT.md`.
- LLM is the strongest Web modality: browser download, C++ lifecycle load, and real generation passed in the current validation with `RA_RUN_LLM_E2E=1 npm run test:browser -- tests/browser/llm-generate.spec.ts`.
- VLM is now passing: `RA_RUN_VLM_E2E=1 npm run test:browser -- tests/browser/vlm-generate.spec.ts` loads the SmolVLM2 primary GGUF + mmproj and `RunAnywhere.processImage(...)` returns text in Chrome/WebGPU once mtmd vision encoding is pinned to CPU/single-thread on Emscripten.
- The root `RunAnywhere` facade now exposes the Swift-shaped flat methods for lifecycle, registry, downloads, LLM, structured output, STT, TTS, VAD, VLM, RAG, and VoiceAgent. Lower-level namespaces remain for backend packages and handle-oriented internals.
- The example app no longer imports `@runanywhere/web/internal` in the modality views checked during this pass. Model download/load, chat generation, VLM analysis, and RAG document/query actions now prefer root flat methods where Web exposes them.
- Web WASM now ships as a split pair:
  - `racommons-llamacpp.wasm` (~22 MB, all-backends, no-pthreads) - bundles full ONNX Runtime WASM and vendored Sherpa-ONNX, and is used by STT/TTS/VAD/RAG plus as the CPU LLM fallback.
  - `racommons-llamacpp-webgpu.wasm` (~16 MB, llama + VLM + JSPI, pthreads) - used for LLM/VLM WebGPU inference.
- All-backends artifact exports `_rac_backend_onnx_register`, `_rac_backend_sherpa_register`, all STT/TTS/VAD/RAG proto-byte symbols, plus LoRA, structured-output, and tool-calling exports.
- Sherpa C API constructors (`SherpaOnnxCreateOfflineRecognizer`, `SherpaOnnxCreateOfflineTts`, `SherpaOnnxCreateVoiceActivityDetector`, plus streaming variants) are patched to wrap construction in try/catch and surface typed errors instead of raw `CppException` across the WASM/JS boundary.
- ONNX Runtime WASM `session_options.h` is patched so `DEFAULT_USE_PER_SESSION_THREADS` defaults to true; Sherpa's per-session `intra_op_num_threads = 1` is now honored and avoids the shared global threadpool that required `pthread_create`.

## Current open gaps

### WEB-ALIGN-001: Example app still has a few Web-native namespace calls

The SDK root facade has Swift-shaped methods, and the example now uses root calls for downloads, lifecycle, LLM generation, VLM analysis, and core RAG operations. Remaining namespace calls are for Web-native storage handles, provider diagnostics, RAG capability/availability checks, RAG list/remove provider capability checks, and `solutions`.

Fix: keep namespace calls only where they represent browser-native facilities or provider diagnostics. Add root wrappers only if Swift exposes the same operation as a flat API and the Web SDK can honestly support it.

### WEB-ALIGN-002: STT/TTS/VAD/RAG E2E rerun pending after ORT no-pthread rebuild

Resolved since the prior stale doc: ONNX Runtime WASM and Sherpa-ONNX archives are vendored, the all-backends RACommons artifact links them, and the required `_rac_backend_onnx_register` / `_rac_backend_sherpa_register` plus STT/TTS/VAD/RAG proto-byte exports are present.

Remaining work: rerun `speech-rag-e2e.spec.ts` and the modality views in the example app against the final no-pthread, exception-catching ORT artifact (built without `--minimal_build` and without `--enable_wasm_threads`). Confirm that `SherpaOnnxCreateOfflineRecognizer`, `SherpaOnnxCreateOfflineTts`, and `SherpaOnnxCreateVoiceActivityDetector` construct cleanly instead of failing with `pthread_create failed`.

### WEB-ALIGN-003: Split CPU vs WebGPU artifact remains intentional

The pthreaded all-backends combination still fails on a non-atomics static archive, so high-performance llama/VLM continues to ship as a separate pthreaded WebGPU/JSPI artifact while ONNX/Sherpa/RAG ride on the no-pthread CPU artifact.

Fix: keep the runtime selection logic that loads `racommons-llamacpp.wasm` for STT/TTS/VAD/RAG and `racommons-llamacpp-webgpu.wasm` for LLM/VLM WebGPU. Only collapse to a single artifact after the pthreaded ONNX/Sherpa link is unblocked upstream.

### WEB-ALIGN-004: VLM image encoder pinned to CPU on Emscripten

Resolved since the prior stale doc: SmolVLM2 primary GGUF + mmproj load and `RunAnywhere.processImage(...)` returns text in Chrome/WebGPU under `RA_RUN_VLM_E2E=1 npm run test:browser -- tests/browser/vlm-generate.spec.ts`.

Implementation note: mtmd vision encoding is forced to CPU and one thread on Emscripten while LLM decode stays WebGPU-capable. If a future change touches mtmd threading, revalidate the VLM E2E before declaring PASS.

### WEB-ALIGN-005: VoiceAgent rerun depends on speech reruns

The public VoiceAgent facade is in place. Once STT/TTS/VAD reruns confirm PASS on the no-pthread ORT artifact, run a full browser voice turn with fixture audio and assert transcript, LLM response, and synthesized audio.

### WEB-ALIGN-006: Tool-calling run loop needs C++ ownership proof

The Web artifact exports `rac_tool_calling_run_loop_proto`, but the current TypeScript surface still needs proof that the full loop delegates to C++ with JS only acting as callback trampoline.

Fix: route/verify `RunAnywhere.generateWithTools` through the C++ run-loop ABI and add a browser E2E with one deterministic JS tool callback. `cross-cutting-e2e.spec.ts` is the home for that assertion.

### WEB-ALIGN-007: Structured output should be fully C++ owned

The public flat methods exist, but Web still has JS parsing/deserialization around structured output generation.

Fix: verify `rac_structured_output_generate_proto`, stream, parse, validate, and schema-to-JSON exports, then keep TypeScript limited to proto marshaling and result decoding. Extend `cross-cutting-e2e.spec.ts` accordingly.

### WEB-ALIGN-008: Package publishing needs runtime symbol gates

`@runanywhere/web-llamacpp` is packable with the LLM/VLM WebGPU artifact. The same package now also bundles the all-backends `racommons-llamacpp.wasm` for ONNX/Sherpa/RAG modalities. `scripts/package-sdk.sh` can pack without enforcing the same symbol expectations as package-level prepublish checks.

Fix: add export inspection/package artifact checks for core, proto-ts, and llamacpp (including the all-backends artifact); fail runtime package checks when selected modality symbols are missing.

### WEB-ALIGN-009: Full browser workflow evidence is incomplete

Default browser tests now include `sdk-smoke`, `backend-readiness`, and `cross-cutting-e2e`. Opt-in browser E2E suites exist for LLM (PASS), VLM (PASS), and speech/RAG (rerun pending). Full evidence is not yet complete for LoRA, Solutions, PluginLoader, and storage/hardware/events.

Fix: use `test_workflows/instructions/web` and store exact PASS/BLOCKED evidence under `test_workflows/logs/<timestamp>-web-full-parity/REPORT.md`.

## Current modality status

| Area | Status | Current evidence |
| --- | --- | --- |
| LLM | PASS | Real browser LLM E2E downloads SmolLM2-360M, loads it, and streams tokens through `RunAnywhere.generateStream`. |
| VLM | PASS | `RA_RUN_VLM_E2E=1` browser E2E loads SmolVLM2 primary GGUF + mmproj and `RunAnywhere.processImage(...)` returns text in Chrome/WebGPU with the mtmd vision encoder pinned to CPU/single-thread. |
| Model registry/lifecycle/downloads | PASS | C++ proto path used by all PASS modalities (LLM + VLM). |
| STT | Pending verification | All-backends artifact exposes `_rac_backend_onnx_register`, `_rac_backend_sherpa_register`, and STT proto-byte symbols; Sherpa C API now exception-safe. E2E rerun pending after no-pthread ORT rebuild. |
| TTS | Pending verification | All-backends artifact exposes Sherpa TTS proto-byte symbols; Sherpa C API exception-safe. E2E rerun pending after no-pthread ORT rebuild. |
| VAD | Pending verification | Silero ONNX downloads, `sherpa_vad_create_impl` exported, exception-safe. E2E rerun pending after no-pthread ORT rebuild. |
| RAG | Pending verification | `rac_rag_*` exports present; depends on the no-pthread ORT rebuild for embeddings. E2E rerun pending. |
| VoiceAgent | Pending | Depends on STT/VAD/LLM/TTS reruns. |
| Tool calling | Partial | Surface/export exists; C++ run-loop browser E2E lives in `cross-cutting-e2e.spec.ts` and is pending validated PASS. |
| Structured output | Partial | Surface/export exists; full C++ generation/stream E2E covered by `cross-cutting-e2e.spec.ts` and pending validated PASS. |
| LoRA | Partial | Public surface exists; adapter apply/remove/list E2E pending. |
| Solutions | Partial | Namespace exists; solutions disabled/stubbed in current Web build. |
| PluginLoader | Partial | Facade exists; browser host/plugin ABI proof pending. |
| Storage | Partial | Browser storage namespace and flat analyzer wrappers exist; cache/temp file-manager bridges missing. |
| Packaging | Open | Package dry-run/symbol checks incomplete. |

## Detailed to-do list

Each item is intentionally small enough for one agent. Agents must stay inside the Web/Web-WASM lane and must not revert unrelated Kotlin, Flutter, React Native, or other platform changes.

### Immediate validation

1. Run `npm run lint` from `sdk/runanywhere-web`.
2. Run `npm run typecheck` from `sdk/runanywhere-web`.
3. Run `npm run build` from `sdk/runanywhere-web`.
4. Run `npm run test` from `sdk/runanywhere-web`.
5. Run default browser smoke with `npm run test:browser` (covers `sdk-smoke`, `backend-readiness`, and `cross-cutting-e2e`).
6. Run LLM E2E with `RA_RUN_LLM_E2E=1 npm run test:browser -- tests/browser/llm-generate.spec.ts`.
7. Run VLM E2E with `RA_RUN_VLM_E2E=1 npm run test:browser -- tests/browser/vlm-generate.spec.ts`.
8. Run speech/RAG E2E with `RA_RUN_SPEECH_E2E=1 npm run test:browser -- tests/browser/speech-rag-e2e.spec.ts` after the no-pthread ORT rebuild lands.
9. Run example app typecheck.
10. Run example app production build.
11. Run `git diff --check`.
12. Capture real-browser readiness via MCP/Puppeteer: cross-origin isolation, SharedArrayBuffer, WebGPU adapter, JSPI, SDK ready, active runtime.
13. Write/update an evidence report with exact PASS/BLOCKED status.

### Public facade cleanup

14. Keep chat example on `RunAnywhere.generateStream`.
15. Keep model selection example on `RunAnywhere.downloadModel`, `RunAnywhere.loadModel`, and `RunAnywhere.unloadModel`.
16. Migrate any future storage analyzer actions to root `getStorageInfo`/`deleteStorage`; keep browser directory-picker state under `RunAnywhere.storage`.
17. Keep VLM view on root `RunAnywhere.processImage`/`cancelVLMGeneration` for app-facing inference.
18. Keep namespaced handle APIs only where the app intentionally shows diagnostics or browser-native state.
19. Delete any reintroduced Web-only compatibility names that are not Swift-shaped after examples/tests are migrated.

### ONNX/Sherpa/STT/TTS/VAD

20. Rerun `sdk/runanywhere-web/wasm/scripts/vendor-onnxruntime-wasm.sh` after the no-pthread ORT rebuild completes and refresh `third_party/onnxruntime-wasm/lib`.
21. Rerun `sdk/runanywhere-web/wasm/scripts/vendor-sherpa-onnx-wasm.sh` after Sherpa is rebuilt against the new ORT artifact.
22. Rebuild Web WASM with `npm run build:wasm -- --all-backends --no-pthreads` and re-verify exports.
23. Verify `_rac_backend_onnx_register`, `_rac_backend_sherpa_register`, STT/TTS/VAD/RAG proto-byte exports remain present.
24. Run `RA_RUN_SPEECH_E2E=1 npm run test:browser -- tests/browser/speech-rag-e2e.spec.ts` and capture transcript/audio/duration/speech-activity assertions.
25. Update modality status rows when results land.

### VoiceAgent

26. Add VoiceAgent readiness UI for STT, VAD, LLM, and TTS prerequisites.
27. Download/load all required models.
28. Initialize VoiceAgent with loaded models.
29. Verify component states.
30. Process one fixture voice turn.
31. Verify transcript, generated response, and synthesized audio.
32. Verify stream events.

### Tool calling and structured output

33. Verify `rac_tool_calling_run_loop_proto` is used by `RunAnywhere.generateWithTools`.
34. Keep JS as callback trampoline only.
35. Extend `cross-cutting-e2e.spec.ts` with a deterministic tool-calling assertion.
36. Verify structured-output generate, stream, parse, validate, and schema-to-JSON exports.
37. Extend `cross-cutting-e2e.spec.ts` with a structured-output schema assertion.

### Packaging and publishability

38. Run package dry-run/pack for `@runanywhere/proto-ts`.
39. Run package dry-run/pack for `@runanywhere/web`.
40. Run package dry-run/pack for `@runanywhere/web-llamacpp` including both the WebGPU pthreaded artifact and the all-backends no-pthread artifact.
41. Add symbol inspection for llamacpp CPU/WebGPU artifacts.
42. Add symbol inspection for ONNX/Sherpa exports in the all-backends artifact.
43. Ensure `@runanywhere/proto-ts` publishes before Web packages.
44. Ensure package `exports` do not expose internal adapters at the root.
45. Ensure backend packages can import `@runanywhere/web/internal` without app-facing leakage.

## Deletion targets

- Delete Web-only public method names after Swift-named methods and examples are migrated.
- Delete any example internal adapter/runtime imports if they reappear.
- Delete stale docs that claim STT/TTS/VAD/RAG/VoiceAgent full support without browser inference evidence.
- Delete old standalone Sherpa asset references after unified ONNX/Sherpa registration is real.
- Delete stale VLM worker-only claims now that the lifecycle provider is the canonical VLM path and the WebGPU E2E passes.

## Validation required before full Web PASS

- Web lint, typecheck, build, unit tests, default browser smoke.
- Example typecheck and production build.
- `git diff --check`.
- WASM export inspection for init, model-path, backend registration, VLM, ONNX/Sherpa, and RAG symbols (both artifacts).
- Browser workflow from `test_workflows/instructions/web` with clean state, captured logs, screenshots, model download, model load, and real inference for every still-pending modality.
