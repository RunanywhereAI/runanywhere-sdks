# RunAnywhere full-stack architectural refactor

> Single source of truth for this refactor.
> Scope: **commons + all five SDK frontends (Swift, Kotlin, Flutter,
> React Native, Web) + all example apps**. Delivered in one plan,
> executed strictly sequentially — commons first, frontends after.
> Working directory: `thoughts/shared/plans/v2_rearchitecture/`.
> Last updated: 2026-04-19.

---

## The one-sentence principle

**The C++ core already holds the real business logic; this refactor
makes it easier to extend, easier to reason about, and faster at
runtime — in place, without breaking any feature, without keeping
any deprecated API — and then every SDK frontend and example app
moves onto the new architecture in lock-step.**

---

## Why this refactor exists

Five architectural truths we want to enforce across `runanywhere-commons`:

1. **Streaming-first primitives.** Today the LLM service uses a token
   callback, the STT service uses a flush/result model, the TTS service
   returns a one-shot buffer, and the VoiceAgent glues them with a batch
   sequential loop. Result: first audio is bottlenecked on full LLM
   generation, no LLM→TTS token streaming, no barge-in. After the
   refactor every L3 primitive is a `Stream<T>` and the VoiceAgent is a
   streaming DAG; first audio target drops from seconds to tens of
   milliseconds.
2. **Plugins, not a compile-time switch.** Today
   `rac_service_register_provider` is called from five per-backend
   register files linked into one library. Adding a sixth backend means
   editing the core registry, the build, and every consumer. After the
   refactor each backend exports a single `ra_plugin_entry` vtable and
   the `PluginRegistry` + `EngineRouter` picks at runtime by primitive +
   model format + hardware.
3. **proto3 at the C ABI boundary.** Today every event/config/error type
   is a hand-written C struct that each SDK adapter hand-copies. After
   the refactor the C ABI carries length-prefixed proto3 bytes; SDK
   adapters (in a later plan) decode with their native proto3 runtime.
   This eliminates the type drift already shipping (e.g. AudioFormat: 5
   cases in Swift, 7 in TS).
4. **Transactional barge-in.** Today there is no barge-in path. After
   the refactor barge-in is a single atomic flag + LLM cancel + sentence
   queue clear + TTS ring-buffer drain, under one mutex, bounded at
   ≤50ms.
5. **Zero-copy within the graph.** Today some audio and token paths copy
   unnecessarily. After the refactor `StreamEdge<T>` and `RingBuffer<T>`
   move PCM frames and token buffers by reference between L3 operators;
   the proto3 surface only appears at the C ABI edge.

**What we are not doing.** We are not deleting features. Every LLM, STT,
TTS, VLM, diffusion, RAG, wake word, voice agent, model download,
extraction, telemetry, OpenAI HTTP server, JNI path survives. We are
changing how they talk to each other, not what they do.

**We do not maintain backwards compatibility.** Any rac_* API can be
renamed, reshaped, or removed. Callers inside commons are rewritten in
the same PR. Callers in SDK frontends are handled in the subsequent
per-frontend plan.

---

## Target directory layout — inside `sdk/runanywhere-commons/`

```text
sdk/runanywhere-commons/
├── idl/                              NEW — proto3 schemas (voice_events, pipeline, solutions)
├── include/rac/
│   ├── abi/                          NEW — stable C ABI (plugin.h, primitives.h, pipeline.h, version.h)
│   ├── graph/                        NEW — L4 primitives (ring_buffer, memory_pool, stream_edge,
│   │                                        cancel_token, pipeline_node, graph_scheduler)
│   ├── registry/                     NEW — PluginRegistry, PluginLoader<VTABLE>
│   ├── router/                       NEW — EngineRouter, HardwareProfile
│   ├── backends/                     existing (header surface stays, details get plugin wrapper)
│   ├── core/                         existing, shrinks in phases 1 + 5 + 8
│   ├── features/                     existing, voice_agent + rag rewritten
│   ├── infrastructure/               existing — unchanged
│   ├── server/                       existing — internal reshape in phase 1
│   └── utils/                        existing — unchanged
├── src/                              mirror of include/ plus .cpp files
│   ├── abi/                          NEW — version.c, status.c
│   ├── graph/                        NEW — graph_scheduler.cpp
│   ├── registry/                     NEW — plugin_registry.cpp
│   ├── router/                       NEW — hardware_profile.cpp, engine_router.cpp
│   ├── gen/                          NEW — proto3 codegen output (*.pb.cc / *.pb.h)
│   ├── backends/                     each backend adds a <name>_plugin.cpp in Phase 1
│   ├── core/                         shrinks
│   ├── features/
│   │   ├── voice_agent/              rewritten in Phase 3 (streaming DAG)
│   │   ├── rag/                      rewritten in Phase 4 (hybrid retriever + reranker)
│   │   └── ...                       others migrated to Stream<T> in Phase 2
│   ├── infrastructure/               unchanged
│   ├── server/                       unchanged API; internals swap to plugin registry
│   └── jni/                          follows C ABI changes, minimal diff
├── tests/
│   ├── core_tests/                   NEW — graph, registry, router primitives (gtest)
│   ├── integration/                  NEW — e2e voice agent, e2e rag, per-primitive streaming
│   └── …existing…                    KEEP
├── cmake/
│   ├── LoadVersions.cmake            existing
│   ├── PluginSystem.cmake            NEW — rac_add_backend_plugin(), rac_add_solution_plugin()
│   ├── Protobuf.cmake                NEW — protoc codegen helper
│   └── Sanitizers.cmake              NEW — ASan / UBSan / TSan wiring
├── scripts/                          existing build scripts, adjusted for new CMake targets
├── vcpkg.json                        NEW — manages protobuf + gtest fallback
├── CMakeLists.txt                    modified across phases (add_subdirectory for new dirs)
└── VERSION / VERSIONS                existing
```

No new top-level directories at the **repo** root. Everything lives under
`sdk/runanywhere-commons/` as promised.

---

## The six layers, in place

```text
L6  SDK frontends (Swift / Kotlin / Dart / TS / Web)          OUT OF SCOPE for this refactor
      ↑ stable C ABI (proto3 messages over length-prefixed bytes)
L5  Solutions — voice_agent, rag, wake_word, diffusion, OpenAI HTTP server
      (lives under src/features/* and src/server/)
L4  Graph runtime — StreamEdge, RingBuffer, MemoryPool, CancelToken,
      GraphScheduler  (lives under src/graph/)
L3  Primitives — LLM service, STT, TTS, VAD, embed, rerank, tokenize,
      window  (lives under src/features/{llm,stt,tts,vad,embeddings}/)
L2  Engines — llama.cpp, whisper.cpp, sherpa-onnx, MetalRT, WhisperKit
      (lives under src/backends/*, each with a <backend>_plugin.cpp)
L1  Runtimes — CoreML, Metal, CUDA, ONNX EP, OpenVINO (future — not part
      of this refactor)
```

Each layer only calls the layer immediately below. L4 owns threading and
cancellation. L5 is a DAG constructed from L3 operators.

---

## Binding decisions made up front

These are the decisions I'm taking without further consultation. If any
are wrong, flag before a phase starts; none need changing mid-phase.

| Decision | Choice | Reasoning |
| --- | --- | --- |
| C ABI name prefix | `ra_` for new symbols; deprecate `rac_` | The existing `rac_` namespace shipped with the old service registry. Using a fresh prefix lets us delete the old symbols cleanly without collision. |
| C++ standard | C++20 | Requires `std::jthread`, `std::span`, concepts, coroutines-ready. Confirmed buildable on AppleClang 15+, GCC 12+, NDK r26+, MSVC 17.6+, emscripten-3.1.50+. |
| IDL format | proto3 | Mature codegen for every target language (swift-protobuf, Wire, protobuf.dart, ts-proto, protobuf-python). See `decisions/idl_choice.md`. |
| Graph channel backing | `std::deque<T>` under mutex for arbitrary `T`; lock-free SPSC ring for `T=float` (audio) | Covers both the audio hot path (zero-alloc, wait-free) and the generic token/event path. |
| Plugin symbol per backend | `ra_plugin_entry_<name>` (unique per plugin) via the `RA_PLUGIN_ENTRY_DECL(name)` macro | Avoids duplicate-symbol linker errors when multiple plugins are statically linked on iOS/WASM. |
| Plugin loading | `dlopen` with `RTLD_NOW \| RTLD_LOCAL` on Android/macOS/Linux; static `RA_STATIC_PLUGIN_REGISTER` on iOS/WASM | iOS App Store §3.3.2 prohibits runtime code loading. |
| Async runtime | `std::jthread` on macOS/Linux/Android/Windows; GCD (`DispatchQueue`) on iOS; asyncify on WASM | Compile-time `#if defined(__APPLE__) && TARGET_OS_IPHONE` selection. iOS `std::thread` risks background-task kills. |
| Sanitizers | ASan + UBSan in the default Debug build; TSan in a separate Debug+TSan build | ASan and TSan are mutually exclusive. Both run in CI. |
| Version scheme | Separate `RA_ABI_VERSION` and `RA_PLUGIN_API_VERSION`, both MAJOR.MINOR.PATCH | Lets us evolve the public C ABI and the plugin vtable independently. |
| RAG vector store | USearch (already vendored) as default; pgvector reserved as optional remote backend (not implemented here) | In-process HNSW, benchmarked at sub-millisecond at 5K chunks. pgvector requires a Postgres server — not mobile-viable. |
| Barge-in model | Transactional cancel boundary with one mutex covering atomic-flag set + LLM cancel + sentence-queue clear + playback-ring drain | Prevents the "cancel arrives after tokens are already in TTS queue" race. |
| Remove old APIs | Yes — no compatibility shims | Per user directive: "do not think about backwards compatibility." |

---

## 15-phase roadmap

Each phase has its own detailed file under `phases/`. Phases are **strictly
sequential** — each one depends on the artifacts of the previous one.

### Commons track (C++ core) — Phases 0–8

| # | Phase | What it delivers | Behaviour change? |
| - | ----- | ---------------- | ----------------- |
| 0 | `phase_0_foundation.md` | ABI headers, graph primitives, plugin registry scaffolding, engine router, proto3 IDL files, CMake + sanitizer setup, primitive unit tests | No |
| 1 | `phase_1_plugin_backends.md` | Every backend exposes `ra_plugin_entry`; PluginRegistry + EngineRouter operational; old `rac_service_*` removed | API break: engine lookup path |
| 2 | `phase_2_streaming_l3_primitives.md` | LLM/STT/TTS/VAD/embed services expose `Stream<T>` APIs; callback APIs removed | API break: every L3 primitive |
| 3 | `phase_3_voice_agent_dag.md` | Voice agent rewritten as a streaming DAG with transactional barge-in; first-audio target ≤80ms | Yes: streaming voice |
| 4 | `phase_4_rag_hybrid.md` | RAG pipeline replaced with parallel BM25 + HNSW + RRF + neural reranker; sub-5ms retrieval at 10K chunks | Yes: better retrieval |
| 5 | `phase_5_proto3_abi.md` | Every C ABI event/config/error carries proto3 bytes; struct-based types removed | API break: entire C ABI surface |
| 6 | `phase_6_sanitizer_ci.md` | ASan + UBSan clean in Debug; TSan job green; integration test coverage | No (tightens quality bars) |
| 7 | `phase_7_plugin_loading.md` | dlopen on dlopen platforms, static on iOS/WASM; backends become shippable plugin binaries | No runtime change, deployment shape changes |
| 8 | `phase_8_cleanup.md` | Deprecated APIs, stub shims, BC aliases all removed; directory layout finalised | No |

### Frontend track (SDKs + example apps) — Phases 9–14

Only starts after Phase 8 is green and the commons C ABI is stable.
The five frontend SDK phases can be worked on with some overlap
since they only share the commons C ABI (not each other); the plan
documents them sequentially but an aggressive team could split them.

| # | Phase | What it delivers |
| - | ----- | ---------------- |
| 9  | `phase_9_swift_sdk.md`         | Swift SDK on new C ABI via XCFramework + swift-protobuf; iOS example app rewritten; Swift 6 strict concurrency |
| 10 | `phase_10_kotlin_sdk.md`       | Kotlin KMP SDK on new C ABI via JNI + Wire; Android example app + IntelliJ plugin demo rewritten; `runanywhere-android/` absorbed into KMP |
| 11 | `phase_11_flutter_sdk.md`      | Flutter SDK on new C ABI via Dart FFI + protoc_plugin; Flutter example app rewritten |
| 12 | `phase_12_react_native_sdk.md` | React Native SDK via TurboModules + JSI, delegating to the Swift + Kotlin SDKs; RN example app rewritten |
| 13 | `phase_13_web_sdk.md`          | Web SDK on new WASM build (CPU + optional WebGPU variants); Web example app rewritten |
| 14 | `phase_14_release_and_infra.md` | Coordinated `v2.0.0` release of all six artifacts; top-level CI consolidation; pre-commit hooks; MIGRATION guide; root README |

**No phase runs in parallel with the next within the commons track.**
Each phase leaves the repo in a shippable state before the next
starts.

**Phases 2 and 3 are the ones with the highest user-visible impact
in commons** — real streaming voice with barge-in. Phase 4 is the
highest user-visible impact for RAG. Phases 9–13 make the new
architecture reachable from every supported language. After Phase 14
the refactor is complete.

---

## What survives unchanged

The refactor deliberately leaves these alone. No rewrite, no rename, no
API churn:

- Every integration inside a backend (`llamacpp_backend.cpp`,
  `whispercpp_backend.cpp`, `onnx_backend.cpp`, MetalRT wrappers,
  WhisperKit wrapper) — only a thin plugin adapter is added.
- `src/infrastructure/` in full — download orchestrator, extraction,
  file manager, model registry, LoRA registry, network, device,
  telemetry, storage.
- `src/server/http_server.cpp` + `openai_handler.cpp` — the OpenAI HTTP
  server's external surface. Its internal call sites move to the
  plugin registry in Phase 1.
- `src/features/diffusion/*` and `src/features/vlm/*` — these follow the
  same callback→stream migration in Phase 2 but are not otherwise
  rewritten.
- JNI bridges — follow C ABI changes, otherwise unchanged.
- CMake options for building per-platform variants — renamed where
  needed, same semantics.
- Third-party downloads + extraction (scripts, VERSIONS pinning) — keep
  as is.

---

## What gets deleted

All of the following are removed across Phases 1, 5, and 8. Together they
are ~1,600 LOC identified in the cleanup audit.

| File / fragment | Why removed | Phase |
| --- | --- | --- |
| `src/core/rac_core.cpp` + `include/rac/core/rac_core.h` — `rac_module_register`, `rac_service_registry`, `rac_service_create`, `rac_service_register_provider` | Superseded by `rac/registry/plugin_registry.h` | Phase 1 (deprecated), Phase 8 (removed) |
| `src/features/wakeword/wakeword_service.cpp:210,233,477-498` — stub inference path that always returns `detected=false` | Replaced by real sherpa-onnx KWS in the ONNX plugin | Phase 1 |
| `src/backends/metalrt/stubs/*` — stub shim used when MetalRT SDK is absent | MetalRT plugin is optional at build time; absence means "don't register the plugin", no shim needed | Phase 8 |
| `include/rac/features/rag/vector_store_usearch.h:38-44` — `chunk_id` / `similarity` alias fields marked "kept for bridge compatibility" | BC shim from a previous refactor; no remaining readers | Phase 4 (during RAG rewrite) |
| All `rac_service_register_provider(...)` call sites across 8 backend register files | Plugin registration replaces this | Phase 1 |
| `rac_error.cpp` + `rac_structured_error.cpp` structured-error taxonomy | Replaced by proto3 `ErrorEvent` | Phase 5 |
| `rac_events.h` struct event union | Replaced by proto3 `VoiceEvent` | Phase 5 |
| Every `typedef struct rac_*_event { … }` in public headers | Replaced by proto3 messages | Phase 5 |

---

## Acceptance criteria for the whole refactor

Complete when all of the following hold simultaneously on `main`:

1. `cmake --build` passes on macOS, Linux, Android (arm64-v8a + x86_64),
   iOS, and WASM presets.
2. `ctest` passes, including:
   - Every test in the existing `tests/` tree (no regressions).
   - New unit tests for `rac/graph/*`, `rac/registry/*`, `rac/router/*`.
   - New integration tests for voice agent (streaming + barge-in),
     RAG (hybrid retrieval + reranker), plugin registry load/unload.
3. ASan + UBSan green on Debug across macOS and Linux; TSan green on
   macOS Debug+TSan; no suppressions.
4. Every backend is loadable through PluginRegistry (static or dlopen).
   `rac_service_*` is entirely gone.
5. Every L3 primitive exposes `Stream<T>`; no callback-based APIs remain.
6. Voice agent streaming benchmark: first audio ≤80ms on M-series MacBook
   with a 4B-parameter LLM on GGUF.
7. RAG benchmark: top-6 hybrid retrieval in ≤5ms over 10,000 chunks.
8. C ABI surface is proto3-only; no `typedef struct rac_*_event` remains
   in public headers.
9. `cleanup/` audit shows zero items remaining in the DELETE-NOW bucket.

---

## Out of scope for this plan

Short list — almost everything is in scope now that frontends and
example apps are included:

- **External consumers outside this monorepo.** None exist, per user
  confirmation. Breaking the C ABI is acceptable.
- **Playground/** (if present as a scratch workspace) — unaffected
  unless it ends up linking against the new APIs.
- **New features not listed above.** This refactor only reshapes
  existing functionality; adding a brand-new primitive
  (e.g. speaker-diarization as a first-class streaming primitive) is
  a follow-up.

---

## How to consume this plan

1. Read `current_state.md` to understand what exists today.
2. Read `testing_strategy.md` — the validation discipline every
   phase inherits. This is a refactor, so feature preservation is
   mandatory and tests live in the same phase as the code.
3. Read `decisions/*.md` if you need rationale for a specific choice.
4. Open the phase doc you're executing — each phase is self-contained
   and lists prerequisites, deliverables, step-by-step implementation,
   acceptance criteria, and a **Validation checkpoint** section that
   spells out what must be green before moving on.
5. Do not skip phases — each builds on the previous. Phase 4 assumes
   Phase 2 streaming primitives exist. Phase 5 assumes Phase 1 plugin
   registry exists.
6. **Mark a phase complete only when its acceptance criteria AND its
   validation checkpoint are green.** Major phase checkpoints
   additionally require a second-engineer sign-off on the feature
   preservation matrix.

---

## Decision escalation

Flag to the user **before** starting a phase only if:

- The phase introduces a runtime dependency not already listed in the
  binding decisions table.
- The phase would require a change to a public C ABI function that a
  frontend (Swift/Kotlin/Dart/TS/Web) currently reads.
- A backend integration (llama.cpp, sherpa-onnx, etc.) requires an
  upstream feature newer than currently pinned in VERSIONS.

Otherwise proceed per the phase doc.
