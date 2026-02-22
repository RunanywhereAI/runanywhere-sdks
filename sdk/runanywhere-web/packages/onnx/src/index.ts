/**
 * @runanywhere/web-onnx
 *
 * ONNX backend for the RunAnywhere Web SDK.
 * Provides on-device STT (speech-to-text), TTS (text-to-speech),
 * and VAD (voice activity detection) via sherpa-onnx compiled to WASM.
 *
 * @packageDocumentation
 *
 * @example
 * ```typescript
 * import { RunAnywhere } from '@runanywhere/web';
 * import { ONNX } from '@runanywhere/web-onnx';
 *
 * await RunAnywhere.initialize();
 * await ONNX.register();
 *
 * // Now STT, TTS, VAD are available
 * const result = await STT.transcribe(audioData);
 * ```
 */

// Module facade & provider
export { ONNX, autoRegister } from './ONNX';
export { ONNXProvider } from './ONNXProvider';

// Extensions
export { STT, STTModelType } from './Extensions/RunAnywhere+STT';
export type {
  STTModelConfig, STTWhisperFiles, STTZipformerFiles, STTParaformerFiles,
  STTTranscriptionResult, STTWord, STTTranscribeOptions, STTStreamCallback, STTStreamingSession,
} from './Extensions/RunAnywhere+STT';
export { TTS } from './Extensions/RunAnywhere+TTS';
export type { TTSVoiceConfig, TTSSynthesisResult, TTSSynthesizeOptions } from './Extensions/RunAnywhere+TTS';
export { VAD, SpeechActivity } from './Extensions/RunAnywhere+VAD';
export type { SpeechActivityCallback, VADModelConfig, SpeechSegment } from './Extensions/RunAnywhere+VAD';

// Foundation
export { SherpaONNXBridge } from './Foundation/SherpaONNXBridge';

// Infrastructure
export { AudioCapture } from './Infrastructure/AudioCapture';
export type { AudioChunkCallback, AudioLevelCallback, AudioCaptureConfig } from './Infrastructure/AudioCapture';
export { AudioPlayback } from './Infrastructure/AudioPlayback';
export type { PlaybackCompleteCallback, PlaybackConfig } from './Infrastructure/AudioPlayback';
export { AudioFileLoader } from './Infrastructure/AudioFileLoader';
export type { AudioFileLoaderResult } from './Infrastructure/AudioFileLoader';
