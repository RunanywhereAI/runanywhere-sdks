// @runanywhere/electron — on-device LLM / VLM / STT / TTS / embeddings for
// Electron & Node, over the Hexagon-ready native addon (Windows-first).
export {
  RunAnywhere,
  LLMModel,
  VLMModel,
  Embedder,
  STTModel,
  TTSVoice,
} from './RunAnywhere';
export type { InitOptions, LoadOptions, DownloadOptions } from './RunAnywhere';
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
