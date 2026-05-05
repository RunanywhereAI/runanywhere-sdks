# Swift / iOS SDK — Current Inconsistencies

Updated: 2026-05-05
Branch: `feat/v2-architecture` @ 6217d9e67
Build: **PASS** (`swift build` on Swift 6.3.1 / Xcode 26, clean build 35s). 134 source files compile. Fresh build emits **483 warning lines** covering **28 unique source locations**, dominated by Swift 6 sendability errors-in-waiting on `OpaquePointer` / `UnsafeMutableRawPointer` C-handle captures plus `AVAudioEngine` / `AVAudioInputNode` / `AVSpeechSynthesizer` captures in `AudioCaptureManager` and `SystemTTSService`. SwiftLint: **0 errors, 174 warnings** (blanket_disable_command on generated proto files dominates).

## Current state summary

Swift is a thin platform bridge over the C ABI. All public data types (`RAModelInfo`, `RALLMGenerateRequest`, `RASDKEvent`, `RAVoiceEvent`, `RAHardwareProfile`, `RAStorageInfo`, `RASTTOptions`, `RATTSOptions`, `RAVADOptions`, `RAVLMImage`, `RADiffusionGenerationOptions`, `RARAGConfiguration`, `RAToolDefinition`) come from `Sources/RunAnywhere/Generated/*.pb.swift`; public Swift names (`SDKEnvironment`, `SDKComponent`, `InferenceFramework`, `ModelCategory`, `ModelFormat`, `ChatMessage`, `MessageRole`, `AudioFormat`, `VoiceAgentConfiguration`, `VoiceSessionConfig`, `VoiceAgentResult`, `ComponentLoadState`) are `typealias`es to the generated types. The public API namespace is `enum RunAnywhere` with 40 generated extension files, exposing proto-request entry points (`loadModel(_:)`, `generate(_:)`, `generateStream(_:)`, `transcribe(audio:)`, `synthesize(_:)`, `detectVoiceActivity(_:)`, `processImage(_:)`, `generateImage(options:)`, `ragCreatePipeline(config:)`, `solutions.run(yaml:)`, `lora.apply(_:)`, `hardware.getProfile()`, `pluginLoader.load(path:)`). Errors throw `SDKException` wrapping proto `RASDKError`. Events stream through `EventBus.shared.events: AnyPublisher<RASDKEvent, Never>` backed by the canonical `rac_sdk_event_subscribe` proto-byte callback. XCFramework slices (`ios-arm64`, `ios-arm64-simulator`, `macos-arm64`) are present under `Binaries/RACommons.xcframework/` with ~17.4 MB static archives each.

## Confirmed gaps

### SWF-SENDABLE-01: 28 Swift 6 sendability warning sites across the bridge surface (MEDIUM)

- **Symptom**: Clean `swift build` against Swift 6.3.1 surfaces 483 warning lines across 28 unique source locations (amplified to 483 because the SDK is built 5x across products). The issues:
  - 20+ `OpaquePointer` / `UnsafeMutableRawPointer` non-Sendable captures in `@Sendable` closures: `CppBridge+Telemetry.swift:75/81/99/117/134/140`, `LLMStreamAdapter.swift:112/163/189`, `VoiceAgentStreamAdapter.swift:95/134/160`, `CppBridge+Download.swift:182`, `CppBridge+SDKEvents.swift:77`, `RunAnywhere+Solutions.swift:35/39/91`, `RunAnywhere+VisionLanguage.swift:17`.
  - `AVAudioEngine` / `AVAudioInputNode` / `AudioCaptureManager` non-Sendable captures in `AudioCaptureManager.swift:163/166/177/9` (module-level `@preconcurrency` missing) and `AudioCaptureManager.swift:507` (`UnsafeMutableRawPointer` from `CFString`).
  - `synthesizer` MainActor-isolated property accessed from nonisolated context at `SystemTTSService.swift:93`.
  - `mutation of captured var 'didInstall' in concurrently-executing code` at `LLMStreamAdapter.swift:70`.
  - `unnecessary check for 'macOS'; enclosing scope ensures guard will always be true` at `SystemFoundationModelsService.swift:64`.
  - `result of call to 'copyBytes(to:from:)' is unused` at `URLSessionHttpTransport.swift:308`.
- **Why it matters**: Swift 6 language mode turns most of these into compile errors. User rule explicitly says "Use the latest Swift 6 APIs always" (see `CLAUDE.md#swift-specific-rules`). Every `@Sendable` closure capturing an opaque C pointer is a future breakage.
- **Fix steps**:
  1. Add a shared `Foundation/Bridge/CSendability.swift` with `extension OpaquePointer: @retroactive @unchecked Sendable {}` and `extension UnsafeMutableRawPointer: @retroactive @unchecked Sendable {}`. Both are safe to send because the C layer owns their lifetime and the Swift layer only threads them through `@convention(c)` trampolines.
  2. Add `@retroactive` to `RunAnywhere+VisionLanguage.swift:17` `extension rac_vlm_image_t: @unchecked Sendable {}`.
  3. In `AudioCaptureManager.swift:9` add `@preconcurrency import AVFoundation` (compiler explicitly suggests this).
  4. In `SystemTTSService.swift:93` wrap the `synthesizer` access in a `MainActor.run { ... }` or mark it `nonisolated(unsafe)` since `AVSpeechSynthesizer` is inherently single-threaded.
  5. Drop the redundant `#available(macOS)` at `SystemFoundationModelsService.swift:64`.
  6. Discard `copyBytes(to:from:)` return at `URLSessionHttpTransport.swift:308` with `_ =`.
  7. Fix `LLMStreamAdapter.swift:70` `didInstall` — mutate inside `state.withLock { }` and return the captured value, don't mutate across concurrent closure scope.
- **Validation**: unique warning sites drops from 28 to under 5 (architecture-specific warnings from DeviceKit tolerable; `@Sendable` / concurrency warnings should be 0).
- **Scope**: M (one dedicated sendability file + ~8 surgical edits).

### SWF-CROSS-01: Missing `initializeVoiceAgentWithLoadedModels()` + `getVoiceAgentComponentStates()` public API (LOW, cross-SDK)

- **Symptom**: `Public/Extensions/VoiceAgent/RunAnywhere+VoiceAgent.swift` exposes only `initializeVoiceAgent(_:)`, `processVoiceTurn(_:)`, `streamVoiceAgent()`, `cleanupVoiceAgent()`. Kotlin (`sdk/runanywhere-kotlin/.../public/extensions/RunAnywhere+VoiceAgent.kt:49,71`) and Web both expose `initializeVoiceAgentWithLoadedModels()` and `getVoiceAgentComponentStates()`. Swift's own `Adapters/VoiceAgentStreamAdapter.swift:13` doc-comment still advertises `RunAnywhere.initializeVoiceAgentWithLoadedModels()` — suggesting Swift used to expose it but it was lost.
- **Why it matters**: Cross-SDK API parity. Example apps that drive load-then-compose voice flows (which the iOS example does) need these as top-level.
- **Fix steps**:
  1. Add `initializeVoiceAgentWithLoadedModels()` static on `RunAnywhere` in `RunAnywhere+VoiceAgent.swift` — builds a `RAVoiceAgentComposeConfig` from currently-loaded model ids (`CppBridge.LLM.shared.currentModelId`, `.STT`, `.TTS`, VAD defaults) and forwards to `initializeVoiceAgent(_:)`.
  2. Add `getVoiceAgentComponentStates() async throws -> RAVoiceAgentComponentStates` static — thin forwarder to the existing `CppBridge.VoiceAgent.shared.componentStatesProto()`.
- **Validation**: `grep "static func initializeVoiceAgentWithLoadedModels\|static func getVoiceAgentComponentStates" sdk/runanywhere-swift/Sources` returns 2 hits.
- **Scope**: S.

### SWF-CROSS-02: Missing `RunAnywhere.clearCache()` / `cleanTempFiles()` top-level API (LOW, cross-SDK)

- **Symptom**: Swift exposes storage ops only through:
  1. The internal `SimplifiedFileManager.shared.clearCache()` / `.cleanTempFiles()` at `Infrastructure/FileManagement/Services/SimplifiedFileManager.swift:127-141`. Declared `public class` with no counterpart in the `RunAnywhere` namespace.
  2. The proto-typed `RunAnywhere.planStorageDelete(_:)` / `deleteStorage(_:)` / `getStorageInfo(_:)` entries in `Public/Extensions/Storage/RunAnywhere+Storage.swift`.
  The iOS example ends up calling `SimplifiedFileManager.shared.clearCache()` directly (`SettingsViewModel.swift:428,439` and `StorageViewModel.swift:64,74`), bypassing the canonical SDK namespace. Kotlin provides `CppBridgeFileManager.clearCache()` at the bridge level and exposes `RunAnywhere.clearCache()` per the documented header at `CRACommons/include/rac_file_manager.h:263`.
- **Why it matters**: Cross-SDK parity.
- **Fix steps**:
  1. Add `public static func clearCache() async throws` and `public static func cleanTempFiles() async throws` on `RunAnywhere` in `Public/Extensions/Storage/RunAnywhere+Storage.swift`, forwarding to `CppBridge.FileManager.clearCache()` / `clearTemp()` (these already exist at the bridge level — see `CppBridge+FileManager.swift:68`).
  2. Downgrade `public class SimplifiedFileManager` to `internal class` (it's SDK-internal plumbing, not user API).
  3. Update the iOS example call sites to use `RunAnywhere.clearCache()` / `RunAnywhere.cleanTempFiles()`.
- **Validation**: `grep "SimplifiedFileManager\." examples/ios/RunAnywhereAI` returns zero matches; iOS example builds.
- **Scope**: S.

### SWF-CROSS-03: Missing `RunAnywhere.registerModel(...)` top-level API (LOW, cross-SDK)

- **Symptom**: Kotlin exposes `fun RunAnywhere.registerModel(...): ModelInfo` as a top-level API (`sdk/runanywhere-kotlin/.../public/extensions/RunAnywhere+ModelManagement.kt:51`). Swift has `RunAnywhere.importModel(_ request: RAModelImportRequest)` at `Public/Extensions/Storage/RunAnywhere+Storage.swift` (correct for file-picker flows) but no terse `registerModel(id:name:url:framework:...)` convenience. The Swift example app CLAUDE.md advertises `RunAnywhere.registerModel(id:name:url:framework:memoryRequirement:supportsThinking:)` as a shim, but the actual example shim file (`RunAnywhere+ExampleShims.swift`, 47 LOC) does not contain it.
- **Why it matters**: Cross-SDK API-shape parity.
- **Fix steps**: Either:
  - (a) Promote by adding `public static func registerModel(id:name:url:framework:...)` that composes an `RAModelImportRequest` internally, OR
  - (b) Add it to `examples/ios/RunAnywhereAI/RunAnywhereAI/Extensions/RunAnywhere+ExampleShims.swift` and clarify in the SDK docs / example CLAUDE.md that it's example-local.
- **Validation**: Cross-SDK naming table below shows aligned rows.
- **Scope**: S.

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
| **Voice agent init from loaded** | **MISSING** | `initializeVoiceAgentWithLoadedModels()` | (unknown) | `initializeVoiceAgentWithLoadedModels()` | **DRIFT** (SWF-CROSS-01) |
| **Voice agent states** | **MISSING** | `getVoiceAgentComponentStates()` | (unknown) | `getVoiceAgentComponentStates()` | **DRIFT** (SWF-CROSS-01) |
| **Storage — clearCache** | Only via internal `SimplifiedFileManager` | `CppBridgeFileManager.clearCache()` + top-level `RunAnywhere.clearCache()` per header docs | (unknown) | docs advertise | **DRIFT** (SWF-CROSS-02) |
| **Storage — cleanTempFiles** | Only via internal `SimplifiedFileManager` | (unknown) | (unknown) | docs advertise | **DRIFT** (SWF-CROSS-02) |
| **Register model (convenience)** | Only `importModel(_ request: RAModelImportRequest)` | `fun RunAnywhere.registerModel(id, name, url, framework, …)` top-level | (unknown) | (unknown) | **DRIFT** (SWF-CROSS-03) |

All `RA*` proto typealias names match Kotlin / Flutter / RN / Web conventions. No drift outside the five rows above.

## Example app (iOS) inconsistencies

1. `examples/ios/RunAnywhereAI/.../SettingsViewModel.swift:428,439` and `.../StorageViewModel.swift:64,74` still call `SimplifiedFileManager.shared.clearCache()` / `cleanTempFiles()` directly. Migration to `RunAnywhere.clearCache()` / `cleanTempFiles()` lands with SWF-CROSS-02.
2. `VoiceAgentViewModel.swift:472,479` contains two comments referring to unexposed symbols: `rac_voice_agent_interrupt(handle)`, `rac_voice_agent_force_commit(handle)`. These are future-work notes and acceptable as-is; flag only if the symbols eventually ship so the example can call the canonical SDK wrapper.

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
2. Should `public class SimplifiedFileManager` lose its `public` modifier? Making it `internal` breaks the example app until SWF-CROSS-02 lands, so the two changes must ship together.
3. `Package.swift:50` (local) hard-codes `useLocalNatives = true` for local dev. The root `Package.swift:54` hard-codes it the same way. Release-tag flow needs to flip this automatically for external consumers. No change on this discovery pass; flagging as a persistent release-process question.
4. Both root and local `Package.swift` expose both the monolithic `RunAnywhere` product and the individual backend products (`RunAnywhereCore`, `RunAnywhereLlamaCPP`, `RunAnywhereONNX`, `RunAnywhereMetalRT`, `RunAnywhereWhisperKit`), so external consumers can link per-backend today. Root-level `Active Issues` 002/005 concerns around collapsing backends into monoliths appear resolved; verify against the published artifact before closing them.
