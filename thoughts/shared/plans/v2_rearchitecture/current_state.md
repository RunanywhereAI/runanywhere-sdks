# C++ core — current state inventory

This is the ground-truth inventory of `sdk/runanywhere-commons/` as the
refactor begins. Every phase plan references this document for "before"
state.

Scope: the C++ core only. SDK frontends (Swift, Kotlin, Dart, TS, Web) and
example apps are **out of scope** for this refactor and remain unchanged
until a separate follow-up plan.

## Top-level layout

```text
sdk/runanywhere-commons/
├── include/rac/                         public C headers (+ C++ internals)
│   ├── core/                            — runtime types, error model, logger, registry, SDK state
│   ├── backends/                        — per-backend public headers (LLM/STT/TTS/VAD/VLM/embeddings/wakeword)
│   ├── features/                        — feature-service headers (llm, stt, tts, vad, vlm, rag, wakeword, voice_agent, diffusion, embeddings, platform)
│   ├── infrastructure/                  — download, extraction, file mgmt, model mgmt, network, device, telemetry, events, storage
│   ├── server/                          — OpenAI-compatible HTTP server
│   └── utils/
├── src/                                 matching implementation tree (same subdirs as include/)
├── scripts/                             per-platform build scripts (build-ios/android/linux/windows.sh)
├── tests/                               existing unit + integration tests
├── CMakeLists.txt                       top-level CMake, options drive which backends build
├── cmake/                               helpers (LoadVersions.cmake, etc.)
├── VERSION / VERSIONS                   version files read by build scripts
└── third_party/                         fetched at build time (llama.cpp, whisper.cpp, sherpa-onnx, usearch, onnxruntime, ggml)
```

## Core infrastructure (`src/core/`, `include/rac/core/`)

| File | LOC | Purpose | Status under refactor |
| --- | --- | --- | --- |
| `rac_core.h/.cpp` | 356 | `rac_module_register`, `rac_service_registry`, `rac_service_create`, `rac_service_register_provider` — the current compile-time backend registry | **REPLACED in Phase 1** by `rac/registry/` PluginRegistry |
| `rac_types.h` | — | Core POD types (IDs, handles, etc.) | **KEEP** |
| `rac_error.h/.cpp` | 387 | Error codes + string tables | **REPLACED in Phase 5** by proto3 `ErrorEvent` + `ra_status_str` |
| `rac_structured_error.h/.cpp` | 1029 | Structured error taxonomy | **REPLACED in Phase 5** |
| `rac_error_model.h/.cpp` | 66 | Error-to-model mapping | **REPLACED in Phase 5** |
| `rac_logger.h/.cpp` | 285 | spdlog wrapper | **KEEP** |
| `rac_events.h` | — | Event publisher interface | **REPLACED in Phase 5** (proto3 VoiceEvent) |
| `rac_sdk_state.h/sdk_state.cpp` | 448 | SDK lifecycle (init, shutdown) | **KEEP**, reshaped in Phase 7 |
| `rac_benchmark*.h/.cpp` | ~500 | Benchmark logging primitives | **KEEP** (referenced by tests) |
| `rac_platform_adapter.h`, `rac_platform_compat.h` | — | Platform abstraction | **KEEP** |
| `rac_memory.cpp`, `rac_time.cpp`, `rac_audio_utils.h` | 78+ | Small utilities | **KEEP** |
| `capabilities/` | — | Per-capability types (text, image, audio, etc.) | **KEEP** — referenced by features |

## Backends (`src/backends/`, `include/rac/backends/`)

Five backends present today. Each has its own register file that calls
`rac_service_register_provider`. Replaced in Phase 1 with a plugin vtable
entry (`ra_plugin_entry`) that reuses the same underlying integration code.

| Backend | Directory | Primary capability | Current registration | Refactor action |
| --- | --- | --- | --- | --- |
| **llama.cpp** | `backends/llamacpp/` | `generate_text`, `embed`, VLM (via mtmd) | `rac_backend_llamacpp_register.cpp` + `rac_backend_llamacpp_vlm_register.cpp` | Wrap as plugin in Phase 1. Existing `llamacpp_backend.cpp`, `rac_llm_llamacpp.cpp`, `rac_vlm_llamacpp.cpp` stay as implementation files. |
| **whisper.cpp** | `backends/whispercpp/` | `transcribe` (STT) | `rac_backend_whispercpp_register.cpp` | Wrap as plugin. |
| **sherpa-onnx** | `backends/onnx/` | `transcribe`, `synthesize`, `detect_voice`, `wake_word`, ONNX embeddings | `rac_backend_onnx_register.cpp` | Wrap as plugin. Multi-primitive plugin. |
| **MetalRT** | `backends/metalrt/` | LLM/STT/TTS/VLM on Apple Silicon M3+ | `rac_backend_metalrt_register.cpp` | Wrap as plugin. Chip-gate check (M3+ only) becomes `capability_check` in vtable. Current stub path under `backends/metalrt/stubs/` handled in Phase 8 cleanup. |
| **WhisperKit CoreML** | `backends/whisperkit_coreml/` | `transcribe` via CoreML | `rac_backend_whisperkit_coreml_register.cpp` | Wrap as plugin. iOS/macOS only. |

All 5 backends currently link statically into `rac_commons`. Phase 7
introduces dlopen/static dual-path so each backend becomes a separately-
loadable plugin on Android/macOS/Linux and stays statically linked on
iOS/WASM.

## Features — L3 primitives (`src/features/`)

| Feature | Files | LOC | Current shape | Refactor action |
| --- | --- | --- | --- | --- |
| **LLM service** | `llm/rac_llm_service.cpp`, `llm_component.cpp`, `streaming_metrics.cpp`, `structured_output.cpp`, `tool_calling.cpp`, `llm_analytics.cpp` | 4,978 | Callback-based: `rac_llm_generate(session, prompt, token_callback, user_data)` | **Phase 2**: stream-based API `Stream<Token> generate(prompt)`. `tool_calling` (1,950 LOC) and `structured_output` (504 LOC) logic retained as is. |
| **STT service** | `stt/stt_component.cpp`, `rac_stt_service*` | ~800 | `feed_audio` + `flush` + callback | **Phase 2**: `Stream<TranscriptChunk> transcribe(Stream<AudioFrame>)`. Partial + final chunks native. |
| **TTS service** | `tts/tts_component.cpp`, `rac_tts_service*` | ~700 | `synthesize(text) → PCM[]` one-shot | **Phase 2**: `Stream<AudioFrame> synthesize(Stream<Text>)` — sentence-chunked. |
| **VAD service** | `vad/energy_vad.cpp`, `vad_component.cpp` | ~400 | Silero + energy VAD, callback on event | **Phase 2**: `Stream<VADEvent>` with `voice_start`, `voice_end_of_utterance`, `barge_in`, `silence`. |
| **Embed service** | `embeddings/embeddings_component.cpp`, `rac_embeddings_service.cpp` | ~600 | Batch: `embed(text) → vec<float>` | **Phase 2 optional**: add streaming batch variant; single-embed keeps current API. |
| **VLM service** | `vlm/vlm_component.cpp`, `rac_vlm_service.cpp` | ~400 | Image + prompt → text (uses llama.cpp mtmd) | **Phase 2**: `Stream<Token> describe(Image, prompt)`. |
| **Wake word** | `wakeword/wakeword_service.cpp` | 88 | **Currently stub — returns detected=false always** (per cleanup audit line 210, 233, 477-498) | **Phase 1**: real sherpa-onnx KeywordSpotter wiring via ONNX plugin. Stub section removed in Phase 8. |
| **Diffusion** | `diffusion/diffusion_component.cpp`, `diffusion_json.cpp`, `diffusion_model_registry.cpp`, `rac_diffusion_service.cpp`, `rac_diffusion_tokenizer.cpp` | ~1,500 | Image generation | **Phase 2**: `Stream<Image>` progressive denoising steps. |
| **Platform** | `platform/rac_backend_platform_register.cpp`, `rac_diffusion_platform.cpp` | ~200 | iOS/Apple FM bridge | **KEEP** — already platform-specific |

## Voice Agent (`src/features/voice_agent/`)

**Current state**: `voice_agent.cpp` (~1,100 LOC per cleanup audit) is a
batch-sequential orchestrator. Pattern: receive full audio → run VAD → run
STT to completion → run LLM to completion → run TTS to completion → play.
No streaming between stages. No barge-in. No LLM→TTS token streaming.

**Refactor (Phase 3)**: Rewrite as streaming DAG:

```text
mic → vad(tee) → stt                         → llm  → sentence_detector → tts → audio_sink
          ↓
     vad.barge_in → barge_in_boundary
                     ↓
                     llm.cancel + sentence_queue.clear + playback_rb.drain
```

Port algorithms from existing out-of-tree reference projects (RCLI +
FastVoice — see `thoughts/shared/plans/v2_rearchitecture/` historical docs):
SentenceDetector, text_sanitizer, transactional barge-in.

## RAG (`src/features/rag/`)

**Current files**: `rag_backend.cpp` (518), `rag_chunker.cpp` (234),
`vector_store_usearch.cpp` (444), `rac_rag_pipeline.cpp`, `onnx_embedding_provider.cpp`,
`bm25_index.cpp`, `rac_rag_register.cpp`.

**Current retrieval**: Single-path — either BM25 or vector, selected by
config. USearch HNSW in `vector_store_usearch`. BM25 partial implementation.
No parallel fan-out. No RRF fusion. No neural reranker.

**Known BC shim** (from cleanup audit): `vector_store_usearch.h:38-44`
carries `chunk_id` / `similarity` alias fields explicitly labelled "kept
for bridge compatibility." Removed in Phase 8.

**Refactor (Phase 4)**:
- Replace single-path retrieval with parallel BM25 (one std::thread) +
  vector search (main thread) joined by Reciprocal Rank Fusion (k=60).
- Zero-alloc pre-allocated score buffers.
- Add neural reranker: `bge-reranker-v2-m3` cross-encoder on top-24 →
  top-6. Runs through LLM `embed` primitive.
- Document chunker stays; tighten to plain-text + HTML only; no
  `pdftotext` shell-out (not portable to iOS/Android).

## Infrastructure (`src/infrastructure/`)

All **KEEP** — these are cross-cutting concerns that the new architecture
doesn't rewrite. They do get reached through new APIs where relevant.

| Dir | Purpose | Notes |
| --- | --- | --- |
| `download/` | Chunked + resumable HTTP model downloader; checksum verification; download orchestrator | **KEEP** |
| `extraction/` | tar + zip extraction for downloaded model archives | **KEEP** |
| `file_management/` | File manager (paths, existence, atomic writes) | **KEEP** |
| `model_management/` | Model registry, LoRA registry, path resolver, model compatibility, model assignment | **KEEP** — referenced by every feature |
| `network/` | Auth, HTTP client, API endpoints | **KEEP** |
| `events/` | `event_publisher.cpp` — observability backbone | **KEEP** internals, but publishers migrate to proto3 event types in Phase 5 |
| `telemetry/` | Telemetry dispatcher | **KEEP** |
| `device/` | Device info, chip detection | **KEEP** — feeds into `rac/router/hardware_profile` in Phase 0 |
| `storage/` | Key-value storage | **KEEP** |
| `registry/` | Misc internal registry | **KEEP** |

## Server (`src/server/`, `include/rac/server/`)

| File | Purpose | Refactor action |
| --- | --- | --- |
| `http_server.cpp/.h` | OpenAI-compatible HTTP server | **KEEP**, re-internalize to call L3 primitives through plugin registry in Phase 1 |
| `openai_handler.cpp/.h` | /v1/chat/completions, /v1/embeddings routing | **KEEP**, same internal-API reshape |
| `openai_translation.cpp/.h` | OpenAI wire format ↔ internal types | **KEEP** |
| `json_utils.cpp/.h` | JSON helpers | **KEEP** |

## JNI (`src/jni/`, backends' `jni/` subfolders)

JNI bridges for Android consumption. Phase-neutral: these talk to the C
ABI from Java. They follow any change the C ABI makes (proto3 wire format
in Phase 5, plugin registry in Phase 1). Planned to be fully regenerated
later from the IDL, but the regeneration is **out of scope** for the C++
refactor — it's a separate per-frontend plan.

## Tests (`tests/`)

Existing tests are unit-level, targeted at individual backends and
features. Phase 0 adds a new test tree (`tests/core_tests/` for graph and
registry primitives; `tests/integration/` for e2e voice agent + RAG). ASan
+ UBSan + TSan enabled in Phase 6.

## CMake + build system

- Top-level `CMakeLists.txt` with `RAC_BUILD_*` options per backend.
- Per-platform build scripts (`build-ios.sh`, `build-android.sh`, etc.)
  in `scripts/`.
- Third-party fetched lazily via `scripts/{ios,android,linux,macos,windows}/download-*.sh`.

Additions across phases:
- **Phase 0**: `cmake/PluginSystem.cmake` (`rac_add_backend_plugin`,
  `rac_add_solution_plugin` functions); `cmake/Protobuf.cmake` (protoc
  codegen integration); `cmake/Sanitizers.cmake` (ASan/UBSan/TSan).
- **Phase 0**: vcpkg manifest `vcpkg.json` under commons for new deps
  (protobuf, gtest fallback, boost::asio where usable).
- **Phase 7**: Plugin build produces separate `libllamacpp_plugin.so` etc.
  on dlopen platforms, static `.a` on iOS/WASM.

## Summary totals

- ~70,000 LOC in commons today across ~300 files.
- ~9,400 LOC across the features being rewritten (LLM service, RAG,
  voice_agent).
- ~1,600 LOC marked `DELETE-NOW` by the cleanup audit (service_registry,
  wake-word stub, MetalRT stubs, BC shims).
- The rest is either `KEEP` (~20,000 LOC of infrastructure) or
  implementation files that get reached through a new API but don't need
  rewriting (backend integrations, OpenAI server, JNI bridges).

**Bottom line**: The refactor is narrow. It touches roughly a third of
commons. Every existing feature — LLM, STT, TTS, VLM, diffusion, RAG,
wake word, voice agent, model download, telemetry, OpenAI server, JNI —
survives.
