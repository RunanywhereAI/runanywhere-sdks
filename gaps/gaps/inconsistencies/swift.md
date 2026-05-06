# Swift / iOS SDK — Current Inconsistencies

Updated: 2026-05-05
Branch: `feat/v2-architecture` @ 6217d9e67
Build: **PASS** (`swift build` on Swift 6.3.1 / Xcode 26, clean build 35s). 134 source files compile. Fresh build emits **483 warning lines** covering **28 unique source locations**, dominated by Swift 6 sendability errors-in-waiting on `OpaquePointer` / `UnsafeMutableRawPointer` C-handle captures plus `AVAudioEngine` / `AVAudioInputNode` / `AVSpeechSynthesizer` captures in `AudioCaptureManager` and `SystemTTSService`. SwiftLint: **0 errors, 174 warnings** (blanket_disable_command on generated proto files dominates).

## Current state summary

Swift is a thin platform bridge over the C ABI. All public data types (`RAModelInfo`, `RALLMGenerateRequest`, `RASDKEvent`, `RAVoiceEvent`, `RAHardwareProfile`, `RAStorageInfo`, `RASTTOptions`, `RATTSOptions`, `RAVADOptions`, `RAVLMImage`, `RADiffusionGenerationOptions`, `RARAGConfiguration`, `RAToolDefinition`) come from `Sources/RunAnywhere/Generated/*.pb.swift`; public Swift names (`SDKEnvironment`, `SDKComponent`, `InferenceFramework`, `ModelCategory`, `ModelFormat`, `ChatMessage`, `MessageRole`, `AudioFormat`, `VoiceAgentConfiguration`, `VoiceSessionConfig`, `VoiceAgentResult`, `ComponentLoadState`) are `typealias`es to the generated types. The public API namespace is `enum RunAnywhere` with 40 generated extension files, exposing proto-request entry points (`loadModel(_:)`, `generate(_:)`, `generateStream(_:)`, `transcribe(audio:)`, `synthesize(_:)`, `detectVoiceActivity(_:)`, `processImage(_:)`, `generateImage(options:)`, `ragCreatePipeline(config:)`, `solutions.run(yaml:)`, `lora.apply(_:)`, `hardware.getProfile()`, `pluginLoader.load(path:)`). Errors throw `SDKException` wrapping proto `RASDKError`. Events stream through `EventBus.shared.events: AnyPublisher<RASDKEvent, Never>` backed by the canonical `rac_sdk_event_subscribe` proto-byte callback. XCFramework slices (`ios-arm64`, `ios-arm64-simulator`, `macos-arm64`) are present under `Binaries/RACommons.xcframework/` with ~17.4 MB static archives each.

## Confirmed gaps

(none open)

## Items to DELETE (hard delete, no deprecation)

(none open)

## Cross-SDK naming alignment gaps

| Capability | Swift | Kotlin | Flutter | Web | Status |
|---|---|---|---|---|---|
| **Init** | `RunAnywhere.initialize(apiKey:baseURL:environment:)` | `RunAnywhere.initialize(apiKey, baseURL, environment)` | `RunAnywhereSDK.instance.initialize(...)` | `RunAnywhere.initialize(...)` | OK |
| **Init async** | `completeServicesInitialization()` | `completeServicesInitialization()` | same | same | OK |
| **State** | `isInitialized`, `areServicesReady` | same | same | same | OK |
| **Version** | `RunAnywhere.version` | same | same | same | OK |
| **Events** | `RunAnywhere.events: EventBus` | same (SharedFlow) | same (rxdart) | same (pub/sub) | OK |
| **LLM generate** | `generate(_:)`, `generateStream(_:)` | same | same | same | OK |
| **Tool calling** | `generateWithTools(prompt:options:toolOptions:)` | same | same | same | OK |
| **Structured out** | `generateStructured(prompt:schema:)` | same | same | same | OK |
| **STT** | `transcribe(audio:options:)` | `transcribe(audioData, options)` | same | same | OK |
| **TTS** | `synthesize(_:options:)`, `speak(_:options:)` | same | same | same | OK |
| **VAD** | `detectVoiceActivity(_:options:)` | same | same | same | OK |
| **VLM** | `processImage(_:options:)` | same | same | same | OK |
| **Diffusion** | `generateImage(options:)` | same | same | same | OK |
| **RAG** | `ragCreatePipeline(config:)`, `ragIngest(_:)`, `ragQuery(_:)` | same | same | same | OK |
| **LoRA** | `RunAnywhere.lora.{apply,remove,list,state,…}` (13 methods) | same | same | same | OK |
| **Solutions** | `RunAnywhere.solutions.run(yaml:)` / `run(config:)` | same | same | same | OK |
| **Hardware** | `RunAnywhere.hardware.{getProfile,getAccelerators,setAcceleratorPreference}` | same | same | same | OK |
| **Plugin loader** | `RunAnywhere.pluginLoader.{load,unload,registeredNames,apiVersion}` | same | same | same | OK |
| **Voice agent init from loaded** | `initializeVoiceAgentWithLoadedModels()` | `initializeVoiceAgentWithLoadedModels()` | (unknown) | `initializeVoiceAgentWithLoadedModels()` | OK |
| **Voice agent states** | `getVoiceAgentComponentStates()` | `getVoiceAgentComponentStates()` | (unknown) | `getVoiceAgentComponentStates()` | OK |
| **Storage — clearCache** | `RunAnywhere.clearCache()` (forwards to `CppBridge.FileManager.clearCache()`) | `CppBridgeFileManager.clearCache()` + top-level `RunAnywhere.clearCache()` per header docs | (unknown) | docs advertise | OK |
| **Storage — cleanTempFiles** | `RunAnywhere.cleanTempFiles()` (forwards to `CppBridge.FileManager.clearTemp()`) | (unknown) | (unknown) | docs advertise | OK |
| **Register model (convenience)** | `RunAnywhere.registerModel(id:name:url:framework:…)` top-level | `fun RunAnywhere.registerModel(id, name, url, framework, …)` top-level | (unknown) | (unknown) | OK |

All `RA*` proto typealias names match Kotlin / Flutter / RN / Web conventions. No drift outside the five rows above.

## Example app (iOS) inconsistencies

1. `VoiceAgentViewModel.swift:472,479` contains two comments referring to unexposed symbols: `rac_voice_agent_interrupt(handle)`, `rac_voice_agent_force_commit(handle)`. These are future-work notes and acceptable as-is; flag only if the symbols eventually ship so the example can call the canonical SDK wrapper.

### SWF-THINKING-MIGRATE: `ThinkingContentParser` still binds 3 now-internal C helpers (MEDIUM)

- **Symptom**: `Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+LLMThinking.swift:34,64,85` still calls `rac_llm_extract_thinking`, `rac_llm_split_thinking_tokens`, `rac_llm_strip_thinking`. These three C symbols were downgraded from `RAC_API` to `@internal` on 2026-05-05 under CPP-05 (Wave 1 Row 12, cpp-layer.md). Commons now populates `RALLMGenerationResult.thinking_content` / `.thinking_tokens` / `.response_tokens` / `.text` directly in the proto generate + stream paths.
- **Immediate impact**: Swift still builds against the current XCFramework (pre-rebuild, 2026-05-04). The NEXT XCFramework rebuild will drop the 3 exports and the Apple linker will reject `CppBridge+LLMThinking.swift`.
- **Callers of `ThinkingContentParser` that must also migrate**:
  - `examples/ios/RunAnywhereAI/.../LLMViewModel.swift:740-743` (strip)
  - `examples/ios/RunAnywhereAI/.../LLMViewModel+ToolCalling.swift:56` (extract)
  - `examples/ios/RunAnywhereAI/.../RAGViewModel.swift:38-48` (extract + strip)
  - `Sources/RunAnywhere/CRACommons/include/rac_llm_thinking.h` (copy of header — sync with commons; strip `RAC_API`)
- **Fix steps**:
  1. Delete `Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+LLMThinking.swift`.
  2. Refactor public entry points that used `ThinkingContentParser.extract(from:)` to read `result.thinkingContent` / `result.text` from `RALLMGenerationResult` directly; similarly for `.strip(from:)` / `.splitTokens(...)`.
  3. Update example-app call sites (3 files, ~6 lines) to use the proto-backed `RALLMGenerationResult` fields produced by `RunAnywhere.generate(_:)` / streamed `RALLMStreamEvent`.
  4. Sync `Sources/RunAnywhere/CRACommons/include/rac_llm_thinking.h` to strip `RAC_API` from the 3 decls (mirroring the upstream commons header).
- **Validation**: `swift build` green; `grep -rn "rac_llm_extract_thinking\|rac_llm_strip_thinking\|rac_llm_split_thinking_tokens" sdk/runanywhere-swift/Sources` returns 0 hits; iOS example app builds.
- **Scope**: S (~120 LOC delete + 6 call-site edits).

## Open questions

1. Should `rac_model_compatibility_check_proto` / `rac_embeddings_create_proto` / `rac_model_registry_fetch_assignments_proto` be exported by the XCFramework? `nm` across the `ios-arm64` slice of `RACommons.xcframework` shows non-`_proto` versions are exported (`_rac_embeddings_create`, `_rac_model_registry_fetch_assignments`), but the proto variants are not. The Swift sources do NOT reference the `_proto` symbol names. **Not a Swift gap** — if commons should expose them, that's a commons issue.
2. `Package.swift:50` (local) hard-codes `useLocalNatives = true` for local dev. The root `Package.swift:54` hard-codes it the same way. Release-tag flow needs to flip this automatically for external consumers. No change on this discovery pass; flagging as a persistent release-process question.
3. Both root and local `Package.swift` expose both the monolithic `RunAnywhere` product and the individual backend products (`RunAnywhereCore`, `RunAnywhereLlamaCPP`, `RunAnywhereONNX`, `RunAnywhereMetalRT`, `RunAnywhereWhisperKit`), so external consumers can link per-backend today. Root-level `Active Issues` 002/005 concerns around collapsing backends into monoliths appear resolved; verify against the published artifact before closing them.
