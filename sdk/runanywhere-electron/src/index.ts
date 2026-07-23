// @runanywhere/electron — on-device LLM / VLM / STT / TTS / embeddings for
// Electron & Node, over the Hexagon-ready native addon (Windows-first).
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
  LoadOptions,
  DownloadOptions,
  GenerateOptions,
  GenerateObjectOptions,
  ToolSpec,
  ToolCall,
  ToolRun,
  LLMStreamEvent,
  LLMGenerationResult,
  Environment,
  VadOptions,
} from './RunAnywhere';
export { SDKException, ErrorCode, ErrorCategory, isSDKException, asSDKException } from './errors';
export { EventBus } from './events';
export type {
  RunAnywhereEvent,
  EventListener,
  Modality,
  LifecycleEvent,
  ModelLoadedEvent,
  ModelUnloadedEvent,
  GenerationEvent,
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
export type { ChatMessage, ChatOptions } from './Chat';
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
export { RagSession } from './rag';
export type { RagConfig, RagDoc, RagQuery, RagResult, RagChunk, RagStats, RagBridge } from './rag';
