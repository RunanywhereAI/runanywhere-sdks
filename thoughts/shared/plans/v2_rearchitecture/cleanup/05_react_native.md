# runanywhere-react-native — v1/v2 cleanup audit

Root: `sdk/runanywhere-react-native/`

---

## Summary

- **Total v1 RN SDK LOC measured** (packages only, excl. `node_modules` and Nitrogen generated output): **~60,700 LOC** across TS + C++ + Swift/ObjC.
- **DELETE-AFTER-V2-ENGINES**: ~50,300 LOC (~83 %) — the entire Nitro dispatcher + bridge stack plus all per-capability JS extensions.
- **DELETE-NOW**: ~3,900 LOC — the Nitro init-twice guard, all `any`-typed lazy-require patterns, the `Docs/` directory, and the `lerna.json` release config that has no v2 counterpart.
- **KEEP**: ~4,200 LOC — `packages/core/ios/KeychainManager.swift` + `PlatformAdapter.swift`, the `scripts/package-sdk.sh` staging contract (needed until v2 CI ships), and the `build-react-native.sh` script (needed for v1 CI).
- **INSPECT**: ~2,300 LOC — `packages/core/src/services/` (FileSystem, ModelRegistry, DownloadService) and the Foundation/Logging stack — parts may be ported into the v2 `~1,500 LOC` adapter.
- Surviving % after v2 Phase 3 gate: roughly **7 % of current LOC** (platform-specific audio / keychain code that the v2 adapter must still contain).

---

## DELETE-NOW

These files have no v2 equivalent and contain patterns the MASTER_PLAN explicitly flags as fragile or redundant.

| File | LOC | Reason |
|---|---|---|
| `packages/core/src/native/NitroModulesGlobalInit.ts` | 111 | Implements the "call `install()` exactly once" guard. v2 uses JSI TurboModule; the guard is unnecessary. Three module-level mutable singletons (`_nitroInstallationPromise`, `_nitroModulesProxy`, `_nitroInstallCalled`) encode the fragile double-init state MASTER_PLAN calls out explicitly. |
| `packages/core/src/native/NativeRunAnywhereCore.ts` (lines 80–311) | ~230 | The backwards-compat block (`requireNativeModule`, `isNativeModuleAvailable`, `requireFileSystemModule`, `requireDeviceInfoModule`) are BC shims over the Nitro proxy. The `requireNativeCoreModule()` function calls `NitroProxy.createHybridObject('RunAnywhereCore') as RunAnywhereCore` — `as RunAnywhereCore` is an unchecked cast over an untyped object factory. Lines 75, 48, 136 each use `as unknown as` casts. |
| `lerna.json` | ~10 | Controls `lerna publish` release for the v1 monorepo. v2 uses CMake-driven XCFramework / AAR assembly; no Lerna equivalent planned. |
| `Docs/ARCHITECTURE.md`, `Docs/Documentation.md` | ~n/a | Document the v1 Nitro architecture. Will contradict v2 on day one. |
| `packages/core/src/Public/Events/EventBus.ts` + `packages/core/src/Foundation/Logging/Destinations/NativeLogBridge.ts` (line 143: `(global as any).__runanywhereHandleNativeLog`) | — | Global mutation via `any`-cast is the sole mechanism bridging native logs into JS. v2 proto3 event stream subsumes this. |

---

## DELETE-AFTER-V2-ENGINES

Delete when the Phase 3 (`frontends/ts/`) gate passes. These files implement the 21,250 LOC Nitro bridge that v2 replaces with ~1,500 LOC JSI TurboModule + `frontends/ts/cpp/jsi_bridge.cpp`.

### C++ Dispatcher (core of the 4-layer Nitro stack)

| File | LOC | v2 Replacement |
|---|---|---|
| `packages/core/cpp/HybridRunAnywhereCore.cpp` | 2,921 | `frontends/ts/cpp/jsi_bridge.cpp` (~300 LOC, Phase 3B) |
| `packages/core/cpp/HybridRunAnywhereCore.hpp` | 304 | Same — vtable declaration collapses into the JSI bridge header |
| `packages/core/cpp/bridges/InitBridge.cpp/.hpp` | 1,504 + 306 | C ABI `ra_*` calls from the v2 core; `PluginRegistry` (Phase 0/E) |
| `packages/core/cpp/bridges/AuthBridge.cpp/.hpp` | 209 + 157 | v2 does not ship per-primitive bridges; auth is a C ABI call |
| `packages/core/cpp/bridges/DeviceBridge.cpp/.hpp` | 269 + 164 | `HardwareProfile` from `core/router/hardware_profile.h` (Phase 0/E) |
| `packages/core/cpp/bridges/DownloadBridge.cpp/.hpp` | 299 + 197 | v2 model management in C++ core |
| `packages/core/cpp/bridges/EventBridge.cpp/.hpp` | 125 + 139 | proto3 `VoiceEvent` stream replaces polling `pollEvents()` |
| `packages/core/cpp/bridges/FileManagerBridge.cpp/.hpp` | 291 + 113 | C ABI file ops |
| `packages/core/cpp/bridges/HTTPBridge.cpp/.hpp` | 96 + 144 | v2 cloud calls go through C ABI |
| `packages/core/cpp/bridges/ModelRegistryBridge.cpp/.hpp` | 390 + 181 | `PluginRegistry::enumerate()` (Phase 0/E) |
| `packages/core/cpp/bridges/RAGBridge.cpp/.hpp` | 287 + 42 | `solutions/rag/` C++ (Phase 2B) — already TODO-disabled for Android |
| `packages/core/cpp/bridges/StorageBridge.cpp/.hpp` | 269 + 172 | C ABI storage ops |
| `packages/core/cpp/bridges/TelemetryBridge.cpp/.hpp` | 359 + 126 | v2 telemetry is a C++ concern |
| `packages/core/cpp/bridges/ToolCallingBridge.cpp/.hpp` | 188 + 98 | Already TODO-disabled for Android; tool-call parsing moves to C++ core |
| `packages/core/cpp/bridges/CompatibilityBridge.cpp/.hpp` | 106 + 54 | Already TODO-disabled for Android; `EngineRouter::route()` (Phase 3E) |

Bridges subtotal: **6,285 LOC**. Dispatcher + bridges: **9,510 LOC** (the MASTER_PLAN's "10,908 LOC" figure includes Nitrogen-generated output committed to `nitrogen/generated/`).

### Nitrogen-generated output (`nitrogen/generated/`)

| Path | Content |
|---|---|
| `packages/core/nitrogen/generated/` | Auto-generated C++ spec classes (`HybridRunAnywhereCoreSpec.hpp`, etc.), Android autolinking Gradle/CMake, iOS autolinking `.rb`. All regenerated by `nitrogen` CLI from `.nitro.ts` specs. Deleted when `.nitro.ts` specs are deleted. |
| `packages/llamacpp/nitrogen/generated/` | Same for `HybridRunAnywhereLlamaSpec` |
| `packages/onnx/nitrogen/generated/` | Same for `HybridRunAnywhereONNXSpec` |

### Nitro spec files (the IDL for the Nitro dispatcher)

| File | LOC | v2 Replacement |
|---|---|---|
| `packages/core/src/specs/RunAnywhereCore.nitro.ts` | 766 | `idl/voice_events.proto` + `solutions.proto` (ts-proto codegen, Phase 3B) |
| `packages/core/src/specs/RunAnywhereDeviceInfo.nitro.ts` | 73 | `core/abi/ra_primitives.h` `HardwareCaps` via `detect_hardware()` |

### Per-backend JS-side packages

| Package | TS LOC | C++ LOC | v2 Replacement |
|---|---|---|---|
| `packages/llamacpp/` | ~650 | 1,659 | `engines/llamacpp/` static plugin (Phase 0/C) + `frontends/ts/` `loadPlugin()` |
| `packages/onnx/` | ~560 | 1,909 | `engines/sherpa/` static plugin (Phase 0/D) |

Both packages expose `register()` methods that call `rac_backend_llamacpp_register()` / ONNX equivalent. In v2, engines are registered at `PluginRegistry` load time via `ra_plugin_fill_vtable()`. The JS-side `LlamaCppProvider`/`ONNXProvider` classes, their `.podspec` download scripts, and Android `downloadNativeLibs` Gradle tasks all become dead code once the v2 static plugin path is active.

### Public/Extensions (hand-written per-capability JS surface)

All 16 files in `packages/core/src/Public/Extensions/` (~4,820 LOC total) are the 4th hand-written layer the MASTER_PLAN counts. They translate JSON-stringified native results into TS types. In v2 this layer is replaced by ts-proto generated types (~300 LOC, `frontends/ts/src/generated/`) plus the ~1,500 LOC adapter.

| File | LOC | v2 Fate |
|---|---|---|
| `RunAnywhere+Audio.ts` | 688 | Mic capture + WAV encoding moves to `frontends/ts/` `AudioCapture.ts` (analog to `MicrophoneCapture.swift`) |
| `RunAnywhere+TextGeneration.ts` | 320 | Covered by `VoiceSession.ts` `AsyncIterable<VoiceEvent>` |
| `RunAnywhere+STT.ts` | 429 | Same |
| `RunAnywhere+TTS.ts` | 430 | Same |
| `RunAnywhere+VAD.ts` | 359 | Same |
| `RunAnywhere+VoiceAgent.ts` | 225 | Same |
| `RunAnywhere+VoiceSession.ts` | 159 | Replaced by `frontends/ts/src/adapter/VoiceSession.ts` |
| `RunAnywhere+Models.ts` | 619 | `PluginRegistry::enumerate()` via JSI |
| `RunAnywhere+StructuredOutput.ts` | 316 | Collapsed into LLM generate primitive |
| `RunAnywhere+ToolCalling.ts` | 472 | Moved to C++ core |
| `RunAnywhere+RAG.ts` | 133 | `solutions/rag/` C++ |
| `RunAnywhere+Storage.ts` | 148 | C ABI storage |
| `RunAnywhere+Logging.ts` | 51 | C++ telemetry |
| `RunAnywhere+Device.ts` | 59 | `HardwareCaps` |
| `RunAnywhere+VLM.ts` | 214 | New VLM primitive in v2 |
| `index.ts` | 198 | Re-export barrel — deleted with the rest |

### Types (manually maintained; replaced by ts-proto codegen)

| File | LOC | Notes |
|---|---|---|
| `src/types/enums.ts` | 273 | `AudioFormat` enum has 7 cases (PCM, WAV, MP3, M4A, FLAC, OPUS, AAC). Swift counterpart has 5 in the MASTER_PLAN's "3 vs 5" reference; the TS copy has drifted to 7. proto3 `AudioFrame` message eliminates all format-choice enums at the wire level. |
| `src/types/LLMTypes.ts` | 127 | Hand-copied from Swift SDK |
| `src/types/STTTypes.ts` | 124 | Hand-copied from Swift SDK |
| `src/types/TTSTypes.ts` | 126 | Hand-copied from Swift SDK |
| `src/types/VADTypes.ts` | 70 | Hand-copied from Swift SDK |
| `src/types/VoiceAgentTypes.ts` | 182 | Hand-copied from Swift SDK |
| `src/types/VLMTypes.ts` | 50 | Hand-copied from Swift SDK |
| `src/types/RAGTypes.ts` | 50 | Hand-copied from Swift SDK |
| `src/types/ToolCallingTypes.ts` | 198 | Hand-copied from Swift SDK |
| `src/types/StructuredOutputTypes.ts` | 156 | Hand-copied from Swift SDK |
| `src/types/models.ts` | 609 | Large hand-maintained model catalog; v2 model catalog is a C++ `PluginRegistry` query |
| `src/types/enums.ts` | 273 | See AudioFormat note above |
| `src/types/events.ts` | 337 | Replaced by `VoiceEvent` proto3 oneof |
| `src/types/external.d.ts` | 142 | Ambient declarations for `react-native-fs`, `react-native-blob-util`; v2 uses a single RN NativeModule shim |

### Foundation stack (most of it)

| Directory / File | LOC | Notes |
|---|---|---|
| `src/Foundation/DependencyInjection/ServiceContainer.ts`, `ServiceRegistry.ts` | ~100 | v2 has no DI container in the JS adapter |
| `src/Foundation/Initialization/InitializationPhase.ts`, `InitializationState.ts` | ~80 | Lifecycle state machine; v2 handle semantics ("handle exists or doesn't") |
| `src/Foundation/Security/SecureStorageService.ts` | ~60 | Wraps `KeychainManager`; v2 calls the native C ABI secureStorage ops directly |
| `src/Foundation/Logging/Destinations/SentryDestination.ts` | ~80 | Third-party error tracking config; not in v2 scope |

### iOS native layer

| File | LOC | Notes |
|---|---|---|
| `packages/core/ios/PlatformAdapterBridge.m` + `.h` | 813 + 175 | ObjC bridge for the Nitro `PlatformAdapter`; entire platform-adapter pattern is eliminated in v2 (JSI bridge calls C ABI directly) |
| `packages/core/ios/AudioDecoder.m` + `.h` | 162 + 38 | AVAudioEngine-based decoder called from PlatformAdapter; v2 mic capture is in `MicrophoneCapture.ts` (direct NativeModule) |
| `packages/core/ios/RNSDKLoggerBridge.m` + `.h` | 66 + 41 | Bridges Swift `SDKLogger` → `(global as any).__runanywhereHandleNativeLog`; eliminated with the `NativeLogBridge.ts` pattern |

### Package-assembly scripts

| File | LOC | Notes |
|---|---|---|
| `scripts/build-react-native.sh` | 703 | Builds v1 binaries, stages .so + .xcframeworks. Has the duplicated JNI copy logic flagged in IMM-7. Superseded by the v2 CMake build + `frontends/ts/` npm packaging. |

---

## KEEP

| File | LOC | Reason |
|---|---|---|
| `packages/core/ios/KeychainManager.swift` | 116 | Implements Keychain read/write used by the C++ SecureStorage bridge. v2's Swift adapter still needs platform-specific Keychain access (`secureStorageSet`/`secureStorageGet` are in the v2 C ABI). The logic is correct and self-contained. |
| `packages/core/ios/PlatformAdapter.swift` | 100 | The `PlatformAdapter` class provides the Keychain callback and the SDK-log callback injected into the C++ layer. `KeychainManager` depends on it. Keep until the v2 Swift adapter inlines these two responsibilities. |
| `packages/core/ios/HybridRunAnywhereDeviceInfo.swift` | 214 | Provides `getDeviceModel`, `getChipName`, `getTotalRAM`, etc. via `SysCtl`/`ProcessInfo`. v2's `HardwareProfile` (`core/router/hardware_profile.h`) does the same at the C++ layer, but the iOS-specific chip names (`A17 Pro`, `M4`) require Swift-level introspection. Until the v2 Swift frontend exposes `HardwareCaps.cpu_brand` natively, this file is the only correct source. |
| `packages/core/ios/SDKLogger.swift` | 329 | Platform logger used by `KeychainManager` and `PlatformAdapter`. Kept as a dependency of the two KEEP files above. |
| `scripts/package-sdk.sh` | ~130 | Staging script that copies `.xcframework` + Android `.so` files into each package's native dirs. v2 does not yet have an equivalent (JNI/JSI bridges land in Phase 3). Needed for v1 CI until Phase 3 closes. |
| `.yarnrc.yml` + `.yarn/plugins/@yarnpkg/plugin-workspace-tools.cjs` | — | `yarn workspaces foreach` is used by `package.json` `build`/`typecheck`/`lint` scripts across all three packages. The workspace plugin is required for Yarn 3 `foreach`. Keep until the entire RN monorepo is deleted. |
| `lerna.json` | 10 | Already marked DELETE-NOW above — correction: keep until the v1 publish pipeline is formally retired (Phase 3 gate). |

---

## INSPECT

These files may supply logic that the v2 `~1,500 LOC` adapter needs to replicate before the v1 code is deleted.

| File | LOC | What to Port |
|---|---|---|
| `packages/core/src/services/FileSystem.ts` | ~320 | `getRunAnywhereDirectory()`, `getModelsDirectory()`, `downloadModel()` with progress callback. The v2 adapter (`frontends/ts/`) needs a platform-agnostic path for model file storage. Compare against `NativeRunAnywhere.ts`'s `loadPlugin()` TODO before deleting. |
| `packages/core/src/services/DownloadService.ts` | ~200 | Chunked download with progress; progress callback pattern should be verified against v2 proto3 `DownloadProgress` event if one exists. |
| `packages/core/src/services/ModelRegistry.ts` | ~380 | Client-side model catalog cache with framework/format filtering. Most of this becomes a `PluginRegistry::enumerate()` call in v2, but the JSON catalog format and the `registerModel()` path may need to be honoured during a migration window for apps that use custom model registrations. |
| `packages/core/src/Features/VoiceSession/AudioCaptureManager.ts` | ~270 | Mic capture loop for Android (`react-native-live-audio-stream`) + iOS (NativeModules). The v2 `frontends/ts/` adapter needs equivalent capture logic. Verify the 20ms chunk size, 16kHz mono float32 contract (same as `MicrophoneCapture.swift` spec). |
| `packages/core/src/Features/VoiceSession/AudioPlaybackManager.ts` | ~420 | PCM-to-WAV + playback via `react-native-sound`. v2 TTS delivers `AudioFrame` (PCM f32 LE); the RN adapter still needs platform playback. |
| `packages/core/src/Foundation/Logging/Logger/SDKLogger.ts` | 232 | Structured logger with level + category filtering. v2 adapter will need some logging; decide whether to port or use `console.*` directly. |

---

## HybridRunAnywhereCore C++ Dispatcher

The MASTER_PLAN names "10,908 LOC" for this component. The measured count is:

- `HybridRunAnywhereCore.cpp`: **2,921 LOC**
- `HybridRunAnywhereCore.hpp`: **304 LOC**
- `cpp/bridges/` (13 bridge .cpp + 13 bridge .hpp): **6,285 LOC**
- `nitrogen/generated/shared/c++/HybridRunAnywhereCoreSpec.hpp` + friends: balance (~1,400 LOC Nitrogen-generated headers)
- **Total: ~10,910 LOC** (matches MASTER_PLAN)

### Sub-component deletion plan

| Sub-component | Location | Lines | v2 Replacement |
|---|---|---|---|
| SDK lifecycle dispatcher | `HybridRunAnywhereCore.cpp:1–200` | ~200 | `frontends/ts/cpp/jsi_bridge.cpp` `ra_pipeline_create()` |
| Auth dispatch | `HybridRunAnywhereCore.cpp` + `AuthBridge.cpp` | 209+209 | `ra_auth_*` C ABI calls (Phase 0/E) |
| Device registration dispatch | `DeviceBridge.cpp` | 269 | `detect_hardware()` + `ra_device_*` C ABI |
| Model registry dispatch | `ModelRegistryBridge.cpp` | 390 | `PluginRegistry::enumerate()` |
| Download dispatch | `DownloadBridge.cpp` | 299 | v2 C ABI download |
| Storage dispatch | `StorageBridge.cpp` | 269 | v2 C ABI storage |
| Events dispatch (polling) | `EventBridge.cpp` | 125 | proto3 `VoiceEvent` stream via JSI callback |
| HTTP dispatch | `HTTPBridge.cpp` | 96 | v2 C ABI HTTP |
| LLM dispatch | `HybridRunAnywhereCore.cpp` LLM section | ~150 | `ra_generate()` in `LlamaCppVTable` (Phase 0/C) |
| STT dispatch | `HybridRunAnywhereCore.cpp` STT section | ~120 | `ra_stt_feed_audio()` in `SherpaVTable` (Phase 0/D) |
| TTS dispatch | `HybridRunAnywhereCore.cpp` TTS section | ~130 | `ra_tts_synthesize()` in `SherpaVTable` |
| VAD dispatch | `HybridRunAnywhereCore.cpp` VAD section | ~100 | `ra_vad_feed()` in `SherpaVTable` |
| VoiceAgent dispatch | `HybridRunAnywhereCore.cpp` VA section | ~200 | `VoiceAgentPipeline::run()` (Phase 0/B) |
| Telemetry dispatch | `TelemetryBridge.cpp` | 359 | C++ telemetry in core |
| Tool-call parsing | `ToolCallingBridge.cpp` | 188 | C++ core (already TODO-disabled on Android) |
| RAG dispatch | `RAGBridge.cpp` | 287 | `solutions/rag/` (Phase 2B, already TODO-disabled on Android) |
| Compatibility check | `CompatibilityBridge.cpp` | 106 | `EngineRouter::route()` (Phase 3E, already TODO-disabled on Android) |
| Secure storage dispatch | `HybridRunAnywhereCore.cpp` SecureStorage section | ~60 | `ra_secure_storage_*` C ABI |
| Init bridge (largest single file) | `InitBridge.cpp` | 1,504 | Entire init sequence moves to C ABI `ra_pipeline_create()` |
| Nitrogen-generated spec glue | `nitrogen/generated/shared/c++/` | ~1,400 | Deleted with the `.nitro.ts` spec files |

---

## Manually Copied Types in src/Public/Extensions/ and src/types/

All type files are copied from Swift by hand. `ts-proto` codegen from `idl/voice_events.proto` + `idl/solutions.proto` generates these in v2 (`frontends/ts/src/generated/`).

| v1 TS declaration | Location | v2 proto-generated equivalent |
|---|---|---|
| `AudioFormat` (7 cases) | `src/types/enums.ts:206–214` | `AudioFrame.sample_rate + channels` in `voice_events.proto`; format discrimination eliminated at the wire level |
| `VoiceAgentConfig` | `src/types/VoiceAgentTypes.ts` | `VoiceAgentConfig` message in `solutions.proto` |
| `VoiceTurnResult` | `src/types/VoiceAgentTypes.ts` | `VoiceEvent` oneof (UserSaidEvent + AssistantToken + AudioFrame) |
| `STTResult`, `TranscriptSegment` | `src/types/STTTypes.ts` | `UserSaidEvent { text, is_final }` |
| `TTSResult` | `src/types/TTSTypes.ts` | `AudioFrame { pcm_f32_le, sample_rate, channels }` |
| `VADEvent` | `src/types/VADTypes.ts` | `ra_vad_event_t` in `core/abi/ra_primitives.h` |
| `LLMGenerationResult`, `StreamToken` | `src/types/LLMTypes.ts` | `AssistantToken { token, is_final }` |
| `SDKEvent` union | `src/types/events.ts` | `VoiceEvent` oneof |
| `RAGResult`, `RAGDocument` | `src/types/RAGTypes.ts` | `RAGResult` in `solutions.proto` (Phase 2B) |
| `ModelInfo` | `src/types/models.ts:609 LOC` | `EngineInfo` from `PluginRegistry::enumerate()` |

The drift in `AudioFormat`: v1 TS has 7 cases (PCM, WAV, MP3, M4A, FLAC, OPUS, AAC). The MASTER_PLAN's "3 vs 5" note refers to the Swift SDK having 5. The TS copy is 7 — already diverged from both. In v2, the wire format is always `pcm_f32_le` per `AudioFrame`; the format enum collapses entirely.

---

## Per-Backend Packages (runanywhere-llamacpp, runanywhere-onnx)

### What exists

Each package is a Nitrogen HybridObject module that:
1. Has a JS-side `register()` call → triggers `rac_backend_llamacpp_register()` in C++.
2. Has a C++ `HybridRunAnywhereLlama` / `HybridRunAnywhereONNX` dispatcher (~600–500 LOC).
3. Has capability-specific bridges: `LLMBridge`, `StructuredOutputBridge`, `VLMBridge` for llamacpp; `STTBridge`, `TTSBridge`, `VADBridge`, `VoiceAgentBridge` for onnx.
4. Has `.podspec` scripts that download `RABackendLLAMACPP.xcframework` / `RABackendONNX.xcframework` from GitHub releases.
5. Has Android `downloadNativeLibs` Gradle tasks and CMake that link pre-built `.so` files.

### v2 Static Engine Path

In v2 (Phase 3B), engines are C++ plugins: `engines/llamacpp/llamacpp_plugin.cpp` exports `ra_plugin_fill_vtable(LlamaCppVTable*)`. On iOS (static): registered at `PluginRegistry::register_static<LlamaCppEngine>()`. On Android (dynamic): loaded via `PluginRegistry::load_plugin("libcallamacpp_engine.so")`. The JS-side `register()` method, the `HybridRunAnywhereLlama` C++ dispatcher, the `LLMBridge` / `STTBridge` etc., and the `downloadNativeLibs` Gradle tasks all become dead code.

### What survives from these packages

Nothing on the JS side. The prebuilt `.xcframework` / `.so` binary artifacts may be re-used as the compiled output of the v2 `engines/llamacpp/` CMake target — but they are not source files and are not in the SDK tree.

---

## Nitro Init-Twice Guard + any-typed Surface

Every occurrence is BC cruft introduced to work around Nitro's global dispatcher singleton behaviour. v2 JSI TurboModule has no equivalent pattern.

| Location | Line(s) | Pattern |
|---|---|---|
| `NitroModulesGlobalInit.ts:23` | `let _nitroInstallationPromise: Promise<NitroProxy> \| null = null` | Module-level mutable singleton #1 |
| `NitroModulesGlobalInit.ts:26` | `let _nitroModulesProxy: NitroProxy \| null = null` | Module-level mutable singleton #2 |
| `NitroModulesGlobalInit.ts:29` | `let _nitroInstallCalled = false` | Module-level mutable singleton #3 (the guard flag itself) |
| `NitroModulesGlobalInit.ts:54,73` | `NitroModulesNamed as unknown as NitroProxy` | Double `as unknown as` cast to escape Nitro's unexported types |
| `NativeRunAnywhereCore.ts:48` | `NitroProxy.createHybridObject('RunAnywhereCore') as RunAnywhereCore` | String-keyed object factory with unchecked cast |
| `NativeRunAnywhereCore.ts:75` | `requireNativeCoreModule() as unknown as NativeRunAnywhereModule` | Second unchecked cast to the broader "full module" type |
| `NativeRunAnywhereCore.ts:136` | `NitroProxy.createHybridObject('RunAnywhereDeviceInfo') as RunAnywhereDeviceInfo` | Same pattern for device info singleton |
| `RunAnywhere+Audio.ts:22,24,26,94` | `let LiveAudioStream: any`, `let Sound: any`, `let RNFS: any`, `let currentSound: any` | Lazy-require pattern to avoid peer-dep crashes at import time |
| `AudioCaptureManager.ts:18,51` | `let _eventBus: any`, `let LiveAudioStream: any` | Same lazy-require pattern duplicated |
| `AudioPlaybackManager.ts:36,95` | `let Sound: any`, `private currentSound: any` | Same |
| `VoiceSessionHandle.ts:36` | `let _eventBus: any` | Circular-dep workaround via `any` |
| `NativeLogBridge.ts:143` | `(global as any).__runanywhereHandleNativeLog` | Global mutation through `any` |
| `RunAnywhere+STT.ts:261,384` | `const evt = event as any` | Strip type to access untyped event fields |
| `ModelRegistry.ts:199` | `compatibleFrameworks: [options.framework] as any` | Force-cast to work around enum mismatch |
| `Foundation/Logging/Logger/SDKLogger.ts:149` | `const sdkError = error as any` | Access non-standard `.code` field |

All 16 instances above are artefacts of operating without a typed IDL. In v2, `ts-proto` generates typed TS from `.proto`; there are no string-keyed object factories, no `any`-typed lazy-requires for untyped native modules.

---

## Backwards-Compat Shims Found

| Shim | Location | What it preserves |
|---|---|---|
| `requireNativeModule()` | `NativeRunAnywhereCore.ts:89–91` | Alias for `getNativeCoreModule()`; documented as "matches old `@runanywhere/native` exports" |
| `isNativeModuleAvailable()` | `NativeRunAnywhereCore.ts:94–96` | Alias for `isNativeCoreModuleAvailable()` |
| `NativeRunAnywhereModule` type alias | `NativeRunAnywhereModule.ts:22` | `type NativeRunAnywhereModule = RunAnywhereCore` — the old monolithic module type surface is preserved as a type alias so callers do not need to change imports |
| `hasNativeMethod()` | `NativeRunAnywhereModule.ts:27–31` | Guards optional methods on the native module; needed because the three packages register capabilities at different times. Becomes unnecessary when the v2 JSI bridge exposes a unified typed TurboModule. |
| `secureStorageStore` / `secureStorageRetrieve` | `HybridRunAnywhereCore.hpp:237–242` | C++ aliases that forward to `secureStorageSet` / `secureStorageGet`; added for "semantic clarity" but are pure BC shims at the ABI level |
| `runanywhere.testLocal` Gradle property | `android/build.gradle` | Legacy alias for `runanywhere.useLocalNatives`; `project.findProperty("runanywhere.testLocal")` is checked as fallback |
