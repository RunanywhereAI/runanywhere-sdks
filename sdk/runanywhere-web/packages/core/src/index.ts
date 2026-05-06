/**
 * RunAnywhere Web SDK - Core Package (Pure TypeScript)
 *
 * Backend-agnostic infrastructure for on-device AI in the browser.
 * This package has ZERO WASM — all inference binaries live in backend packages.
 *
 * After the V2 cleanup, the public surface is built entirely on the proto-byte
 * adapters that wrap the commons C ABI. JS-side model lifecycle policy
 * (ModelManager / ModelRegistry / ModelDownloader / ExtensionPoint /
 * ExtensionRegistry / archive helpers / provider routing) has been deleted.
 *
 * @packageDocumentation
 *
 * @example
 * ```typescript
 * import { RunAnywhere } from '@runanywhere/web';
 *
 * await RunAnywhere.initialize({ environment: 'development' });
 * // Backend packages register their proto-byte handles via setRunanywhereModule().
 * ```
 */

// Main entry point
export { RunAnywhere } from './Public/RunAnywhere';
export type { StorageBackend } from './Public/RunAnywhere';

// Namespace extensions — symmetric with Swift's namespace pattern.
export type {
  StorageAvailabilityRequest,
  StorageAvailabilityResult,
  StorageDeletePlan,
  StorageDeletePlanRequest,
  StorageDeleteRequest,
  StorageDeleteResult,
  StorageInfoRequest,
  StorageInfoResult,
} from '@runanywhere/proto-ts/storage_types';
export { Downloads } from './Public/Extensions/RunAnywhere+Downloads';
export { SDKEvents } from './Public/Extensions/RunAnywhere+SDKEvents';
export { ModelRegistry } from './Public/Extensions/RunAnywhere+ModelRegistry';
export { ModelLifecycle } from './Public/Extensions/RunAnywhere+ModelLifecycle';
export type {
  ComponentLifecycleEvent,
  ComponentLifecycleSnapshot,
  CurrentModelRequest,
  CurrentModelResult,
  ModelLoadRequest,
  ModelLoadResult,
  ModelUnloadRequest,
  ModelUnloadResult,
} from './Public/Extensions/RunAnywhere+ModelLifecycle';
export { ComponentLifecycleState } from './Public/Extensions/RunAnywhere+ModelLifecycle';
export { TextGeneration, generateStructuredStream, extractStructuredOutput } from './Public/Extensions/RunAnywhere+TextGeneration';
export type { StructuredOutputResult, JSONSchemaDescriptor } from './Public/Extensions/RunAnywhere+TextGeneration';
export { StructuredOutput } from './Public/Extensions/RunAnywhere+StructuredOutput';
export { ToolCalling } from './Public/Extensions/RunAnywhere+ToolCalling';
export type { ToolCallingGenerationOptions } from './Public/Extensions/RunAnywhere+ToolCalling';
export { STT, transcribe } from './Public/Extensions/RunAnywhere+STT';
export type {
  STTOptions,
  STTOutput,
  STTPartialResult,
  TranscribeOptions,
} from './Public/Extensions/RunAnywhere+STT';
export { TTS, synthesize } from './Public/Extensions/RunAnywhere+TTS';
export type {
  TTSOptions,
  TTSOutput,
  TTSVoiceInfo,
  SynthesizeOptions,
} from './Public/Extensions/RunAnywhere+TTS';
export { VAD, detectVoice } from './Public/Extensions/RunAnywhere+VAD';
export type {
  VADConfiguration,
  VADOptions,
  VADResult,
  VADStatistics,
  SpeechActivityEvent,
  DetectVoiceOptions,
} from './Public/Extensions/RunAnywhere+VAD';
export { LoRA } from './Public/Extensions/RunAnywhere+LoRA';
export { RAG } from './Public/Extensions/RunAnywhere+RAG';
export { solutions as Solutions } from './Public/Extensions/RunAnywhere+Solutions';
export { Logging } from './Public/Extensions/RunAnywhere+Logging';
export { Hardware } from './Public/Extensions/RunAnywhere+Hardware';
export type { HardwareProfile, HardwareProfileResult } from './Public/Extensions/RunAnywhere+Hardware';

// LoRA / RAG / VoiceAgent C-ABI extensions.
export {
  applyLoraAdapters,
  checkLoraCompatibility,
  getLoraCatalogEntry,
  getLoraState,
  listLoraCatalog,
  listLoraAdapters,
  markLoraAdapterDownloadCompleted,
  missingLoRACatalogExports,
  missingLoRAExports,
  queryLoraCatalog,
  registerLoraAdapter,
  removeLoraAdapters,
  supportsNativeLoRACatalog,
  supportsNativeLoRA,
} from './Public/Extensions/RunAnywhere+LoRA';
export type {
  LoRAAdapterConfig,
  LoRAAdapterInfo,
  LoRAApplyRequest,
  LoRAApplyResult,
  LoRARemoveRequest,
  LoRAState,
  LoraAdapterCatalogEntry,
  LoraAdapterCatalogGetRequest,
  LoraAdapterCatalogGetResult,
  LoraAdapterCatalogListRequest,
  LoraAdapterCatalogListResult,
  LoraAdapterCatalogQuery,
  LoraAdapterDownloadCompletedRequest,
  LoraAdapterDownloadCompletedResult,
  LoraCompatibilityResult,
} from './Public/Extensions/RunAnywhere+LoRA';

export {
  ragCreatePipeline,
  ragDestroyPipeline,
  ragIngest,
  ragAddDocumentsBatch,
  ragQuery,
  ragClearDocuments,
  ragGetDocumentCount,
  ragGetStatistics,
  ragListDocuments,
  ragRemoveDocument,
  ragGetCapabilities,
  createDefaultRAGConfiguration,
  createRAGNativeProvider,
  setRAGSessionHandle,
  unavailableRAGResult,
  unavailableRAGStatistics,
  getRAGAvailability,
  isRAGAvailable,
  setRAGProvider,
} from './Public/Extensions/RunAnywhere+RAG';
export type {
  RAGAvailability,
  RAGAvailabilitySource,
  RAGDocumentSummary,
  RAGNativeProviderOptions,
  RAGProvider,
  RAGProviderCapabilities,
  RAGQueryOverrides,
} from './Public/Extensions/RunAnywhere+RAG';

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
  createVoiceAgentHandleProvider,
  getVoiceAgentAvailability,
  isVoiceAgentAvailable,
  setVoiceAgentProvider,
  setVoiceAgentHandle,
  unavailableVoiceAgentResult,
} from './Public/Extensions/RunAnywhere+VoiceAgent';
export type {
  VoiceAgentAvailability,
  VoiceAgentAvailabilitySource,
  VoiceAgentProvider,
  VoiceAgentStreamSource,
} from './Public/Extensions/RunAnywhere+VoiceAgent';

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

// Storage provider interface — uniform contract for OPFS / FSA / memory.
export type {
  StorageProvider,
  StorageProviderId,
  StorageProviderCapabilities,
} from './Infrastructure/StorageProvider';

// Voice orchestration — single canonical path:
//   `VoiceAgentStreamAdapter` wraps the WASM proto-stream
//   (`rac_voice_agent_set_proto_callback`) and yields an
//   `AsyncIterable<VoiceEvent>` symmetric with iOS / Android / Flutter / RN.
//   Backends must register a native handle/provider; the core facade reports
//   typed unavailable results/events when no handle is present.
export { VoiceAgentStreamAdapter } from './Adapters/VoiceAgentStreamAdapter';
export type { VoiceAgentStreamTransport } from '@runanywhere/proto-ts/streams/voice_agent_service_stream';
export type { VoiceAgentRequest } from '@runanywhere/proto-ts/voice_agent_service';

// LLM proto-byte streaming (symmetric to VoiceAgentStreamAdapter).
// Used by backend packages to expose a platform-agnostic
// AsyncIterable<LLMStreamEvent> over the C++ proto callback.
export { LLMStreamAdapter } from './Adapters/LLMStreamAdapter';
export type { LLMStreamTransport } from '@runanywhere/proto-ts/streams/llm_service_stream';
export type { LLMGenerateRequest, LLMStreamEvent } from '@runanywhere/proto-ts/llm_service';
// IDL-06: The former `LLMTokenKind` re-export has been removed — the canonical
// `TokenKind` (from voice_events.proto) is re-exported below alongside the
// VoiceEvent types.
export {
  DiffusionProtoAdapter,
  EmbeddingsProtoAdapter,
  LLMProtoAdapter,
  LoRAProtoAdapter,
  ModalityProtoAdapter,
  RAGProtoAdapter,
  STTProtoAdapter,
  TTSProtoAdapter,
  VADProtoAdapter,
  VLMProtoAdapter,
  VoiceAgentProtoAdapter,
} from './Adapters/ModalityProtoAdapter';
export type {
  ModalityProtoModule,
  ProtoEventHandler,
} from './Adapters/ModalityProtoAdapter';

// Solutions runtime — proto/YAML-driven L5 pipeline runtime.
// Construct via `RunAnywhere.solutions.run(...)` (preferred) or directly via
// `SolutionAdapter.run(...)`.
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
  InterruptReason,
  PipelineState as VoiceEventPipelineState,
} from '@runanywhere/proto-ts/voice_events';
// IDL-18: VADStreamEventKind is the canonical VAD event enum (absorbed the
// deleted VADEventType from voice_events.proto).
export { VADStreamEventKind } from '@runanywhere/proto-ts/vad_options';
export {
  clearRunanywhereModule,
  setRunanywhereModule,
  tryRunanywhereModule,
} from './runtime/EmscriptenModule';
export type { EmscriptenRunanywhereModule } from './runtime/EmscriptenModule';

// HTTP adapter — wraps the commons HTTP transport so every Web site goes
// through the same path as Swift/Kotlin/RN/Flutter. Backend packages install
// their Emscripten module via HTTPAdapter.setDefaultModule(module) after WASM load.
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

// JS-side HTTP transport. Provides the scaffolding for `fetch()`-backed
// routing registered via the commons transport vtable.
export { FetchHttpTransport } from './Adapters/FetchHttpTransport';
export type { FetchHttpTransportModule } from './Adapters/FetchHttpTransport';

// Model registry / lifecycle / download / hardware / SDK-event / storage
// proto-byte bridges. Symmetric with Swift / Kotlin / RN / Flutter.
export { ModelRegistryAdapter } from './Adapters/ModelRegistryAdapter';
export type {
  ModelRegistryModule,
  ModelInfoList,
  ModelRegistryAvailability,
  RefreshOptions,
} from './Adapters/ModelRegistryAdapter';
export { ModelLifecycleAdapter } from './Adapters/ModelLifecycleAdapter';
export type { ModelLifecycleModule } from './Adapters/ModelLifecycleAdapter';
export { DownloadAdapter } from './Adapters/DownloadAdapter';
export type { DownloadModule, ProtoDownloadProgressHandler } from './Adapters/DownloadAdapter';
export { HardwareAdapter } from './Adapters/HardwareAdapter';
export type { HardwareModule } from './Adapters/HardwareAdapter';
export { StorageAdapter } from './Adapters/StorageAdapter';
export type { StorageModule } from './Adapters/StorageAdapter';
export { SDKEventStreamAdapter } from './Adapters/SDKEventStreamAdapter';
export type {
  SDKEventHandler,
  SDKEventStreamModule,
  SDKEventUnsubscribe,
} from './Adapters/SDKEventStreamAdapter';

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

// I/O Infrastructure (backend-agnostic capture/playback). Browser-specific
// platform adapters that the C++ core cannot do directly.
export { AudioCapture } from './Infrastructure/AudioCapture';
export type { AudioChunkCallback, AudioLevelCallback, AudioCaptureConfig } from './Infrastructure/AudioCapture';
export { AudioPlayback } from './Infrastructure/AudioPlayback';
export type { PlaybackCompleteCallback, PlaybackConfig } from './Infrastructure/AudioPlayback';
export { AudioFileLoader } from './Infrastructure/AudioFileLoader';
export type { AudioFileLoaderResult } from './Infrastructure/AudioFileLoader';
export { VideoCapture } from './Infrastructure/VideoCapture';
export type { VideoCaptureConfig, CapturedFrame } from './Infrastructure/VideoCapture';

// Browser-specific persistent storage adapters (File System Access API).
// These are platform helpers the C++ commons layer cannot speak directly.
// NOTE: A prior `OPFSStorage` export was removed — it was orphan code in V2
// (never instantiated; only `isSupported` was read for storageBackend
// feature-detection). OPFS persistence for downloaded models is not yet wired
// through PlatformAdapter; tracked as a follow-up.
export { detectCapabilities, getDeviceInfo } from './Infrastructure/DeviceCapabilities';
export type { WebCapabilities } from './Infrastructure/DeviceCapabilities';
export { LocalFileStorage } from './Infrastructure/LocalFileStorage';
