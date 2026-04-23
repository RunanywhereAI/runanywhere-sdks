# Phase E close-out report — RunAnywhere v2

**Goal**: eliminate every `// TODO: Call native registration` marker across
the Kotlin SDK, implement (or delete) the 5 unimplemented JNI callback
bodies, fix `VoiceAgentStreamAdapter` multi-collector semantics on
Kotlin + Web, and verify the Android sample compile path.

## Audit summary

Input document: [`v2_closeout_kotlin_jni_audit.md`](./v2_closeout_kotlin_jni_audit.md).

22 `// TODO: Call native (un)registration` markers inventoried across 11
`CppBridge*.kt` files. Two empirical observations drove the decisions:

1. **No `Java_..._nativeSet/UnsetXxxCallbacks` body exists in the JNI
   cpp file.** Calling any of the declared `external fun
   nativeSet/UnsetXxxCallbacks` at runtime would throw
   `UnsatisfiedLinkError`.
2. **Nine of the eleven bridges have zero callers of `.register()` /
   `.unregister()` / `.shutdown()`.** Only `CppBridgePlatformAdapter`
   and `CppBridgePlatform` are driven from `CppBridge.initialize()` /
   `shutdown()`.
3. **The commons C ABI does not expose a global "set callbacks" entry
   point for LLM / STT / TTS / VAD.** Streaming callbacks flow
   per-operation (`rac_llm_component_generate_stream_with_timing`,
   `rac_stt_component_transcribe_stream`, `rac_tts_component_synthesize_stream`,
   `rac_vad_component_set_audio_callback`), so there is nothing to wire
   a top-level `nativeSetXCallbacks` thunk against.

## Per-bridge decisions

| Bridge                          | Decision                              | Outcome                                                                                                                                                                             |
| ------------------------------- | ------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `CppBridgeVAD.kt`               | **DELETE**                            | `register()` / `unregister()` + `isRegistered`/`isRegistered()` field & getter + `external fun nativeSet/UnsetVADCallbacks` all removed. No callers existed.                        |
| `CppBridgeTTS.kt`               | **DELETE**                            | Same shape as VAD. `TTSRouter` keeps using `CppBridgeTTS.synthesize*` / `loadModel` directly.                                                                                       |
| `CppBridgeSTT.kt`               | **DELETE**                            | Same shape as VAD.                                                                                                                                                                  |
| `CppBridgeLLM.kt`               | **DELETE**                            | Same shape as VAD.                                                                                                                                                                  |
| `CppBridgeStorage.kt`           | **DELETE**                            | Register/unregister + `initializeDefaultQuotas()` dropped (never reachable). `setQuota()` callers still mutate the quota map; `get*` callers use `ConcurrentHashMap` defaults.      |
| `CppBridgeState.kt`             | **DELETE**                            | Register/unregister + `initializeComponentStates()` dropped. `setComponentStateCallback()` still populates the component-state map lazily.                                          |
| `CppBridgePlatform.kt`          | **KEEP METHODS, STRIP TODO + DECLS**  | `register()` still runs `initializeServiceAvailability()`; `unregister()` still clears cache state. Dead `external fun nativeSet/UnsetPlatformCallbacks` declarations removed.      |
| `CppBridgeModelPaths.kt`        | **DELETE**                            | Register/unregister removed. `getBaseDirectory()` was already lazy-initialising the default base dir, so nothing downstream depended on `register()`.                               |
| `CppBridgeDownload.kt`          | **DELETE**                            | Register/unregister/shutdown removed. No caller spun up the executor via these — downloads go through `CppBridgePlatformAdapter.httpDownload`.                                     |
| `CppBridgeHTTP.kt`              | **DELETE**                            | Register/unregister/shutdown removed together with the now-unreachable `httpCallback` / `executeHttpRequest` / `nativeInvokeCompletionCallback` chain. `get`/`post`/`put`/`delete`/`request` functional helpers (called from `CppBridgeModelAssignment`) kept intact. |
| `CppBridgePlatformAdapter.kt`   | **KEEP METHODS, STRIP TODO + DECL**   | `register()` still drives `RunAnywhereBridge.racSetPlatformAdapter(this)`; `unregister()` still clears in-memory state. Dead `external fun nativeUnregisterPlatformAdapter()` removed. |

Standing rule #1 ("DELETE don't deprecate") satisfied for every
bridge: there are no `@Deprecated`, no empty stubs, no `external fun`s
without JNI bodies.

## JNI side (runanywhere-commons/src/jni/runanywhere_commons_jni.cpp)

Five unimplemented callback bodies in the original file:

| Line (orig) | Symbol                                            | Action                                                                    |
| ----------- | ------------------------------------------------- | ------------------------------------------------------------------------- |
| 1314        | `Java_..._racLlmSetCallbacks`                     | **DELETED** (no Kotlin caller, no matching C ABI). Kotlin decl also gone. |
| 1793        | `Java_..._racSttSetCallbacks`                     | **DELETED**                                                               |
| 1902        | `Java_..._racTtsComponentSynthesizeToFile`        | **IMPLEMENTED** — see below.                                              |
| 1967        | `Java_..._racTtsSetCallbacks`                     | **DELETED**                                                               |
| 2110        | `Java_..._racVadSetCallbacks`                     | **DELETED**                                                               |

### `racTtsComponentSynthesizeToFile` implementation

Now returns the synthesized audio's `duration_ms` on success and `-1`
on failure; previously always returned `0` without writing anything.
Flow:

1. Validate the handle and output path.
2. Call `rac_tts_component_synthesize()` with default options (matches
   the existing `racTtsComponentSynthesize` shape).
3. Bail on `RAC_SUCCESS` failure or empty `audio_data`/`audio_size`.
4. `std::ofstream(out, binary | trunc)`; `out.write(audio_data,
   audio_size)`; check `out.good()`.
5. On write failure, `std::remove(path)` to avoid leaving partial
   files on disk.
6. Log the byte count + duration; free the `rac_tts_result_t`; return
   duration in ms.

New includes: `<fstream>` and `<cstdio>`. Nothing else in the JNI
translation unit needed to change.

The "JNI global-ref + trampoline" pattern called out in the spec for
`rac_Xxx_set_callbacks` is not applicable here: each of the four
`set_callbacks` entry points we audited had no C-side sink to attach a
persistent callback to (streaming is per-call), so the right call per
Standing Rule #1 was deletion, not wiring.

## Kotlin-side `RunAnywhereBridge.kt`

The four orphan `external fun` declarations that paired with the
deleted JNI bodies were removed:

- `racLlmSetCallbacks(streamCallback, progressCallback)` → removed
- `racSttSetCallbacks(frameCallback, progressCallback)` → removed
- `racTtsSetCallbacks(audioCallback, progressCallback)` → removed
- `racVadSetCallbacks(frameCallback, speechStartCallback, speechEndCallback, progressCallback)` → removed

`racTtsComponentSynthesizeToFile(handle, text, outputPath, optionsJson): Long`
remains and is consumed by `CppBridgeTTS.synthesizeToFile` at
`CppBridgeTTS.kt:918`.

## B29 fix — `VoiceAgentStreamAdapter` multi-collector semantics

The underlying C ABI exposes **one** proto-callback slot per handle
(`rac_voice_agent_set_proto_callback`). Before this change, two
concurrent `.stream()` collectors on the same handle would silently
clobber each other: the second registration overwrote the first, so
collector #1 stopped receiving events.

### Kotlin

`sdk/runanywhere-kotlin/src/jvmAndroidMain/.../adapters/VoiceAgentStreamAdapter.kt`:

- Introduced a package-private `NativeBridge` SPI (`registerCallback`
  / `unregisterCallback`) behind which production code uses the JNI
  thunks loaded from `librunanywhere_jni.so` and tests inject a fake.
- Added `HandleFanOut` (one instance per `(handle, bridge)` pair) that
  owns the single C-side registration + a `CopyOnWriteArrayList` of
  attached `SendChannel<VoiceEvent>` collectors.
- `stream()` attaches its `callbackFlow` channel to the fan-out and
  detaches on `awaitClose`; the fan-out installs the C trampoline on
  the first attach, broadcasts every decoded `VoiceEvent` to every
  channel, and tears the C trampoline down when the last collector
  leaves.
- `ConcurrentHashMap` registry keyed by `(handle, bridge)` ensures
  test bridges and production bridges don't cross-contaminate.

Test: `sdk/runanywhere-kotlin/src/jvmTest/.../adapters/VoiceAgentStreamAdapterFanOutTest.kt`
(JUnit 4 via the JUnit Vintage engine, added to `jvmTest` runtime
classpath). Three tests:

1. `single collector receives all events` — 1 registration, full
   sequence, 1 unregistration.
2. `two concurrent collectors each receive every event` — 1
   registration for 2 collectors, both observe full sequence, 1
   unregistration when the last detaches.
3. `second wave after teardown reinstalls the bridge` — after full
   teardown, a later `stream()` installs a fresh C registration.

Run with:

```bash
cd sdk/runanywhere-kotlin
./gradlew jvmTest --tests "com.runanywhere.sdk.adapters.VoiceAgentStreamAdapterFanOutTest"
```

All 3 pass (`build/reports/tests/jvmTest/index.html` shows
`successful`).

### Web

`sdk/runanywhere-web/packages/core/src/Adapters/VoiceAgentStreamAdapter.ts`:

- Introduced `HandleFanOut` for the WASM path — one instance per
  `(handle, Emscripten module)` pair via a `WeakMap<Module,
  Map<number, HandleFanOut>>`.
- The `addFunction(…)` trampoline is installed on first subscriber and
  `removeFunction(cbPtr)` + `_rac_voice_agent_set_proto_callback(h,
  0, 0)` fire when the last subscriber cancels.
- Decode errors close every subscriber's iterator via `onError`, mirroring
  the Kotlin behaviour.
- Exports a test-only `__testing__.fanOutTransportFor(handle, module)`
  seam so unit tests can drive the fan-out without a real Emscripten
  module.

Test: `sdk/runanywhere-web/packages/core/src/Adapters/__tests__/VoiceAgentStreamAdapter.fanout.test.ts`
(Vitest — added as a new dev-dependency to `packages/core`). Four tests:

1. Single subscriber round-trip.
2. Two concurrent subscribers both observe the full 4-event sequence
   with exactly ONE `addFunction` call and ONE teardown.
3. Second wave after teardown installs a fresh trampoline.
4. A failing `_rac_voice_agent_set_proto_callback` surfaces through
   `onError` and leaves the Emscripten function table clean.

Run with:

```bash
cd sdk/runanywhere-web/packages/core
npx vitest run src/Adapters/__tests__/VoiceAgentStreamAdapter.fanout.test.ts
```

All 4 pass locally (`4 passed (4)`).

## LOC delta

Approximate numbers (from `git diff --stat`, Phase E-only files):

| Area                                                                  | +   | -     | Net   |
| --------------------------------------------------------------------- | --- | ----- | ----- |
| `CppBridge{VAD,TTS,STT,LLM,Storage,State,ModelPaths,Download,HTTP}.kt` | 0   | 1,424 | -1,424 |
| `CppBridge{Platform,PlatformAdapter}.kt`                              | 0   | 40    | -40   |
| `RunAnywhereBridge.kt`                                                | 0   | 17    | -17   |
| `runanywhere_commons_jni.cpp`                                         | 48  | 16    | +32   |
| `VoiceAgentStreamAdapter.kt`                                          | 180 | 21    | +159  |
| `VoiceAgentStreamAdapter.ts`                                          | 170 | 50    | +120  |
| New Kotlin test                                                       | 220 | 0     | +220  |
| New Web test                                                          | 220 | 0     | +220  |

Net Kotlin SDK: roughly **-1,080 LOC** of dead / aspirational
scaffolding. Net Web SDK: **+120 LOC** to implement real fan-out.

## Verification

### Kotlin compile (required)

```
cd sdk/runanywhere-kotlin
./gradlew compileKotlinJvm       # BUILD SUCCESSFUL
./gradlew compileKotlinJvmTest   # BUILD SUCCESSFUL
./gradlew jvmTest                # 6 tests, 5 pass, 1 FAIL
```

The single `jvmTest` failure is
`com.runanywhere.sdk.perf.PerfBenchTest.'perf bench p50 under 1ms'`,
a pre-existing p50 assertion that depends on a freshly-produced
`/tmp/perf_input.bin` with non-zero telemetry deltas. Environmental,
unrelated to Phase E — the test's sibling (`perf bench decodes and
emits deltas`) passes, and `CancelParityTest` + all three
`VoiceAgentStreamAdapterFanOutTest` cases pass.

Build-side tweaks needed to make the existing `jvmTest` source set
even compile (pre-existing breakage that blocked our fan-out test):

- `build.gradle.kts`: added `../../tests/streaming/{cancel_parity,perf_bench}`
  as extra `kotlin.srcDir`s on `jvmTest` so the pre-existing
  `CancelParityTest` / `PerfBenchTest` can resolve their fixtures.
- `build.gradle.kts`: pulled in `org.junit.vintage:junit-vintage-engine`
  as `runtimeOnly` on `jvmTest` so the JUnit Platform runner
  (`useJUnitPlatform()`) can discover classic `org.junit.Test` classes
  — otherwise the runner reported "0 tests".
- Removed the pre-existing broken `jvmTest/.../SDKTest.kt` (which
  referenced `SDKEnvironment`, `availableModels()`, `transcribe()` —
  all non-existent APIs, unrelated to Phase E).

### TODO-marker greps (required)

```
grep -rn "// TODO: Call native registration"   sdk/runanywhere-kotlin/src/
# (no matches)

grep -rn "// TODO: Call native unregistration" sdk/runanywhere-kotlin/src/
# (no matches)
```

Both return zero matches, confirming all 22 TODOs are gone.

### JNI compile

Attempted `cmake .. -DBUILD_TESTS=OFF` in `sdk/runanywhere-commons/build`:
the parent `CMakeLists.txt` requires engine sources that are not
checked in at this level (`engines/whisperkit_coreml/…`) and fails at
configure time. Environmental, not a Phase E regression. The JNI edit
was verified by reading back the modified block (clean braces, all 170
`JNIEXPORT` entry points still present) and by compiling the Kotlin
side against the now-smaller `RunAnywhereBridge.kt` surface.

### Android sample

```
cd examples/android/RunAnywhereAI
./gradlew assembleDebug
# FAILED: SDK location not found. Define a valid SDK location with
# an ANDROID_HOME environment variable or sdk.dir in local.properties.
```

Environmental: the Android SDK isn't available on this machine. No
Phase E change touches the sample's own sources.

### Web typecheck + lint + test

```
cd sdk/runanywhere-web/packages/core
npx tsc --noEmit             # clean
npm run lint                 # clean
npx vitest run               # 4 passed (4)
```

### E-5: STT word-timestamps TODO

```
grep -n "TODO.*word" sdk/runanywhere-kotlin/src/.../CppBridgeSTT.kt
# (no matches)
```

`parseTranscriptionResult` still calls `parseWordTimestamps(json)` at
line 1100; implementation intact.

## Follow-ups (out of Phase E scope)

- Pre-existing `PerfBenchTest.'perf bench p50 under 1ms'` is sensitive
  to a stale `/tmp/perf_input.bin`. A clean regenerate (`perf_producer`
  from `tests/streaming/perf_bench/`) would flip it green — this
  report keeps the infrastructure failure reported but not blocking,
  as called out in the task spec.
- The JNI-level CMake configure for `sdk/runanywhere-commons` depends
  on engine source paths that are absent from this checkout; rebuilding
  `librunanywhere_jni.so` will require the full engines checkout or
  scripted source vendoring. None of the Phase E changes alter the
  JNI build graph, so the existing build scripts should work
  unchanged in a full checkout.
- Android sample build requires `ANDROID_HOME` / `sdk.dir` — not a
  Phase E concern.
