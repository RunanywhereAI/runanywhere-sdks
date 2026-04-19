# runanywhere-web — v1/v2 cleanup audit

## Summary

- `sdk/runanywhere-web/` contains ~18,200 LOC across 67 source files (excluding `node_modules/` and `emsdk/`), split across three npm workspaces: `packages/core`, `packages/llamacpp`, `packages/onnx`.
- `frontends/web/` (the v2 adapter) is ~400 LOC: three TS files (`RunAnywhere.ts`, `VoiceSession.ts`, `VoiceEvent.ts`) + one WASM CMakeLists.txt; it replaces everything inference-related.
- Approximately 80–85% of v1 LOC is **DELETE-AFTER-V2-ENGINES** (the two backend packages and the v1 WASM build system). The remaining 15–20% is genuinely browser-specific I/O infrastructure that either survives verbatim or can be ported.
- Zero pre-built WASM artifacts exist on disk today (`packages/llamacpp/wasm/` and `packages/onnx/wasm/sherpa/` directories are absent); the build is always run from source via `scripts/build-web.sh`.
- No consumer code (examples or tests) calls `VoiceAgent.create()` — it has never been reachable, confirming immediate deletion is safe.

---

## DELETE-NOW

Files that are dead today regardless of v2 status.

| File | Reason |
|---|---|
| `packages/core/src/Public/Extensions/RunAnywhere+VoiceAgent.ts` | Every exported method (`create`, `loadModels`, `processVoiceTurn`, `transcribe`, `generateResponse`, `destroy`) unconditionally throws `SDKError.componentNotReady('VoiceAgent', 'No WASM backend registered')`. `isReady` always returns `false`. No consumer (example app, test) calls it. Confirmed by exhaustive grep of `examples/` and `packages/**`. |
| `packages/core/src/Public/Extensions/VoiceAgentTypes.ts` | Type declarations (`VoiceAgentModels`, `VoiceTurnResult`, `PipelineState`, etc.) exist solely to type the throwing class above. `PipelineState` is re-exported by `VoicePipelineTypes.ts`; the duplicate in `VoiceAgentTypes.ts` is unused once the class is deleted. |
| `packages/core/src/Public/Extensions/RunAnywhere+ModelManagement.ts` | A legacy download utility that writes models to the Emscripten FS at `/models`. It duplicates `ModelDownloader.ts` (the real download path) and still references `MODELS_DIR = '/models'` (an old single-module WASM path that no longer exists). Not re-exported from `packages/core/src/index.ts`. |

---

## DELETE-AFTER-V2-ENGINES

Files that are alive today (used by the v1 demo app) but become redundant once `frontends/web/` lands with real engine integrations. Deletion is gated on Phase 3 (v2 WASM engines complete).

### Entire `packages/llamacpp/` package (~6,100 LOC)

This package is the TypeScript bridge layer to the v1 `racommons-llamacpp.wasm` module. In v2 the equivalent is a static engine plugin inside `frontends/web/wasm/CMakeLists.txt` (`llamacpp_engine` target at line 18). Every file below maps directly to a v2 replacement.

| File | v1 Role | v2 Replacement |
|---|---|---|
| `Foundation/LlamaCppBridge.ts` (674 LOC) | Loads `racommons-llamacpp.wasm`, exposes `ccall`/`cwrap` C ABI | `frontends/web/wasm/runanywhere_wasm_main.cpp` + WASM bridge in v2 adapter |
| `Foundation/LlamaCppOffsets.ts` | Reads WASM struct sizes via `_rac_wasm_sizeof_*` to compute field offsets | Eliminated: v2 uses proto3 serialization, no raw struct pointer arithmetic |
| `Foundation/PlatformAdapter.ts` (475 LOC) | Registers JS-side platform callbacks (`_rac_set_platform_adapter`) for HTTP, logging, time | v2 C++ core owns platform adapters; Emscripten provides defaults |
| `Foundation/AnalyticsEventsBridge.ts` (454 LOC) | Fires analytics events by calling `_rac_analytics_emit_*` C functions from TS | Analytics emitted from C++ core, surfaced via proto3 events to TS adapter |
| `Foundation/TelemetryService.ts` (402 LOC) | Manages telemetry via `_rac_telemetry_manager_*` C API calls | Telemetry lives in C++ core |
| `Foundation/WASMAnalyticsEmitter.ts` | Routes TS-side SDK events into WASM analytics calls | Eliminated |
| `Infrastructure/VLMWorkerBridge.ts` (426 LOC) | Web Worker postMessage bridge for VLM inference off the main thread | v2 streams VLM results via `AsyncIterable<Event>` from C++ core |
| `Infrastructure/VLMWorkerRuntime.ts` (744 LOC) | Worker-side VLM runtime that owns the WASM module copy and calls `_rac_vlm_*` | Eliminated |
| `workers/vlm-worker.ts` + `vlm-worker.js` | Web Worker entry points | Eliminated |
| `Extensions/RunAnywhere+TextGeneration.ts` (601 LOC) | LLM generate/stream via `_rac_llm_component_*` C API | v2 exposes `ra_pipeline_run` → `AsyncIterable<Event>` |
| `Extensions/RunAnywhere+VLM.ts` | VLM process/stream via `_rac_vlm_component_*` C API | Same v2 pipeline path |
| `Extensions/RunAnywhere+ToolCalling.ts` (694 LOC) | Tool-call JSON parse/format via `_rac_tool_call_*` C functions | Implemented in C++ core, exposed via proto3 event |
| `Extensions/RunAnywhere+Embeddings.ts` | Embeddings via `_rac_embeddings_component_*` | C++ primitive, v2 L3 `embed` operator |
| `Extensions/RunAnywhere+Diffusion.ts` | Diffusion via `_rac_diffusion_component_*` | C++ primitive |
| `Extensions/RunAnywhere+StructuredOutput.ts` | Structured output JSON via `_rac_structured_output_*` | C++ core utility |
| `LlamaCPP.ts` | Public `LlamaCPP.register()` opt-in entry point | v2 plugin auto-registered at compile time (no opt-in) |
| `LlamaCppProvider.ts` | Manual registration: calls `ModelManager.setLLMLoader`, `ExtensionPoint.registerBackend` | Eliminated: v2 `PluginRegistry::register_static<LlamaCppEngine>()` at compile time |

### Entire `packages/onnx/` package (~2,800 LOC)

This package is the TypeScript bridge to the separately built `sherpa-onnx.wasm` module. In v2 sherpa-onnx becomes a static engine plugin (`sherpa_engine` target in `frontends/web/wasm/CMakeLists.txt` line 18).

| File | v1 Role | v2 Replacement |
|---|---|---|
| `Foundation/SherpaONNXBridge.ts` (500 LOC) | Loads `sherpa-onnx.wasm` as a separate Emscripten module, exposes sherpa C API | Sherpa compiled into the single v2 WASM binary as a static engine |
| `Foundation/SherpaHelperLoader.ts` | Loads CJS helper JS files (`sherpa-onnx-asr.js`, `-tts.js`, `-vad.js`) via Blob URL patching because they are not ESM-compatible | Eliminated: no separate JS helpers needed when sherpa is statically linked |
| `Extensions/RunAnywhere+STT.ts` (526 LOC) | STT transcription via sherpa C API | v2 `transcribe` primitive via `_ra_pipeline_feed_audio` |
| `Extensions/RunAnywhere+TTS.ts` | TTS synthesis via sherpa C API | v2 `synthesize` primitive |
| `Extensions/RunAnywhere+VAD.ts` | VAD via sherpa C API | v2 `detect_voice` primitive |
| `ONNX.ts` | Public `ONNX.register()` opt-in entry point | Eliminated: sherpa is statically compiled in, no runtime opt-in |
| `ONNXProvider.ts` (438 LOC) | Manual registration: `ModelManager.setSTTLoader`, `setTTSLoader`, `setVADLoader` | Eliminated: v2 plugin registry |

### v1 WASM build system

| Path | v1 Role | v2 Replacement |
|---|---|---|
| `wasm/CMakeLists.txt` (919 LOC) | Emscripten build config for `racommons-llamacpp.wasm`; 26 cmake options, 100+ exported function names listed manually, backend-specific opt-in flags (`RAC_WASM_LLAMACPP`, `RAC_WASM_ONNX`, etc.) | `frontends/web/wasm/CMakeLists.txt` (37 LOC): links statically to `RunAnywhere::core` + engine plugins; activated via `cmake --preset wasm-release` |
| `wasm/src/wasm_exports.cpp` (535 LOC) | Defines `rac_wasm_ping`, sizeof helpers, dev-config shims compiled into the WASM module | v2 exports defined by `_ra_pipeline_*` in `frontends/web/wasm/CMakeLists.txt` line 35 |
| `wasm/platform/wasm_platform_shims.cpp` | Backtrace stub, Emscripten platform detection shims | v2 C++ core handles platform shims via `#if defined(EMSCRIPTEN)` |
| `wasm/scripts/build.sh` (~200 LOC) | Per-backend cmake invocations with `--llamacpp`, `--vlm`, `--webgpu`, etc. flags | `cmake --preset wasm-release` from repo root |
| `wasm/scripts/build-sherpa-onnx.sh` | Separate git-clone-and-build of `sherpa-onnx v1.12.20` as a standalone WASM module | Sherpa source included as `sherpa_engine` static library in v2 CMake tree |
| `wasm/scripts/setup-emsdk.sh` | Clones and installs emsdk 5.0.0 | Same emsdk needed by v2; the script is reusable but lives in the wrong tree |
| `wasm/scripts/patch-sherpa-glue.js` | Post-processes sherpa JS glue file to add ESM exports | Eliminated: no separate sherpa JS glue |
| `scripts/build-web.sh` (596 LOC) | Orchestrates emsdk setup, separate CPU and WebGPU WASM builds, sherpa build, TypeScript build | `cmake --preset wasm-release` + `npm run build` in `frontends/web/` |
| `scripts/package-sdk.sh` | Packs three separate npm tarballs (`core`, `llamacpp`, `onnx`) | v2 ships a single `@runanywhere/v2-web` package |

### v1 opt-in backend registration (the footgun pattern)

In v1, inference engines are off by default. Consumers must:
1. Pass a build flag: `--llamacpp`, `--onnx`, `--webgpu` (in `wasm/scripts/build.sh`)
2. Await a runtime registration call: `await LlamaCPP.register()`, `await ONNX.register()`
3. Manually wire loaders: `ModelManager.setLLMLoader(TextGeneration)`, `ModelManager.setSTTLoader(...)` (done inside `LlamaCppProvider.ts:44-46` and `ONNXProvider.ts`)

These three steps are independent failure points. Forgetting any one of them results in runtime errors thrown at the point of use, not at startup.

In v2, all engines are statically linked into a single WASM binary at compile time (`target_link_libraries` in `frontends/web/wasm/CMakeLists.txt:14-21`). The TS adapter calls `ra_pipeline_create_from_solution()` on the single module — no runtime registration, no loader wiring.

Files eliminated by removing this footgun:
- `packages/llamacpp/src/LlamaCPP.ts` — `LlamaCPP.register()` entry point
- `packages/llamacpp/src/LlamaCppProvider.ts` — all `ModelManager.set*Loader` and `ExtensionPoint.register*` calls
- `packages/onnx/src/ONNX.ts` — `ONNX.register()` entry point
- `packages/onnx/src/ONNXProvider.ts` — all `ModelManager.set*Loader` calls
- `packages/core/src/Infrastructure/ModelLoaderTypes.ts` — `LLMModelLoader`, `STTModelLoader`, `TTSModelLoader`, `VADModelLoader` interfaces (exist only to define the manual-registration contract)

### ModelManager / ModelDownloader / ModelRegistry (~2,100 LOC combined)

In v2 the model registry lives in C++ (`core/model_registry/`), surfaced to TS via proto3 events. The browser no longer needs its own registry or download orchestrator. The v1 TS classes are:

| File | v1 LOC | What it does | v2 status |
|---|---|---|---|
| `ModelManager.ts` (658 LOC) | Composes registry + downloader; routes load calls to whichever loader was `set*Loader`'d | DELETE-AFTER-V2-ENGINES: replaced by `_ra_pipeline_*` calls + C++ model registry |
| `ModelDownloader.ts` (705 LOC) | Fetch with progress, OPFS persistence, quota check, LRU eviction | DELETE-AFTER-V2-ENGINES: download + storage managed by C++ core or by the v2 adapter's simpler `wasmUrl` loader |
| `ModelRegistry.ts` | In-memory catalog with `onChange` subscriptions | DELETE-AFTER-V2-ENGINES: `_ra_model_registry_*` C ABI already exported in v1 CMakeLists.txt; v2 uses the C++ version |
| `ModelLoaderTypes.ts` | Interfaces `LLMModelLoader`, `STTModelLoader`, etc. | DELETE-AFTER-V2-ENGINES (opt-in registration contract, see above) |
| `ModelFileInference.ts` | Infers model category from filename extension | INSPECT: may still be needed for the model-picker import flow in the v2 adapter if the C++ registry does not yet provide inference |
| `Infrastructure/ExtensionPoint.ts` | `BackendCapability` enum, `ServiceKey` enum, `registerBackend`, `registerProvider` | DELETE-AFTER-V2-ENGINES: provider lookup not needed when all engines are statically compiled |
| `Infrastructure/ExtensionRegistry.ts` | Reverse-order cleanup of registered extensions | DELETE-AFTER-V2-ENGINES: lifecycle managed by `ra_pipeline_destroy` |

---

## KEEP

Genuinely browser-specific code with no C++ equivalent that the v2 adapter will continue to require.

| File | Reason to keep |
|---|---|
| `packages/core/src/Infrastructure/OPFSStorage.ts` (440 LOC) | Browser Origin Private File System wrapper. C++ core has no browser storage access. The v2 adapter needs to place the downloaded WASM binary and model files somewhere persistent. This class provides `saveModel`, `loadModel`, `saveModelFromStream`, `loadModelFile`, LRU metadata — all via `navigator.storage.getDirectory()` which is unavailable in C++. |
| `packages/core/src/Infrastructure/LocalFileStorage.ts` (506 LOC) | File System Access API wrapper (user-chosen folder, IndexedDB handle persistence). Same reasoning: this is a browser UI concern not reachable from C++. |
| `packages/core/src/Infrastructure/ArchiveUtility.ts` (186 LOC) | tar.gz extractor using browser-native `DecompressionStream`. The file header comments (lines 4-18) explicitly explain why native `rac_extract_archive_native` (libarchive) cannot be used from the browser: separate WASM modules have isolated virtual filesystems. Even in v2 with a single WASM module, model archives still need to be extracted in JavaScript before handing bytes to the WASM FS. |
| `packages/core/src/Infrastructure/AudioCapture.ts` | `getUserMedia` + `AudioContext` + `ScriptProcessorNode` mic capture. C++ cannot call Web Audio API. Required by the v2 adapter to feed PCM chunks to `_ra_pipeline_feed_audio`. |
| `packages/core/src/Infrastructure/AudioPlayback.ts` | `AudioContext` + `AudioBufferSourceNode` for TTS audio playback. Required by the v2 adapter to play PCM frames from `ra_tts` events. |
| `packages/core/src/Infrastructure/AudioFileLoader.ts` | `AudioContext.decodeAudioData` + resampling. Browser utility for batch STT transcription from file. |
| `packages/core/src/Infrastructure/VideoCapture.ts` | `getUserMedia` (video), `OffscreenCanvas`, RGBA→RGB frame extraction for VLM. |
| `packages/core/src/Infrastructure/DeviceCapabilities.ts` | Detects WebGPU, SharedArrayBuffer, OPFS, WASM SIMD, device memory. Browser-environment detection; required by the v2 adapter to choose the correct WASM binary (CPU vs WebGPU). |
| `packages/core/src/Foundation/EventBus.ts` | TS event bus for UI → SDK communication within the browser page. |
| `packages/core/src/Foundation/SDKLogger.ts` | Browser console logging with log levels. |
| `packages/core/src/Foundation/ErrorTypes.ts` | `SDKError` class, `SDKErrorCode` enum mapping to `rac_error.h` ranges. |
| `packages/core/src/Foundation/StructOffsets.ts` | Interface types for struct offset maps. Survives as long as the v2 TS adapter uses `ccall`/`cwrap` to call C functions with raw struct pointers. Can be deleted once the adapter is fully proto3-based. |
| `packages/core/src/Foundation/WASMBridge.ts` | Only exports `AccelerationMode = 'webgpu' | 'cpu'`. Trivial but used by `DeviceCapabilities.ts`. |
| `packages/core/src/services/HTTPService.ts` | Fetch wrapper with auth headers. Needed for API calls that remain JS-side. |
| `packages/core/src/services/AnalyticsEmitter.ts` | TS-side analytics event forwarding. |
| `packages/core/src/types/` (all files) | `LLMTypes.ts`, `STTTypes.ts`, `TTSTypes.ts`, `VADTypes.ts`, `VLMTypes.ts`, `enums.ts`, `models.ts`, `index.ts`. Type definitions used by the adapter public API surface. |
| `packages/core/src/Public/Extensions/RunAnywhere+VoicePipeline.ts` | The live v1 voice orchestrator (STT→LLM→TTS) using `ExtensionPoint.requireProvider`. This is the class that the example app actually uses (`voice.ts` in the demo). In Phase 3 it gets replaced by the v2 adapter's `VoiceSession`, but until then it is the only working pipeline. |
| `packages/core/src/Public/Extensions/VoicePipelineTypes.ts` | Types for `VoicePipeline`. |
| `tsconfig.base.json`, `eslint.config.mjs`, `package.json` | Workspace tooling. |

---

## INSPECT

Files where the classification depends on decisions not yet made.

| File | Open question |
|---|---|
| `packages/core/src/Infrastructure/ModelFileInference.ts` | Does the v2 C++ model registry provide filename-to-category inference, or does the v2 TS adapter need to do it for the model-picker import flow? If the C++ registry infers type, delete. If not (likely for Phase 3), keep. |
| `packages/core/src/Public/RunAnywhere.ts` (351 LOC) | The v1 `RunAnywhere` singleton. The v2 adapter exports its own `RunAnywhere` object (`frontends/web/src/adapter/RunAnywhere.ts`). Decide whether v1's model management, local storage, file picker, and shutdown APIs are ported to v2 or dropped. |
| `packages/core/src/Infrastructure/ProviderTypes.ts` | `LLMProvider`, `STTProvider`, `TTSProvider` interfaces. These currently type the `VoicePipeline` dependency on `ExtensionPoint`. Once `VoicePipeline` is deleted (Phase 3), this file goes with it — unless the v2 adapter reuses the same interface shapes. |
| `wasm/scripts/setup-emsdk.sh` | emsdk setup is still needed by v2 (same version, 5.0.0). Could be moved to `scripts/` at the repo root so both builds share it, or duplicated. Currently lives in the wrong tree. |
| `packages/core/src/__tests__/types.test-d.ts` | Type-level test. Depends on which v1 types survive in the v2 adapter. |

---

## The `VoiceAgent` class that only throws

**Location:** `packages/core/src/Public/Extensions/RunAnywhere+VoiceAgent.ts`

**What it does:** Exports `VoiceAgentSession` (class) and `VoiceAgent` (factory object). Every callable surface throws identically:

```
SDKError.componentNotReady('VoiceAgent', 'No WASM backend registered — use a backend package')
```

Specifically:
- `VoiceAgent.create()` — line 137
- `VoiceAgentSession.loadModels()` — line 60
- `VoiceAgentSession.processVoiceTurn()` — line 70
- `VoiceAgentSession.transcribe()` — line 90
- `VoiceAgentSession.generateResponse()` — line 100
- `VoiceAgentSession.isReady` getter — returns `false`, line 78

**Consumer audit:** A full search of `examples/web/RunAnywhereAI/src/` finds zero calls to `VoiceAgent.create()` or `VoiceAgentSession`. The example app uses `VoicePipeline` (the live orchestrator). `VoiceAgent` and `VoiceAgentSession` are re-exported from `packages/core/src/index.ts` (lines 27-28) but never imported in any application code.

**Deletion plan:**
1. Remove `packages/core/src/Public/Extensions/RunAnywhere+VoiceAgent.ts`
2. Remove `packages/core/src/Public/Extensions/VoiceAgentTypes.ts`
3. Remove the two re-export lines from `packages/core/src/index.ts` (lines 27-28)
4. `PipelineState` is still needed by `VoicePipeline`; it is already independently re-exported from `VoicePipelineTypes.ts` / `RunAnywhere+VoicePipeline.ts` — no breakage.

**v2 replacement:** `frontends/web/src/adapter/RunAnywhere.ts` exposes `RunAnywhere.solution({ kind: 'voice-agent', config })` which calls `VoiceSession.create(config, opts)`. The session is backed by the C++ L5 VoiceAgent DAG pipeline compiled into the single v2 WASM binary.

---

## Infrastructure layer (ModelManager, OPFSStorage, ArchiveUtility, etc.)

### Redundant with C++ model registry — DELETE-AFTER-V2-ENGINES

| Class | Why redundant |
|---|---|
| `ModelManagerImpl` (`ModelManager.ts`) | TypeScript re-implementation of `rac_model_registry_*` C API. The v1 WASM CMakeLists.txt exports 20+ `_rac_model_registry_*` functions (lines 244-260). In v2, the C++ core owns model state; the TS adapter reads it via `_ra_build_info`/proto3 events. |
| `ModelRegistry` | In-memory catalog with `onChange` callbacks. v2 equivalent: C++ `core/model_registry/`. |
| `ModelDownloader` | Fetch orchestration, OPFS write, quota check, LRU eviction. In v2 the C++ core or a minimal v2 TS download helper replaces this. The 705-LOC implementation carries significant complexity (streaming download, per-key write locks, chunked OPFS write, quota eviction) that belongs in a single place. |
| `ModelLoaderTypes` (`LLMModelLoader`, `STTModelLoader`, `TTSModelLoader`, `VADModelLoader`) | The interface contract for manual backend registration. Eliminated by the static plugin registry. |
| `ExtensionPoint` | Dynamic provider lookup registry. Eliminated by static compilation. |
| `ExtensionRegistry` | Reverse-cleanup registry for extensions. Eliminated by `ra_pipeline_destroy`. |

### Genuinely browser-only — KEEP

| Class | Why browser-only |
|---|---|
| `OPFSStorage` | `navigator.storage.getDirectory()` is a browser API with no C++ equivalent. Needed to persist model files across page loads (WASM linear memory is volatile). |
| `LocalFileStorage` | `window.showDirectoryPicker()` + `indexedDB` handle persistence. Browser-only UI concern. |
| `ArchiveUtility` | `DecompressionStream('gzip')` is a browser API. The v1 CMakeLists.txt does export `_rac_extract_archive` (line 214) but that operates on Emscripten FS paths after a file is already in the WASM virtual filesystem. Extracting before writing to WASM FS requires this JS-side utility. |
| `AudioCapture` | `navigator.getUserMedia` + `AudioContext`. |
| `AudioPlayback` | `AudioContext.createBuffer`. |
| `DeviceCapabilities` | `navigator.gpu`, `crossOriginIsolated`, `navigator.storage`. |

---

## Opt-in backend flags + manual-registration ModelManager loaders

The v1 Web SDK requires three independent manual steps before any inference is possible. Each step is a silent footgun if omitted.

**Step 1 — build-time backend flags** (`wasm/scripts/build.sh` and `wasm/CMakeLists.txt`):
```bash
--llamacpp    → sets RAC_WASM_LLAMACPP=ON  (LLM)
--vlm         → sets RAC_WASM_VLM=ON       (VLM via mtmd)
--webgpu      → sets RAC_WASM_WEBGPU=ON    (WebGPU, separate binary)
--onnx        → sets RAC_WASM_ONNX=ON      (sherpa: STT/TTS/VAD)
--whispercpp  → sets RAC_WASM_WHISPERCPP=ON (whisper.cpp STT)
```
If a backend flag is omitted, its C functions are not exported. The TS wrapper checks `typeof m._rac_backend_llamacpp_register !== 'function'` at runtime (LlamaCppBridge.ts:~300) and throws a descriptive error — but only at the point of registration, not at startup.

**Step 2 — runtime registration call** (`LlamaCPP.register()`, `ONNX.register()`):
- `LlamaCppProvider.ts:36` calls `bridge.ensureLoaded()`, then loads offsets, then calls `ModelManager.setLLMLoader(TextGeneration)`, then `ExtensionPoint.registerBackend(...)`, then `ExtensionPoint.registerProvider('llm', TextGeneration)`.
- `ONNXProvider.ts` does the same for STT/TTS/VAD loaders.
- If the developer forgets `await LlamaCPP.register()`, all `ModelManager.loadModel()` calls throw `'No LLM loader registered.'` (ModelManager.ts:501).

**Step 3 — loader wiring** (done inside the provider but exposed as a footgun because the provider itself is optional):
- `ModelManager.setLLMLoader()`, `setSTTLoader()`, `setTTSLoader()`, `setVADLoader()` (ModelManager.ts lines 116-119) are `null` by default.
- Any call to `ModelManager.loadModel()` without prior registration throws immediately.

In v2 (`frontends/web/wasm/CMakeLists.txt:14-21`), all four engine plugins are linked statically at build time with no flags. The TS adapter calls `_ra_pipeline_create_from_solution()` on module init. There is no step 1, no step 2, no step 3.

---

## Pre-built WASM artifacts + build-web.sh

**Current state of WASM artifacts:** As of this audit, neither `packages/llamacpp/wasm/` nor `packages/onnx/wasm/sherpa/` exist on disk (confirmed by `ls` checks returning empty). The WASM files are always generated by running `scripts/build-web.sh`.

**v1 build pipeline** (`scripts/build-web.sh` → `wasm/scripts/build.sh` → `wasm/CMakeLists.txt`):
- Clones emsdk 5.0.0 into `sdk/runanywhere-web/emsdk/` via `wasm/scripts/setup-emsdk.sh`
- Invokes `emcmake cmake` + `make` inside `wasm/build/` or `wasm/build-webgpu/` (separate build directories per variant)
- Separately clones `sherpa-onnx v1.12.20` into `wasm/third_party/sherpa-onnx/` and builds it with its own Emscripten flags
- Post-build copies output to `packages/llamacpp/wasm/` and `packages/onnx/wasm/sherpa/`
- Then invokes `npm run build:ts` across all three workspaces

This is 596 LOC of bash orchestration (`scripts/build-web.sh`) + 200 LOC (`wasm/scripts/build.sh`) + 919 LOC (`wasm/CMakeLists.txt`) = ~1,715 LOC of build infrastructure.

**v2 build** (`frontends/web/wasm/CMakeLists.txt`, 37 LOC):
```bash
cmake --preset wasm-release
```
One command. Engines are statically linked. No separate sherpa build. Output: `runanywhere_v2_wasm.wasm` + `.js` glue.

**What goes away:**
- `sdk/runanywhere-web/scripts/build-web.sh`
- `sdk/runanywhere-web/wasm/scripts/build.sh`
- `sdk/runanywhere-web/wasm/scripts/build-sherpa-onnx.sh`
- `sdk/runanywhere-web/wasm/scripts/patch-sherpa-glue.js`
- `sdk/runanywhere-web/wasm/CMakeLists.txt`
- `sdk/runanywhere-web/wasm/src/wasm_exports.cpp`
- `sdk/runanywhere-web/wasm/platform/wasm_platform_shims.cpp`
- `sdk/runanywhere-web/scripts/package-sdk.sh` (three-package packing → one-package packing)
- `sdk/runanywhere-web/emsdk/` directory (if present after `--setup`) — still needed but should live at repo root, shared between v1 and v2

**emsdk fate:** emsdk version 5.0.0 is used by both v1 (`wasm/scripts/setup-emsdk.sh:25`) and v2 (implicitly, via the same `cmake --preset wasm-release`). The `emsdk/` directory inside `sdk/runanywhere-web/` is a side effect of running `--setup`. Once `sdk/runanywhere-web/` is deleted, emsdk must move to a repo-level location (e.g. `tools/emsdk/`) so v2 can continue to use it.

---

## Backwards-compat shims found

| Location | What it shims |
|---|---|
| `packages/core/src/Infrastructure/ModelManager.ts:33-34` | `export { ModelCategory, LLMFramework, ModelStatus, DownloadStage }` — re-exports enums from `types/enums.ts` at the `ModelManager` module path "so existing imports from `./Infrastructure/ModelManager` still work". Once `ModelManager` is deleted this re-export disappears too. |
| `packages/core/src/Infrastructure/ModelRegistry.ts:14` | `export { ModelCategory, LLMFramework, ModelStatus }` — same pattern, same reason. |
| `packages/core/src/Public/Extensions/RunAnywhere+VoiceAgent.ts:24` | Re-exports `PipelineState` from `VoiceAgentTypes`, which itself duplicates the `PipelineState` defined and properly exported by `VoicePipelineTypes.ts`. The duplicate exists to preserve the import path `RunAnywhere+VoiceAgent` for any consumer that imported from there before the pipeline split. No consumer currently imports from that path. |
| `packages/llamacpp/src/Foundation/LlamaCppBridge.ts:~300` | Runtime guard `if (typeof m._rac_backend_llamacpp_register !== 'function')` that detects a core-only WASM build (no llama.cpp backend compiled in) and throws a descriptive error rather than crashing with an Emscripten `Assertion failed`. This is a shim for the footgun described in the opt-in section — it exists because the build system allows producing a WASM binary with no backends, which is useless. Eliminated when the build always includes all engines. |
