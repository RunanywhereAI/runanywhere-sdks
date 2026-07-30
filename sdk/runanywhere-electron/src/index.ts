// @runanywhere/electron — on-device LLM / VLM / STT / TTS / VAD / embeddings /
// rerank / diarization / segmentation / RAG for Electron & Node, over the native
// addon. The v3 surface is the namespaced API; everything under "deprecated"
// below is a pre-v3 forwarder kept for one release.

// ---- v3 surface ----
export { createRunAnywhere } from './api/facade';
export type { InitializeOptions, RunAnywhereApi, SecureStore } from './api/facade';
export { NativeBackend, RAC_CATEGORY, RAC_FRAMEWORK } from './api/native-backend';
export { RpcBackend } from './api/rpc-backend';
export type { RpcSend } from './api/rpc-backend';
export { BACKEND_METHODS, BACKEND_STREAMING_METHODS, rpcMethodFor } from './api/backend';
export type { RaBackend, LoadSlot } from './api/backend';
export { bridgeStream, collect, streamOf } from './api/iter';
export type { StreamSink } from './api/iter';
export { SdkEventHub } from './api/hub';
export {
  audio,
  image,
  ragDocument,
  AgentState,
  AudioFormat,
  Environment,
  FinishReason,
  ImageMode,
  InferenceFramework,
  ModelCategory,
  NormalizeMode,
  PoolingMode,
  ReasoningMode,
  Role,
  TokenKind,
  ToolChoice,
  newRequestId,
} from './api/types';
export type {
  AppliedAdapter,
  Audio,
  AudioChunk,
  AudioFormatSpec,
  AudioInput,
  ChatMessage,
  ClassInfo,
  DiarizationResult,
  DownloadEvent,
  Embedding,
  GenerationEvent,
  GenerationMetrics,
  GenerationResult,
  ImageData,
  ImageEvent,
  ImageInput,
  ImageResult,
  LoraState,
  Match,
  ModelFilter,
  ModelInfo,
  ModelRef,
  ModelRegistration,
  ModelsState,
  RagDocument,
  RagEvent,
  RagResult,
  RagStats,
  RankedResult,
  SdkEvent,
  Segment,
  SegmentationResult,
  SpeakerSegment,
  SttState,
  StructuredResult,
  ToolCall,
  ToolDefinition,
  ToolExecutor,
  Transcription,
  TranscriptionEvent,
  VadEvent,
  VadResult,
  Voice,
  VoiceEvent,
  Word,
} from './api/types';
export type {
  DiarizationOptions,
  EmbedOptions,
  Endpointing,
  ImageOptions,
  Interruption,
  LlmOptions,
  LoadOptions,
  RagConfig,
  ReasoningOptions,
  SegmentationOptions,
  SttOptions,
  StructuredOutput,
  TtsOptions,
  TurnHandlingOptions,
  VadOptions,
} from './api/options';
// The namespace interfaces are reached through `RunAnywhereApi`, not by name.
export type { VoiceSession, VoiceSessionConfig } from './api/speech';
export type { RagSession } from './api/data';

// ---- deprecated (pre-v3) ----
// Where a pre-v3 name collides with a v3 one, the v3 name is canonical and the old
// type is re-exported with a `Legacy` prefix. The verbs themselves are unchanged.
export {
  RunAnywhere,
  LLMModel,
  VLMModel,
  Embedder,
  STTModel,
  TTSVoice,
  Vad,
} from './RunAnywhere';
export type {
  InitOptions,
  LoadOptions as LegacyLoadOptions,
  DownloadOptions,
  GenerateOptions,
  GenerateObjectOptions,
  ToolSpec,
  ToolRun,
  LLMStreamEvent,
  LLMGenerationResult,
  Environment as LegacyEnvironment,
  VadOptions as LegacyVadOptions,
} from './RunAnywhere';
export { SDKException, ErrorCode, ErrorCategory, isSDKException, asSDKException, raiseForRac } from './errors';
export { EventBus } from './events';
export type {
  RunAnywhereEvent,
  EventListener,
  Modality,
  LifecycleEvent,
  ModelLoadedEvent,
  ModelUnloadedEvent,
  GenerationEvent as GenerationTelemetryEvent,
} from './events';
export { jsonSchemaToGrammar } from './grammar';
export type { JsonSchema } from './grammar';
export { objectGrammar, toolCallSchema, toolCallPrompt } from './structured';
export { splitThinking, stripThinking, isThinking } from './thinking';
export type { ThinkingSplit } from './thinking';
export { streamWithMetrics } from './stream';
export {
  float32ToPcm16,
  pcm16ToFloat32,
  pcm16Bytes,
  downsample,
  rms,
  encodeWav,
  decodeWav,
  MicRecorder,
  SpeakerPlayer,
} from './audio';
export type { MicRecorderOptions } from './audio';
export { Chat } from './Chat';
export type { ChatMessage as LegacyChatMessage, ChatOptions } from './Chat';
export { VoiceAgent } from './VoiceAgent';
export type {
  VoiceAgentModels,
  VoiceAgentOptions,
  VoiceTurn,
  VoiceTurnCallbacks,
} from './VoiceAgent';
export type { NativeAddon } from './bridge';
export { CATALOG, isCatalogId } from './catalog';
export type { CatalogEntry, ModelType } from './catalog';
export { resolveModel, downloadFile, modelsRoot } from './download';
export type { DownloadProgress, ResolvedModel } from './download';
export {
  RagSession as LegacyRagSession,
  createRagSessionFromCatalog,
  frameworkForModelPath,
  RagModelCategory,
  RagInferenceFramework,
} from './rag';
export type {
  RagConfig as LegacyRagConfig,
  RagDoc,
  RagQuery,
  RagGenerationOptions,
  RagResult as LegacyRagResult,
  RagChunk,
  RagStats as LegacyRagStats,
  RagBridge,
  RagCatalogBridge,
  RagResolvedModel,
} from './rag';
