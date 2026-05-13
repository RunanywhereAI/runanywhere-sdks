# React Native SDK - Swift Alignment Inconsistencies

Updated: 2026-05-13
Scope: `sdk/runanywhere-react-native/`, `examples/react-native/RunAnywhereAI/`, and React Native gap docs.
Source of truth: `sdk/runanywhere-swift/ARCHITECTURE.md`, with C++ commons/proto as the source of truth for domain types, lifecycle contracts, modality request/result shapes, model state, and SDK business logic.

React Native is being aligned deletion-first to the Swift SDK. Swift controls public API shape, folder layout, bridge slices, package split, native ownership, iOS deployment target, and validation expectations. C++/proto controls domain types and business rules. React Native differences are allowed only for Nitro/JSI mechanics, TypeScript facade ergonomics, and platform-native transport/runtime details.

The current direction is aggressive SDK convergence, not compatibility preservation. Old RN aliases, local helper/type barrels, duplicate DTOs, broad convenience exports, and JS-owned SDK business logic should be deleted once Swift/proto-shaped replacements exist.

Do not touch Kotlin, Flutter, Web, Swift, or unrelated commons changes in this lane. Do not revert any other agent's work. No commit is required unless explicitly requested.

## Current Validation Snapshot

- `yarn workspace @runanywhere/proto-ts build`: PASS.
- `yarn workspace @runanywhere/core nitrogen`: PASS.
- `yarn workspace @runanywhere/core typecheck`: PASS.
- `./node_modules/.bin/tsc -b sdk/runanywhere-react-native/packages/core`: PASS.
- `yarn workspace @runanywhere/llamacpp typecheck`: PASS.
- `yarn workspace @runanywhere/onnx typecheck`: PASS.
- `yarn workspace runanywhere-ai-example typecheck`: PASS.
- `yarn typecheck` from `examples/react-native/RunAnywhereAI`: PASS.
- Core lint via package-local eslint, `node_modules/.bin/eslint "packages/core/src/**/*.ts"` from `sdk/runanywhere-react-native`: PASS.
- Workspace script `yarn workspace @runanywhere/core lint` currently fails before linting because eslint is not resolved in that workspace command path; use package-local eslint until the script wiring is fixed.
- Example lint, `yarn lint` from `examples/react-native/RunAnywhereAI`: PASS with 8 warnings and 0 errors.
- `bash scripts/smoke.sh` from `examples/react-native/RunAnywhereAI`: PASS.
- Android RN core native build, from `examples/react-native/RunAnywhereAI/android`: PASS.
- Android RN example `:app:assembleDebug`: PASS.
- iOS CocoaPods refresh with React Native example Podfile: PASS using `pod install`; the refreshed Pods project includes `HybridRunAnywhereCore+PluginLoader.cpp`.
- iOS `RunAnywhereAI` Debug simulator build on isolated DerivedData: PASS after the PluginLoader Pods refresh.
- Android fresh install/launch from the current APK: PASS after fixing internal Nitro initialization in the `RunAnywhere` facade.
- Android real LLM E2E: PASS for `LiquidAI LFM2 350M Q4_K_M` with UI-driven download, selection/load, and generated output. Evidence lives under `test_workflows/logs/20260513-002341-react-native-alignment-smoke/03_react_native_android/`.
- iOS fresh simulator install/launch from the current `.app`: PASS. Evidence lives under `test_workflows/logs/20260513-002341-react-native-alignment-smoke/04_react_native_ios/`.
- Scoped `git diff --check` for RN SDK, RN example, and RN gap docs: PASS after final doc edits.
- Full all-modality E2E is still open until STT, TTS, VAD, VoiceAgent, VLM, RAG, structured output, tool calling, LoRA, Solutions, PluginLoader runtime checks, screenshots, and deeper log review pass on target devices/simulators.

## Completed Alignment In This Pass

- Reduced the root `@runanywhere/core` public export to the Swift-shaped facade: `RunAnywhere`, `SDKEnvironment`, `SDKInitOptions`, SDK errors, `EventBus`, PluginLoader public types, and `ToolExecutor`.
- Added intentional internal subpath export `@runanywhere/core/internal` for sibling provider packages and examples that need Nitro/native/logging/audio plumbing.
- Deleted generic local helper barrels under `packages/core/src/helpers/**`.
- Deleted local duplicate type barrels `packages/core/src/types/index.ts` and `packages/core/src/types/enums.ts`.
- Deleted public compatibility paths for `RunAnywhere.Audio`, `LiveTranscriptionSession`, and VLM model aliases.
- Moved audio utility code into `Internal/Audio/AudioUtilities.ts`.
- Moved handwritten Nitro accessor specs out of `src/generated` into `Internal/Nitro`.
- Moved SDK event extension to the Swift-shaped `Public/Extensions/Events/RunAnywhere+SDKEvents.ts`.
- Added Swift-shaped `Public/Events/EventBus.ts`.
- Removed stale public aliases from LLM: `chat`, `isModelLoaded`, `unloadModel`, and `currentLLMModel`.
- Removed stale public aliases from STT: `isSTTModelLoaded`, `unloadSTTModel`, `transcribeSimple`, `transcribeBuffer`, `transcribeFile`, and `currentSTTModel`.
- Removed stale public aliases from TTS: `isTTSModelLoaded`, `isTTSVoiceLoaded`, `unloadTTSModel`, `availableTTSVoices`, `getTTSVoiceInfo`, `synthesizeStreamAsync`, `isSpeaking`, `cleanupTTS`, and `currentTTSModel`.
- Removed stale public aliases from VAD: `isVADModelLoaded`, `unloadVADModel`, `detectSpeech`, `streamVADActivity`, and `getVADStatistics`.
- Removed stale public aliases from VLM: `registerVLMBackend`, `loadVLMModel`, `loadVLMModelById`, `isVLMModelLoaded`, `unloadVLMModel`, `describeImage`, and `askAboutImage`.
- Removed stale public aliases from VoiceAgent: `areAllVoiceComponentsReady`, `isVoiceAgentReady`, `voiceAgentTranscribe`, and `voiceAgentSynthesizeSpeech`.
- Kept VoiceAgent handle access private to the extension implementation rather than public API.
- Removed public structured-output convenience aliases that Swift does not expose: prompt builders, entity extraction, classification, and validation helpers.
- Added Swift-shaped `generateWithStructuredOutput` beside `generateStructured`, `generateStructuredStream`, and `extractStructuredOutput`.
- Removed public tool-calling parser/formatter/validator helpers and deleted `continueWithToolResult`.
- Removed model lifecycle alias methods and kept Swift-shaped `loadModel`, `unloadModel`, `currentModel`, and `componentLifecycleSnapshot`.
- Removed registry deletion/cancellation aliases from public `RunAnywhere`; cancellation now uses async iterator `return()` and deletion uses storage APIs.
- Added native-backed PluginLoader Nitro methods for API version, registered count, registered names, loaded plugins, load, and unload.
- Added C++ PluginLoader bridge implementation over the C plugin loader ABI.
- Regenerated Nitro output after PluginLoader spec changes.
- Refreshed iOS Pods so `HybridRunAnywhereCore+PluginLoader.cpp` is part of the iOS build.
- Moved Nitro global initialization inside `RunAnywhere.initialize()` so internal Nitro plumbing can stay out of the public root without breaking app startup.
- De-publicized provider classes from LlamaCPP and ONNX package roots while preserving registration facades.
- Migrated provider package imports to `@runanywhere/core/internal` and generated proto enums/types.
- Migrated the RN example source off deleted root APIs and local SDK type barrels.
- Added example lifecycle utility using `RunAnywhere.currentModel` and `RunAnywhere.unloadModel`.
- Updated example STT/TTS/VLM/VoiceAgent/Settings/Chat paths to call Swift-shaped public methods.
- Renamed example VLM service usage from `describeImage` to `processImage`.
- Updated RN SDK docs, package docs, backend docs, example docs, and smoke script away from deleted public names.

## Remaining Current Inconsistencies

### Public API And File Organization

- `SDKInitOptions` still lives in `packages/core/src/types/models.ts`; decide whether this should move to a Swift-shaped public configuration file or become generated proto input.
- `Public/Configuration/SDKEnvironment.ts` exists as a Swift-shaped file, but root currently exports `SDKEnvironment` directly from proto-ts. Decide whether the file should be kept as a source-compatible wrapper or deleted.
- `Foundation/**`, `services/**`, `native/**`, `Adapters/**`, and `Features/**` still exist inside the package. They are no longer root public API, but each file still needs a Swift-by-file keep/delete/internal-location audit.
- `Foundation/DependencyInjection/index.ts`, `Foundation/index.ts`, `Features/index.ts`, `services/index.ts`, and `services/Network/index.ts` are now mostly index shells. Delete them if no package-internal imports require them.
- Logging is still partly TypeScript-owned. Verify redaction, destinations, severity mapping, and native log forwarding against Swift logging helpers.
- `SecureStorageService`, `SecureStorageKeys`, `SecureStorageError`, and `DeviceIdentity` remain package-internal code. Confirm whether each is needed as RN-native glue or should be deleted in favor of native auth/device ownership.

### Initialization, Auth, Device, And Network

- `RunAnywhere.initialize()` still builds JSON for the native bridge. Swift parity wants generated init proto bytes or a clearly documented RN-native adapter exception.
- Phase 2 service initialization is serialized in TypeScript, but the native bridge returns an ad hoc boolean/unknown result. Align the return shape with Swift/native proto state.
- JS initialization state still mirrors native state and can drift if native initialization changes underneath it.
- Auth/user/org/device getters still call string/boolean bridge methods rather than generated proto request/result bytes.
- Network configuration remains a TypeScript helper for base URL and credential normalization. Confirm it contains no endpoint routing or SDK-owned network behavior.

### Native Bridge And Modalities

- RN has proto compatibility helpers, but it still lacks one central Swift-style native proto ABI helper used consistently by every C++ bridge file.
- Init/auth/device/model registry/storage/download/event bridge methods still include JSON or ad hoc shapes that need a Swift source-of-truth pass.
- Tool calling still owns the generate/parse/execute/follow-up loop in TypeScript. C++ now owns parsing and prompt formatting, but final orchestration should move native/proto-side with JS limited to executor callback dispatch.
- RAG helper and metadata migration logic still need a Swift parity audit and deletion pass.
- LoRA helper/public methods still need a Swift parity audit.
- LLM and VoiceAgent streaming fan-out semantics still need proof against Swift expectations.
- PluginLoader is now native-backed, but runtime E2E coverage and typed unavailable-path behavior still need proof on Android and iOS.
- Unsupported/unavailable native feature paths need typed `SDKException` parity rather than generic `Error` paths.

### Examples, Docs, Packaging, Validation

- React Native SDK docs have been cleaned of the deleted public API names, but examples should remain a next-step migration lane because UX screens still include example-local abstractions and demo-specific helpers.
- Example app follow-up should focus on source-of-truth model selection, real asset download/load UX, and removing demo-only lifecycle assumptions where native SDK state can be queried directly.
- `gaps/gaps/file organization/react-native.md` was referenced in an earlier request but is not present in this checkout; only the inconsistency and PR review docs exist under the supplied paths.
- Android and iOS static/native builds pass, Android LLM download/load/inference passes, and iOS launch smoke passes. Remaining E2E work is the all-modality matrix plus iOS model inference.
- No commit has been created.

## Remaining Agent Todo List

Each item is sized for one agent. Agents may spawn subagents internally, but must stay in the React Native lane and must not revert Kotlin, Flutter, Swift, Web, or unrelated changes.

### Phase 1 - Public Surface Finalization

- RN-1001: Compare root `packages/core/src/index.ts` export by export against Swift `ARCHITECTURE.md`.
- RN-1002: Decide whether `SDKInitOptions` belongs in `Public/Configuration`, generated proto-ts, or an RN-only internal type.
- RN-1003: Move or delete `packages/core/src/types/models.ts` after `SDKInitOptions` ownership is decided.
- RN-1004: Decide whether `Public/Configuration/SDKEnvironment.ts` should become the public re-export path or be deleted.
- RN-1005: Check root `ErrorCode`, `ErrorCategory`, and `SDKException` naming against Swift `RASDKError` naming.
- RN-1006: Audit `EventBus` type names and cancellation names against Swift event subscription naming.
- RN-1007: Audit root `PluginInfo` and `PluginLoaderCapability` names against Swift PluginLoader naming.
- RN-1008: Audit root `ToolExecutor` as the only RN-local public type because function references cannot be generated proto values.
- RN-1009: Run a root-export stale API scan after every public surface change.
- RN-1010: Update README import examples whenever root exports change.

### Phase 2 - Internal File Deletion Audit

- RN-2001: Audit `Foundation/index.ts` for remaining imports and delete if unused.
- RN-2002: Audit `Foundation/DependencyInjection/index.ts` and delete if it only points at deleted DI files.
- RN-2003: Audit `Features/index.ts` and delete if package-internal imports can use direct files.
- RN-2004: Audit `Features/VoiceSession/AudioCaptureManager.ts` for Swift parity or delete in favor of example-local audio capture.
- RN-2005: Audit `Features/VoiceSession/AudioPlaybackManager.ts` for Swift parity or delete in favor of example-local audio playback.
- RN-2006: Audit `services/index.ts` and delete if unused.
- RN-2007: Audit `services/Network/index.ts` and delete if unused.
- RN-2008: Audit `services/Network/NetworkConfiguration.ts` for endpoint/routing behavior and keep only RN-native config normalization.
- RN-2009: Audit `Internal/AudioFileReader.ts` and keep only if examples or RN bridge still need host-file byte loading.
- RN-2010: Audit `Adapters/LLMStreamAdapter.ts` for Swift streaming fan-out parity.
- RN-2011: Audit `Adapters/VoiceAgentStreamAdapter.ts` for Swift streaming fan-out parity.
- RN-2012: Delete any internal barrel that exists only to preserve old import paths.
- RN-2013: Run `rg` for deleted public names after internal deletion.
- RN-2014: Run core and example typechecks after each deletion batch.

### Phase 3 - Initialization, Auth, Device, Network

- RN-3001: Define a generated init request/result shape or document why RN initialization must stay JSON.
- RN-3002: Replace `native.initialize(configJson)` with proto bytes if the C++ ABI supports it.
- RN-3003: Align `completeServicesInitialization` result shape with Swift/native state rather than boolean/unknown.
- RN-3004: Move initialization state ownership native-side or prove the JS mirror cannot drift.
- RN-3005: Convert `getUserId` to a generated auth/user proto request when available.
- RN-3006: Convert `getOrganizationId` to a generated auth/org proto request when available.
- RN-3007: Convert `isAuthenticated` to a generated auth state proto request when available.
- RN-3008: Convert `isDeviceRegistered` to a generated device state proto request when available.
- RN-3009: Convert `getDeviceId`/`deviceId` to a generated device proto request when available.
- RN-3010: Verify DeviceIdentity fields against Swift's native device model field-for-field.
- RN-3011: Delete JS device persistence if native owns stable device identity.
- RN-3012: Delete JS secure storage surfaces that duplicate native auth/device storage.
- RN-3013: Verify network/base URL behavior has no JS-owned endpoint table.
- RN-3014: Verify telemetry/logging upload behavior is native-owned.

### Phase 4 - Native ABI Centralization

- RN-4001: Add a central C++ `NativeProtoABI` helper matching Swift allocation/free/call patterns.
- RN-4002: Refactor lifecycle proto bridge calls through `NativeProtoABI`.
- RN-4003: Refactor storage proto bridge calls through `NativeProtoABI`.
- RN-4004: Refactor download proto bridge calls through `NativeProtoABI`.
- RN-4005: Refactor registry proto bridge calls through `NativeProtoABI`.
- RN-4006: Refactor event proto bridge calls through `NativeProtoABI`.
- RN-4007: Refactor STT proto bridge calls through `NativeProtoABI`.
- RN-4008: Refactor TTS proto bridge calls through `NativeProtoABI`.
- RN-4009: Refactor VAD proto bridge calls through `NativeProtoABI`.
- RN-4010: Refactor VLM proto bridge calls through `NativeProtoABI`.
- RN-4011: Refactor structured-output proto bridge calls through `NativeProtoABI`.
- RN-4012: Refactor tool-calling proto bridge calls through `NativeProtoABI`.
- RN-4013: Refactor PluginLoader bridge error conversion through the same typed error path.
- RN-4014: Regenerate Nitro after any spec changes.
- RN-4015: Rebuild Android and iOS after bridge centralization.

### Phase 5 - Feature Logic Ownership

- RN-5001: Move tool-calling orchestration out of TypeScript and into native/proto flow.
- RN-5002: Keep JavaScript tool execution as callback trampoline only.
- RN-5003: Add ToolValue JSON/proto bridge parity if Swift exposes ToolValue helpers.
- RN-5004: Delete TypeScript follow-up prompt orchestration after native run-loop lands.
- RN-5005: Audit RAG create/destroy/ingest/query names against Swift exactly.
- RN-5006: Move any RAG metadata migration or helper business logic out of JS.
- RN-5007: Audit LoRA public method names against Swift exactly.
- RN-5008: Move LoRA helper business logic out of JS if commons/proto owns it.
- RN-5009: Prove LLM stream cancellation and fan-out match Swift.
- RN-5010: Prove VoiceAgent stream cancellation and fan-out match Swift.
- RN-5011: Prove VAD stream cancellation and event shapes match Swift.
- RN-5012: Prove VLM stream cancellation and event shapes match Swift.
- RN-5013: Prove structured-output stream event names and final-result semantics match Swift.
- RN-5014: Prove PluginLoader load/unload/list methods work on both Android and iOS or return typed unavailable errors.
- RN-5015: Convert remaining generic `Error` throws in public extension paths to `SDKException` parity.

### Phase 6 - Example App Next-Step Lane

- RN-6001: Treat the example app as the next migration lane after SDK pruning, not as backwards-compatibility protection.
- RN-6002: Replace example-local `isModelLoadedForCategory` helper with direct screen calls if Swift-shaped lifecycle calls are clear enough.
- RN-6003: Replace example-local `unloadModelsForCategory` helper with direct screen calls if Swift-shaped lifecycle calls are clear enough.
- RN-6004: Audit Chat screen for remaining demo-only model assumptions.
- RN-6005: Audit STT screen for file/audio-byte conversion ownership.
- RN-6006: Audit TTS screen for playback ownership and native TTS output semantics.
- RN-6007: Audit Settings screen for download cancellation using iterator `return()`.
- RN-6008: Audit Settings screen for deletion using `deleteStorage`.
- RN-6009: Audit VoiceAssistant screen against Swift VoiceAgent flow names.
- RN-6010: Audit VLM screen and hook names against `processImage`/`processImageStream`.
- RN-6011: Audit model selection components for generated proto enum names only.
- RN-6012: Remove demo-only wrappers if they hide canonical `RunAnywhere` names.
- RN-6013: Update screenshots/test scripts after example migration.

### Phase 7 - Documentation And Packaging

- RN-7001: Keep root RN README imports limited to `@runanywhere/core` root exports plus generated `@runanywhere/proto-ts/*` types.
- RN-7002: Keep core README public API examples limited to Swift-shaped public names.
- RN-7003: Keep LlamaCPP README free of provider class exports.
- RN-7004: Keep ONNX README/source docs free of deleted STT/TTS aliases.
- RN-7005: Document `@runanywhere/core/internal` as internal package plumbing only.
- RN-7006: Audit package `files` entries after deleted helpers/types.
- RN-7007: Audit podspec source globs after new C++ bridge files.
- RN-7008: Audit Android CMake globs after new C++ bridge files.
- RN-7009: Keep `scripts/package-sdk.sh` product staging aligned with Swift package ownership.
- RN-7010: Keep gap docs current-only after every alignment pass.

### Phase 8 - Full E2E Validation

- RN-8001: Run core typecheck.
- RN-8002: Run LlamaCPP package typecheck.
- RN-8003: Run ONNX package typecheck.
- RN-8004: Run RN example typecheck.
- RN-8005: Run package-local core eslint until workspace lint script is fixed.
- RN-8006: Run RN example lint and record warning count.
- RN-8007: Run Nitro generation/validation after spec changes.
- RN-8008: Run Android core native build.
- RN-8009: Run Android example debug build.
- RN-8010: Run `pod install` after podspec/source changes.
- RN-8011: Run iOS simulator Debug build on isolated DerivedData.
- RN-8012: Run scoped `git diff --check`.
- RN-8013: Fresh uninstall Android example from connected/authorized device or emulator.
- RN-8014: Fresh install Android debug APK.
- RN-8015: Start continuous Android logs before launch.
- RN-8016: Launch Android app and verify no native crash or JS red screen.
- RN-8017: Fresh install iOS simulator app.
- RN-8018: Start continuous iOS simulator logs before launch.
- RN-8019: Launch iOS app and verify no native crash or JS red screen.
- RN-8020: Download/import one LLM model through SDK-owned native flow.
- RN-8021: Load the LLM model through lifecycle.
- RN-8022: Run real LLM inference.
- RN-8023: Download/load and run real STT inference if assets are available.
- RN-8024: Download/load and run real TTS inference if assets are available.
- RN-8025: Download/load and run real VAD inference if assets are available.
- RN-8026: Download/load and run real VLM inference if assets are available.
- RN-8027: Run real structured-output inference.
- RN-8028: Run real tool-calling flow.
- RN-8029: Run real RAG ingestion/query flow if embedding assets are available.
- RN-8030: Run real VoiceAgent flow if STT/LLM/TTS assets are available.
- RN-8031: Run PluginLoader runtime checks or typed unavailable checks.
- RN-8032: Capture screenshots for launch, download/load, and inference result.
- RN-8033: Review logs for missing symbols, native crashes, bridge exceptions, JS red screens, and silent no-op behavior.
