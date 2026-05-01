/**
 * RunAnywhere Web SDK - Core Package (Pure TypeScript)
 *
 * Backend-agnostic infrastructure for on-device AI in the browser.
 * This package has ZERO WASM — all inference binaries live in backend packages:
 *   - @runanywhere/web-llamacpp — LLM, VLM, embeddings, diffusion (ships racommons-llamacpp.wasm)
 *   - @runanywhere/web-onnx — STT, TTS, VAD (ships sherpa-onnx.wasm)
 *
 * @packageDocumentation
 *
 * @example
 * ```typescript
 * import { RunAnywhere } from '@runanywhere/web';
 * import { LlamaCPP } from '@runanywhere/web-llamacpp';
 * import { ONNX } from '@runanywhere/web-onnx';
 *
 * await RunAnywhere.initialize({ environment: 'development' });
 * await LlamaCPP.register();
 * await ONNX.register();
 * ```
 */

// Main entry point
export { RunAnywhere } from './Public/RunAnywhere';
export type { StorageBackend } from './Public/RunAnywhere';

// Namespace extensions — symmetric with Swift's 19-extension pattern.
export { Storage } from './Public/Extensions/RunAnywhere+Storage';
export type { StorageInfoExtended } from './Public/Extensions/RunAnywhere+Storage';
export { PluginLoader } from './Public/Extensions/RunAnywhere+PluginLoader';
export { TextGeneration, generateStructuredStream, extractStructuredOutput } from './Public/Extensions/RunAnywhere+TextGeneration';
export type { StructuredOutputResult, JSONSchemaDescriptor } from './Public/Extensions/RunAnywhere+TextGeneration';
export { StructuredOutput } from './Public/Extensions/RunAnywhere+StructuredOutput';
export { ToolCalling } from './Public/Extensions/RunAnywhere+ToolCalling';
export { LoRA } from './Public/Extensions/RunAnywhere+LoRA';
export { STT } from './Public/Extensions/RunAnywhere+STT';
export { TTS } from './Public/Extensions/RunAnywhere+TTS';
export { VAD } from './Public/Extensions/RunAnywhere+VAD';
export { VoiceAgent } from './Public/Extensions/RunAnywhere+VoiceAgent';
export { VisionLanguage } from './Public/Extensions/RunAnywhere+VisionLanguage';
export type { VLMGenerationOptions, VLMResult } from './Public/Extensions/RunAnywhere+VisionLanguage';
export { VLMModels } from './Public/Extensions/RunAnywhere+VLMModels';
export { Diffusion } from './Public/Extensions/RunAnywhere+Diffusion';
export type {
  DiffusionGenerationOptions,
  DiffusionResult,
  DiffusionConfiguration,
  DiffusionCapabilities,
  DiffusionProgress,
} from './Public/Extensions/RunAnywhere+Diffusion';
export {
  generateImage,
  generateImageStream,
  loadDiffusionModel,
  unloadDiffusionModel,
  getIsDiffusionModelLoaded,
  cancelImageGeneration,
  getDiffusionCapabilities,
} from './Public/Extensions/RunAnywhere+Diffusion';
export { RAG } from './Public/Extensions/RunAnywhere+RAG';
export { ModelManagement } from './Public/Extensions/RunAnywhere+ModelManagement';
export { ModelAssignments } from './Public/Extensions/RunAnywhere+ModelAssignments';
export type { ModelAssignment } from './Public/Extensions/RunAnywhere+ModelAssignments';
export { Frameworks } from './Public/Extensions/RunAnywhere+Frameworks';
export { solutions as Solutions } from './Public/Extensions/RunAnywhere+Solutions';
export { Logging } from './Public/Extensions/RunAnywhere+Logging';
export { Hardware } from './Public/Extensions/RunAnywhere+Hardware';
export type { HardwareProfile } from './Public/Extensions/RunAnywhere+Hardware';

// Phase 4d: top-level convenience verbs (chat / generate / transcribe /
// synthesize / speak / detectSpeech / setVADCallback / etc.) — also reachable
// as static methods on `RunAnywhere`. Re-exported for tree-shakability.
export {
  chat,
  generate,
  generateStream,
  generateStructured,
  transcribe,
  synthesize,
  speak,
  isSpeaking,
  stopSpeaking,
  detectSpeech,
  setVADCallback,
  startVAD,
  stopVAD,
  cleanupVAD,
  isVADReady,
} from './Public/Extensions/RunAnywhere+Convenience';

// LoRA / RAG / VoiceAgent C-ABI extensions (Phase 4d).
// Today these dispatch through provider hooks installed by backend packages.
export {
  loadLoraAdapter,
  removeLoraAdapter,
  clearLoraAdapters,
  getLoadedLoraAdapters,
  checkLoraCompatibility,
  registerLoraAdapter,
  loraAdaptersForModel,
  allRegisteredLoraAdapters,
  setLoRAProvider,
} from './Public/Extensions/RunAnywhere+LoRA';
export type { LoRAProvider } from './Public/Extensions/RunAnywhere+LoRA';

export {
  ragCreatePipeline,
  ragDestroyPipeline,
  ragIngest,
  ragAddDocumentsBatch,
  ragQuery,
  ragClearDocuments,
  ragGetDocumentCount,
  ragGetStatistics,
  setRAGProvider,
} from './Public/Extensions/RunAnywhere+RAG';
export type { RAGProvider } from './Public/Extensions/RunAnywhere+RAG';

export {
  initializeVoiceAgent,
  initializeVoiceAgentWithLoadedModels,
  isVoiceAgentReady,
  getVoiceAgentComponentStates,
  areAllVoiceComponentsReady,
  processVoiceTurn,
  voiceAgentTranscribe,
  voiceAgentGenerateResponse,
  voiceAgentSynthesizeSpeech,
  streamVoiceAgent,
  cleanupVoiceAgent,
  setVoiceAgentProvider,
} from './Public/Extensions/RunAnywhere+VoiceAgent';
export type { VoiceAgentProvider } from './Public/Extensions/RunAnywhere+VoiceAgent';

// Runtime config (acceleration). Backend hooks for the llamacpp pkg.
export {
  Runtime,
  setAccelerationSwitcher,
  setActiveAccelerationMode,
} from './Foundation/RuntimeConfig';
export type {
  RuntimeAccelerationMode,
  RuntimeAccelerationSwitcher,
} from './Foundation/RuntimeConfig';

// Storage provider interface (Phase 4d P1) — uniform contract for OPFS /
// File System Access / memory backends.
export type {
  StorageProvider,
  StorageProviderId,
  StorageProviderCapabilities,
} from './Infrastructure/StorageProvider';

// Voice orchestration — single canonical path:
//   `VoiceAgentStreamAdapter` wraps the WASM proto-stream
//   (`rac_voice_agent_set_proto_callback`) and yields an
//   `AsyncIterable<VoiceEvent>` symmetric with iOS / Android / Flutter / RN.
//   The legacy TS-side compose orchestrator (`VoicePipeline`) was removed
//   per CANONICAL_API.md §15; example apps inline their own STT→LLM→TTS
//   composition directly via `ExtensionPoint.requireProvider(...)` until
//   the Web WASM voice-agent bindings land.
export { VoiceAgentStreamAdapter } from './Adapters/VoiceAgentStreamAdapter';
export type { VoiceAgentStreamTransport } from '@runanywhere/proto-ts/streams/voice_agent_service_stream';
export type { VoiceAgentRequest } from '@runanywhere/proto-ts/voice_agent_service';

// LLM proto-byte streaming (GAP 09 — symmetric to VoiceAgentStreamAdapter).
// Used by backend packages (e.g. @runanywhere/web-llamacpp) to expose a
// platform-agnostic AsyncIterable<LLMStreamEvent> over the C++ proto callback.
export { LLMStreamAdapter } from './Adapters/LLMStreamAdapter';
export type { LLMStreamTransport } from '@runanywhere/proto-ts/streams/llm_service_stream';
export type { LLMGenerateRequest, LLMStreamEvent } from '@runanywhere/proto-ts/llm_service';
export { LLMTokenKind } from '@runanywhere/proto-ts/llm_service';

// Solutions runtime (T4.7 / T4.8) — proto/YAML-driven L5 pipeline runtime.
// Construct via `RunAnywhere.solutions.run(...)` (preferred) or directly via
// `SolutionAdapter.run(...)`. Returns a `SolutionHandle` whose verbs map 1:1
// to `rac_solution_*` in the C ABI.
export {
  SolutionAdapter,
  SolutionHandle,
  type SolutionRunInput,
} from './Adapters/SolutionAdapter';
export {
  VoiceEvent,
  UserSaidEvent,
  AssistantTokenEvent,
  AudioFrameEvent,
  VADEvent,
  InterruptedEvent,
  StateChangeEvent,
  ErrorEvent,
  MetricsEvent,
  TokenKind,
  AudioEncoding,
  VADEventType,
  InterruptReason,
  PipelineState as VoiceEventPipelineState,
} from '@runanywhere/proto-ts/voice_events';
export { clearRunanywhereModule, setRunanywhereModule } from './runtime/EmscriptenModule';
export type { EmscriptenRunanywhereModule } from './runtime/EmscriptenModule';

// HTTP adapter (T3.13) — wraps the commons libcurl-backed C ABI so every
// Web site goes through the same HTTP transport as Swift/Kotlin/RN/Flutter.
// Backend packages install their Emscripten module via
// HTTPAdapter.setDefaultModule(module) after WASM load.
export { HTTPAdapter, DownloadStatus, HTTP_FETCH_CARVE_OUTS } from './Adapters/HTTPAdapter';
export type {
  HTTPRequest,
  HTTPResponse,
  HTTPHeader,
  HTTPModule,
  ChunkHandler,
  DownloadRequest,
  DownloadProgressHandler,
} from './Adapters/HTTPAdapter';

// Stage 3d — JS-side HTTP transport. Provides the scaffolding for
// `fetch()`-backed routing registered via the commons transport vtable.
// HTTPAdapter.setDefaultModule auto-installs this when the module exposes
// `_rac_http_transport_register_from_js`; export is available for tests
// and for callers that want direct lifecycle control.
export { FetchHttpTransport } from './Adapters/FetchHttpTransport';
export type { FetchHttpTransportModule } from './Adapters/FetchHttpTransport';

// Model registry refresh (T4.9) — wraps the commons
// `rac_model_registry_refresh` C ABI so the web surface is symmetric with
// Swift / Kotlin / RN / Flutter. Backend packages install their Emscripten
// module via `ModelRegistryAdapter.setDefaultModule(module)` after load.
export { ModelRegistryAdapter } from './Adapters/ModelRegistryAdapter';
export type {
  ModelRegistryModule,
  RefreshOptions,
} from './Adapters/ModelRegistryAdapter';

// Types
export * from './types';

// Foundation
export { SDKErrorCode, SDKException, isSDKException } from './Foundation/SDKException';
export type { ProtoSDKError, ProtoErrorContext } from './Foundation/SDKException';
export { ProtoErrorCategory, ProtoErrorCode } from './Foundation/SDKException';
// Proto helpers — accessors that match Web event payload field names.
export { tokensUsed, latencyMs } from './Foundation/ProtoHelpers';
export { SDKLogger, LogLevel } from './Foundation/SDKLogger';
export { EventBus } from './Foundation/EventBus';
export type { EventListener, Unsubscribe, SDKEventEnvelope } from './Foundation/EventBus';
export { AsyncQueue } from './Foundation/AsyncQueue';
export type { AccelerationMode } from './Foundation/WASMBridge';
export type {
  AllOffsets,
  ConfigOffsets,
  LLMOptionsOffsets,
  LLMResultOffsets,
  VLMImageOffsets,
  VLMOptionsOffsets,
  VLMResultOffsets,
  StructuredOutputConfigOffsets,
  StructuredOutputValidationOffsets,
  EmbeddingsOptionsOffsets,
  EmbeddingsResultOffsets,
  EmbeddingVectorOffsets,
  DiffusionOptionsOffsets,
  DiffusionResultOffsets,
} from './Foundation/StructOffsets';

// I/O Infrastructure (backend-agnostic capture/playback)
export { AudioCapture } from './Infrastructure/AudioCapture';
export type { AudioChunkCallback, AudioLevelCallback, AudioCaptureConfig } from './Infrastructure/AudioCapture';
export { AudioPlayback } from './Infrastructure/AudioPlayback';
export type { PlaybackCompleteCallback, PlaybackConfig } from './Infrastructure/AudioPlayback';
export { AudioFileLoader } from './Infrastructure/AudioFileLoader';
export type { AudioFileLoaderResult } from './Infrastructure/AudioFileLoader';
export { VideoCapture } from './Infrastructure/VideoCapture';
export type { VideoCaptureConfig, CapturedFrame } from './Infrastructure/VideoCapture';

// Infrastructure
export { detectCapabilities, getDeviceInfo } from './Infrastructure/DeviceCapabilities';
export type { WebCapabilities } from './Infrastructure/DeviceCapabilities';
export { ModelManager } from './Infrastructure/ModelManager';
export type {
  ManagedModel, CompactModelDef, DownloadProgress,
  ModelFileDescriptor, ArtifactType, VLMLoader, VLMLoadParams,
} from './Infrastructure/ModelManager';
export type { QuotaCheckResult, EvictionCandidateInfo } from './Infrastructure/ModelDownloader';
export { OPFSStorage } from './Infrastructure/OPFSStorage';
export type { StoredModelInfo, MetadataMap, ModelMetadata } from './Infrastructure/OPFSStorage';
export { ExtensionRegistry } from './Infrastructure/ExtensionRegistry';
export type { SDKExtension } from './Infrastructure/ExtensionRegistry';
export { ExtensionPoint, BackendCapability, ServiceKey } from './Infrastructure/ExtensionPoint';
export type { BackendExtension } from './Infrastructure/ExtensionPoint';
export type {
  ProviderCapability,
  ProviderMap,
  LLMProvider,
  STTProvider,
  TTSProvider,
  VADProvider,
} from './Infrastructure/ProviderTypes';
export type { ModelLoadContext, LLMModelLoader, STTModelLoader, TTSModelLoader, VADModelLoader } from './Infrastructure/ModelLoaderTypes';
export { extractTarGz } from './Infrastructure/ArchiveUtility';
export { LocalFileStorage } from './Infrastructure/LocalFileStorage';
export { inferModelFromFilename, sanitizeId } from './Infrastructure/ModelFileInference';
export type { InferredModelMeta } from './Infrastructure/ModelFileInference';

// Services
export { AnalyticsEmitter } from './services/AnalyticsEmitter';
export type { AnalyticsEmitterBackend } from './services/AnalyticsEmitter';
