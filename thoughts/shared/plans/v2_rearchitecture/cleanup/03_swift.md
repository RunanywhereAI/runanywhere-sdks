# runanywhere-swift — v1/v2 cleanup audit

## Summary

- **Total v1 Swift LOC audited:** ~24,922 (Sources + Tests) plus 844 LOC of distribution scripts, 97 C headers, and ~7,000 LOC of Binaries artifacts.
- **DELETE-NOW:** ~18,700 LOC (~75 %) — all bridge logic (CppBridge + rac_* headers), every `RunAnywhere+*` public extension, and the distribution scripts are fully superseded by `frontends/swift/` and `core/abi/`.
- **DELETE-AFTER-V2-ENGINES:** ~3,500 LOC (~14 %) — the audio capture/playback platform code and the WhisperKit runtime wrapper; v2 owns the concept but Phase 1 bridge stubs aren't wired yet.
- **KEEP:** ~2,700 LOC (~11 %) — `AudioCaptureManager` / `AudioPlaybackManager` contain platform knowledge the v2 `AudioSession.swift` + `MicrophoneCapture.swift` should absorb but have not yet fully replaced; `SDKLogger` OS subsystem wiring; `KeychainManager` is still referenced by v1 examples.
- **INSPECT:** 3 items — `SystemFoundationModelsService`, `DiffusionPlatformService`, `LiveTranscriptionSession`. These are capabilities with no v2 equivalent yet.

---

## DELETE-NOW

All files here are direct implementations of the rac_* C ABI or the hand-written Swift-to-C dispatch layer. Once `frontends/swift/` owns the L6 adapter role, none of these have any consumer.

| Path (relative to `sdk/runanywhere-swift/`) | Lines | Reason | Replaced by |
|---|---|---|---|
| `Sources/RunAnywhere/Foundation/Bridge/CppBridge.swift` | 209 | Central rac_* dispatch coordinator | `frontends/swift/Sources/RunAnywhere/Adapter/RunAnywhere.swift` |
| `Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+Auth.swift` | 297 | rac_auth_* callbacks | auth moves into C++ core; no L6 equivalent needed |
| `Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+Device.swift` | 275 | rac_device_* callbacks | HardwareProfile in `core/router/hardware_profile.h` |
| `Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+Diffusion.swift` | 451 | rac_diffusion_* callbacks | not yet in v2 scope |
| `Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+Download.swift` | 313 | rac_download_* callbacks | model registry moves to C++ core |
| `Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+Environment.swift` | 149 | rac_environment/dev_config | C++ core owns config |
| `Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+FileManager.swift` | 265 | rac_file_manager callbacks | C++ core owns file I/O |
| `Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+HTTP.swift` | 42 | rac_http_client callback | C++ core owns network |
| `Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+LLM.swift` | 191 | rac_llm_* handle management | `engines/llamacpp` plugin + `core/abi/ra_primitives.h` |
| `Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+LoraRegistry.swift` | 109 | rac_lora_registry callbacks | C++ engine plugin |
| `Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+ModelAssignment.swift` | 227 | rac_model_assignment callbacks | `core/router` |
| `Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+ModelPaths.swift` | 181 | rac_model_paths callbacks | C++ core model registry |
| `Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+ModelRegistry.swift` | 362 | rac_model_registry callbacks | C++ core model registry |
| `Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+Platform.swift` | 615 | rac_llm_platform / rac_tts_platform | engines/sherpa + engines/llamacpp |
| `Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+PlatformAdapter.swift` | 559 | rac_platform_adapter callbacks | `frontends/swift/Adapter/AudioSession.swift` |
| `Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+RAG.swift` | 143 | rac_rag_pipeline lifecycle | `solutions/rag/` |
| `Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+Services.swift` | 322 | rac_* service registry | PluginRegistry in `core/registry/` |
| `Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+State.swift` | 369 | rac_sdk_state management | eliminated; v2 has no public state machine |
| `Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+Storage.swift` | 282 | rac_storage_analyzer | C++ core |
| `Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+Strategy.swift` | 76 | rac_model_strategy callbacks | `core/router/engine_router.h` |
| `Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+STT.swift` | 127 | rac_stt_* handle management | `engines/sherpa` plugin |
| `Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+Telemetry.swift` | 499 | rac_telemetry_* / rac_analytics_events callbacks | C++ core |
| `Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+ToolCalling.swift` | 323 | rac_tool_calling callbacks | LLM plugin (llama.cpp tool call parsing) |
| `Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+TTS.swift` | 103 | rac_tts_* handle management | `engines/sherpa` plugin |
| `Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+VAD.swift` | 157 | rac_vad_* handle management | `engines/sherpa` plugin |
| `Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+VLM.swift` | 196 | rac_vlm_* handle management | not yet in v2 scope |
| `Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+VoiceAgent.swift` | 83 | rac_voice_agent_create/cleanup | `core/voice_pipeline/voice_pipeline.cpp` via `ra_pipeline.h` |
| `Sources/RunAnywhere/Foundation/Bridge/Extensions/ModelTypes+CppBridge.swift` | 382 | Swift↔C type conversions for all rac_* types | proto3-generated types from `idl/codegen/generate_swift.sh` |
| `Sources/RunAnywhere/CRACommons/` (entire directory) | ~97 headers | 78 rac_* headers in CRACommons + 5 in LlamaCPP + 11 in ONNX + 3 in MetalRT | `core/abi/ra_primitives.h`, `ra_pipeline.h`, `ra_plugin.h` |
| `Sources/RunAnywhere/Public/RunAnywhere.swift` | 492 | v1 public entry point wrapping all CppBridge calls | `frontends/swift/Sources/RunAnywhere/Adapter/RunAnywhere.swift` (142 LOC) |
| `Sources/RunAnywhere/Public/Extensions/LLM/LLMTypes.swift` | 644 | v1 LLM request/response types | proto3 `AssistantToken`, `VoiceAgentConfig` etc. |
| `Sources/RunAnywhere/Public/Extensions/LLM/RunAnywhere+TextGeneration.swift` | 545 | generate() / streamGenerate() over rac_llm | `VoiceSession.run()` in v2 |
| `Sources/RunAnywhere/Public/Extensions/LLM/RunAnywhere+LoRA.swift` | 74 | LoRA adapter loading over rac_lora_registry | C++ engine plugin |
| `Sources/RunAnywhere/Public/Extensions/LLM/RunAnywhere+StructuredOutput.swift` | 290 | structured output over rac_llm | C++ LLM plugin |
| `Sources/RunAnywhere/Public/Extensions/LLM/RunAnywhere+ToolCalling.swift` | 352 | tool calling dispatch over rac_tool_calling | C++ LLM plugin |
| `Sources/RunAnywhere/Public/Extensions/LLM/ToolCallingTypes.swift` | 410 | v1 tool-call Swift types | proto3-generated |
| `Sources/RunAnywhere/Public/Extensions/STT/RunAnywhere+STT.swift` | 318 | transcribe() / streamTranscribe() over rac_stt | `VoiceSession` event stream |
| `Sources/RunAnywhere/Public/Extensions/STT/STTTypes.swift` | 334 | v1 STT Swift types | proto3 `TranscriptChunk` |
| `Sources/RunAnywhere/Public/Extensions/TTS/RunAnywhere+TTS.swift` | 318 | synthesize() over rac_tts | `VoiceSession` event stream |
| `Sources/RunAnywhere/Public/Extensions/TTS/TTSTypes.swift` | 463 | v1 TTS Swift types | proto3 `AudioFrame` |
| `Sources/RunAnywhere/Public/Extensions/VAD/RunAnywhere+VAD.swift` | 201 | VAD pipeline over rac_vad | C++ pipeline internal |
| `Sources/RunAnywhere/Public/Extensions/VAD/VADTypes.swift` | 241 | v1 VAD Swift types | proto3 `VADEvent` |
| `Sources/RunAnywhere/Public/Extensions/RAG/RunAnywhere+RAG.swift` | 111 | RAG pipeline over rac_rag | `solutions/rag/` + v2 `VoiceSession` |
| `Sources/RunAnywhere/Public/Extensions/RAG/RAGTypes.swift` | 284 | v1 RAG Swift types | proto3 `RAGConfig` |
| `Sources/RunAnywhere/Public/Extensions/RAG/RAGEvents.swift` | 109 | v1 RAG event types | proto3 `VoiceEvent` |
| `Sources/RunAnywhere/Public/Extensions/Models/RunAnywhere+ModelManagement.swift` | 489 | model download/load/unload over rac_* | C++ model registry |
| `Sources/RunAnywhere/Public/Extensions/Models/RunAnywhere+ModelAssignments.swift` | 284 | model assignment over rac_model_assignment | `core/router/engine_router.h` |
| `Sources/RunAnywhere/Public/Extensions/Models/RunAnywhere+Frameworks.swift` | 66 | backend framework registration | `frontends/swift/Adapter/RegistrationBuilder.swift` (22 LOC) |
| `Sources/RunAnywhere/Public/Extensions/Models/ModelTypes.swift` | 515 | v1 ModelSpec, ModelInfo, etc. | proto3 `ra_model_spec_t` + v2 config structs |
| `Sources/RunAnywhere/Public/Extensions/Storage/RunAnywhere+Storage.swift` | 113 | storage analysis over rac_storage_analyzer | C++ core |
| `Sources/RunAnywhere/Public/Extensions/Storage/StorageTypes.swift` | 204 | v1 storage Swift types | eliminated |
| `Sources/RunAnywhere/Public/Extensions/VoiceAgent/RunAnywhere+VoiceAgent.swift` | 284 | startVoiceSession() factory + model-load logic | `RunAnywhere.solution()` in v2 |
| `Sources/RunAnywhere/Public/Extensions/VoiceAgent/VoiceAgentTypes.swift` | 269 | VoiceSessionConfig, VoiceSessionEvent, VoiceSessionError | `VoiceSession.Event` + `VoiceAgentConfig` in v2 |
| `Sources/RunAnywhere/Public/Extensions/RunAnywhere+Logging.swift` | 57 | setLogLevel() over rac_logger | C++ core logging |
| `Sources/RunAnywhere/Public/Events/EventBus.swift` | 76 | v1 event bus | eliminated; v2 uses `AsyncThrowingStream` |
| `Sources/RunAnywhere/Public/Configuration/SDKEnvironment.swift` | 245 | environment config wired to rac_environment | C++ core |
| `Sources/RunAnywhere/Public/Sessions/LiveTranscriptionSession.swift` | 299 | streaming STT session over rac_stt | v2 `VoiceSession.run()` |
| `Sources/RunAnywhere/Data/Network/Services/HTTPService.swift` | 321 | HTTP transport wired via rac_http_client | C++ core owns HTTP |
| `Sources/RunAnywhere/Data/Network/Protocols/NetworkService.swift` | 60 | v1 network protocol | eliminated |
| `Sources/RunAnywhere/Data/Network/Models/Auth/AuthenticationResponse.swift` | 44 | auth response model | C++ core |
| `Sources/RunAnywhere/Foundation/Errors/CommonsErrorMapping.swift` | 497 | rac_error_code → SDKError mapping | v2 uses proto3 `ErrorEvent` + `RunAnywhereError` |
| `Sources/RunAnywhere/Foundation/Errors/ErrorCategory.swift` | 59 | v1 error category enum | `RunAnywhereError` in v2 |
| `Sources/RunAnywhere/Foundation/Errors/ErrorCode.swift` | 318 | v1 error code enum | `RunAnywhereError` in v2 |
| `Sources/RunAnywhere/Foundation/Constants/SDKConstants.swift` | 36 | v1 constants (server URLs, timeouts) | C++ core config |
| `Sources/RunAnywhere/Core/Module/RunAnywhereModule.swift` | 55 | v1 module system | RegistrationBuilder in v2 |
| `Sources/RunAnywhere/Core/Types/ComponentTypes.swift` | 83 | v1 ComponentType enum | PluginRegistry categories |
| `Sources/RunAnywhere/Core/Types/AudioTypes.swift` | 68 | v1 AudioFormat/SampleRate types | proto3 `AudioFrame` |
| `Sources/LlamaCPPRuntime/LlamaCPP.swift` | 164 | Swift registration of RABackendLLAMACPP.xcframework | `engines/llamacpp` C plugin |
| `Sources/LlamaCPPRuntime/include/` (5 headers) | 5 files | rac_llm_llamacpp.h etc. | `core/abi/` via `LlamaCppVTable` |
| `Sources/ONNXRuntime/ONNX.swift` | 146 | Swift registration of RABackendONNX.xcframework | `engines/sherpa` C plugin |
| `Sources/ONNXRuntime/include/` (11 headers) | 11 files | rac_stt_onnx.h, rac_tts_onnx.h, rac_vad_onnx.h etc. | `core/abi/` via `SherpaVTable` |
| `Sources/MetalRTRuntime/MetalRT.swift` | 127 | Swift registration of RABackendMetalRT.xcframework | future L1 Metal runtime in `runtimes/` |
| `Sources/MetalRTRuntime/include/` (3 headers) | 3 files | rac_backend_metalrt.h etc. | future `runtimes/metal/` |
| `scripts/build-swift.sh` | 501 | builds commons → Binaries/ XCFrameworks → Package.swift toggle | `cmake --preset ios-release` + `xcodebuild -create-xcframework` per Phase 1C |
| `scripts/package-sdk.sh` | 85 | zips XCFrameworks for GitHub release | CMake-based release CI |
| `scripts/create-onnxruntime-xcframework.sh` | 258 | assembles split ONNX Runtime XCFramework | vcpkg provides ORT; sherpa-onnx already embeds it |
| `Binaries/RACommons.xcframework` | binary | pre-built v1 commons binary | CMake-built `RunAnywhereCore.xcframework` |
| `Binaries/RABackendLLAMACPP.xcframework` | binary | pre-built llama.cpp backend | `engines/llamacpp` CMake target |
| `Binaries/RABackendONNX.xcframework` | binary | pre-built ONNX backend | `engines/sherpa` CMake target |
| `Binaries/RABackendSDCPP.xcframework` | binary | pre-built sdcpp backend | not in v2 scope yet |
| `Binaries/RABackendRAG.xcframework` | binary | pre-built RAG backend | `solutions/rag/` CMake target |
| `Binaries/RABackendMetalRT.xcframework` | binary | pre-built MetalRT backend | future `runtimes/metal/` CMake target |
| `Binaries/onnxruntime-ios.xcframework` | binary | ONNX Runtime for iOS | vcpkg `onnxruntime` or sherpa-onnx bundled |
| `Binaries/onnxruntime-macos.xcframework` | binary | ONNX Runtime for macOS | vcpkg `onnxruntime` |
| `Binaries/*.zip` (v0.19.4, v0.19.5) | archives | old release zips for local testing | CMake build artifacts |
| `Infrastructure/Device/Models/Domain/DeviceInfo.swift` | 305 | device fingerprinting for rac_device_manager | `core/router/hardware_profile.h` |
| `Infrastructure/Device/Services/DeviceIdentity.swift` | 90 | device UUID + keychain for rac_device_manager | C++ core |
| `Infrastructure/Logging/SentryDestination.swift` | 95 | Sentry log sink wired via rac_logger | v2 uses C++ logger |
| `Infrastructure/Logging/SentryManager.swift` | 113 | Sentry SDK init wired to rac_telemetry | C++ core |
| `Foundation/Security/KeychainManager.swift` | 251 | keychain wired via rac_platform_adapter | `frontends/swift/Adapter/` (not yet present) |

---

## DELETE-AFTER-V2-ENGINES

These files own a concept that v2 has declared but where the Phase 1 bridge is a stub (`TODO(phase-1)` comments in `frontends/swift/Adapter/VoiceSession.swift`). They cannot be deleted until `ra_pipeline_run()` is wired to `ra_stt_feed_audio()` / `ra_tts_synthesize()` calls.

| Path | Lines | Reason | Replaced by | Blocker |
|---|---|---|---|---|
| `Sources/RunAnywhere/Features/STT/Services/AudioCaptureManager.swift` | 570 | AVAudioEngine mic capture + 16 kHz float32 — real platform code | `frontends/swift/` `MicrophoneCapture.swift` (Phase 1B, not yet written) | Phase 1B `MicrophoneCapture.swift` must ship |
| `Sources/RunAnywhere/Features/TTS/Services/AudioPlaybackManager.swift` | 260 | AVAudioEngine audio playback queue | v2 `AudioSession.swift` (partial, 85 LOC) needs playback queue added | Phase 1B `AudioSession.swift` playback side |
| `Sources/WhisperKitRuntime/WhisperKitSTT.swift` | 228 | WhisperKit ANE STT provider (real, not stubbed) | sherpa-onnx STT via `ra_stt_feed_audio()` or retained as optional L2 plugin | Phase 1 gate: sherpa STT latency must match |
| `Sources/WhisperKitRuntime/WhisperKitSTTService.swift` | 202 | WhisperKit service lifecycle + streaming result | same as above | same |

---

## KEEP

| Path | Lines | Reason |
|---|---|---|
| `Sources/RunAnywhere/Infrastructure/Logging/SDKLogger.swift` | 408 | Uses `os.Logger` with `com.runanywhere` subsystem + category; v2 `frontends/swift/` does not yet have a replacement. The iOS example app's log stream command (`log stream --predicate 'subsystem CONTAINS "com.runanywhere"'`) depends on this. |
| `Sources/RunAnywhere/Infrastructure/Download/Services/AlamofireDownloadService.swift` | 460 | Resumable download with progress for model files — v2 has no model downloader in the Swift frontend yet; the C++ core model registry handles path lookup but not HTTP download. |
| `Sources/RunAnywhere/Infrastructure/Download/Services/AlamofireDownloadService+Execution.swift` | 201 | Execution extension for the above. |
| `Sources/RunAnywhere/Infrastructure/Download/Services/ExtractionService.swift` | 157 | ZIP extraction for downloaded model bundles. Same rationale. |
| `Sources/RunAnywhere/Infrastructure/Download/Models/` (4 files) | 277 | DownloadConfiguration, DownloadProgress, DownloadState, DownloadTask — used by the download service above. |
| `Sources/RunAnywhere/Infrastructure/FileManagement/Services/SimplifiedFileManager.swift` | 210 | App-side file layout helper; v2 C++ core does not expose Swift-level file path utilities yet. |
| `Sources/RunAnywhere/Infrastructure/FileManagement/Utilities/FileOperationsUtilities.swift` | 194 | File hash and atomic write utilities used by the download service. |
| `Sources/RunAnywhere/Foundation/Errors/SDKError.swift` | 497 | v1 typed error hierarchy; v1 consumers depend on it until migration is complete. Post-migration this collapses to the 5-case `RunAnywhereError` in v2. |
| `Sources/RunAnywhere/Features/TTS/System/SystemTTSModule.swift` | 69 | Apple `AVSpeechSynthesizer` fallback TTS. No v2 equivalent. v1 consumers rely on this for zero-model TTS. |
| `Sources/RunAnywhere/Features/TTS/System/SystemTTSService.swift` | 181 | Same. |
| `Sources/RunAnywhere/Features/LLM/System/SystemFoundationModelsModule.swift` | 92 | Apple Foundation Models (on-device LLM, iOS 18.1+) integration. No v2 equivalent. |
| `Tests/RunAnywhereTests/AudioCaptureManagerTests.swift` | 161 | Tests real AVAudioEngine behavior (permission request, 16 kHz capture). This logic must be ported to `frontends/swift/` before these tests can be deleted. |
| `README.md` | — | v1 docs; keep until v2 README at `frontends/swift/` covers the same surface. |
| `VERSION` | 1 | Version tag consumed by CI release scripts. |

---

## INSPECT

These three items have overlap with v2 concepts but no clear direct replacement exists yet.

1. **`Sources/RunAnywhere/Features/LLM/System/SystemFoundationModelsService.swift` (274 LOC)** — wraps `FoundationModels.framework` (Apple on-device LLM, iOS 18.1+). v2 has no L2 engine plugin for Foundation Models. This is not a rac_* bridge; it is a pure Swift feature. Whether it moves to `frontends/swift/Adapter/` or becomes an optional L2 plugin is unresolved in the MASTER_PLAN.

2. **`Sources/RunAnywhere/Features/Diffusion/DiffusionPlatformService.swift` (400 LOC) + `Public/Extensions/Diffusion/` (~879 LOC total)** — wraps `ml-stable-diffusion` for CoreML image generation. Not mentioned in the v2 MASTER_PLAN at all. There is no `engines/diffusion` plugin target. Diffusion may remain a Swift-only L6 feature or move to a future v2 phase.

3. **`Sources/RunAnywhere/Public/Extensions/VLM/` (RunAnywhere+VisionLanguage.swift 244 LOC + VLMTypes.swift 230 LOC + RunAnywhere+VLMModels.swift 39 LOC)** — VLM over rac_vlm_llamacpp. v2 MASTER_PLAN does not define a VLM primitive or engine plugin. Overlap status unclear.

---

## C ABI header replacement map

| v1 header (`Sources/RunAnywhere/CRACommons/include/`) | v2 replacement (`core/abi/`) | Notes |
|---|---|---|
| `rac_types.h` | `ra_primitives.h` | `ra_status_t`, `ra_primitive_t`, `ra_model_format_t` |
| `rac_error.h` | `ra_primitives.h` (`RA_OK`, `RA_ERR_*` constants) | |
| `rac_llm.h` + `rac_llm_types.h` + `rac_llm_component.h` + `rac_llm_service.h` + `rac_llm_platform.h` | `ra_primitives.h` (`ra_session_t`, `ra_generate`, `ra_token_callback_t`) | LlamaCppVTable owns generate |
| `rac_stt.h` + `rac_stt_types.h` + `rac_stt_component.h` + `rac_stt_service.h` + `rac_stt_whispercpp.h` + `rac_stt_whisperkit_coreml.h` | `ra_primitives.h` (`ra_stt_session_t`, `ra_stt_feed_audio`, `ra_transcript_chunk_t`) | SherpaVTable STT side |
| `rac_tts.h` + `rac_tts_types.h` + `rac_tts_component.h` + `rac_tts_service.h` + `rac_tts_platform.h` | `ra_primitives.h` (`ra_tts_session_t`, `ra_tts_synthesize`) | SherpaVTable TTS side |
| `rac_vad.h` + `rac_vad_types.h` + `rac_vad_component.h` + `rac_vad_service.h` + `rac_vad_energy.h` | `ra_primitives.h` (`ra_vad_session_t`, `ra_vad_feed`, `ra_vad_event_t`) | SherpaVTable VAD side |
| `rac_rag.h` + `rac_rag_pipeline.h` | `ra_pipeline.h` | RAG is an L5 Solution, not a direct ABI primitive |
| `rac_voice_agent.h` | `ra_pipeline.h` (`ra_pipeline_run`, `ra_pipeline_cancel`) | VoiceAgent is now an L5 Solution |
| `rac_core.h` + `rac_lifecycle.h` | `ra_version.h` + implicit plugin init | SDK init is now PluginRegistry |
| `rac_model_types.h` + `rac_model_registry.h` + `rac_model_paths.h` + `rac_model_assignment.h` + `rac_model_strategy.h` | `ra_primitives.h` (`ra_model_spec_t`) + `core/router/` | Router owns model selection |
| `rac_platform_adapter.h` | no v2 equivalent | platform callbacks (file I/O, clock) are gone; C++ core handles them |
| `rac_device_manager.h` | `core/router/hardware_profile.h` (`HardwareCaps`, `detect_hardware()`) | |
| `rac_telemetry_manager.h` + `rac_telemetry_types.h` + `rac_analytics_events.h` + `rac_llm_analytics.h` + `rac_stt_analytics.h` + `rac_tts_analytics.h` + `rac_vad_analytics.h` + `rac_llm_metrics.h` | no v2 equivalent yet | telemetry is not in the MASTER_PLAN scope |
| `rac_download.h` + `rac_download_orchestrator.h` | no v2 equivalent yet | model download is handled by app layer in v2 |
| `rac_auth_manager.h` + `rac_endpoints.h` + `rac_http_client.h` | no v2 equivalent | authentication removed from v2 scope (on-device, no cloud) |
| `rac_storage_analyzer.h` | no v2 equivalent | storage reporting not in v2 scope |
| `rac_tool_calling.h` | `LlamaCppVTable.ra_generate` (tool call JSON embedded in prompt/response) | no separate header needed |
| `rac_lora_registry.h` | `LlamaCppVTable` session config | LoRA handled inside plugin |
| `rac_vlm.h` + `rac_vlm_types.h` + `rac_vlm_component.h` + `rac_vlm_service.h` + `rac_vlm_llamacpp.h` | no v2 equivalent | VLM not in current MASTER_PLAN |
| `rac_diffusion.h` + `rac_diffusion_*` (6 headers) | no v2 equivalent | Diffusion not in current MASTER_PLAN |
| `rac_api_types.h` + `rac_dev_config.h` + `rac_environment.h` + `rac_sdk_state.h` + `rac_structured_error.h` + `rac_logger.h` | eliminated | v2 has no public state machine or environment config at L6 |

---

## Package.swift at monorepo root vs `frontends/swift/Package.swift`

**Current state:** The monorepo root `Package.swift` (at `/runanywhere-sdks3/runanywhere-sdks/Package.swift`) is the sole SPM package manifest. It roots all v1 source targets under `sdk/runanywhere-swift/` (via path references like `sdk/runanywhere-swift/Sources/RunAnywhere`) and all binary targets pointing to either `sdk/runanywhere-swift/Binaries/` (local mode) or GitHub release URLs (production mode). `frontends/swift/Package.swift` is a separate, independent package (`RunAnywhereV2`) at `frontends/swift/`.

**What survives:** After the Phase 1 gate passes, only `frontends/swift/Package.swift` should remain as the active consumer-facing manifest. The monorepo-root `Package.swift` should be deleted. It conflates two concerns: (1) SPM distribution of the v1 SDK (the `name: "runanywhere-sdks"` package published via GitHub releases), and (2) local development path overrides for the Xcode example app. Both concerns disappear when:

- v2 is distributed via `frontends/swift/Package.swift` (product name `RunAnywhereV2`, later renamed to `RunAnywhere` after cutover).
- The v1 examples are migrated or removed.

**Transition note:** The root `Package.swift` comment block at lines 7–13 already documents the dual-package consumption pattern during the migration window (`RunAnywhere` + `RunAnywhereV2` in the same SPM dependency list). This is the correct interim approach. After the Phase 1 gate, the root `Package.swift` becomes dead.

---

## XCFramework / Binaries / vendor / CocoaPods cleanup

**`sdk/runanywhere-swift/Binaries/`** — Contains 6 XCFrameworks (`RACommons`, `RABackendLLAMACPP`, `RABackendONNX`, `RABackendSDCPP`, `RABackendRAG`, `RABackendMetalRT`) plus 2 ONNX Runtime XCFrameworks (iOS + macOS slices) and 6 zip archives from versions v0.19.4 and v0.19.5. All of these are build artifacts of `sdk/runanywhere-commons/` and the associated engine libraries. Under v2, the CMake build (`cmake --preset ios-release` + `xcodebuild -create-xcframework`) produces `RunAnywhereCore.xcframework` in `build/ios-static/`, which the `frontends/swift/Package.swift` references directly. The entire `Binaries/` tree becomes unused.

**`scripts/build-swift.sh`** — Drives `sdk/runanywhere-commons/scripts/build-ios.sh` and then copies the resulting XCFrameworks into `Binaries/`. Also patches the `useLocalNatives` flag in the root `Package.swift`. Both responsibilities vanish under v2: CMake owns the build and `frontends/swift/Package.swift` references the CMake output path directly. The `--set-local` / `--set-remote` flag-patching logic is particularly bespoke and has no v2 equivalent.

**`scripts/package-sdk.sh`** — Zips XCFrameworks for GitHub releases and computes `sha256` checksums to paste into the root `Package.swift` binary target declarations. Under v2, the `CMakePresets.json` `ios-release` preset produces the XCFramework and CI uploads it; the checksum is embedded in `frontends/swift/Package.swift` via the same CI step. `package-sdk.sh` is obsolete.

**`scripts/create-onnxruntime-xcframework.sh`** — Merges separate iOS and macOS ONNX Runtime binaries into a combined XCFramework for local development. Under v2, `vcpkg` provides ORT as a build dependency and sherpa-onnx bundles it. This script is obsolete.

**CocoaPods (`fix_pods_sandbox.sh`)** — There is no `fix_pods_sandbox.sh` or `Podfile` in `sdk/runanywhere-swift/` or in the iOS example app (`examples/ios/RunAnywhereAI/`). The CocoaPods workaround mentioned in the MASTER_PLAN pain-point analysis was removed from the Swift SDK at some earlier point; the CLAUDE.md instructions for the iOS example app still reference `pod install` and `fix_pods_sandbox.sh`, but the actual files are absent from the repo. The v2 Phase 1 gate explicitly requires zero `pod install` — this is already satisfied at the SDK level.

---

## Backwards-compat shims found

1. **`VoiceSessionHandle.processCurrentAudio()` (RunAnywhere+VoiceSession.swift:204-298)** — The batch sequential pipeline flagged in the MASTER_PLAN. It runs: `audioCapture.stopRecording()` → `voiceAgentTranscribe()` (full STT, blocking) → `generate()` (full LLM, blocking) → `voiceAgentSynthesizeSpeech()` (full TTS, blocking) → `audioPlayback.play()`. This is the exact "batch sequential loop" the MASTER_PLAN describes as the root cause of the latency problem. The v2 `VoiceSession.run()` replaces this entire function with an `AsyncThrowingStream` driven by the C++ streaming pipeline. The v1 `processCurrentAudio()` is entirely redundant once Phase 1 is complete — there is nothing to port; the streaming behavior lives in C++.

2. **`metalrtRemoteBinaryAvailable = false` flag (monorepo-root Package.swift)** — A guard that suppresses the `MetalRT` product from the SPM graph when no real GitHub release checksum exists (placeholder `"0000...0000"` checksum). This prevents SPM resolution failures for external consumers. Under v2, MetalRT becomes an L1 runtime compiled via CMake; this SPM-level flag has no counterpart.

3. **`useLocalNatives` toggle (monorepo-root Package.swift)** — Switches all binary targets between local `Binaries/` paths and remote GitHub release URLs. Patched by `build-swift.sh --set-local` / `--set-remote`. Under v2, the `Package.swift` `binaryTarget` points to a fixed CMake output path; there is no toggle.

4. **`CppBridge.isInitialized` / `CppBridge._servicesInitialized` flags (CppBridge.swift:54-56)** — Two-phase initialization guards that prevent double-init of rac_* callbacks. The MASTER_PLAN explicitly eliminates this: "No public lifecycle state machines. Handles exist or they don't. Lifecycle is internal." These flags and the two-phase `initialize()`/`initializeServices()` pattern are entirely replaced by `PluginRegistry::global()` lazy static registration.

5. **`rac_bool_t` / `RAC_TRUE` / `RAC_FALSE` pattern (CppBridge+VoiceAgent.swift:57-59)** — C-style boolean return values bridged manually to Swift `Bool`. v2 `ra_status_t` / `RA_OK` / `RA_ERR_*` is a clean numeric status; boolean results are expressed as `bool` in the vtable signatures directly.
