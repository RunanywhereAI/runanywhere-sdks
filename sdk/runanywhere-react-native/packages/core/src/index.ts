/**
 * @runanywhere/core — the React Native public SDK surface.
 *
 * `RunAnywhere` is the single entry point: `initialize` once, then reach every
 * capability through its namespace. The v3 option, input, result, and event
 * types live alongside it here; wire-level generated messages stay in
 * `@runanywhere/proto-ts`, and provider plumbing in
 * `@runanywhere/core/internal`.
 *
 * @packageDocumentation
 */

export { RunAnywhere } from './Public/RunAnywhere';

export { AudioInputs, ImageInputs } from './Public/Api/Inputs';
export type { RagOpenOptions } from './Public/Api/Rag';
export type { VoiceCreateSessionOptions } from './Public/Api/Voice';

export type {
  AgentState,
  ArchiveLayout,
  Audio,
  AudioChunk,
  AudioEncoding,
  AudioFormatName,
  AudioInput,
  AppliedAdapter,
  ChatMessage,
  ChatRole,
  ClassInfo,
  DiarizationOptions,
  DiarizationResult,
  DownloadEvent,
  EmbedOptions,
  Embedding,
  Environment,
  FinishReason,
  GenerationEvent,
  GenerationResult,
  ImageData,
  ImageEvent,
  ImageInput,
  ImageMode,
  ImageOptions,
  ImagePixelFormat,
  ImageResult,
  InitializeOptions,
  JsonSchema,
  LlmOptions,
  LoadOptions,
  LoraState,
  Match,
  ModelFile,
  ModelFilter,
  ModelRef,
  ModelRegistration,
  ModelsState,
  PoolingMode,
  RagConfig,
  RagDocument,
  RagEvent,
  RagResult,
  RagSession,
  RagStats,
  RankedResult,
  ReasoningOptions,
  SdkEvent,
  Segment,
  SegmentationOptions,
  SegmentationResult,
  SpeakerSegment,
  SttOptions,
  SttState,
  StructuredOutput,
  StructuredResult,
  TokenKind,
  ToolCall,
  ToolChoice,
  ToolDefinition,
  ToolExecutor,
  Transcription,
  TranscriptionEvent,
  TtsOptions,
  TurnHandlingOptions,
  VadEvent,
  VadOptions,
  VadResult,
  Voice,
  VoiceEvent,
  VoiceSession,
  Word,
} from './Public/Api/Types';

// Hybrid STT router (offline sherpa <-> cloud). THIN binding over the commons
// hybrid router — commons owns all routing. Outside the v3 modality spec.
export {
  HybridSTTRouter,
  CloudSTT,
  HybridDeviceState,
  HybridBackendKind,
  DEFAULT_CLOUD_PROVIDER,
  HYBRID_STT_CONFIDENCE_THRESHOLD,
  Filters,
  Cascades,
  offlineSherpa,
  onlineCloud,
} from './Public/Extensions/Hybrid';
export type {
  HybridModel,
  HybridTranscribeOptions,
  HybridTranscribeResult,
  HybridRoutedMetadata,
  HybridFilter,
  HybridCascade,
  HybridRoutingPolicy,
  CustomFilterCheck,
  CloudModelEntry,
  CloudRegisterOptions,
  CloudSttProviderHandler,
  CloudSttProviderRequest,
  CloudSttProviderResult,
  HybridDeviceStateProvider,
} from './Public/Extensions/Hybrid';

export { SDKEnvironment } from '@runanywhere/proto-ts/model_types';

// SDKEnvironment behaviour helpers.
export {
  deployableEnvironments,
  environmentDescription,
  isProduction,
  isTesting,
  requiresBackendURL,
  shouldSendTelemetry,
  shouldSyncWithBackend,
  requiresAuthentication,
  defaultLogLevel,
} from './Public/Helpers/SDKEnvironment+Helpers';

// SDKComponent display names.
export { sdkComponentDisplayName } from './Public/Helpers/SDKComponent+DisplayName';

// Framework display names sourced from the commons table.
export { formatFramework } from './Public/Helpers/formatFramework';

// Explicit tool-calling run loop — mirrors Swift/Kotlin generateWithTools for
// hosts that need full control over the tool-loop budget (max calls, thinking,
// parallel execution) beyond what llm.generate's inline tools expose.
export { generateWithTools } from './Public/Extensions/LLM/RunAnywhere+ToolCalling';
export type {
  GenerateWithToolsOptions,
  ToolCallingOptions,
  ToolCallingResult,
} from './Public/Extensions/LLM/RunAnywhere+ToolCalling';

// Pushable audio stream — feeds microphone chunks into the streaming verbs.
export {
  createPushableAudioStream,
  type PushableAudioStream,
} from './Public/Helpers/PushableAudioStream';

// PCM conversion helpers for apps that own their own audio capture UI.
export { AudioConvert } from './Public/Extensions/Audio/RunAnywhere+AudioConvert';

// Computer-Use Agent (CUA) — mirror Swift RunAnywhere+CUA.swift.
export {
  cua,
  systemPrompt as cuaSystemPrompt,
  parseAction as cuaParseAction,
  CuaActionKind,
  FARA_PROFILE,
} from './Public/Extensions/CUA/RunAnywhere+CUA';
export type {
  CuaAction,
  CuaCoordinate,
  CuaDisplaySize,
} from './Public/Extensions/CUA/RunAnywhere+CUA';

// Embedding vector math helpers.
export {
  cosineSimilarity,
  computeNorm,
} from './Public/Extensions/Embeddings/EmbeddingsProto+Helpers';

// Storage proto helpers.
export {
  makeDeviceStorageInfo,
  makeAppStorageInfo,
  makeModelStorageMetrics,
  makeStorageAvailability,
  emptyStorageInfo,
  totalModelsSizeBytes,
  totalModelsSize,
  usagePercentage,
} from './Public/Extensions/Storage/StorageProto+Helpers';

export {
  ErrorCode,
  ErrorCategory,
  SDKException,
  isSDKException,
  asSDKException,
  isExpectedErrorCode,
  sdkExceptionFromRcResult,
  throwIfRcError,
} from './Foundation/Errors';
export type { ErrorContext } from './Foundation/Errors';

// In-SDK audio capture/playback for apps that drive their own audio UI.
export { AudioCaptureManager } from './Features/VoiceSession/AudioCaptureManager';
export { AudioPlaybackManager } from './Features/VoiceSession/AudioPlaybackManager';

export type {
  PluginInfo,
  PluginLoaderCapability,
} from './Public/Extensions/RunAnywhere+PluginLoader';
