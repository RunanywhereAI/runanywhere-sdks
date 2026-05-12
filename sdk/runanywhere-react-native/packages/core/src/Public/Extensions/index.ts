/**
 * RunAnywhere Extensions
 *
 * Re-exports all extension modules for convenient importing.
 */

// Text Generation (LLM)
export {
  isModelLoaded,
  unloadModel,
  chat,
  generate,
  generateStream,
  cancelGeneration,
} from './LLM/RunAnywhere+TextGeneration';

// Speech-to-Text
export {
  isSTTModelLoaded,
  unloadSTTModel,
  transcribe,
  transcribeSimple,
  transcribeBuffer,
  transcribeStream,
  transcribeFile,
  currentSTTModel,
} from './STT/RunAnywhere+STT';

// Text-to-Speech
export {
  isTTSModelLoaded,
  isTTSVoiceLoaded,
  unloadTTSModel,
  synthesize,
  synthesizeStream,
  synthesizeStreamAsync,
  speak,
  isSpeaking,
  stopSpeaking,
  availableTTSVoices,
  getTTSVoiceInfo,
  stopSynthesis,
  cancelTTS,
  cleanupTTS,
} from './TTS/RunAnywhere+TTS';

// Voice Activity Detection
export {
  isVADModelLoaded,
  unloadVADModel,
  detectSpeech,
  detectVoiceActivity,
  processVAD,
  resetVAD,
  // VAD activity stream (§6)
  streamVADActivity,
  // VAD streaming (§6)
  streamVAD,
  // VAD statistics (§6)
  getVADStatistics,
} from './VAD/RunAnywhere+VAD';

// Voice Agent
export {
  initializeVoiceAgent,
  initializeVoiceAgentWithLoadedModels,
  isVoiceAgentReady,
  getVoiceAgentComponentStates,
  areAllVoiceComponentsReady,
  processVoiceTurn,
  voiceAgentTranscribe,
  voiceAgentSynthesizeSpeech,
  cleanupVoiceAgent,
} from './VoiceAgent/RunAnywhere+VoiceAgent';

// v3.1: Voice Session exports DELETED. Use VoiceAgentStreamAdapter from
// the package root (`@runanywhere/core`) for streaming voice events.

// Structured Output
export {
  generateStructured,
  generateStructuredStream,
  extractStructuredOutput,
  prepareStructuredOutputPrompt,
  validateStructuredOutput,
  generate as generateStructuredType,
  extractEntities,
  classify,
} from './LLM/RunAnywhere+StructuredOutput';

// Hardware Profile (CANONICAL_API §14)
export {
  getProfile as getHardwareProfile,
  getChip as getHardwareChip,
  hasNeuralEngine as hardwareHasNeuralEngine,
  accelerationMode as hardwareAccelerationMode,
  getAccelerators as getHardwareAccelerators,
  setAcceleratorPreference as setHardwareAcceleratorPreference,
  AccelerationPreference,
  Hardware,
} from './RunAnywhere+Hardware';
export type {
  AcceleratorInfo,
  HardwareProfileResult,
} from './RunAnywhere+Hardware';

// Logging
export {
  configureLogging,
  setLocalLoggingEnabled,
  setLogLevel,
  setSentryLoggingEnabled,
  addLogDestination,
  setDebugMode,
  flushLogs,
} from './RunAnywhere+Logging';

// Plugin Loader
export { pluginLoader } from './RunAnywhere+PluginLoader';
export type {
  PluginInfo,
  PluginLoaderCapability,
} from './RunAnywhere+PluginLoader';

// Canonical SDK event stream
export {
  pollSDKEvent,
  publishSDKEvent,
  publishSDKFailure,
  subscribeSDKEvents,
} from '../Events/RunAnywhere+SDKEvents';

// Canonical model/component lifecycle (commons-driven loading)
export {
  getComponentLifecycleSnapshot,
  getCurrentModel,
  getLifecycleResolvedArtifactPath,
  loadModelLifecycle,
  resolveVLMArtifactsFromLifecycleResult,
  unloadModelLifecycle,
} from './Models/RunAnywhere+ModelLifecycle';

// Storage
export {
  clearCache,
  cleanTempFiles,
  deleteStorage,
  getStorageInfo,
  getStorageInfoProto,
} from './Storage/RunAnywhere+Storage';

// Audio Utilities
export {
  requestAudioPermission,
  startRecording,
  stopRecording,
  cancelRecording,
  playAudio,
  stopPlayback,
  pausePlayback,
  resumePlayback,
  createWavFromPCMFloat32,
  cleanup as cleanupAudio,
  formatDuration,
  AUDIO_SAMPLE_RATE,
  TTS_SAMPLE_RATE,
} from './RunAnywhere+Audio';
export type {
  RecordingCallbacks,
  PlaybackCallbacks,
  RecordingResult,
} from './RunAnywhere+Audio';

// Re-export Audio as namespace for RunAnywhere.Audio access
import * as Audio from './RunAnywhere+Audio';
export { Audio };

// Tool Calling
export {
  registerTool,
  unregisterTool,
  getRegisteredTools,
  clearTools,
  executeTool,
  validateToolCall,
  formatToolsForPromptAsync,
  generateWithTools,
  continueWithToolResult,
} from './LLM/RunAnywhere+ToolCalling';

// RAG Pipeline
export {
  ragCreatePipeline,
  ragDestroyPipeline,
  ragIngest,
  ragAddDocumentsBatch,
  ragQuery,
  ragClearDocuments,
  ragGetDocumentCount,
  ragGetStatistics,
} from './RAG/RunAnywhere+RAG';

// Solutions Runtime (T4.7 / T4.8)
export { solutions, SolutionHandle } from './Solutions/RunAnywhere+Solutions';
export type { SolutionRunArgs } from './Solutions/RunAnywhere+Solutions';

// Vision Language Model
export {
  registerVLMBackend,
  loadVLMModel,
  loadVLMModelById,
  isVLMModelLoaded,
  unloadVLMModel,
  describeImage,
  askAboutImage,
  processImage,
  processImageStream,
  cancelVLMGeneration,
} from './VLM/RunAnywhere+VisionLanguage';
export type { VLMBackendProvider } from './VLM/RunAnywhere+VisionLanguage';

// Model Management — register / list / download / delete / load (Swift parity)
export {
  registerModel,
  registerMultiFileModel,
  listModels,
  queryModels,
  getModel,
  downloadedModels,
  importModel,
  downloadModel,
  cancelDownload,
  deleteModel,
  loadModel,
} from './Models/RunAnywhere+ModelRegistry';
export type {
  RegisterModelInput,
  RegisterMultiFileModelInput,
} from './Models/RunAnywhere+ModelRegistry';
