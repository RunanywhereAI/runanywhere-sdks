# runanywhere-commons — v1/v2 cleanup audit

## Summary

- **DELETE-NOW (7 groups, ~1,600 LOC):** The v1 service-vtable dispatch layer
  (`rac_core.h` module/service registry API), the `wakeword_service.cpp` stub that
  always returns `detected=false`, and the MetalRT silent stubs are all superseded
  by v2 constructs that already exist in `core/` and `engines/`.
- **DELETE-AFTER-V2-ENGINES (6 groups, ~9,900 LOC):** The real ML backends
  (llamacpp, onnx/sherpa, whispercpp) plus their JNI wrappers, the v1 RAG
  pipeline, and the v1 voice-agent orchestrator contain real working inference
  code that the v2 engine plugins have not yet replaced (all three return
  `RA_ERR_RUNTIME_UNAVAILABLE` today).
- **KEEP (10 groups, ~9,700 LOC):** Infrastructure not replicated in v2:
  download/extraction/file management, model-management metadata, telemetry,
  auth/network, energy-VAD, tool-calling, structured-output, and the
  platform backend (Apple Foundation Models / System TTS).
- **INSPECT (3 items):** Diffusion service, image utils, and the OpenAI-compatible
  HTTP server have no v2 counterpart and no clear disposition in the plan.
- One confirmed v1-internal BC shim: the `chunk_id`/`similarity` alias fields on
  `SearchResult` in `vector_store_usearch.h:38-44`, kept for JNI/RN bridge compat.

---

## DELETE-NOW (7 groups, ~1,600 LOC)

| Path | Lines | Reason |
|------|-------|--------|
| `sdk/runanywhere-commons/src/core/rac_core.cpp` (lines 1-356, **module/service registry section only** — `rac_module_register`, `rac_service_register_provider`, `rac_service_create`) | ~180 | v2 owns discovery via `core/registry/plugin_registry.cpp` + `ra_plugin.h`; the rac_* capability-routing vtable is fully superseded |
| `sdk/runanywhere-commons/include/rac/core/rac_core.h` (lines 110-295: `MODULE REGISTRATION API` and `SERVICE PROVIDER API` blocks) | ~185 | Same: `core/registry/plugin_registry.h` + `core/abi/ra_plugin.h` replace both APIs entirely |
| `sdk/runanywhere-commons/src/infrastructure/registry/service_registry.cpp` | 272 | Implements the v1 priority-based `canHandle` provider dispatch; replaced by `core/registry/plugin_registry.cpp` + `PluginLoader<VTABLE>` template |
| `sdk/runanywhere-commons/src/infrastructure/registry/module_registry.cpp` | 247 | Module capability list (`rac_module_register`/`rac_module_list`); superseded by `ra_engine_metadata_t` in `core/abi/ra_plugin.h` |
| `sdk/runanywhere-commons/src/features/wakeword/wakeword_service.cpp` (lines 460-498: inference section) | 39 | `engines/wakeword/wakeword_plugin.cpp` comment at line 6 explicitly states this stub is replaced; the whole inference section is `TODO: Process through ONNX backend` with `detected = false` hardcoded at line 465 |
| `sdk/runanywhere-commons/src/backends/metalrt/stubs/metalrt_c_api_stub.c` | 145 | Pure no-op stub (file header lines 10-11 say so); only exists because `METALRT_ROOT` is absent. v2 will use `runtimes/coreml/` (Phase 3). No runtime path ever calls these |
| `sdk/runanywhere-commons/src/core/sdk_state.cpp` | 448 | Tracks v1 SDK lifecycle states (`RAC_LIFECYCLE_STATE_*`); v2 has no public lifecycle state machines (MASTER_PLAN.md design principle 7: "Handles exist or they don't") |

---

## DELETE-AFTER-V2-ENGINES (6 groups, ~9,900 LOC)

| Path | Lines | Replaced by | Blocked on |
|------|-------|-------------|------------|
| `sdk/runanywhere-commons/src/backends/llamacpp/` (all 5 `.cpp` files: `llamacpp_backend.cpp`, `rac_llm_llamacpp.cpp`, `rac_backend_llamacpp_register.cpp`, `rac_backend_llamacpp_vlm_register.cpp`, `rac_vlm_llamacpp.cpp`) | 2,542 | `engines/llamacpp/llamacpp_plugin.cpp` — today stubs `RA_ERR_RUNTIME_UNAVAILABLE` at generate; real decode loop is Phase 0 Agent C | Phase 0 Agent C: `llamacpp_engine.cpp` with real `llama_load_model_from_file` + `ra_generate` token loop |
| `sdk/runanywhere-commons/src/backends/llamacpp/jni/rac_backend_llamacpp_jni.cpp` | 303 | `frontends/kotlin/src/main/cpp/jni_bridge.cpp` (Phase 2) via v2 C ABI | Phase 2 Kotlin adapter (Sub-task 2A) |
| `sdk/runanywhere-commons/src/backends/onnx/` (all 4 `.cpp` files: `onnx_backend.cpp`, `rac_onnx.cpp`, `rac_backend_onnx_register.cpp`, `wakeword_onnx.cpp`) + `src/backends/whispercpp/` (all 3: `whispercpp_backend.cpp`, `rac_stt_whispercpp.cpp`, `rac_backend_whispercpp_register.cpp`) | 3,367 | `engines/sherpa/sherpa_plugin.cpp` — all three STT/TTS/VAD entry points return `RA_ERR_RUNTIME_UNAVAILABLE`; real sherpa-onnx C API calls are Phase 0 Agent D | Phase 0 Agent D: `sherpa_engine.cpp` with real `SherpaOnnxCreate*` calls and 20ms streaming STT |
| `sdk/runanywhere-commons/src/backends/onnx/jni/rac_backend_onnx_jni.cpp`, `src/backends/whispercpp/jni/rac_backend_whispercpp_jni.cpp` | 236 | `frontends/kotlin/src/main/cpp/jni_bridge.cpp` (Phase 2) | Phase 2 Kotlin adapter |
| `sdk/runanywhere-commons/src/features/voice_agent/voice_agent.cpp` | 1,103 | `core/voice_pipeline/voice_pipeline.cpp` — fully re-implemented with `StreamEdge<T>`, `CancelToken`, and transactional barge-in; v1 voice agent is a sequential batch loop (STT→LLM→TTS one-shot), no streaming | v2 VoiceAgentPipeline depends on engines/llamacpp and engines/sherpa returning real audio (Phase 0 gate) |
| `sdk/runanywhere-commons/src/features/rag/` (all 9 files: `rac_rag_pipeline.cpp`, `bm25_index.cpp/.h`, `vector_store_usearch.cpp/.h`, `onnx_embedding_provider.cpp/.h`, `rac_onnx_embeddings_register.cpp`, `rag_backend.cpp/.h`, `rag_chunker.cpp/.h`) + `src/features/rag/jni/rac_rag_jni.cpp` | 2,350 | `solutions/rag/bm25_index.cpp`, `solutions/rag/hybrid_retriever.cpp` (Phase 2 Sub-task 2B) — v1 RAG uses USearch + ONNX embeddings; v2 adds neural reranker and BM25+HNSW RRF hybrid | Phase 2 RAG solution (Sub-task 2B) fully wired with `ra_embed` from llamacpp engine |

---

## KEEP (10 groups, ~9,700 LOC)

| Path | Lines | Reason |
|------|-------|--------|
| `sdk/runanywhere-commons/src/infrastructure/download/download_manager.cpp` + `download_orchestrator.cpp` + `include/rac/infrastructure/download/` | 1,496 | v2 has only a skeleton `core/model_registry/model_downloader.cpp` (delegates to `curl`); v1 owns the real download orchestration, progress tracking, retry, and platform-callback delegation that the Swift/Kotlin SDKs depend on today |
| `sdk/runanywhere-commons/src/infrastructure/extraction/rac_extraction.cpp` + `src/infrastructure/file_management/file_manager.cpp` + headers | 935 | ZIP extraction and file-manager services have no v2 equivalent; called by current iOS/Android SDKs after model download |
| `sdk/runanywhere-commons/src/infrastructure/model_management/` (all 6 `.cpp`: `model_registry.cpp`, `model_paths.cpp`, `model_strategy.cpp`, `model_compatibility.cpp`, `model_assignment.cpp`, `lora_registry.cpp`) + headers | 1,582 | v2 `core/model_registry/model_registry.cpp` covers only `upsert`/`find`/`for_capability`; v1 has LoRA registry, backend-strategy dispatch, compatibility checking, and path resolution used by active iOS/Android SDKs |
| `sdk/runanywhere-commons/src/infrastructure/network/auth_manager.cpp` + `http_client.cpp` + `endpoints.cpp` + `environment.cpp` + `development_config.cpp` + headers | 856 | Auth token lifecycle and platform-delegated HTTP executor are not in v2 (v2 design explicitly delegates networking to SDK layer, per `rac_core.h:67` comment); still needed by Kotlin and Swift SDKs |
| `sdk/runanywhere-commons/src/infrastructure/telemetry/telemetry_manager.cpp` + `telemetry_json.cpp` + `telemetry_types.cpp` + headers | 818 | Not replicated in v2; telemetry pipeline (event queuing, batching, modality grouping) is v1-only concern and active in production |
| `sdk/runanywhere-commons/src/infrastructure/device/rac_device_manager.cpp` + `src/infrastructure/storage/storage_analyzer.cpp` + headers | 370 | Device profiling and storage analysis are used by the Swift SDK today; not in v2 scope (v2 has `core/router/hardware_profile.cpp` but that is for engine routing, not SDK-layer device registration) |
| `sdk/runanywhere-commons/src/features/vad/energy_vad.cpp` + header | 906 | Pure-C++ energy-based VAD (no ONNX dependency); used as fallback when sherpa-onnx VAD is unavailable. v2 `engines/sherpa` only covers ONNX VAD — this fallback has no v2 replacement |
| `sdk/runanywhere-commons/src/features/llm/tool_calling.cpp` + `structured_output.cpp` + headers | 2,454 | Tool-call parsing (two format variants) and JSON structured-output extraction are not in v2 (`engines/llamacpp` vtable has no tool-call or grammar slot). The MASTER_PLAN is silent on this capability |
| `sdk/runanywhere-commons/src/features/platform/` (all `.cpp`: `rac_llm_platform.cpp`, `rac_tts_platform.cpp`, `rac_diffusion_platform.cpp`, `rac_backend_platform_register.cpp`) + headers | ~750 | Apple Foundation Models LLM + System TTS backend. Swift callbacks are registered at runtime; no v2 equivalent planned (v2 Phase 3 L1 runtimes cover CoreML/MLX tensors, not the high-level Foundation Models API) |
| `sdk/runanywhere-commons/src/backends/whisperkit_coreml/` + header | ~115 | Swift-callback bridge for WhisperKit Apple Neural Engine STT; no v2 equivalent; active on iOS |

---

## INSPECT (3 items)

1. **`sdk/runanywhere-commons/src/features/diffusion/`** (all 4 `.cpp`: `diffusion_component.cpp`, `diffusion_model_registry.cpp`, `rac_diffusion_service.cpp`, `rac_diffusion_tokenizer.cpp`) — ~1,300 LOC.
   *Open question:* Diffusion (image generation) is not mentioned anywhere in the MASTER_PLAN, `implementation_plan.md`, or the v2 engine plugin list. Is this capability being carried forward into v2 at all, or is it abandoned? It is conditionally excluded on Android (`rac_core.cpp:21-23` `#if !defined(RAC_PLATFORM_ANDROID)`) and depends on a platform callback path through `rac_diffusion_platform.cpp`. Need a product decision before assigning a bucket.

2. **`sdk/runanywhere-commons/src/utils/rac_image_utils.cpp`** — 523 LOC.
   *Open question:* Image pre/post-processing for VLM (vision-language model) inference. VLM is listed as a v1 capability (`rac_vlm_service.h`, `rac_vlm_llamacpp.cpp`) but the v2 MASTER_PLAN's primitive list at the L3 table (`generate_text`, `transcribe`, `synthesize`, `detect_voice`, `embed`, `rerank`, `tokenize`, `window`) does not include a vision primitive. Does VLM survive into v2, and if so, which v2 engine plugin implements it?

3. **`sdk/runanywhere-commons/src/server/`** (4 files: `http_server.cpp`, `openai_handler.cpp`, `openai_translation.cpp`, `json_utils.cpp`) — 1,308 LOC. Built only with `RAC_BUILD_SERVER=ON` (CMakeLists.txt:45, default OFF).
   *Open question:* This OpenAI-compatible HTTP server has no v2 counterpart in `core/`, `engines/`, or `solutions/`. It is mentioned in zero v2 planning documents. Is it a developer tool that should move to `tools/`, become a v2 solution, or simply be dropped?

---

## Backwards-compatibility shims found

### v1-internal shim: `SearchResult::chunk_id` / `SearchResult::similarity` aliases

**File:** `sdk/runanywhere-commons/src/features/rag/vector_store_usearch.h:38-44`

```cpp
struct SearchResult {
    std::string id;           // Primary chunk identifier
    std::string chunk_id;     // Alias for id (kept for bridge compatibility)
    float score = 0.0f;       // Primary similarity score
    float similarity = 0.0f;  // Alias for score (kept for bridge compatibility)
};
```

These two alias fields exist solely to keep old JNI and React Native bridge code working that was written against the earlier field names. The comment at line 35 says "kept for bridge compatibility". When this whole RAG module is deleted post-v2 (DELETE-AFTER-V2-ENGINES bucket), the shim goes with it. No separate action needed.

---

## Risks if we delete DELETE-NOW today

1. **`rac_module_register` / `rac_service_create` removal:** Every existing Swift SDK call to `rac_service_register_provider()` would fail at link time. The Swift platform adapter (`rac_backend_platform_register.cpp`) calls `rac_service_register_provider` and `rac_module_register` at startup (visible in `rac_backend_platform_register.cpp:37-100`). Removing the registry API without simultaneously porting the platform backend registration to v2 `PluginRegistry::register_static()` would break all current iOS/macOS SDK users.

2. **`wakeword_service.cpp` inference section removal:** The Android SDK's JNI bridge calls `rac_wakeword_process_audio()` directly. Removing the stub (which at least returns `RAC_SUCCESS` with `detected=false`) would turn those calls into null-pointer crashes. The v2 `engines/wakeword/wakeword_plugin.cpp` is not yet wired into the Kotlin JNI bridge.

3. **`sdk_state.cpp` removal:** `runanywhere_commons_jni.cpp` at line 44 includes `rac_core.h` and calls lifecycle state functions that originate in `sdk_state.cpp`. The entire 4,836-LOC JNI bridge would need to be audited for transitive dependencies before removing SDK state.

4. **MetalRT stubs removal:** Safe to remove today — the CMakeLists.txt default is `RAC_BACKEND_METALRT=OFF` and the wrapper layer (`rac_llm_metalrt.cpp:1-10`) already guards with `RAC_METALRT_ENGINE_AVAILABLE` before calling any stub symbol. No runtime path reaches these stubs in the default build.
