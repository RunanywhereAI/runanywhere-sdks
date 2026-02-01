/**
 * RunAnywhere Extensions
 *
 * Re-exports all extension modules for convenient importing.
 */

// Text Generation (LLM)
export {
  loadModel,
  isModelLoaded,
  unloadModel,
  chat,
  generate,
  generateStream,
  cancelGeneration,
} from './RunAnywhere+TextGeneration';

// Speech-to-Text
export {
  loadSTTModel,
  isSTTModelLoaded,
  unloadSTTModel,
  transcribe,
  transcribeSimple,
  transcribeBuffer,
  transcribeStream,
  transcribeFile,
  startStreamingSTT,
  stopStreamingSTT,
  isStreamingSTT,
} from './RunAnywhere+STT';

// Text-to-Speech
export {
  loadTTSModel,
  loadTTSVoice,
  unloadTTSVoice,
  isTTSModelLoaded,
  isTTSVoiceLoaded,
  unloadTTSModel,
  synthesize,
  synthesizeStream,
  speak,
  isSpeaking,
  stopSpeaking,
  availableTTSVoices,
  getTTSVoices,
  getTTSVoiceInfo,
  stopSynthesis,
  cancelTTS,
  cleanupTTS,
} from './RunAnywhere+TTS';

// Voice Activity Detection
export {
  initializeVAD,
  isVADReady,
  loadVADModel,
  isVADModelLoaded,
  unloadVADModel,
  detectSpeech,
  processVAD,
  startVAD,
  stopVAD,
  resetVAD,
  setVADSpeechActivityCallback,
  setVADAudioBufferCallback,
  cleanupVAD,
  getVADState,
} from './RunAnywhere+VAD';

// Voice Agent
export {
  initializeVoiceAgent,
  initializeVoiceAgentWithLoadedModels,
  isVoiceAgentReady,
  getVoiceAgentComponentStates,
  areAllVoiceComponentsReady,
  processVoiceTurn,
  voiceAgentTranscribe,
  voiceAgentGenerateResponse,
  voiceAgentSynthesizeSpeech,
  cleanupVoiceAgent,
} from './RunAnywhere+VoiceAgent';

// Voice Session
export {
  startVoiceSession,
  startVoiceSessionWithCallback,
  createVoiceSession,
  DEFAULT_VOICE_SESSION_CONFIG,
} from './RunAnywhere+VoiceSession';
export type {
  VoiceSessionConfig,
  VoiceSessionEvent,
  VoiceSessionEventCallback
} from './RunAnywhere+VoiceSession';

// Structured Output
export {
  generateStructured,
  generateStructuredStream,
  generate as generateStructuredType,
  extractEntities,
  classify,
} from './RunAnywhere+StructuredOutput';
export type {
  StreamToken,
  StructuredOutputStreamResult
} from './RunAnywhere+StructuredOutput';

// Logging
export { setLogLevel } from './RunAnywhere+Logging';

// Storage
export { getStorageInfo, clearCache } from './RunAnywhere+Storage';

// Models
export {
  getAvailableModels,
  getModelInfo,
  isModelDownloaded,
  downloadModel,
  cancelDownload,
  deleteModel,
} from './RunAnywhere+Models';

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
export * as Audio from './RunAnywhere+Audio';

// Model Compatibility Check
export {
  checkModelCompatibility,
  checkModelsCompatibility,
  getDeviceCapabilities,
} from './RunAnywhere+Compatibility';