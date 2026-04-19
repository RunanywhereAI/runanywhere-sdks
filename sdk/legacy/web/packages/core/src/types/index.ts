/**
 * RunAnywhere Web SDK - Type Exports
 *
 * Re-exports all types for convenient importing.
 * All feature types (LLM, VLM, STT, TTS, VAD) are defined here in core
 * so backend packages are pure plug-and-play implementations.
 */

// Enums
export {
  AccelerationPreference,
  ComponentState,
  ConfigurationSource,
  DownloadStage,
  ExecutionTarget,
  FrameworkModality,
  HardwareAcceleration,
  LLMFramework,
  ModelCategory,
  ModelFormat,
  ModelStatus,
  RoutingPolicy,
  SDKComponent,
  SDKEnvironment,
  SDKEventType,
} from './enums';

// Models
export type {
  DeviceInfoData,
  GenerationOptions,
  GenerationResult,
  ModelInfoMetadata,
  PerformanceMetrics,
  SDKInitOptions,
  STTAlternative,
  STTOptions,
  STTResult,
  STTSegment,
  StorageInfo,
  StoredModel,
  ThinkingTagPattern,
  TTSConfiguration,
  TTSResult,
  VADConfiguration,
} from './models';

// LLM Types
export type {
  LLMGenerationOptions,
  LLMGenerationResult,
  LLMStreamingResult,
  LLMStreamingMetrics,
  LLMTokenCallback,
  LLMStreamCompleteCallback,
  LLMStreamErrorCallback,
} from './LLMTypes';

// VLM Types
export { VLMImageFormat } from './VLMTypes';
export type {
  VLMImage,
  VLMGenerationOptions,
  VLMGenerationResult,
  VLMStreamingResult,
} from './VLMTypes';

// STT Types
export type {
  STTTranscriptionResult,
  STTWord,
  STTTranscribeOptions,
  STTStreamCallback,
  STTStreamingSession,
} from './STTTypes';

// TTS Types
export type {
  TTSSynthesisResult,
  TTSSynthesizeOptions,
} from './TTSTypes';

// VAD Types
export { SpeechActivity } from './VADTypes';
export type {
  SpeechActivityCallback,
  SpeechSegment,
} from './VADTypes';
