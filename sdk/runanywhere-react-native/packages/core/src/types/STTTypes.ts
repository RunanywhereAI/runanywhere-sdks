/**
 * STTTypes.ts
 *
 * Type definitions for Speech-to-Text functionality.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/STT/STTTypes.swift
 */

/**
 * STT options
 */
export interface STTOptions {
  /** Language code (e.g., 'en') */
  language?: string;

  /** Sample rate in Hz (default: 16000) */
  sampleRate?: number;

  /** Enable word timestamps */
  timestamps?: boolean;

  /** Enable multiple alternatives */
  alternatives?: boolean;

  /** Maximum alternatives to return */
  maxAlternatives?: number;
}

/**
 * STT transcription output
 */
export interface STTOutput {
  /** Transcribed text */
  text: string;

  /** Confidence score (0.0 - 1.0) */
  confidence: number;

  /** Word timestamps (if requested) */
  wordTimestamps?: WordTimestamp[];

  /** Detected language */
  detectedLanguage?: string;

  /** Alternative transcriptions */
  alternatives?: STTAlternative[];

  /** Transcription metadata */
  metadata: TranscriptionMetadata;
}

/**
 * Word timestamp
 */
export interface WordTimestamp {
  word: string;
  startTime: number;
  endTime: number;
  confidence?: number;
}

/**
 * Alternative transcription
 */
export interface STTAlternative {
  text: string;
  confidence: number;
}

/**
 * Transcription metadata
 */
export interface TranscriptionMetadata {
  /** Model ID used */
  modelId: string;

  /** Processing time in seconds */
  processingTime: number;

  /** Audio length in seconds */
  audioLength: number;

  /** Real-time factor (processing time / audio length) */
  realTimeFactor?: number;
}

/**
 * STT partial result (for streaming)
 */
export interface STTPartialResult {
  /** Partial transcript */
  transcript: string;

  /** Confidence (if available) */
  confidence?: number;

  /** Word timestamps (if available) */
  timestamps?: WordTimestamp[];

  /** Detected language */
  language?: string;

  /** Alternative transcriptions */
  alternatives?: STTAlternative[];

  /** Whether this is the final result */
  isFinal: boolean;
}

/**
 * STT streaming callback
 */
export type STTStreamCallback = (result: STTPartialResult) => void;

/**
 * STT streaming options
 */
export interface STTStreamOptions extends STTOptions {
  /** Callback for partial results */
  onPartialResult?: STTStreamCallback;

  /** Interval for partial results in ms */
  partialResultInterval?: number;
}
