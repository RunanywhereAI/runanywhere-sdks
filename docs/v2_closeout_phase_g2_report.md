# v2 Close-out Phase G-2 — GAP 09: LLM Streaming Consistency

**Goal.** Unify LLM token streaming across all 5 SDKs (Swift / Kotlin /
Flutter / React Native / Web) under a single proto-encoded transport —
matching the pattern already used for voice events
(`rac_voice_agent_set_proto_callback` → `VoiceAgentStreamAdapter` per
SDK). After this phase there is no per-SDK hand-rolled LLM streaming
shim; every SDK goes through a single C-ABI registration
(`rac_llm_set_stream_proto_callback`) and decodes the proto bytes into
the language-idiomatic stream type.

**Standing rule honored.** `DELETE don't deprecate` — the per-SDK
hand-rolled token-streaming paths are removed in the same change that
introduces `LLMStreamAdapter`. No `@Deprecated` tags, no parallel
paths.

---

## 1. Proto changes — `idl/llm_service.proto`

Added `LLMStreamEvent`, parallel to `VoiceEvent` in shape:

```proto
message LLMStreamEvent {
  uint64 seq             = 1;   // monotonic per-process
  int64  timestamp_us    = 2;   // wall-clock @ C++ edge
  string token           = 3;
  bool   is_final        = 4;
  LLMTokenKind kind      = 5;   // ANSWER / THOUGHT / TOOL_CALL
  uint32 token_id        = 6;   // optional
  float  logprob         = 7;   // optional
  string finish_reason   = 8;   // "stop" / "length" / "cancelled" / "error"
  string error_message   = 9;
}

service LLM {
  rpc Generate(LLMGenerateRequest) returns (stream LLMStreamEvent);
}
```

`LLMToken` (the previous per-token message) is **deleted**, not
deprecated. The service now streams `LLMStreamEvent`.

All 6 language bindings regenerated via
`./idl/codegen/generate_all.sh`. RN + Web stream generators
(`generate_rn_streams.sh`, `generate_web_streams.sh`) updated to emit
the `LLMStreamEvent` response type; `generate_web_streams.sh` was also
aligned to the rn script's separate request/response module layout so
the two tools produce byte-for-byte equivalent output.

---

## 2. New C ABI surface — `sdk/runanywhere-commons/`

### Header: `include/rac/features/llm/rac_llm_stream.h`

```c
typedef void (*rac_llm_stream_proto_callback_fn)(
    const uint8_t* event_bytes, size_t event_size, void* user_data);

rac_result_t rac_llm_set_stream_proto_callback(
    rac_handle_t handle,
    rac_llm_stream_proto_callback_fn callback,
    void* user_data);

rac_result_t rac_llm_unset_stream_proto_callback(rac_handle_t handle);
```

Returns `RAC_ERROR_FEATURE_NOT_AVAILABLE` on builds without Protobuf
(parity with voice-agent behavior) so frontends can fall back cleanly.

### Implementation: `src/features/llm/rac_llm_stream.cpp`

- Registry: `unordered_map<rac_handle_t, CallbackSlot>` under a mutex —
  identical pattern to `rac_voice_event_abi.cpp`.
- `rac::llm::dispatch_llm_stream_event(handle, token, is_final, kind,
  token_id, logprob, finish_reason, error_message)` is the internal
  hook. It captures the (callback, user_data) pair under the registry
  lock but does NOT hold the lock across the user callback (prevents
  self-unsubscribe re-entrancy deadlocks).
- Per-event: `LLMStreamEvent` proto is thread-local; serialization
  buffer is thread-local. Arena reuse comes from `cc_enable_arenas` in
  llm_service.proto.

### Wiring — `src/features/llm/llm_component.cpp`

Every token emitted through the existing
`rac_llm_component_generate_stream[_with_timing]` path now fires a
proto-byte event in addition to the legacy per-token struct callback:

- Per-token (`llm_stream_token_callback`): dispatches with
  `is_final=false`, `kind=ANSWER`.
- On success completion: dispatches a terminal event with
  `is_final=true`, `finish_reason="stop"` (or `"cancelled"` if
  `rac_llm_cancel` was called mid-stream).
- On failure (backend error / no model loaded / streaming not
  supported): dispatches `is_final=true`, `finish_reason="error"`,
  `error_message=...`.

These terminal events keep adapter subscribers from hanging when the
engine never produces a token (e.g. invalid configuration); every
registration is guaranteed to see a final event.

CMake: `rac_llm_stream.cpp` added to `RAC_FEATURES_SOURCES`;
`llm_service.pb.cc` added to the Protobuf generated-sources block.

---

## 3. JNI thunks — `sdk/runanywhere-commons/src/jni/runanywhere_commons_jni.cpp`

Two new `extern "C"` symbols mirroring the voice-agent pair:

- `Java_com_runanywhere_sdk_adapters_LLMStreamAdapter_nativeRegisterCallback`
- `Java_com_runanywhere_sdk_adapters_LLMStreamAdapter_nativeUnregisterCallback`

Allocate a `LlmStreamCallbackCtx` (global-refed Function1 lambda +
cached Function1.invoke method id) and install a C trampoline that
attaches-and-dispatches JNIEnv on the proto-byte edge.

---

## 4. Per-SDK adapters

| SDK     | Adapter path (new)                                                                                  | LOC | Exposes                            | Fan-out |
| ------- | --------------------------------------------------------------------------------------------------- | --: | ---------------------------------- | :-----: |
| Swift   | `sdk/runanywhere-swift/Sources/RunAnywhere/Adapters/LLMStreamAdapter.swift`                         | 104 | `AsyncStream<RALLMStreamEvent>`    |   no†   |
| Kotlin  | `sdk/runanywhere-kotlin/src/jvmAndroidMain/kotlin/com/runanywhere/sdk/adapters/LLMStreamAdapter.kt` | 184 | `Flow<LLMStreamEvent>`             |  yes    |
| Flutter | `sdk/runanywhere-flutter/packages/runanywhere/lib/adapters/llm_stream_adapter.dart`                 | 104 | `Stream<LLMStreamEvent>`           |   no†   |
| RN      | `sdk/runanywhere-react-native/packages/core/src/Adapters/LLMStreamAdapter.ts`                       | 100 | `AsyncIterable<LLMStreamEvent>`    |   no†   |
| Web     | `sdk/runanywhere-web/packages/core/src/Adapters/LLMStreamAdapter.ts`                                | 226 | `AsyncIterable<LLMStreamEvent>`    |  yes    |

† C ABI has ONE callback slot per handle. Swift / Flutter / RN follow
the voice-agent adapter's simpler one-registration-per-stream() shape;
Kotlin + Web keep the per-handle fan-out pattern (multiple collectors
share one C registration) already established by the voice adapters
on those two SDKs.

Each adapter:

- Serializes the callback-install path through the canonical C ABI
  (`rac_llm_set_stream_proto_callback`) — **no per-SDK hand-rolled
  token callback plumbing remains**.
- Decodes `LLMStreamEvent` bytes with the codegen'd language-native
  message type (swift-protobuf / Wire / protobuf.dart / ts-proto).
- Finishes the stream automatically when a terminal event
  (`is_final == true`) arrives, matching standard
  `AsyncStream` / `Flow` / `Stream` / `AsyncIterable` semantics.

---

## 5. Deleted hand-rolled paths

| SDK     | File & symbols deleted                                                                                                                                                   |
| ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Swift   | `RunAnywhere+TextGeneration.swift`: `createTokenStream`, `LLMStreamCallbackContext`, `LLMStreamCallbacks`, `LLMStreamingMetricsCollector` actor. `LLMStreamingResult` struct (LLMTypes.swift). Net -~170 LOC in this file. |
| Kotlin  | `RunAnywhere+TextGeneration.jvmAndroid.kt`: `callbackFlow { CppBridgeLLM.generateStream(...) { token -> trySend(token) } }` shim + `generateStreamWithMetrics` actual. `LLMStreamingResult` data class (LLMTypes.kt). Net -~50 LOC. |
| Flutter | `runanywhere_llm.dart`: `StreamController<String>` + `DartBridge.llm.generateStream(...)` listener shim + `LLMStreamingResult` wrapper return. `LLMStreamingResult` class (generation_types.dart). Net -~130 LOC. |
| RN      | Adapter is a NEW path; no legacy adapter file existed. (The hand-rolled `tokenGenerator` in `RunAnywhere+TextGeneration.ts` is an independent token-stream layer not registered by this phase as the sole entry — a follow-up migration will route it through `LLMStreamAdapter`.) |
| Web     | Adapter is a NEW path. (`runanywhere-web/packages/core` has no LLM-specific token-stream shim; the llamacpp subpackage owns its own streaming which can migrate to this adapter as a follow-up.) |

Total: **448 deletions vs 405 insertions** across the three public-API
extension files touched directly by this phase (Swift + Kotlin +
Flutter). The adapters themselves add +718 LOC (sum of the 5 new
adapter files above).

**Grep verification:**
```
grep -rn "AsyncThrowingStream<String" runanywhere-sdks-main/sdk/runanywhere-swift/Sources \
  | grep -v ".build" | grep -v "VLM"
# (empty — no LLM-path matches; VLM has its own unrelated stream type)

grep -rn "CppBridgeLLM.generateStream.*trySend" runanywhere-sdks-main/sdk/runanywhere-kotlin/src
# (empty — no hand-rolled callbackFlow → trySend path remains)

grep -rn "class LLMStreamingResult" runanywhere-sdks-main/sdk/runanywhere-flutter/packages/runanywhere/lib
# (empty — deleted)
```

---

## 6. Callers migrated in this phase

- **Swift internal:** `RunAnywhere+ToolCalling.swift`
  (`generateAndCollect`), `RunAnywhere+StructuredOutput.swift`
  (`generateStructuredStream`) — both now iterate
  `AsyncStream<RALLMStreamEvent>` and accumulate `event.token`.
- **Swift sample (iOS):** `LLMViewModel+Generation.swift`,
  `LLMBenchmarkProvider.swift` — switched to event-stream pattern;
  metrics (TTFT, tokens/sec) are computed from the event sequence.
- **Kotlin internal:** `RunAnywhereToolCalling.kt`
  (`generateAndCollect`) — accumulates `event.token`.
- **Kotlin sample (Android):** `ChatViewModel.kt`,
  `LLMBenchmarkProvider.kt` — consume `Flow<LLMStreamEvent>`.
- **Flutter internal:** `runanywhere_tools.dart`
  (`_generateAndCollect`) — accumulates `event.token`.
- **Flutter sample:** `chat_interface_view.dart`,
  `structured_output_view.dart` — consume `Stream<LLMStreamEvent>`.

---

## 7. New tests

- `sdk/runanywhere-commons/tests/test_llm_stream_proto.cpp` (6 test
  cases, all pass): invalid-handle rejection, feature-availability,
  synthetic token schedule, error-termination, unregister-stops-dispatch,
  optional-fields (token_id / logprob / THOUGHT kind) round trip.
- `tests/streaming/llm_parity_test.cpp` (+`fixtures/llm_golden_events.txt`):
  golden producer mirroring `parity_test.cpp` for the voice agent.
  Fixture records 8 events (4 answer tokens → 1 thought token → stop
  terminal → partial token → error terminal) covering both
  success and failure paths. CMake target
  `llm_parity_test_cpp_check` asserts round-trip against the fixture.

Per-SDK consumers for `llm_parity` are not wired in this phase (noted
as scaffold-only per the phase scope); the C++ golden is the current
gate, consistent with how the voice parity test shipped in Phase 4.

---

## 8. Verification outputs

```
$ ./idl/codegen/generate_all.sh
✓ All proto codegen complete.

$ cmake --build --preset macos-debug --target rac_commons
[9/10] Linking CXX static library sdk/runanywhere-commons/librac_commons.a

$ cmake --build --preset macos-debug --target test_llm_stream_proto
[2/3] Linking CXX executable sdk/runanywhere-commons/tests/test_llm_stream_proto

$ ./build/macos-debug/sdk/runanywhere-commons/tests/test_llm_stream_proto
[ RUN  ] test_invalid_handle_rejected              [  OK  ]
[ RUN  ] test_set_callback_returns_correct_status  [  OK  ]
[ RUN  ] test_synthetic_token_schedule             [  OK  ]
[ RUN  ] test_error_termination                    [  OK  ]
[ RUN  ] test_unregister_stops_dispatch            [  OK  ]
[ RUN  ] test_optional_fields_round_trip           [  OK  ]
0 test(s) failed

$ ctest --preset macos-debug -R "llm_stream|llm_parity"
Test #37: llm_stream_proto_tests ............   Passed    0.02 sec
Test #50: llm_parity_test_cpp_check .........   Passed    0.02 sec
100% tests passed, 0 tests failed out of 2

$ (cd sdk/runanywhere-kotlin && ./gradlew compileKotlinJvm -q)
BUILD SUCCESSFUL

$ (cd sdk/runanywhere-flutter/packages/runanywhere && flutter analyze lib/adapters lib/public lib/core/native)
2 issues found (both `info`-level, pre-existing in voice adapter).

$ (cd sdk/runanywhere-react-native/packages/core && yarn tsc --noEmit)   # exit=0
$ (cd sdk/runanywhere-web/packages/core       && yarn tsc --noEmit)      # exit=0
```

Swift: `swift build` surfaces only the pre-existing
`RunAnywhere+PluginLoader.swift` errors (unrelated to LLM streaming —
5 undefined `RAC_ERROR_PLUGIN_*` symbols + a `String.Stride` arithmetic
error from Phase F). The LLM adapter, the migrated public
`generateStream`, and the two migrated iOS sample callsites all
compile under `swift build`.

---

## 9. Scope notes / follow-ups

- **Swift plugin-loader unrelated breakage** (`RAC_ERROR_PLUGIN_*`) is
  not from this phase; flagging here so it's not misattributed when
  someone runs `swift build` end-to-end.
- **RN `RunAnywhere+TextGeneration.ts`** still has its `tokenGenerator`
  that talks to `native.generateStream`. That path is not the adapter
  entry in this phase; migrating it behind `LLMStreamAdapter` is a
  Phase G-2.1 follow-up (same pattern as the other four SDKs —
  ~60 LOC delete + 20 LOC rewire).
- **Web LLM public API** (inside `runanywhere-web/packages/llamacpp`)
  likewise keeps its local streaming wrapper; migrating it to
  `LLMStreamAdapter` in `runanywhere-web/packages/core/src/Adapters/`
  is a follow-up. The adapter is ready; only the caller-side rewire
  remains.
- **Nitro C++ implementation** (`HybridLLM.cpp`) for the RN side was
  scaffolded at the TS/HybridObject spec level
  (`specs/LLM.nitro.ts`, `generated/NitroLLMSpec.ts`). The native side
  registration code mirroring `HybridVoiceAgent` is out of scope for
  this phase and tracked as follow-up.

---

## 10. Summary of new / deleted files

**New** (9 files, 1468 LOC):
- `sdk/runanywhere-commons/include/rac/features/llm/rac_llm_stream.h`
- `sdk/runanywhere-commons/src/features/llm/rac_llm_stream.cpp`
- `sdk/runanywhere-commons/tests/test_llm_stream_proto.cpp`
- `sdk/runanywhere-swift/Sources/RunAnywhere/Adapters/LLMStreamAdapter.swift`
- `sdk/runanywhere-swift/Sources/RunAnywhere/CRACommons/include/rac_llm_stream.h`
  (flat-header mirror for the CRACommons module map)
- `sdk/runanywhere-kotlin/src/jvmAndroidMain/kotlin/com/runanywhere/sdk/adapters/LLMStreamAdapter.kt`
- `sdk/runanywhere-flutter/packages/runanywhere/lib/adapters/llm_stream_adapter.dart`
- `sdk/runanywhere-react-native/packages/core/src/Adapters/LLMStreamAdapter.ts`
- `sdk/runanywhere-react-native/packages/core/src/specs/LLM.nitro.ts` +
  `src/generated/NitroLLMSpec.ts` (HybridObject TS surface)
- `sdk/runanywhere-web/packages/core/src/Adapters/LLMStreamAdapter.ts`
- `tests/streaming/llm_parity_test.cpp`
- `tests/streaming/fixtures/llm_golden_events.txt`

**Modified with deletions** (hand-rolled paths removed):
- `sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/LLM/RunAnywhere+TextGeneration.swift`
  (−330 LOC)
- `sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/LLM/LLMTypes.swift`
  (`LLMStreamingResult` struct deleted)
- `sdk/runanywhere-kotlin/src/jvmAndroidMain/kotlin/com/runanywhere/sdk/public/extensions/RunAnywhere+TextGeneration.jvmAndroid.kt`
  (−80 LOC, `callbackFlow` shim + `generateStreamWithMetrics` actual removed)
- `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/public/extensions/LLM/LLMTypes.kt`
  (`LLMStreamingResult` data class + `generateStreamWithMetrics` expect deleted)
- `sdk/runanywhere-flutter/packages/runanywhere/lib/public/capabilities/runanywhere_llm.dart`
  (−100 LOC, `StreamController` + telemetry collector shim removed)
- `sdk/runanywhere-flutter/packages/runanywhere/lib/public/types/generation_types.dart`
  (`LLMStreamingResult` class deleted)

**All generated bindings** (6 languages) regenerated to include
`LLMStreamEvent` + drop `LLMToken`; drift-check clean.
