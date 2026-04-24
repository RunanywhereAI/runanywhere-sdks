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

// Voice orchestration — two paths:
//   1. VoicePipeline      — TS-side composition (STT -> LLM -> TTS) via ExtensionPoint.
//   2. VoiceAgentStreamAdapter — WASM proto-stream (VoiceEvent) parity with iOS/Android/Flutter/RN.
//      Also accepts a custom VoiceAgentStreamTransport for TS-backed / test transports.
export { VoicePipeline } from './Public/Extensions/RunAnywhere+VoicePipeline';
export { PipelineState } from './Public/Extensions/VoiceAgentTypes';
export type { VoicePipelineCallbacks, VoicePipelineOptions, VoicePipelineTurnResult } from './Public/Extensions/VoicePipelineTypes';
export { VoiceAgentStreamAdapter } from './Adapters/VoiceAgentStreamAdapter';
export type { VoiceAgentStreamTransport } from './generated/streams/voice_agent_service_stream';
export type { VoiceAgentRequest } from './generated/voice_agent_service';

// LLM proto-byte streaming (GAP 09 — symmetric to VoiceAgentStreamAdapter).
// Used by backend packages (e.g. @runanywhere/web-llamacpp) to expose a
// platform-agnostic AsyncIterable<LLMStreamEvent> over the C++ proto callback.
export { LLMStreamAdapter } from './Adapters/LLMStreamAdapter';
export type { LLMStreamTransport } from './generated/streams/llm_service_stream';
export type { LLMGenerateRequest, LLMStreamEvent } from './generated/llm_service';
export { LLMTokenKind } from './generated/llm_service';

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
} from './generated/voice_events';
export { setRunanywhereModule } from './runtime/EmscriptenModule';
export type { EmscriptenRunanywhereModule } from './runtime/EmscriptenModule';

// HTTP adapter (T3.13) — wraps the commons libcurl-backed C ABI so every
// Web site goes through the same HTTP transport as Swift/Kotlin/RN/Flutter.
// Backend packages install their Emscripten module via
// HTTPAdapter.setDefaultModule(module) after WASM load.
export { HTTPAdapter, DownloadStatus } from './Adapters/HTTPAdapter';
export type {
  HTTPRequest,
  HTTPResponse,
  HTTPHeader,
  HTTPModule,
  ChunkHandler,
  DownloadRequest,
  DownloadProgressHandler,
} from './Adapters/HTTPAdapter';

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
export { SDKError, SDKErrorCode, isSDKError } from './Foundation/ErrorTypes';
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
} from './Infrastructure/ProviderTypes';
export type { ModelLoadContext, LLMModelLoader, STTModelLoader, TTSModelLoader, VADModelLoader } from './Infrastructure/ModelLoaderTypes';
export { extractTarGz } from './Infrastructure/ArchiveUtility';
export { LocalFileStorage } from './Infrastructure/LocalFileStorage';
export { inferModelFromFilename, sanitizeId } from './Infrastructure/ModelFileInference';
export type { InferredModelMeta } from './Infrastructure/ModelFileInference';

// Services
export { AnalyticsEmitter } from './services/AnalyticsEmitter';
export type { AnalyticsEmitterBackend } from './services/AnalyticsEmitter';
