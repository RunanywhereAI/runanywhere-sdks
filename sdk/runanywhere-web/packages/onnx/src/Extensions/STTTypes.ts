/**
 * RunAnywhere Web SDK - STT Types (ONNX Backend)
 *
 * Re-exports generic STT types from core and defines backend-specific
 * model configuration types for sherpa-onnx.
 */

// Re-export all generic STT types from core
export type { STTTranscriptionResult, STTWord } from '@runanywhere/web';

// ---------------------------------------------------------------------------
// Backend-specific: sherpa-onnx model configurations
// ---------------------------------------------------------------------------

export enum STTModelType {
  Whisper = 'whisper',
  Zipformer = 'zipformer',
  Paraformer = 'paraformer',
}

export interface STTModelConfig {
  modelId: string;
  type: STTModelType;
  /**
   * Model files already written to sherpa-onnx virtual FS.
   * Paths are FS paths (e.g., '/models/whisper-tiny/encoder.onnx').
   */
  modelFiles: STTWhisperFiles | STTZipformerFiles | STTParaformerFiles;
  /** Sample rate (default: 16000) */
  sampleRate?: number;
  /** Language code (e.g., 'en', 'zh') */
  language?: string;
}

export interface STTWhisperFiles {
  encoder: string;
  decoder: string;
  tokens: string;
}

export interface STTZipformerFiles {
  encoder: string;
  decoder: string;
  joiner: string;
  tokens: string;
}

export interface STTParaformerFiles {
  model: string;
  tokens: string;
}
