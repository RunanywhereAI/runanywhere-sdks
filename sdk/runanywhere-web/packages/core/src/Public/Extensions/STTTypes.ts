/**
 * RunAnywhere Web SDK - Speech-to-Text Types
 *
 * Type definitions for STT models and transcription results.
 * Separated from the main STT extension for clean imports.
 */

// ---------------------------------------------------------------------------
// STT Types
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

export interface STTTranscriptionResult {
  text: string;
  confidence: number;
  detectedLanguage?: string;
  processingTimeMs: number;
  words?: STTWord[];
}

export interface STTWord {
  text: string;
  startMs: number;
  endMs: number;
  confidence: number;
}
