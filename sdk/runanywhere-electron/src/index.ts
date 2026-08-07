// @runanywhere/electron — on-device LLM/VLM/STT/TTS/VAD/embeddings/RAG for
// Electron and Node, a thin binding over the C++ commons core. The public
// surface mirrors the Swift SDK; both hosts (main process and renderer) share
// one facade over a RaBackend.

export { createRunAnywhere } from './facade.js';
export type { InitializeOptions, RunAnywhereApi } from './facade.js';

export { NativeBackend } from './native/backend.js';
export { loadAddon } from './native/load.js';
export type { NativeAddon } from './native/addon-api.js';
export { RpcBackend } from './rpc/backend.js';
export type { RpcSend } from './rpc/backend.js';
export type { ControlPlaneRequest, ProtoBytes, ProtoSink, RaBackend } from './backend.js';
export { BACKEND_METHODS, BACKEND_STREAMING_METHODS, rpcMethodFor } from './backend.js';

export { SDKException, ErrorCode, ErrorCategory, isSDKException, asSDKException, raiseForRac } from './errors.js';
export { NativeResource, ResourceGuard } from './resources.js';
export { AsyncQueue, bridgeStream, collect, streamOf } from './stream.js';
export type { StreamSink } from './stream.js';
export { SdkEventHub } from './events.js';

export { Environment, Role, FinishReason } from './types.js';
export type {
  AudioInput,
  ChatMessage,
  DownloadEvent,
  DownloadProgress,
  Embedding,
  GenerationEvent,
  GenerationMetrics,
  GenerationResult,
  ImageInput,
  LoadedModel,
  ModelFilter,
  ModelInfo,
  ModelRef,
  ModelsState,
  RankedResult,
  SDKCapabilities,
  SdkEvent,
  ToolCall,
  UnavailableCapability,
} from './types.js';

export { LLM_DEFAULTS, toLlmGenerationOptions } from './options.js';
export type { LlmOptions } from './options.js';
export { jsonSchemaToGrammar } from './grammar.js';
export type { JsonSchema } from './grammar.js';

export type {
  LlmNamespace,
  ToolsNamespace,
  ToolDefinition,
  ToolExecutor,
  ToolCallRecord,
  ToolRunResult,
} from './namespaces/llm.js';
export { ModelRegistration } from './namespaces/models.js';
export type {
  ModelsNamespace,
  ModelRegistrationSpec,
  ModelFileSpec,
  ModelFramework,
  ModelModality,
  LoadOptions,
} from './namespaces/models.js';
export type { VlmNamespace } from './namespaces/vlm.js';
export type {
  SttNamespace,
  SttOptions,
  Transcription,
  AudioFormatSpec,
  TranscriptionEvent,
  SttState,
  SttStream,
} from './namespaces/stt.js';
export type { TtsNamespace, TtsOptions, Audio, AudioChunk, Voice, SampleFormat } from './namespaces/tts.js';
export type { VadNamespace, VadOptions, VadFrame, VadResult, VadEvent, VadStream, Segment } from './namespaces/vad.js';
export type { EmbeddingsNamespace, EmbedOptions } from './namespaces/embeddings.js';
export type {
  DiarizationNamespace,
  DiarizationParams,
  Diarization,
  SpeakerSegment,
} from './namespaces/diarization.js';
export type {
  SegmentationNamespace,
  SegmentationParams,
  Segmentation,
} from './namespaces/segmentation.js';
export type {
  RagNamespace,
  RagSession,
  RagConfig,
  RagDoc,
  RagResult,
  RagStats,
  Match,
  RagQueryOptions,
  RagEvent,
} from './namespaces/rag.js';

export { toPcm16, downsample, rms, resampleInput, to16kPcm16, audioToRaw, audioToSource } from './audio.js';
export type { RawAudio, AudioSourceFields } from './audio.js';
export type { RerankNamespace } from './namespaces/placeholders.js';
export type { ImagesNamespace, ImageOptions, ImageResult, ImageData } from './namespaces/images.js';
export type { LoraNamespace, AppliedAdapter } from './namespaces/lora.js';
export type {
  VoiceNamespace,
  VoiceSession,
  VoiceSessionConfig,
  VoiceTurn,
} from './namespaces/voice.js';

// Renderer entry + RPC plumbing (electron-free). RunAnywhereMain / preload / host
// import electron and are reached only through the ./main, ./preload, ./host
// package subpaths, never the root entry.
export { connectRenderer } from './rpc/renderer.js';
export { ALLOWED_RPC_METHODS, dispatch } from './rpc/dispatch.js';
export type { BackendMap, DispatchDeps, DispatchPort } from './rpc/dispatch.js';
export { STREAMING_METHODS } from './rpc/protocol.js';
export type { RpcErrorPayload, RpcMessage, RpcRequest } from './rpc/protocol.js';
