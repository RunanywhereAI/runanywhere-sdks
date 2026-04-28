/**
 * RunAnywhere React Native SDK - Types
 *
 * Re-exports the canonical proto-generated types from
 * `@runanywhere/proto-ts/*` plus a small set of RN-only structural types
 * that have no proto counterpart (LLM streaming, ToolCalling, NPU,
 * generic enums, model registry shapes).
 *
 * Wave 2 cleanup: all per-modality legacy interfaces (STT/TTS/VAD/VLM/
 * Diffusion/LoRA/RAG/StructuredOutput/VoiceAgent) have been deleted.
 * Consumers MUST import the proto-canonical shapes directly.
 */

// =========================================================================
// Enums (RN-local, no proto equivalent)
// =========================================================================

export {
  ComponentState,
  ConfigurationSource,
  ExecutionTarget,
  FrameworkModality,
  HardwareAcceleration,
  LLMFramework,
  LLMFrameworkDisplayNames,
  ModelCategory,
  ModelCategoryDisplayNames,
  ModelFormat,
  PrivacyMode,
  RoutingPolicy,
  SDKComponent,
  SDKEnvironment,
  SDKEventType,
  ModelArtifactType,
} from './enums';

// =========================================================================
// Models (RN-local: ModelInfo registry shape, init params, device info,
// generation result + storage shapes used by Public/RunAnywhere)
// =========================================================================

export type {
  ComponentHealth,
  ConfigurationData,
  DefaultGenerationSettings,
  DeviceInfoData,
  FrameworkAvailability,
  GenerationOptions,
  InitializationResult,
  ModelInfo,
  ModelCompatibilityResult,
  ModelInfoMetadata,
  SDKInitOptions,
  StorageInfo,
  StoredModel,
  ThinkingTagPattern,
  VoiceAudioChunk,
} from './models';

// =========================================================================
// Events — RN runtime payload shapes (native-bridge JSON envelopes)
// =========================================================================

export type {
  AnySDKEvent,
  ComponentInitializationEvent,
  SDKConfigurationEvent,
  SDKDeviceEvent,
  SDKRuntimeEvent as SDKEvent,
  SDKEventListener,
  SDKFrameworkEvent,
  SDKGenerationEvent,
  SDKInitializationEvent,
  SDKModelEvent,
  SDKNetworkEvent,
  SDKPerformanceEvent,
  SDKStorageEvent,
  SDKVoiceEvent,
  UnsubscribeFunction,
} from '../Public/Events/SDKEventTypes';

// Canonical proto-encoded event envelope (analytics / cross-SDK transport)
export type {
  SDKEvent as ProtoSDKEvent,
  InitializationEvent as ProtoInitializationEvent,
  ConfigurationEvent as ProtoConfigurationEvent,
  GenerationEvent as ProtoGenerationEvent,
  ModelEvent as ProtoModelEvent,
  VoiceLifecycleEvent as ProtoVoiceLifecycleEvent,
  PerformanceEvent as ProtoPerformanceEvent,
  NetworkEvent as ProtoNetworkEvent,
  StorageEvent as ProtoStorageEvent,
  FrameworkEvent as ProtoFrameworkEvent,
  DeviceEvent as ProtoDeviceEvent,
  ComponentInitializationEvent as ProtoComponentInitializationEvent,
} from '@runanywhere/proto-ts/sdk_events';
export {
  EventSeverity as ProtoEventSeverity,
  EventDestination as ProtoEventDestination,
  InitializationStage as ProtoInitializationStage,
  ConfigurationEventKind as ProtoConfigurationEventKind,
  GenerationEventKind as ProtoGenerationEventKind,
  ModelEventKind as ProtoModelEventKind,
  VoiceEventKind as ProtoVoiceEventKind,
  PerformanceEventKind as ProtoPerformanceEventKind,
  NetworkEventKind as ProtoNetworkEventKind,
  StorageEventKind as ProtoStorageEventKind,
  FrameworkEventKind as ProtoFrameworkEventKind,
  DeviceEventKind as ProtoDeviceEventKind,
  ComponentInitializationEventKind as ProtoComponentInitializationEventKind,
} from '@runanywhere/proto-ts/sdk_events';

// =========================================================================
// STT — proto-canonical
// =========================================================================

export type {
  STTConfiguration,
  STTOptions,
  STTOutput,
  STTPartialResult,
  WordTimestamp,
  TranscriptionAlternative,
  TranscriptionMetadata,
} from '@runanywhere/proto-ts/stt_options';
export { STTLanguage } from '@runanywhere/proto-ts/stt_options';

// =========================================================================
// TTS — proto-canonical
// =========================================================================

export type {
  TTSConfiguration,
  TTSOptions,
  TTSOutput,
  TTSPhonemeTimestamp,
  TTSSynthesisMetadata,
  TTSSpeakResult,
  TTSVoiceInfo,
} from '@runanywhere/proto-ts/tts_options';
export { TTSVoiceGender } from '@runanywhere/proto-ts/tts_options';

// =========================================================================
// VAD — proto-canonical
// =========================================================================

export type {
  VADConfiguration,
  VADOptions,
  VADResult,
  VADStatistics,
  SpeechActivityEvent,
} from '@runanywhere/proto-ts/vad_options';
export { SpeechActivityKind } from '@runanywhere/proto-ts/vad_options';

// =========================================================================
// VLM — proto-canonical
// =========================================================================

export type {
  VLMImage,
  VLMConfiguration,
  VLMGenerationOptions,
  VLMResult,
} from '@runanywhere/proto-ts/vlm_options';
export {
  VLMImageFormat,
  VLMErrorCode,
} from '@runanywhere/proto-ts/vlm_options';

// =========================================================================
// Diffusion — proto-canonical
// =========================================================================

export type {
  DiffusionTokenizerSource,
  DiffusionConfiguration,
  DiffusionGenerationOptions,
  DiffusionProgress,
  DiffusionResult,
  DiffusionCapabilities,
} from '@runanywhere/proto-ts/diffusion_options';
export {
  DiffusionMode,
  DiffusionScheduler,
  DiffusionModelVariant,
  DiffusionTokenizerSourceKind,
} from '@runanywhere/proto-ts/diffusion_options';

// =========================================================================
// LoRA — proto-canonical
// =========================================================================

export type {
  LoRAAdapterConfig,
  LoRAAdapterInfo,
  LoraAdapterCatalogEntry,
  LoraCompatibilityResult,
} from '@runanywhere/proto-ts/lora_options';

// =========================================================================
// RAG — proto-canonical
// =========================================================================

export type {
  RAGConfiguration,
  RAGQueryOptions,
  RAGSearchResult,
  RAGResult,
  RAGStatistics,
} from '@runanywhere/proto-ts/rag';

// =========================================================================
// Structured Output — proto-canonical
// =========================================================================

export type {
  JSONSchemaProperty,
  JSONSchema,
  StructuredOutputOptions,
  StructuredOutputResult,
  EntityExtractionResult,
  ClassificationCandidate,
  ClassificationResult,
  SentimentResult,
  NamedEntity,
  NERResult,
} from '@runanywhere/proto-ts/structured_output';
export {
  JSONSchemaType,
  Sentiment,
} from '@runanywhere/proto-ts/structured_output';

// =========================================================================
// Voice Agent — proto-canonical (control RPCs + streaming events)
// =========================================================================

export type {
  VoiceEvent,
  VoiceAgentComponentStates,
} from '@runanywhere/proto-ts/voice_events';
export {
  ComponentLoadState,
} from '@runanywhere/proto-ts/voice_events';
export type {
  VoiceSessionConfig as VoiceAgentConfig,
} from '@runanywhere/proto-ts/voice_agent_service';

// =========================================================================
// LLM types — proto-canonical (LLMGenerationOptions, LLMGenerationResult,
// LLMConfiguration, StreamToken) plus RN-local streaming primitives.
// =========================================================================

export type {
  LLMGenerationOptions,
  LLMGenerationResult,
  LLMConfiguration,
  StreamToken,
  LLMStreamingResult,
  LLMStreamingMetrics,
  LLMTokenCallback,
  LLMStreamCompleteCallback,
  LLMStreamErrorCallback,
} from './LLMTypes';

// =========================================================================
// Tool Calling Types (RN-local)
// =========================================================================

export type {
  ParameterType,
  ToolParameter,
  ToolDefinition,
  ToolCall,
  ToolResult,
  ToolExecutor,
  RegisteredTool,
  ToolCallingOptions,
  ToolCallingResult,
} from './ToolCallingTypes';

// =========================================================================
// NPU Chip Types (RN-local — device dispatch only)
// =========================================================================

export type { NPUChip } from './NPUChip';
export {
  NPU_CHIPS,
  NPU_BASE_URL,
  getNPUDownloadUrl,
  npuChipFromSocModel,
} from './NPUChip';
