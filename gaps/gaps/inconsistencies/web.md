# Web SDK - Current Inconsistencies

Updated: 2026-05-14
Source of truth: `sdk/runanywhere-swift/ARCHITECTURE.md`
Reference implementation for Web-facing TypeScript bridge shape: `sdk/runanywhere-react-native`
Scope: `sdk/runanywhere-web`, `examples/web/RunAnywhereAI`, Web WASM packaging, and Web validation only.

## Alignment rule

Swift is the canonical API, naming, folder, bridge, and business-logic shape. Web may keep browser-native code only for browser storage, Fetch/Emscripten transport, media capture/playback, WebGPU/JSPI selection, browser persistence, workers, and UI state. Everything else should be proto/C++ owned or match Swift's public facade.

No backwards compatibility is required. Prefer deletion over deprecated aliases.

## Current truth

- Current evidence report: `test_workflows/logs/20260514-160224-web-swift-alignment/REPORT.md`.
- LLM is the strongest Web modality: browser download, C++ lifecycle load, and real generation passed in the current validation with `RA_RUN_LLM_E2E=1 npm run test:browser -- tests/browser/llm-generate.spec.ts`.
- The root `RunAnywhere` facade now exposes the Swift-shaped flat methods for lifecycle, registry, downloads, LLM, structured output, STT, TTS, VAD, VLM, RAG, and VoiceAgent. Lower-level namespaces remain for backend packages and handle-oriented internals.
- The example app no longer imports `@runanywhere/web/internal` in the modality views checked during this pass. Model download/load, chat generation, VLM analysis, and RAG document/query actions now prefer root flat methods where Web exposes them.
- VLM is closer than the old docs said: the catalog declares primary GGUF plus mmproj sidecar, CPU and WebGPU llama artifacts export VLM symbols, and the public path is `RunAnywhere.loadModel(...)` -> `RunAnywhere.processImage(...)` through the lifecycle provider. Current blocker is runtime proof: WebGPU VLM E2E now fails during `RunAnywhere.loadModel(...)` with `RuntimeError: unreachable` in `racommons-llamacpp-webgpu.wasm`; the earlier CPU path timed out after prompt preparation.
- STT/TTS/model-backed VAD are blocked by artifacts, not TypeScript naming. `sdk/runanywhere-commons/third_party/onnxruntime-wasm` and `sdk/runanywhere-commons/third_party/sherpa-onnx-wasm` only contain `.gitkeep`, so `_rac_backend_onnx_register` and `_rac_backend_sherpa_register` are absent.
- RAG is blocked because `rac_rag_*` exports are absent and embeddings depend on ONNX Runtime WASM.
- VoiceAgent is blocked until STT, VAD, LLM, and TTS can all be loaded and exercised in the browser.

## Current open gaps

### WEB-ALIGN-001: Example app still has a few Web-native namespace calls

The SDK root facade has Swift-shaped methods, and the example now uses root calls for downloads, lifecycle, LLM generation, VLM analysis, and core RAG operations. Remaining namespace calls are for Web-native storage handles, provider diagnostics, RAG capability/availability checks, RAG list/remove provider capability checks, and `solutions`.

Fix: keep namespace calls only where they represent browser-native facilities or provider diagnostics. Add root wrappers only if Swift exposes the same operation as a flat API and the Web SDK can honestly support it.

### WEB-ALIGN-002: ONNX/Sherpa WASM static archives are missing

The Web build cannot register ONNX/Sherpa backends because usable WASM static archive/header payloads are absent from:

- `sdk/runanywhere-commons/third_party/onnxruntime-wasm`
- `sdk/runanywhere-commons/third_party/sherpa-onnx-wasm`

Fix: build/vendor ONNX Runtime WASM and Sherpa-ONNX/Piper/eSpeak WASM archives, rebuild the Web artifact with ONNX/Sherpa enabled, and inspect exports before claiming STT/TTS/VAD readiness.

### WEB-ALIGN-003: STT/TTS/VAD browser inference cannot pass yet

The Web facades now fail loudly when speech backend registration exports are missing. That is correct, but full Swift parity needs real model-backed inference.

Fix: after ONNX/Sherpa archives exist, download/load STT, TTS, and Silero VAD models through the app and run fixture-based browser tests.

### WEB-ALIGN-004: VLM inference fails current WebGPU E2E

Resolved since the prior stale doc: multi-file SmolVLM metadata exists, VLM symbols exist in CPU/WebGPU artifacts, and lifecycle-owned `RunAnywhere.processImage` exists. Remaining issue: CPU VLM timed out after prompt preparation; WebGPU/JSPI was rebuilt with proto exports and now aborts in a real browser/Playwright workflow.

Current result: `RA_RUN_VLM_E2E=1 npm run test:browser -- tests/browser/vlm-generate.spec.ts` fails during `RunAnywhere.loadModel(...)` with `RuntimeError: unreachable` in `racommons-llamacpp-webgpu.wasm`. Playwright captured the trace under `sdk/runanywhere-web/test-results/vlm-generate-Web-SDK-VLM-e-1670b-proj-and-processes-an-image-chromium/`.

Fix: debug the WebGPU lifecycle load abort inside the llama/VLM backend, keep CPU fallback diagnostics, and only mark PASS after primary+mmproj model load and image inference return real text in a browser.

### WEB-ALIGN-005: RAG cannot run in the current Web artifact

The Web build keeps RAG disabled because embeddings require ONNX Runtime WASM, and the current emitted glue lacks `rac_rag_*` proto exports.

Fix: enable RAG only after ONNX embeddings are available, then validate create pipeline, ingest, stats/count, clear, and query in the browser.

### WEB-ALIGN-006: VoiceAgent is not end-to-end

The public VoiceAgent facade exists, but the runtime cannot complete a voice turn because STT/TTS/VAD are blocked.

Fix: after speech modalities pass, run a full browser voice turn with fixture audio and assert transcript, LLM response, and synthesized audio.

### WEB-ALIGN-007: Tool-calling run loop needs C++ ownership proof

The Web artifact exports `rac_tool_calling_run_loop_proto`, but the current TypeScript surface still needs proof that the full loop delegates to C++ with JS only acting as callback trampoline.

Fix: route/verify `RunAnywhere.generateWithTools` through the C++ run-loop ABI and add a browser E2E with one deterministic JS tool callback.

### WEB-ALIGN-008: Structured output should be fully C++ owned

The public flat methods exist, but Web still has JS parsing/deserialization around structured output generation.

Fix: verify `rac_structured_output_generate_proto`, stream, parse, validate, and schema-to-JSON exports, then keep TypeScript limited to proto marshaling and result decoding.

### WEB-ALIGN-009: Package publishing needs runtime symbol gates

`@runanywhere/web-llamacpp` is packable with CPU/WebGPU artifacts. `@runanywhere/web-onnx` is packable as a shell but not an honest speech-runtime package until the unified RACommons WASM exports ONNX/Sherpa symbols. `scripts/package-sdk.sh` can pack without enforcing the same symbol expectations as package-level prepublish checks.

Fix: add export inspection/package artifact checks for core, proto-ts, llamacpp, and onnx; fail runtime package checks when selected modality symbols are missing.

### WEB-ALIGN-010: Full browser workflow evidence is incomplete

Default browser tests are smoke-level. Current evidence is complete for Web lint/typecheck/build/unit/browser smoke and real LLM browser E2E. Full evidence is not complete for STT, TTS, VAD, VLM, RAG, VoiceAgent, LoRA, Solutions, PluginLoader, tool calling, and structured output.

Fix: use `test_workflows/instructions/web` and store exact PASS/BLOCKED evidence under `test_workflows/logs/<timestamp>-web-swift-alignment/REPORT.md`.

## Current modality status

| Area | Status | Current evidence |
| --- | --- | --- |
| LLM | PASS | Current real browser LLM E2E downloads SmolLM2-360M, loads it, and streams tokens through `RunAnywhere.generateStream`. |
| Model registry/lifecycle/downloads | Partial PASS | C++ proto path exists and flat facade exists; VLM multi-file path needs current browser proof. |
| STT | Blocked | `_rac_backend_onnx_register` and `_rac_backend_sherpa_register` absent; no real transcription possible. |
| TTS | Blocked | ONNX/Sherpa/Piper Web archives absent; no real synthesis possible. |
| VAD | Blocked | Model-backed Silero path depends on ONNX/Sherpa exports; no energy fallback should be counted as Swift parity. |
| VLM | Blocked | Multi-file metadata and VLM symbols exist; WebGPU E2E aborts during `RunAnywhere.loadModel(...)` with `RuntimeError: unreachable`; CPU path timed out after prompt prep. |
| RAG | Blocked | `rac_rag_*` exports missing; embeddings require ONNX Runtime WASM. |
| VoiceAgent | Blocked | Depends on STT/VAD/LLM/TTS all being real and loaded. |
| Tool calling | Partial | Surface/export exists; C++ run-loop E2E pending. |
| Structured output | Partial | Surface/export exists; full C++ generation/stream E2E pending. |
| LoRA | Partial | Public surface exists; adapter apply/remove/list E2E pending. |
| Solutions | Partial | Namespace exists; solutions disabled/stubbed in current Web build. |
| PluginLoader | Partial | Facade exists; browser host/plugin ABI proof pending. |
| Storage | Partial | Browser storage namespace and flat analyzer wrappers exist; cache/temp file-manager bridges missing. |
| Packaging | Open | Package dry-run/symbol checks incomplete; ONNX package is shell-only. |

## Detailed to-do list

Each item is intentionally small enough for one agent. Agents must stay inside the Web/Web-WASM lane and must not revert unrelated Kotlin, Flutter, React Native, or other platform changes.

### Immediate validation

1. Run `npm run lint` from `sdk/runanywhere-web`.
2. Run `npm run typecheck` from `sdk/runanywhere-web`.
3. Run `npm run build` from `sdk/runanywhere-web`.
4. Run `npm run test` from `sdk/runanywhere-web`.
5. Run default browser smoke with `npm run test:browser`.
6. Run LLM E2E with `RA_RUN_LLM_E2E=1 npm run test:browser -- tests/browser/llm-generate.spec.ts`.
7. Run VLM E2E with `RA_RUN_VLM_E2E=1 npm run test:browser -- tests/browser/vlm-generate.spec.ts` and keep the exact failure trace if it aborts.
8. Run example app typecheck.
9. Run example app production build.
10. Run `git diff --check`.
11. Capture real-browser readiness via MCP/Puppeteer: cross-origin isolation, SharedArrayBuffer, WebGPU adapter, JSPI, SDK ready, active runtime.
12. Write/update an evidence report with exact PASS/BLOCKED status.

### Public facade cleanup

13. Keep chat example on `RunAnywhere.generateStream`.
14. Keep model selection example on `RunAnywhere.downloadModel`, `RunAnywhere.loadModel`, and `RunAnywhere.unloadModel`.
15. Migrate any future storage analyzer actions to root `getStorageInfo`/`deleteStorage`; keep browser directory-picker state under `RunAnywhere.storage`.
16. Keep VLM view on root `RunAnywhere.processImage`/`cancelVLMGeneration` for app-facing inference.
17. Keep namespaced handle APIs only where the app intentionally shows diagnostics or browser-native state.
18. Delete any reintroduced Web-only compatibility names that are not Swift-shaped after examples/tests are migrated.

### ONNX/Sherpa/STT/TTS/VAD

19. Build or vendor ONNX Runtime WASM static archive into `third_party/onnxruntime-wasm/lib`.
20. Stage ONNX Runtime WASM headers into `third_party/onnxruntime-wasm/include`.
21. Build or vendor Sherpa-ONNX WASM static archives into `third_party/sherpa-onnx-wasm/lib`.
22. Stage Sherpa headers into `third_party/sherpa-onnx-wasm/include`.
23. Build/vendor Piper/eSpeak/UCD dependencies required by TTS.
24. Rebuild Web WASM with ONNX/Sherpa enabled.
25. Verify `_rac_backend_onnx_register` exists in emitted glue.
26. Verify `_rac_backend_sherpa_register` exists in emitted glue.
27. Verify STT component/proto exports exist.
28. Verify TTS component/proto exports exist.
29. Verify VAD component model-load/is-loaded/proto exports exist.
30. Add browser STT fixture and keyword assertion.
31. Add browser TTS fixture and audio-byte/duration assertion.
32. Add browser VAD speech/silence fixture and transition assertions.

### VLM

33. Inspect WebGPU artifact for `rac_vlm_process_proto` JSPI wrapping.
34. Debug the current WebGPU `RunAnywhere.loadModel(...)` abort in `racommons-llamacpp-webgpu.wasm`.
35. Re-run SmolVLM download/load/process E2E with clean browser state after the lifecycle load fix.
36. If WebGPU VLM passes, update status from partial to PASS with report path.
37. Remove stale worker-only documentation if lifecycle provider remains the canonical VLM path.

### RAG

38. Add explicit `--rag` build path that fails fast while ONNX embeddings are absent.
39. Enable `RAC_BACKEND_RAG=ON` only after embedding backend is linked.
40. Verify `rac_rag_session_create_proto`, ingest, query, stats, clear, and destroy exports.
41. Add Web embedding model catalog entry.
42. Download/load embedding and LLM models.
43. Create RAG pipeline.
44. Ingest fixed document.
45. Query fixed question and assert retrieved evidence plus answer.

### VoiceAgent

46. Add VoiceAgent readiness UI for STT, VAD, LLM, and TTS prerequisites.
47. Download/load all required models.
48. Initialize VoiceAgent with loaded models.
49. Verify component states.
50. Process one fixture voice turn.
51. Verify transcript, generated response, and synthesized audio.
52. Verify stream events.

### Tool calling and structured output

53. Verify `rac_tool_calling_run_loop_proto` is used by `RunAnywhere.generateWithTools`.
54. Keep JS as callback trampoline only.
55. Add deterministic browser tool-calling E2E.
56. Verify structured-output generate, stream, parse, validate, and schema-to-JSON exports.
57. Add browser structured-output schema E2E.

### Packaging and publishability

58. Run package dry-run/pack for `@runanywhere/proto-ts`.
59. Run package dry-run/pack for `@runanywhere/web`.
60. Run package dry-run/pack for `@runanywhere/web-llamacpp`.
61. Run package dry-run/pack for `@runanywhere/web-onnx`.
62. Add symbol inspection for llamacpp CPU/WebGPU artifacts.
63. Add symbol inspection for ONNX/Sherpa artifacts when present.
64. Ensure `@runanywhere/proto-ts` publishes before Web packages.
65. Ensure package `exports` do not expose internal adapters at the root.
66. Ensure backend packages can import `@runanywhere/web/internal` without app-facing leakage.

## Deletion targets

- Delete Web-only public method names after Swift-named methods and examples are migrated.
- Delete any example internal adapter/runtime imports if they reappear.
- Delete stale docs that claim STT/TTS/VAD/RAG/VoiceAgent full support without browser inference evidence.
- Delete old standalone Sherpa asset references after unified ONNX/Sherpa registration is real.
- Delete stale VLM worker-only claims if lifecycle provider remains canonical.

## Validation required before full Web PASS

- Web lint, typecheck, build, unit tests, default browser smoke.
- Example typecheck and production build.
- `git diff --check`.
- WASM export inspection for init, model-path, backend registration, VLM, ONNX/Sherpa, and RAG symbols.
- Browser workflow from `test_workflows/instructions/web` with clean state, captured logs, screenshots, model download, model load, and real inference.
