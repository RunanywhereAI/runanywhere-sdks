/**
 * NativeRunAnywhereModule.ts
 *
 * Full native module type that includes ALL methods from core + backends.
 * All methods are defined as required for TypeScript compilation.
 * At runtime, methods that require backend packages may throw errors.
 */

import type { RunAnywhereCore } from '../specs/RunAnywhereCore.nitro';

/**
 * Extended native module type that includes all possible methods.
 * This combines core functionality with backend methods.
 *
 * Methods are organized by package:
 * - Core: Always available
 * - LLM: Requires @runanywhere/llamacpp
 * - STT/TTS/VAD/VoiceAgent: Requires @runanywhere/onnx
 */
export interface NativeRunAnywhereModule extends RunAnywhereCore {
  // ==========================================================================
  // DEPRECATED: Legacy methods for backwards compatibility
  // ==========================================================================

  /** @deprecated Use initialize() instead */
  createBackend(name: string): Promise<boolean>;

  // ==========================================================================
  // LLM Methods (require @runanywhere/llamacpp)
  // ==========================================================================

  loadTextModel(path: string, configJson?: string): Promise<boolean>;
  isTextModelLoaded(): Promise<boolean>;
  unloadTextModel(): Promise<boolean>;
  generate(prompt: string, optionsJson?: string): Promise<string>;
  generateStream(
    prompt: string,
    optionsJson: string,
    callback: (token: string, isComplete: boolean) => void
  ): Promise<string>;
  cancelGeneration(): Promise<boolean>;
  generateStructured(
    prompt: string,
    schema: string,
    optionsJson?: string
  ): Promise<string>;

  // ==========================================================================
  // STT Methods (require @runanywhere/onnx)
  // ==========================================================================

  loadSTTModel(
    path: string,
    modelType: string,
    configJson?: string
  ): Promise<boolean>;
  isSTTModelLoaded(): Promise<boolean>;
  unloadSTTModel(): Promise<boolean>;
  transcribe(
    audioBase64: string,
    sampleRate: number,
    language?: string
  ): Promise<string>;
  transcribeFile(filePath: string, language?: string): Promise<string>;
  supportsSTTStreaming(): Promise<boolean>;
  startStreamingSTT(language?: string): Promise<boolean>;
  stopStreamingSTT(): Promise<boolean>;
  isStreamingSTT(): Promise<boolean>;

  // ==========================================================================
  // TTS Methods (require @runanywhere/onnx)
  // ==========================================================================

  loadTTSModel(
    path: string,
    modelType: string,
    configJson?: string
  ): Promise<boolean>;
  isTTSModelLoaded(): Promise<boolean>;
  unloadTTSModel(): Promise<boolean>;
  synthesize(
    text: string,
    voiceId: string,
    speedRate: number,
    pitchShift: number
  ): Promise<string>;
  getTTSVoices(): Promise<string>;
  cancelTTS(): Promise<boolean>;

  // ==========================================================================
  // VAD Methods (require @runanywhere/onnx)
  // ==========================================================================

  loadVADModel(path: string, configJson?: string): Promise<boolean>;
  isVADModelLoaded(): Promise<boolean>;
  unloadVADModel(): Promise<boolean>;
  processVAD(audioBase64: string, optionsJson?: string): Promise<string>;
  resetVAD(): Promise<void>;

  // ==========================================================================
  // Voice Agent Methods (require @runanywhere/onnx + @runanywhere/llamacpp)
  // ==========================================================================

  initializeVoiceAgent(configJson: string): Promise<boolean>;
  initializeVoiceAgentWithLoadedModels(): Promise<boolean>;
  isVoiceAgentReady(): Promise<boolean>;
  getVoiceAgentComponentStates(): Promise<string>;
  processVoiceTurn(audioBase64: string): Promise<string>;
  voiceAgentTranscribe(audioBase64: string): Promise<string>;
  voiceAgentGenerateResponse(prompt: string): Promise<string>;
  voiceAgentSynthesizeSpeech(text: string): Promise<string>;
  cleanupVoiceAgent(): Promise<void>;

  // ==========================================================================
  // Download Service Extensions
  // ==========================================================================

  startModelDownload(
    modelId: string,
    url?: string,
    destPath?: string
  ): Promise<string>;
  pauseDownload(modelId: string): Promise<boolean>;
  resumeDownload(modelId: string): Promise<boolean>;
  pauseAllDownloads(): Promise<boolean>;
  resumeAllDownloads(): Promise<boolean>;
  cancelAllDownloads(): Promise<boolean>;
  configureDownloadService(configJson: string): Promise<boolean>;
  isDownloadServiceHealthy(): Promise<boolean>;

  // ==========================================================================
  // Model Registry Extensions
  // ==========================================================================

  discoverModels(): Promise<string>;
  getModel(modelId: string): Promise<string>;
  availableModels(): Promise<string>;
  updateModel(modelIdOrJson: string, modelJson?: string): Promise<boolean>;
  removeModel(modelId: string): Promise<boolean>;
  addModelFromURL(url: string, optionsJson?: string): Promise<string>;
  getDownloadedModels(): Promise<string>;

  // ==========================================================================
  // Secure Storage Extensions
  // ==========================================================================

  secureStorageIsAvailable(): Promise<boolean>;
  secureStorageStore(key: string, value: string): Promise<boolean>;
  secureStorageRetrieve(key: string): Promise<string | null>;
  secureStorageDelete(key: string): Promise<boolean>;
  secureStorageExists(key: string): Promise<boolean>;

  // ==========================================================================
  // Backend Registration (LlamaCPP + ONNX)
  // ==========================================================================

  registerLlamaCppBackend(): Promise<boolean>;
  unregisterLlamaCppBackend(): Promise<boolean>;
  registerONNXBackend(): Promise<boolean>;
  unregisterONNXBackend(): Promise<boolean>;
}

/**
 * Type guard to check if a method is available on the native module
 */
export function hasNativeMethod<K extends keyof NativeRunAnywhereModule>(
  native: NativeRunAnywhereModule,
  method: K
): boolean {
  return typeof native[method] === 'function';
}
