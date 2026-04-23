# Comprehensive Status — `feat/v2-architecture`

_Single deep-dive reference document. Audited by 6 parallel
exploration agents covering native C++/engines, Swift, Kotlin,
Flutter, React Native + Web, sample apps + build/CI/tests, and
cross-cutting drift. Updated: 2026-04-22._

> If you only have 5 minutes, read sections **0** + **5** + **6**.

---

## 0. Executive summary

- **Branch state**: `feat/v2-architecture`, **114 commits ahead of `main`**, NOT merged, NOT released. ~93k insertions / ~18k deletions / 543 files vs main.
- **Versions**: ALL packages match main's baseline (`0.19.13` / Kotlin `0.1.5-SNAPSHOT`). The earlier 3.x/4.0 markers were premature; reset.
- **Architectural state**: 9 of 10 in-repo GAPs are functionally done. Voice agent rewritten across all 5 SDKs. C ABI introduced (`RAC_PLUGIN_API_VERSION = 3u`); legacy `service_registry.cpp` deleted.
- **Build**: macos-debug + linux-debug green in CI. `test_proto_event_dispatch` 11/11, `test_graph_primitives` 13/13.
- **25 known bugs** spanning 4 P0 (release blockers), 8 P1 (high-value engineering), 13 P2-P4 (architectural / docs / QA / deferred).
- **Headline gotchas not in any prior status doc**:
  1. GAP 06 doc claim "all 9 engines on the macro" is **false** — llamacpp is still hand-rolled.
  2. **Flutter v4 is a facade**, not a refactor — the 2,620-LOC god-class still does the work; v4 just forwards.
  3. **Web SDK voice-agent is a stub** — all methods `throw componentNotReady`.
  4. **RN sample has a compile break**: calls `RunAnywhere.getVoiceAgentHandle()` which doesn't exist on the TS facade (only on the native Nitro spec).

---

## 1. Current architecture

### 1.1 Repo layout (post-branch)

```
runanywhere-sdks-main/
├── cmake/               ← NEW: shared CMake helpers
│   ├── plugins.cmake    ← rac_add_engine_plugin() macro + rac_force_load()
│   ├── platform.cmake
│   ├── protobuf.cmake
│   └── sanitizers.cmake
├── engines/             ← NEW: per-engine plugins (was sdk/runanywhere-commons/src/backends/)
│   ├── llamacpp/        ← LLM (+ VLM via mtmd) — STILL hand-rolled CMake
│   ├── onnx/            ← STT/TTS/VAD + RAG embeddings — uses macro
│   ├── whispercpp/      ← STT (FetchContent whisper.cpp) — uses macro
│   ├── whisperkit_coreml/ ← STT via Apple Neural Engine — uses macro
│   ├── metalrt/         ← LLM/STT/TTS/VLM Apple-only — OBJECT library variant
│   ├── sherpa/          ← STT scaffold (NULL ops) — uses macro
│   ├── genie/           ← Qualcomm QNN LLM scaffold — uses macro
│   ├── diffusion-coreml/ ← Apple diffusion scaffold — uses macro
│   └── CMakeLists.txt
├── idl/                 ← NEW: 7 .proto files + 9 codegen scripts
│   ├── voice_events.proto
│   ├── voice_agent_service.proto
│   ├── llm_service.proto
│   ├── download_service.proto
│   ├── model_types.proto, pipeline.proto, solutions.proto
│   └── codegen/generate_{cpp,swift,kotlin,dart,ts,python,rn_streams,web_streams,all}.sh
├── tests/               ← NEW: cross-SDK harnesses
│   ├── streaming/parity_test.cpp + per-SDK consumers
│   ├── streaming/perf_bench/ (perf_producer + per-SDK consumers + Python aggregator)
│   └── streaming/cancel_parity/ (cancel_producer + per-SDK consumers + Python aggregator)
├── sdk/                 ← (existed) per-language SDKs
│   ├── runanywhere-commons/  ← C++ core (rac_* C ABI)
│   ├── runanywhere-swift/
│   ├── runanywhere-kotlin/
│   ├── runanywhere-flutter/  ← 4 packages (runanywhere + 3 backends)
│   ├── runanywhere-react-native/  ← 3 packages (core + llamacpp + onnx)
│   └── runanywhere-web/      ← 3 packages (core + llamacpp + onnx)
├── examples/            ← (existed) sample apps for each platform
├── scripts/             ← Build + release operator scripts
├── .github/workflows/   ← CI (pr-build.yml + idl-drift-check.yml + release.yml)
└── docs/                ← Consolidated to canonical 4 docs + archive
```

### 1.2 Architecture stack

```
┌────────────────────────────────────────────────────────────────────┐
│ Sample apps (iOS / Android / Flutter / RN)                         │
│   Voice ViewModels → VoiceAgentStreamAdapter(handle).stream()      │
│   Other features  → SDK static or v4 instance API                  │
└────────────────────────┬───────────────────────────────────────────┘
                         │
┌────────────────────────▼───────────────────────────────────────────┐
│ 5 SDK frontends (Swift / Kotlin / Dart / RN / Web)                 │
│   Public API + thin adapters + ts-proto/Wire/protoc/swift-protobuf │
│   Voice via VoiceAgentStreamAdapter wrapping rac_voice_agent_set_proto_callback │
└────────────────────────┬───────────────────────────────────────────┘
                         │ FFI / JNI / Nitro / Emscripten WASM
┌────────────────────────▼───────────────────────────────────────────┐
│ runanywhere-commons (C++20)                                        │
│   ra_*  C++ API · rac_*  C ABI (RAC_PLUGIN_API_VERSION = 3u)       │
│   plugin registry (rac_plugin_*) · engine router (rac_plugin_route)│
│   voice agent (rac_voice_agent_*) · proto event bus                │
│   DAG primitives (CancelToken / RingBuffer / StreamEdge)           │
│   ~5,300 LOC JNI bridge for Kotlin                                 │
└────────────────────────┬───────────────────────────────────────────┘
                         │ rac_engine_vtable_t per plugin
┌────────────────────────▼───────────────────────────────────────────┐
│ Engine plugins (rac_backend_<name> static / runanywhere_<name>.so) │
│   llamacpp (LLM+VLM) · onnx (STT+TTS+VAD+embed) · whispercpp (STT) │
│   whisperkit_coreml (Apple ANE) · metalrt (Apple) · 3 stubs        │
└────────────────────────────────────────────────────────────────────┘
```

### 1.3 Voice agent flow (the headline architectural change)

```
                                  Sample app voice ViewModel
                                            │
                                            ▼
          ┌─────────────────────────────────────────────────────────┐
          │ VoiceAgentStreamAdapter(handle)  per-language idiom:    │
          │   Swift:  AsyncStream<RAVoiceEvent>                     │
          │   Kotlin: Flow<VoiceEvent>                              │
          │   Dart:   Stream<VoiceEvent>                            │
          │   RN/Web: AsyncIterable<VoiceEvent>                     │
          └────────────────────┬────────────────────────────────────┘
                               │ wraps
                               ▼
              rac_voice_agent_set_proto_callback(handle, cb, user)
                               │
                               ▼
              C++ voice agent  →  Serializes VoiceEvent proto bytes
                                  per-event into the registered cb
                                  (one callback slot per handle)
```

---

## 2. What's been done

### 2.1 By area (LOC delta from main)

| Area | New | Deleted | Notes |
|---|---|---|---|
| `sdk/` (all 5 SDKs) | ~78,961 | ~29,079 | Includes generated proto + backend reorg renames |
| `engines/` (NEW) | ~13,323 | 0 | Engines moved out of `sdk/runanywhere-commons/src/backends/` (renames double-count above) |
| `tests/` (NEW) | ~2,858 | 0 | parity / perf_bench / cancel_parity harnesses |
| `cmake/` (NEW) | ~368 | 0 | plugins.cmake + helpers |
| `scripts/` | ~492 | 0 | Build + release operator scripts |
| `docs/` | ~5,538 | ~63 | Consolidated to 4 canonical + archive |
| `idl/` (NEW) | ~1,504 | 0 | 7 proto files + codegen scripts |
| `examples/` | ~1,223 | ~297 | Sample app voice migrations |

### 2.2 Top deleted files (architectural removals)

1. `CppBridgeServices.kt` — 1,285 LOC (Kotlin legacy bridge)
2. `CppBridgeStrategy.kt` — 1,204 LOC (Kotlin legacy bridge)
3. Per-SDK `build-*.sh` scripts — 5,003 LOC across 6 files (replaced by root CMake/Gradle)
4. `VoiceSessionHandle.ts` (RN) — 626 LOC
5. `service_registry.cpp` (commons) — 272 LOC (legacy plugin registry)

### 2.3 Top new files (large)

1. `solutions.pb.h` — 4,674 LOC (generated proto)
2. `voice_events.pb.h` — 4,425 LOC (generated proto)
3. `voice_events.pb.cc` — 4,192 LOC
4. `solutions.pb.cc` — 4,120 LOC
5. Plus per-language proto codegen across 5 SDKs

### 2.4 GAP closure (10 specs in repo; GAP 10 spec was never written)

| GAP | Status | Done by |
|---|---|---|
| 01 IDL + codegen | DONE | branch `5ad4ebaa` … `5ce9048a` (proto + codegen + drift CI) |
| 02 Unified engine plugin ABI | DONE | branch `e3ad196b`, `7dc2cbdc`, `b55d41ff` |
| 03 Dynamic plugin loading | DONE (test depth deferred) | branch `c6aa7109`, `7e93d0fe` |
| 04 Engine router + HW profile | DONE (device E2E deferred) | branch `f2efc81d`, `b5a14b3d` |
| 05 DAG runtime | DONE (skeleton only) | branch `8e1c3ebb` (CancelToken/RingBuffer/StreamEdge + 13 tests); scheduler deferred per spec L63-64 |
| 06 Engines top-level reorg | **PARTIAL** (claim is wrong) | Macro shipped + 8/9 engines use it. **llamacpp still hand-rolled** despite docs claiming otherwise. |
| 07 Single root CMake | DONE | branch `67463b0b`, `b1d523bc`, `3d2674cc` |
| 08 Frontend duplication delete | MOSTLY DONE | Kotlin orchestration deleted; Flutter god-class wrapped (not refactored); download orchestration deferred |
| 09 Streaming consistency | DONE | branch `ba3ecef1`, `99715ccd`, `dda0fd52`, `dcef1c67` |
| 11 Legacy cleanup | DONE | branch `7dc2cbdc`, `b55d41ff`, voice-session deletes across SDKs |

---

## 3. Per-SDK current state

### 3.1 C++ commons + engines (`sdk/runanywhere-commons/` + `engines/`)

| Aspect | State |
|---|---|
| C ABI version | `RAC_PLUGIN_API_VERSION = 3u` (didn't exist on main) |
| Plugin registry | `rac_plugin_*` API; `service_registry.cpp` deleted |
| Engine vtable | `rac_engine_vtable_t` with 8 primitive slots + 10 reserved |
| Voice agent C ABI | `rac_voice_agent_*` + proto-byte callback (`rac_voice_event_abi.h`, `RAC_ABI_VERSION = 2u`) |
| DAG primitives | `CancelToken`, `RingBuffer<T>`, `StreamEdge<T>` (header-only) + 13 unit tests |
| Generated proto code | 14 files / ~31,252 LOC under `src/generated/proto/` |
| JNI bridge | `runanywhere_commons_jni.cpp` ~5,300 LOC, ~174 JNIEXPORT entry points (LLM/STT/TTS/VAD/VLM/VoiceAgent/Auth/Download/Events/etc.) |
| 9 engines | 4 stubs use macro; llamacpp hand-rolled; onnx/whispercpp/whisperkit_coreml use macro; metalrt = OBJECT-library variant |
| Build presets | macos-{debug,release}, ios-{device,simulator}, android-{arm64,armv7,x86_64}, wasm, linux-{debug,release}, linux-asan |
| Tests | 12 always-built + 8 backend-gated. `macos-release` has `RAC_BUILD_TESTS=OFF` by default; `macos-debug` enables them |

### 3.2 Swift SDK (`sdk/runanywhere-swift/`)

| Aspect | State |
|---|---|
| Public entry | `public enum RunAnywhere` in `Sources/RunAnywhere/Public/RunAnywhere.swift` (~497 LOC) |
| Voice adapter | `Sources/RunAnywhere/Adapters/VoiceAgentStreamAdapter.swift` returns `AsyncStream<RAVoiceEvent>` |
| Bridge layer | 28 `CppBridge+X.swift` files mapping each rac_* C ABI |
| Generated proto | 7 `.pb.swift` files (compiled); 3 `.grpc.swift` excluded via `Package.swift` |
| Mirror headers | `CRACommons/include/` (87 entries); `RAC_PLUGIN_API_VERSION = 3u` matches commons |
| Public extensions | 28 files / ~8,484 LOC under `Public/Extensions/` (LLM, STT, TTS, VLM, VAD, RAG, Storage, Models, etc.) |
| `LiveTranscriptionSession` | 312 LOC (advanced live STT) |
| Deletions confirmed | `VoiceSessionHandle`, `VoiceSessionEvent`, `RunAnywhere+VoiceSession.swift` — only comment-only mentions remain |
| xcframeworks | `sdk/runanywhere-swift/Binaries/` does NOT exist locally; `useLocalNatives = false` requires GitHub release artifacts that match `sdkVersion` |
| Sample app | iOS `VoiceAgentViewModel.swift` migrated to `CppBridge.VoiceAgent.shared.getHandle()` + `VoiceAgentStreamAdapter(handle:).stream()` ✓ |

### 3.3 Kotlin SDK (`sdk/runanywhere-kotlin/`)

| Aspect | State |
|---|---|
| Public entry | `RunAnywhere` object + 11 `RunAnywhere+X.jvmAndroid.kt` extensions |
| Voice adapter | `adapters/VoiceAgentStreamAdapter.kt` returns `Flow<VoiceEvent>` |
| Voice handle | `CppBridgeVoiceAgent.kt` (87 LOC) wraps 4 JNI thunks added on this branch |
| JNI declarations | `RunAnywhereBridge.kt` — 152 `external fun` declarations |
| CppBridge family | 25 `CppBridge*.kt` files; largest are Download (1485), Platform (1461), Events (1451), TTS (1384), VAD (1350), LLM (1350), Device (1236) |
| Generated proto | 56 Wire-generated files / ~7,990 LOC under `commonMain/.../generated/` |
| KMP source sets | commonMain (~25,400 LOC), jvmAndroidMain (~25,200), jvmMain (~1,030), androidMain (~2,100), jvmTest (~135) |
| Build | KMP plugin + Wire (committed generated, no Gradle plugin); `resolvedVersion` fallback `0.1.5-SNAPSHOT` |
| Sample app | Android `VoiceAssistantViewModel.kt` uses `CppBridgeVoiceAgent.getHandle()` + `VoiceAgentStreamAdapter(handle).stream()` ✓ |

### 3.4 Flutter SDK (`sdk/runanywhere-flutter/`)

| Aspect | State |
|---|---|
| 4 packages | `runanywhere` (core, 4 capability packages) + `runanywhere_llamacpp`, `runanywhere_onnx`, `runanywhere_genie` |
| Public entry | `class RunAnywhere` (LEGACY) — class-level `@Deprecated` annotation; **2,620 LOC body** (not refactored, just wrapped) |
| v4 facade | `class RunAnywhereSDK` (NEW) at `lib/public/runanywhere_v4.dart` — 109 LOC; lazy capability getters delegate to legacy `RunAnywhere` static methods |
| 7 capability classes | 22-86 LOC each (RunAnywhereLLM/STT/TTS/VLM/Voice/Models/Downloads). Each forwards to legacy static. **Net effect: facade only, not a refactor** |
| Voice adapter | `lib/adapters/voice_agent_stream_adapter.dart` returns `Stream<VoiceEvent>` |
| Voice handle | `DartBridgeVoiceAgent.shared.getHandle()` lazy-allocates with shared LLM/STT/TTS/VAD handles |
| FFI bridge | 32 `dart_bridge*.dart` files in `lib/native/` |
| Generated proto | 28 files / ~5,658 LOC under `lib/generated/` |
| Sample app | Mixed — `model_manager.dart` + `chat_interface_view.dart` use v4 instance API; rest still use legacy `RunAnywhere.X` static |
| Backend plugins | All 3 (llamacpp/onnx/genie) still `import 'package:runanywhere/runanywhere.dart'` and call deprecated `RunAnywhere` — will break when static is deleted |

### 3.5 React Native SDK (`sdk/runanywhere-react-native/`)

| Aspect | State |
|---|---|
| 3 packages | `core`, `llamacpp`, `onnx` (Yarn 3 workspace) |
| Public entry | `RunAnywhere` object in `packages/core/src/Public/RunAnywhere.ts` (~771 LOC) |
| Voice adapter | `packages/core/src/Adapters/VoiceAgentStreamAdapter.ts` returns `AsyncIterable<VoiceEvent>` |
| Native bridge | Nitro Modules (JSI-based zero-copy); 3 Nitro specs: `RunAnywhereCore`, `VoiceAgent`, `RunAnywhereDeviceInfo` |
| C++ HybridObjects | `HybridRunAnywhereCore.cpp` (~3.1k LOC), `HybridVoiceAgent.cpp` (~131 LOC) |
| Voice handle | Native: `getVoiceAgentHandle(): Promise<number>` in Nitro spec + C++ impl returns `reinterpret_cast<uintptr_t>(handle)` as `double` |
| **🐞 BUG**: TS facade missing `getVoiceAgentHandle()` | Sample tries `RunAnywhere.getVoiceAgentHandle()` → COMPILE BREAK (must use `requireNativeModule()` directly) |
| Generated proto | 11 ts-proto files + Nitrogen output |
| Sample app | `VoiceAssistantScreen.tsx` migrated to `VoiceAgentStreamAdapter` + `VoiceEvent` proto ✓ (BUT calls missing `getVoiceAgentHandle`) |

### 3.6 Web SDK (`sdk/runanywhere-web/`)

| Aspect | State |
|---|---|
| 3 packages | `core`, `llamacpp`, `onnx` |
| Public entry | `RunAnywhere` in `packages/core/src/Public/RunAnywhere.ts` (~352 LOC) |
| Voice adapter | `packages/core/src/Adapters/VoiceAgentStreamAdapter.ts` returns `AsyncIterable<VoiceEvent>` |
| **🐞 BUG**: VoiceAgent extension is a STUB | `Public/Extensions/RunAnywhere+VoiceAgent.ts` lines 54-137 — every method `throws componentNotReady` |
| WASM build | `wasm/CMakeLists.txt` with extensive `RAC_EXPORTED_FUNCTIONS` list including `_rac_voice_agent_set_proto_callback` |
| WASM artifacts | NOT committed; `packages/llamacpp/wasm/` empty; require `build-core-wasm.sh` to populate |
| Sample app | `examples/web/RunAnywhereAI/src/views/voice.ts` does NOT use `VoiceAgentStreamAdapter` — uses `VoicePipeline` instead. **Web is NOT on the same voice path as RN/iOS/Android/Flutter** |

### 3.7 Sample apps (`examples/`)

| App | Voice migration | Other features |
|---|---|---|
| iOS | DONE — `VoiceAgentStreamAdapter` ✓ | Most stable |
| Android | DONE — `VoiceAgentStreamAdapter` ✓ | Most stable |
| Flutter | DONE for voice; mixed for everything else (model_manager + chat on v4 instance, rest still on legacy `RunAnywhere.X`) | Will compile + run |
| React Native | DONE — adapter wired BUT calls missing `getVoiceAgentHandle()` | Compile break per known bug |
| Web | NOT migrated — uses `VoicePipeline` (different code path) | Functional but inconsistent with other 4 SDKs |

### 3.8 Tests

| Test | Where | Status |
|---|---|---|
| `test_proto_event_dispatch` | `sdk/runanywhere-commons/tests/` | 11/11 passing on macos-debug |
| `test_graph_primitives` | `sdk/runanywhere-commons/tests/` | 13/13 passing on macos-debug |
| `test_engine_vtable`, `test_engine_router`, `test_static_registration`, `test_legacy_coexistence`, `test_hardware_profile`, `test_llm_thinking`, `test_core`, `test_extraction`, `test_download_orchestrator`, `rac_benchmark_tests` | Always-built (when `RAC_BUILD_TESTS=ON`) | Build green; pass status not verified |
| `test_plugin_loader*` (3 tests) | Conditional: `NOT RAC_STATIC_PLUGINS` | iOS/wasm skip these |
| `test_plugin_entry_llamacpp`, `test_plugin_entry_onnx` | Backend-gated | Built if respective backend ON |
| `test_vad`, `test_stt`, `test_tts`, `test_wakeword`, `test_llm`, `test_voice_agent` | Backend-gated (ONNX / LlamaCPP / both) | Built when backends ON |
| `parity_test_cpp_check` | `tests/streaming/` | CTest registered; second `parity_test_cpp_produce` mentioned in comments but NOT registered |
| `perf_producer` (cross-SDK p50 latency) | `tests/streaming/perf_bench/` | Builds clean; per-SDK consumers exist (Swift/Kotlin/Dart/RN/Web) but NOT wired into CI |
| `cancel_producer` (5-SDK cancel parity) | `tests/streaming/cancel_parity/` | Builds clean; per-SDK consumers exist but NOT wired into CI |
| CI test execution | `pr-build.yml` | Runs ctest only on macos-debug + linux-debug + linux-asan. NO Swift / Kotlin / Flutter / RN / Web test execution in CI |

### 3.9 Build / CI

| Item | State |
|---|---|
| Root CMake | `CMakeLists.txt` orchestrates entire repo via `add_subdirectory(sdk/runanywhere-commons)` + `add_subdirectory(engines)` + conditional `add_subdirectory(tests)` |
| Presets (`CMakePresets.json`) | 11 configure presets: macos-{debug,release}, ios-{device,simulator}, android-{arm64,armv7,x86_64}, wasm, linux-{debug,release}, linux-asan |
| `RAC_BUILD_TESTS` | OFF by default in `macos-release`; ON in `macos-debug` |
| `RAC_BACKEND_*` flags | LLAMACPP/ONNX/RAG default ON; WHISPERCPP default OFF; WHISPERKIT_COREML/METALRT default ON on Apple |
| NDK pin | Root `gradle.properties` sets `racNdkVersion=27.0.12077973`, `racFlutterNdkVersion=25.2.9519653` |
| GitHub Actions | `pr-build.yml` (11 jobs), `idl-drift-check.yml`, `release.yml` (tag-based), `auto-tag.yml`, `secret-scan.yml` |
| **🐞 Doc bug**: `ci-drift-check.yml` referenced in docs | Actual file is `idl-drift-check.yml` |
| Release scripts | `scripts/release-swift-binaries.sh` (operator), `build-core-{xcframework,android,wasm}.sh`, `sync-checksums.sh`, `validate-artifact.sh`, `sync-versions.sh` |

---

## 4. Bug inventory (25 total)

### 4.1 P0 — Release blockers (4)

| # | Severity | Bug | File / Evidence |
|---|---|---|---|
| B1 | P0 | **GAP 06 doc claim is wrong**: `docs/GAP_STATUS.md` says "All 9 engines on `rac_add_engine_plugin()`"; reality is **8/9** — `engines/llamacpp/CMakeLists.txt` lines 204-214 still hand-rolls `add_library(rac_backend_llamacpp ...)` | `engines/llamacpp/CMakeLists.txt:204-214` |
| B2 | P0 | **ONNX `RAG_DIR` resolves to non-existent path** — `engines/onnx/CMakeLists.txt` line 234 sets `RAG_DIR = ${CMAKE_CURRENT_SOURCE_DIR}/../../features/rag` which evaluates to `engines/onnx/../../features/rag` (= `features/rag` at repo root). Doesn't exist. The `if(EXISTS …) list(APPEND …)` block silently SKIPS `onnx_embedding_provider.cpp`. RAG-on-ONNX never compiled | `engines/onnx/CMakeLists.txt:231-244` |
| B3 | P0 | **ONNX `g_onnx_*_ops` linkage hazard** — `g_onnx_stt_ops`, `g_onnx_tts_ops`, `g_onnx_vad_ops` defined inside anonymous namespace (internal linkage) but `rac_plugin_entry_onnx.cpp` declares them with `extern "C"`. Works for STATIC archives (deferred resolution); would FAIL for SHARED build | `engines/onnx/rac_backend_onnx_register.cpp:39-162` + `engines/onnx/rac_plugin_entry_onnx.cpp:23-25` |
| B4 | P0 | **RN sample compile break** — `examples/react-native/RunAnywhereAI/src/screens/VoiceAssistantScreen.tsx:284` calls `RunAnywhere.getVoiceAgentHandle()` but that method doesn't exist on `RunAnywhere` TS facade (only on the native `RunAnywhereCore` Nitro spec). Sample requires either patching the facade or using `requireNativeModule().getVoiceAgentHandle()` | `examples/react-native/RunAnywhereAI/src/screens/VoiceAssistantScreen.tsx:284` |

### 4.2 P1 — High-value engineering (8)

| # | Severity | Bug |
|---|---|---|
| B5 | P1 | **Web `VoiceAgent` is a stub** — `Public/Extensions/RunAnywhere+VoiceAgent.ts:54-137` — all substantive methods `throw componentNotReady`. Web has WASM exports for `_rac_voice_agent_*` but no working high-level voice-agent session. Web sample uses `VoicePipeline` instead |
| B6 | P1 | **Flutter v4 is a facade, not a refactor** — `RunAnywhereSDK.instance.{capability}` calls forward to the deprecated 2,620-LOC `RunAnywhere` static class. The god-class problem is unchanged. v4 is a deprecation layer, not the architectural split GAP 08 #4 called for |
| B7 | P1 | **Web sample app voice path inconsistent** — `examples/web/RunAnywhereAI/src/views/voice.ts` uses `VoicePipeline` from the Web SDK; not `VoiceAgentStreamAdapter`. Other 4 sample apps (iOS/Android/Flutter/RN) all use the adapter. Web is on a different code path |
| B8 | P1 | **Swift xcframework absent** — `sdk/runanywhere-swift/Binaries/` doesn't exist; `useLocalNatives = false` (line 43 of `Package.swift`); checksums in `binaryTargets()` reference v0.19.13 GitHub release artifacts. External SPM consumers can build only with `useLocalNatives = true` after running `scripts/release-swift-binaries.sh` |
| B9 | P1 | **Flutter backend plugins import deprecated class** — `runanywhere_llamacpp/lib/llamacpp.dart`, `runanywhere_onnx/lib/onnx.dart`, `runanywhere_genie/lib/genie.dart` all `import 'package:runanywhere/runanywhere.dart'` and call deprecated `RunAnywhere`. Will break when static class is deleted |
| B10 | P1 | **Flutter sample split-brain** — `lib/app/runanywhere_ai_app.dart`, `lib/features/models/*`, `lib/features/settings/*`, `lib/features/vision/*`, `lib/features/structured_output/*`, `lib/features/voice/{speech_to_text,text_to_speech}_view.dart` still use `RunAnywhere.X` (deprecated). Only `model_manager.dart` + `chat_interface_view.dart` migrated to v4 |
| B11 | P1 | **`runanywhere_commons_jni.cpp` has many TODOs** — multiple "TODO: Implement callback registration" markers (lines 1316, 1795, 1969, 2113); "TODO: Write result to file" (~1902). Indicates partial JNI surface implementation |
| B12 | P1 | **Kotlin `CppBridge*.kt` files have many native registration TODOs** — VAD, TTS, STT, Storage all have "TODO: Call native registration/unregistration" markers (e.g. `CppBridgeVAD.kt:443, 1156`). Stub register/unregister callbacks |

### 4.3 P2 — Architectural / multi-month (4)

| # | Severity | Bug |
|---|---|---|
| B13 | P2 | **Kotlin GAP 08 #3 download orchestration** — Cannot resolve without choosing a commons HTTP client (libcurl/cpr/platform-native). `CppBridgeDownload.kt` (1,485 LOC) is the Android HTTP executor; commons download manager delegates HTTP back to platform. See `docs/v3_2_kotlin_download_blocker.md` |
| B14 | P2 | **Wakeword service is largely TODO/stub** — `sdk/runanywhere-commons/src/features/wakeword/wakeword_service.cpp` has multiple TODO stubs: destroy backend, load via backend, ONNX/VAD/wakeword inference, model info arrays (lines 164, 207, 229, 286, 411, 463, 473) |
| B15 | P2 | **HybridRunAnywhereCore.cpp tool-call thunks TODO** — RN tool-calling delegates to commons but `HybridRunAnywhereCore.cpp` has TODO for `rac_tool_call_*` symbols (lines 2918, 2936, etc.). Means tool-calling on RN is incomplete |
| B16 | P2 | **GAP 05 DAG scheduler / PipelineNode / MemoryPool deferred** — Per spec L63-64: "build when 2nd pipeline needs them". Skeleton primitives shipped; full DAG runtime waits for first consumer beyond voice agent |

### 4.4 P3 — Documentation / drift (8)

| # | Severity | Bug |
|---|---|---|
| B17 | P3 | **Doc-vs-CI workflow filename mismatch** — `docs/GAP_STATUS.md` GAP 01 summary says `ci-drift-check.yml`; actual file is `.github/workflows/idl-drift-check.yml` |
| B18 | P3 | **HISTORY.md "missing rac_stt_whispercpp.h" claim is stale** — header DOES exist at `sdk/runanywhere-commons/include/rac/backends/rac_stt_whispercpp.h`. The actual issue is include-path resolution (`CRACommons.h` does `#include "rac_stt_whispercpp.h"` without the `rac/backends/` prefix; resolves only because `CMakeLists.txt` adds extra `-I rac/backends`) |
| B19 | P3 | **iOS sample `VoiceAgentViewModel.swift` has stale doc comments** — comment block at lines 381-388 still describes deprecated `startVoiceSession` / `VoiceSessionHandle` despite implementation using `VoiceAgentStreamAdapter` |
| B20 | P3 | **Flutter / Android sample READMEs out of sync** — `examples/flutter/RunAnywhereAI/README.md` and `examples/android/RunAnywhereAI/README.md` still document `startVoiceSession` / `VoiceSessionEvent` / `processVoice` as primary APIs |
| B21 | P3 | **Swift adapter docstring references non-existent API** — `Adapters/VoiceAgentStreamAdapter.swift` lines 12-14 says "use `RunAnywhere.voiceAgent.stream()`" but `RunAnywhere.voiceAgent` doesn't exist as a public namespace |
| B22 | P3 | **`tests/streaming/CMakeLists.txt` comments claim 2 ctests but only 1 registered** — `parity_test_cpp_produce` mentioned in comments; only `parity_test_cpp_check` actually registered as ctest |
| B23 | P3 | **`tests/streaming/README.md` still labels per-language parity as "Scaffold (Wave C ship)"** — docs out of sync with shipped per-language harnesses |
| B24 | P3 | **`idl-drift-check.yml` workflow doesn't run on push to `feat/v2-architecture` branch** — only on `main` (line 19). Drift on the branch only catches PR diffs |

### 4.5 P4 — QA effort / out of engineering scope (1 group)

| # | Severity | Bug |
|---|---|---|
| B25 | P4 | **QA backlog**: GAP 03 real-model GGUF E2E + valgrind under CI; GAP 04 iOS17 / ANE device E2E; GAP 08 #9 sample-app E2E (Detox/Maestro/XCUITest/Espresso); GAP 08 #10 real-device behavioral parity verification. These were always out of engineering scope; need a separate QA workstream |

### 4.6 Pre-built xcframework cache caveat

`.build/artifacts/` contains cached `RACommons.xcframework` from v0.19.13 era. These predate the v3u ABI introduced on this branch. If anyone uses `useLocalNatives = false` AND has stale cache, they get the wrong ABI. Solutions: clear `.build/`, or run `scripts/release-swift-binaries.sh` to regen.

---

## 5. What's remaining (prioritized backlog)

### 5.1 P0 — Must fix before any merge to main (4 items, ~3-5 days)

| Item | Description | Estimate |
|---|---|---|
| Fix B1 | Either migrate `engines/llamacpp/CMakeLists.txt` to `rac_add_engine_plugin()` macro, OR update `docs/GAP_STATUS.md` to honestly say "8/9 engines on macro; llamacpp intentionally hand-rolled because <reason>" | 1-2 days |
| Fix B2 | Point `engines/onnx/CMakeLists.txt` `RAG_DIR` to the real path under commons. Surface the latent stale `#include "../../backends/onnx/onnx_backend.h"` in `onnx_embedding_provider.cpp` (fix to a working include) | 0.5-1 day |
| Fix B3 | Move `g_onnx_*_ops` definitions out of anonymous namespace; wrap in `extern "C"` to match the plugin-entry declarations. Same fix likely needed in llamacpp | 1-2 days |
| Fix B4 | Either add `getVoiceAgentHandle()` method to RN `RunAnywhere.ts` facade (forwards to native module), OR update RN sample to call via `requireNativeModule()` directly | 0.5 day |

### 5.2 P1 — High-value engineering (8 items, ~3-4 weeks)

| Item | Description | Estimate |
|---|---|---|
| Fix B5 | Implement Web `VoiceAgent` extension methods (move from stub to real WASM-backed impl) | 1-2 weeks |
| Fix B6 | Either accept Flutter v4 as facade-only (rename) OR do the actual god-class refactor (move method bodies into capability classes; delete the deprecated class) | 1-2 weeks (real refactor) |
| Fix B7 | Migrate Web sample to use `VoiceAgentStreamAdapter` for parity with other 4 SDKs | 2-3 days |
| Fix B8 | Run `scripts/release-swift-binaries.sh` (operator step; needs Xcode + GitHub release credentials + manual `third_party/onnxruntime-ios/onnxruntime.xcframework` prereq) | 0.5-1 day operator effort |
| Fix B9 | Decide: keep deprecated `RunAnywhere` static class long-term OR migrate Flutter backend plugins to use `RunAnywhereSDK.instance` | 1 day |
| Fix B10 | Migrate remaining Flutter sample files (model UI, settings, VLM, structured output, STT/TTS views) to v4 instance API | 2-3 days |
| Fix B11 | Triage the 4-5 JNI callback registration TODOs in `runanywhere_commons_jni.cpp`. Many may be dead code | 1-2 weeks |
| Fix B12 | Triage the Kotlin `CppBridge*.kt` "TODO: Call native registration" stubs. Same as B11 | 1-2 weeks |

### 5.3 P2 — Architectural (multi-month, vendor decisions)

| Item | Description | Estimate |
|---|---|---|
| Fix B13 | Kotlin GAP 08 #3 download orchestration → commons HTTP client. Requires choosing libcurl/cpr/platform-native shims | 1-3 months |
| Fix B14 | Wakeword service real implementation | 2-4 weeks |
| Fix B15 | RN tool-calling commons backend | 1-2 weeks |
| Fix B16 | GAP 05 full DAG runtime (when 2nd pipeline needs it) | Indefinite |

### 5.4 P3 — Documentation (1 day total)

Fix all 8 doc-drift items (B17-B24): update `GAP_STATUS.md`, fix workflow filename references, update HISTORY claim about whispercpp header, update sample READMEs, update Swift adapter docstring, fix tests/streaming docs.

### 5.5 P4 — QA workstream (separate effort)

GAP 03 / 04 / 08 #9 / #10 — out of engineering scope per original plan. Separate QA owner needed.

---

## 6. Release readiness

### 6.1 What's ready

- C ABI + plugin registry: shipped + tested (11/11 + 13/13 native tests)
- Voice agent rewrite: shipped across 5 SDKs (with Web caveat)
- IDL drift CI: active
- All package versions reset to main baseline (no premature bumps)
- Macos-debug + linux-debug + linux-asan green in CI

### 6.2 What's blocking ship

| Block | Resolution |
|---|---|
| 4 P0 bugs (B1-B4) | Must fix before merge |
| Swift xcframework not published | Operator runs `scripts/release-swift-binaries.sh` post-merge |
| Web voice-agent stub | Either ship as-is + document as "use VoicePipeline on web", or implement (B5) |
| Flutter v4 misnamed | Either rename "v4" to "facade pattern" + accept god-class persists, or do real refactor |
| Kotlin Maven publishing | Verified ready (signing + maven-publish in `build.gradle.kts`) |
| RN/Web npm publishing | Need to check if `prepublishOnly` scripts run cleanly after `pnpm install` |
| Migration guide | `docs/migrations/v3_to_v4_flutter.md` + `docs/migrations/VoiceSessionEvent.md` exist; should add a `<from>_to_<to>.md` matching whatever release version is chosen |

### 6.3 Suggested release sequence (when team decides)

1. Fix all 4 P0 bugs (~3-5 days)
2. Fix B7 (web sample voice migration) for cross-SDK parity OR document as "web uses VoicePipeline" intentionally
3. Decide: ship Flutter as `RunAnywhereSDK` facade (truthful naming) or do actual god-class refactor
4. Decide release version: v0.20.0 (additive minor in 0.x), v1.0.0 (clean break), or v2.0.0 (matches branch name)
5. Bump versions across 14 files (VERSION × 2, Package.swift, 4 pubspecs, 8 package.jsons, build.gradle.kts)
6. Run `scripts/release-swift-binaries.sh` on macOS box with credentials
7. `gh release create vX.Y.Z` for xcframework zips
8. `pub publish` Flutter packages, `npm publish` RN/Web packages, Maven Central / JitPack for Kotlin
9. Squash-merge `feat/v2-architecture` → `main`

---

## 7. Recommended next actions (this week)

If the goal is to be merge-ready in 1-2 weeks:

1. **Today**: Fix P3 doc drift (1 day; B17-B24). Low risk, high readability win.
2. **Day 2-3**: Fix B1 (decide llamacpp macro vs documented exception) + B2 (ONNX RAG_DIR).
3. **Day 4-5**: Fix B3 (ops linkage) + B4 (RN handle method).
4. **Week 2**: Pick one P1 item per developer:
   - Engineer A: B6 Flutter god-class real refactor (or rename v4 honestly)
   - Engineer B: B5 Web VoiceAgent implementation (if cross-SDK parity matters)
   - Engineer C: B7 Web sample migration + B10 Flutter sample migration
   - Engineer D: B8 Swift xcframework publication (if external SPM consumers needed)
5. **Then**: Decide release strategy + execute Section 6.3 sequence.

If the goal is to MERGE first + iterate after:

1. Fix only B4 (RN compile break — actual blocker).
2. Update docs to honestly reflect known-incomplete items (B5/B6/B7 noted as "deferred to v0.20.1+").
3. Squash-merge to main.
4. Release as v0.20.0 (additive minor signal for 0.x semver).
5. Iterate on P1 items in dot-releases.

---

## 8. Bottom line

**The architectural work shipped on this branch is real and substantial** — IDL-driven, plugin-based, proto-streaming. **9 of 10 in-repo GAPs are functionally done** (10th was never spec'd; 11th is closed).

**The actual blockers are smaller than the doc-drift suggests**: 4 P0 bugs (~3-5 days), one of which is just doc honesty (B1), one is a path typo (B2), one is a linkage cleanup (B3), one is a missing TS facade method (B4).

**The bigger architectural debt items** (Flutter v4 facade vs real refactor, Web voice-agent stub, Kotlin download HTTP migration) are P1/P2 — they don't block a merge, but they're the truthful "what's left."

**The QA work** (GAP 03/04/08 #9/#10) is a separate workstream and was never engineering scope.
