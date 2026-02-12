/**
 * RunAnywhere Web SDK
 *
 * On-device AI inference in the browser via RACommons WebAssembly.
 *
 * @packageDocumentation
 *
 * @example
 * ```typescript
 * import { RunAnywhere } from '@runanywhere/web';
 *
 * // Initialize
 * await RunAnywhere.initialize({ environment: 'development' });
 *
 * // Check capabilities
 * console.log('WebGPU:', RunAnywhere.isWASMLoaded);
 *
 * // Future: Generate text
 * // const result = await RunAnywhere.generate('Hello!', { maxTokens: 100 });
 * ```
 */

// Main entry point
export { RunAnywhere } from './Public/RunAnywhere';

// Extensions
export { TextGeneration } from './Public/Extensions/RunAnywhere+TextGeneration';
export { ModelManagement } from './Public/Extensions/RunAnywhere+ModelManagement';
export type { DownloadProgressCallback, ModelDownloadOptions } from './Public/Extensions/RunAnywhere+ModelManagement';
export { STT } from './Public/Extensions/RunAnywhere+STT';
export type { STTTranscriptionResult, STTWord, STTTranscribeOptions, STTStreamCallback } from './Public/Extensions/RunAnywhere+STT';
export { TTS } from './Public/Extensions/RunAnywhere+TTS';
export type { TTSSynthesisResult, TTSSynthesizeOptions } from './Public/Extensions/RunAnywhere+TTS';
export { VAD } from './Public/Extensions/RunAnywhere+VAD';
export type { SpeechActivity, SpeechActivityCallback, VADConfig } from './Public/Extensions/RunAnywhere+VAD';
export { VoiceAgent, VoiceAgentSession } from './Public/Extensions/RunAnywhere+VoiceAgent';
export type { PipelineState, VoiceAgentModels, VoiceTurnResult, VoiceAgentEventData, VoiceAgentEventCallback } from './Public/Extensions/RunAnywhere+VoiceAgent';
export { VLM } from './Public/Extensions/RunAnywhere+VLM';
export type { VLMImage, VLMImageFormat, VLMModelFamily, VLMGenerationOptions, VLMGenerationResult, VLMStreamingResult } from './Public/Extensions/RunAnywhere+VLM';
export { StructuredOutput } from './Public/Extensions/RunAnywhere+StructuredOutput';
export type { StructuredOutputConfig, StructuredOutputValidation } from './Public/Extensions/RunAnywhere+StructuredOutput';
export { Diffusion } from './Public/Extensions/RunAnywhere+Diffusion';
export type { DiffusionGenerationOptions, DiffusionGenerationResult, DiffusionProgressCallback } from './Public/Extensions/RunAnywhere+Diffusion';

// Types
export * from './types';

// Foundation
export { SDKError, SDKErrorCode } from './Foundation/ErrorTypes';
export { SDKLogger, LogLevel } from './Foundation/SDKLogger';
export { EventBus } from './Foundation/EventBus';
export type { EventListener, Unsubscribe, SDKEventEnvelope } from './Foundation/EventBus';
export { WASMBridge } from './Foundation/WASMBridge';
export type { RACommonsModule } from './Foundation/WASMBridge';

// Infrastructure
export { detectCapabilities, getDeviceInfo } from './Infrastructure/DeviceCapabilities';
export type { WebCapabilities } from './Infrastructure/DeviceCapabilities';
export { AudioCapture } from './Infrastructure/AudioCapture';
export type { AudioChunkCallback, AudioCaptureConfig } from './Infrastructure/AudioCapture';
export { AudioPlayback } from './Infrastructure/AudioPlayback';
export type { PlaybackCompleteCallback, PlaybackConfig } from './Infrastructure/AudioPlayback';
export { OPFSStorage } from './Infrastructure/OPFSStorage';
export type { StoredModelInfo } from './Infrastructure/OPFSStorage';
