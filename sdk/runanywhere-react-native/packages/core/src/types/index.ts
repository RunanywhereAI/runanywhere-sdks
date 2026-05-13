/**
 * RunAnywhere React Native SDK public types.
 *
 * Structures, model metadata, event envelopes, storage, download, tool, and
 * voice contracts are generated from proto IDL. RN-only survivors here are
 * limited to JS call-site helpers that cannot round-trip over proto, such as
 * callback/function-reference types.
 */

// =========================================================================
// Proto enums plus RN-only helper enums
// =========================================================================

export {
  AccelerationPreference,
  AudioFormat,
  ComponentLifecycleState,
  EventCategory,
  EventDestination,
  ErrorSeverity,
  ExecutionTarget,
  FrameworkModality,
  InferenceFramework,
  ModelArtifactType,
  ModelCategory,
  ModelCategoryDisplayNames,
  ModelFormat,
  ModelSource,
  PrivacyMode,
  RoutingPolicy,
  SDKComponent,
  SDKEnvironment,
} from './enums';

export type { SDKInitOptions } from './models';

// =========================================================================
// Model registry / lifecycle — proto-canonical
// =========================================================================

export type {
  ArchiveArtifact,
  CurrentModelRequest,
  CurrentModelResult,
  DiscoveredModel,
  ExpectedModelFiles,
  ModelCompatibilityResult,
  ModelDeleteRequest,
  ModelDeleteResult,
  ModelDiscoveryRequest,
  ModelDiscoveryResult,
  ModelFileDescriptor,
  ModelGetRequest,
  ModelGetResult,
  ModelImportRequest,
  ModelImportResult,
  ModelInfo,
  ModelInfoList,
  ModelInfoMetadata,
  ModelListRequest,
  ModelListResult,
  ModelLoadRequest,
  ModelLoadResult,
  ModelQuery,
  ModelRegistryRefreshRequest,
  ModelRegistryRefreshResult,
  ModelRuntimeCompatibility,
  ModelUnloadRequest,
  ModelUnloadResult,
  MultiFileArtifact,
  SingleFileArtifact,
} from '@runanywhere/proto-ts/model_types';
export type { ThinkingTagPattern } from '@runanywhere/proto-ts/thinking_tag_pattern';
export {
  ArchiveStructure,
  ArchiveType,
  ModelFileRole,
  ModelQuerySortField,
  ModelQuerySortOrder,
  ModelRegistryStatus,
} from '@runanywhere/proto-ts/model_types';

// =========================================================================
// Events / components — proto-canonical
// =========================================================================

export type {
  ComponentInitializationEvent,
  ComponentLifecycleEvent,
  ComponentLifecycleSnapshot,
  ComponentLifecycleSnapshotRequest,
  ComponentLifecycleSnapshotResult,
  ConfigurationEvent,
  DeviceEvent,
  FrameworkEvent,
  GenerationEvent,
  InitializationEvent,
  ModelEvent,
  NetworkEvent,
  PerformanceEvent,
  SDKEvent,
  SessionEvent,
  StorageEvent,
  VoiceLifecycleEvent,
} from '@runanywhere/proto-ts/sdk_events';
export {
  ComponentInitializationEventKind,
  ConfigurationEventKind,
  DeviceEventKind,
  FrameworkEventKind,
  GenerationEventKind,
  InitializationStage,
  ModelEventKind,
  NetworkEventKind,
  PerformanceEventKind,
  SessionEventKind,
  StorageEventKind,
  VoiceEventKind,
} from '@runanywhere/proto-ts/sdk_events';

// =========================================================================
// Download / storage — proto-canonical
// =========================================================================

export type {
  DownloadCancelRequest,
  DownloadCancelResult,
  DownloadFilePlan,
  DownloadPlanRequest,
  DownloadPlanResult,
  DownloadProgress,
  DownloadResumeRequest,
  DownloadResumeResult,
  DownloadStartRequest,
  DownloadStartResult,
  DownloadSubscribeRequest,
} from '@runanywhere/proto-ts/download_service';
export {
  DownloadStage,
  DownloadState,
} from '@runanywhere/proto-ts/download_service';

export type {
  AppStorageInfo,
  DeviceStorageInfo,
  ModelStorageMetrics,
  StorageAvailability,
  StorageAvailabilityRequest,
  StorageAvailabilityResult,
  StorageDeleteCandidate,
  StorageDeletePlan,
  StorageDeletePlanRequest,
  StorageDeleteRequest,
  StorageDeleteResult,
  StorageInfo,
  StorageInfoRequest,
  StorageInfoResult,
  StoredModel,
} from '@runanywhere/proto-ts/storage_types';
export { NPUChip } from '@runanywhere/proto-ts/storage_types';

// =========================================================================
// Hardware — proto-canonical
// =========================================================================

export type {
  AcceleratorInfo,
  HardwareProfile,
  HardwareProfileResult,
} from '@runanywhere/proto-ts/hardware_profile';

// =========================================================================
// STT / TTS / VAD / VLM / Diffusion — proto-canonical
// =========================================================================

export type {
  STTAudioSource,
  STTConfiguration,
  STTLanguageDetectionResult,
  STTOptions,
  STTOutput,
  STTPartialResult,
  STTServiceState,
  STTStreamEvent,
  STTTranscriptionRequest,
  TranscriptionAlternative,
  TranscriptionMetadata,
  WordTimestamp,
} from '@runanywhere/proto-ts/stt_options';
export {
  STTAudioEncoding,
  STTLanguage,
  STTStreamEventKind,
} from '@runanywhere/proto-ts/stt_options';

export type {
  TTSConfiguration,
  TTSOptions,
  TTSOutput,
  TTSPhonemeTimestamp,
  TTSServiceState,
  TTSSpeakResult,
  TTSSynthesisMetadata,
  TTSSynthesisRequest,
  TTSStreamEvent,
  TTSVoiceInfo,
} from '@runanywhere/proto-ts/tts_options';
export {
  TTSStreamEventKind,
  TTSVoiceGender,
} from '@runanywhere/proto-ts/tts_options';

export type {
  SpeechActivityEvent,
  VADAudioSource,
  VADConfiguration,
  VADOptions,
  VADProcessRequest,
  VADResult,
  VADServiceState,
  VADStatistics,
  VADStreamEvent,
} from '@runanywhere/proto-ts/vad_options';
export {
  SpeechActivityKind,
  VADAudioEncoding,
  VADStreamEventKind,
} from '@runanywhere/proto-ts/vad_options';

export type {
  VLMConfiguration,
  VLMGenerationOptions,
  VLMGenerationRequest,
  VLMImage,
  VLMResult,
  VLMServiceState,
  VLMStreamEvent,
} from '@runanywhere/proto-ts/vlm_options';
export {
  VLMImageFormat,
  VLMModelFamily,
  VLMStreamEventKind,
} from '@runanywhere/proto-ts/vlm_options';

export type {
  DiffusionCapabilities,
  DiffusionConfig,
  DiffusionConfiguration,
  DiffusionGenerationOptions,
  DiffusionGenerationRequest,
  DiffusionProgress,
  DiffusionResult,
  DiffusionServiceState,
  DiffusionStreamEvent,
  DiffusionTokenizerSource,
} from '@runanywhere/proto-ts/diffusion_options';
export {
  DiffusionMode,
  DiffusionModelVariant,
  DiffusionScheduler,
  DiffusionStreamEventKind,
  DiffusionTokenizerSourceKind,
} from '@runanywhere/proto-ts/diffusion_options';

// =========================================================================
// LLM / chat / embeddings — proto-canonical plus RN-only stream wrappers
// =========================================================================

export type {
  LLMConfiguration,
  LLMGenerationOptions,
  LLMGenerationRequest,
  LLMGenerationResult,
  LLMGenerationStatus,
  PerformanceMetrics,
  StreamToken,
} from '@runanywhere/proto-ts/llm_options';
export { LLMGenerationState } from '@runanywhere/proto-ts/llm_options';

export type {
  ChatAttachment,
  ChatConversationState,
  ChatGenerationRequest,
  ChatGenerationResult,
  ChatMessage,
  ChatStreamEvent,
} from '@runanywhere/proto-ts/chat';
export {
  ChatMessageStatus,
  ChatStreamEventKind,
  MessageRole,
} from '@runanywhere/proto-ts/chat';

export type {
  EmbeddingVector,
  EmbeddingsConfiguration,
  EmbeddingsOptions,
  EmbeddingsRequest,
  EmbeddingsResult,
  EmbeddingsServiceState,
} from '@runanywhere/proto-ts/embeddings_options';
export {
  EmbeddingsNormalizeMode,
  EmbeddingsPoolingStrategy,
} from '@runanywhere/proto-ts/embeddings_options';

// =========================================================================
// LoRA / RAG / structured output — proto-canonical
// =========================================================================

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
} from '@runanywhere/proto-ts/lora_options';

export type {
  RAGConfiguration,
  RAGDocument,
  RAGIngestRequest,
  RAGIngestResult,
  RAGQueryOptions,
  RAGQueryRequest,
  RAGResult,
  RAGSearchResult,
  RAGServiceState,
  RAGStatistics,
  RAGStreamEvent,
} from '@runanywhere/proto-ts/rag';
export { RAGStreamEventKind } from '@runanywhere/proto-ts/rag';

export type {
  ClassificationCandidate,
  ClassificationResult,
  EntityExtractionResult,
  JSONSchema,
  JSONSchemaProperty,
  NamedEntity,
  NERResult,
  SentimentResult,
  StructuredOutputOptions,
  StructuredOutputResult,
  StructuredOutputStreamEvent,
} from '@runanywhere/proto-ts/structured_output';
export {
  JSONSchemaType,
  Sentiment,
  StructuredOutputStreamEventKind,
} from '@runanywhere/proto-ts/structured_output';

// =========================================================================
// Voice agent / voice events — proto-canonical
// =========================================================================

export type {
  AgentResponseCompletedEvent,
  AgentResponseStartedEvent,
  AssistantTokenEvent,
  AudioFrameEvent,
  AudioLevelEvent,
  SessionStartedEvent,
  SessionStoppedEvent,
  UserSaidEvent,
  VoiceAgentComponentStates,
  VoiceEvent,
  VoiceSessionError,
} from '@runanywhere/proto-ts/voice_events';
export type {
  VoiceAgentComposeConfig,
  VoiceAgentComposeConfig as VoiceAgentConfig,
  VoiceAgentRequest,
  VoiceAgentResult,
  VoiceAgentTurnRequest,
  VoiceSessionConfig,
} from '@runanywhere/proto-ts/voice_agent_service';

// =========================================================================
// Tool Calling — proto-canonical plus RN-only function-reference helpers
// =========================================================================

export type {
  ToolCall,
  ToolCallingOptions,
  ToolCallingResult,
  ToolCallingStreamEvent,
  ToolDefinition,
  ToolParameter,
  ToolParseRequest,
  ToolParseResult,
  ToolRegistrySnapshot,
  ToolResult,
  ToolValue,
} from '@runanywhere/proto-ts/tool_calling';
export {
  ToolCallFormatName,
  ToolCallingStreamEventKind,
  ToolChoiceMode,
  ToolParameterType,
} from '@runanywhere/proto-ts/tool_calling';

export type {
  RegisteredTool,
  ToolExecutor,
} from '../Public/Extensions/LLM/RunAnywhere+ToolCalling';
