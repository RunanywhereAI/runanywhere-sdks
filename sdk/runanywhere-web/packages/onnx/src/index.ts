/**
 * @runanywhere/web-onnx
 *
 * ONNX backend for the RunAnywhere Web SDK. Two runtimes coexist:
 *
 *   * `sherpa-onnx.wasm`  (via SherpaONNXBridge)  — STT, TTS, VAD
 *   * `onnxruntime-web`   (via ORTRuntimeBridge)  — wake-word, RAG embeddings
 *
 * Both are lazy-loaded — apps only pay the download cost for the features
 * they actually call.
 *
 * @packageDocumentation
 *
 * @example
 * ```typescript
 * import { RunAnywhere } from '@runanywhere/web';
 * import { ONNX, WakeWord, Embeddings } from '@runanywhere/web-onnx';
 *
 * await RunAnywhere.initialize();
 * await ONNX.register();  // sherpa-onnx.wasm backend for STT / TTS / VAD
 *
 * // Wake-word + embeddings use a separate onnxruntime-web runtime
 * await WakeWord.load({ ... });
 * await Embeddings.load({ ... });
 * ```
 */

// Module facade & provider
export { ONNX, autoRegister } from './ONNX';
export type { ONNXRegisterOptions } from './ONNX';
export { ONNXProvider } from './ONNXProvider';

// Extensions (backend-specific implementations + backend-specific config types)
export { STT, STTModelType } from './Extensions/RunAnywhere+STT';
export type { STTModelConfig, STTWhisperFiles, STTZipformerFiles, STTParaformerFiles } from './Extensions/RunAnywhere+STT';
export { TTS } from './Extensions/RunAnywhere+TTS';
export type { TTSVoiceConfig } from './Extensions/RunAnywhere+TTS';
export { VAD } from './Extensions/RunAnywhere+VAD';
export type { VADModelConfig } from './Extensions/RunAnywhere+VAD';

// Wake-word detection (via onnxruntime-web — full openWakeWord pipeline)
export { WakeWord, WakeWordService } from './Extensions/RunAnywhere+WakeWord';
export type {
  WakeWordConfig,
  WakeWordSharedModelConfig,
  WakeWordClassifierConfig,
  WakeWordDetection,
  WakeWordCallback,
} from './Extensions/WakeWordTypes';

// Text embeddings for RAG (via onnxruntime-web — BERT encoder + WordPiece tokenizer)
export { Embeddings, EmbeddingsService } from './Extensions/RunAnywhere+Embeddings';
export type {
  EmbeddingsModelConfig,
  EmbedOptions,
  EmbeddingResult,
} from './Extensions/EmbeddingsTypes';

// Backward-compatible re-exports of shared contract types
export type {
  STTTranscriptionResult, STTWord, STTTranscribeOptions,
  STTStreamCallback, STTStreamingSession,
  TTSSynthesisResult, TTSSynthesizeOptions,
  SpeechActivityCallback, SpeechSegment,
} from '@runanywhere/web';
export { SpeechActivity } from '@runanywhere/web';

// Foundation
export { SherpaONNXBridge } from './Foundation/SherpaONNXBridge';
export { ORTRuntimeBridge } from './Foundation/ORTRuntimeBridge';
export type { ORTRuntimeInitOptions } from './Foundation/ORTRuntimeBridge';
export { WordPieceTokenizer } from './Foundation/WordPieceTokenizer';
export type {
  TokenizerOptions,
  EncodeResult,
} from './Foundation/WordPieceTokenizer';
