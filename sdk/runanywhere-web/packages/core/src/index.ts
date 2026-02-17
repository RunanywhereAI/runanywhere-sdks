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

// Voice orchestration (cross-backend, uses provider interfaces)
export { VoiceAgent, VoiceAgentSession, PipelineState } from './Public/Extensions/RunAnywhere+VoiceAgent';
export type { VoiceAgentModels, VoiceTurnResult, VoiceAgentEventData, VoiceAgentEventCallback } from './Public/Extensions/RunAnywhere+VoiceAgent';
export { VoicePipeline } from './Public/Extensions/RunAnywhere+VoicePipeline';
export type { VoicePipelineCallbacks, VoicePipelineOptions, VoicePipelineTurnResult } from './Public/Extensions/VoicePipelineTypes';

// Types
export * from './types';

// Foundation
export { SDKError, SDKErrorCode } from './Foundation/ErrorTypes';
export { SDKLogger, LogLevel } from './Foundation/SDKLogger';
export { EventBus } from './Foundation/EventBus';
export type { EventListener, Unsubscribe, SDKEventEnvelope } from './Foundation/EventBus';
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
export type { ModelLoadContext, LLMModelLoader, STTModelLoader, TTSModelLoader, VADModelLoader } from './Infrastructure/ModelLoaderTypes';
export { extractTarGz } from './Infrastructure/ArchiveUtility';
export { LocalFileStorage } from './Infrastructure/LocalFileStorage';
export { inferModelFromFilename, sanitizeId } from './Infrastructure/ModelFileInference';
export type { InferredModelMeta } from './Infrastructure/ModelFileInference';
