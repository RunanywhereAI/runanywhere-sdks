/**
 * STTModels.ts
 *
 * Input/Output models for STT component
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Components/STT/STTComponent.swift
 */

import type { ComponentInput, ComponentOutput } from '../../Core/Components/BaseComponent';

/**
 * Options for speech-to-text transcription
 */
export interface STTOptions {
  /** Language code for transcription (e.g., "en", "es", "fr") */
  readonly language: string;
  /** Whether to auto-detect the spoken language */
  readonly detectLanguage: boolean;
  /** Enable automatic punctuation in transcription */
  readonly enablePunctuation: boolean;
  /** Enable speaker diarization (identify different speakers) */
  readonly enableDiarization: boolean;
  /** Maximum number of speakers to identify (requires enableDiarization) */
  readonly maxSpeakers: number | null;
  /** Enable word-level timestamps */
  readonly enableTimestamps: boolean;
  /** Custom vocabulary words to improve recognition */
  readonly vocabularyFilter: string[];
  /** Sample rate of input audio (default: 16000 Hz for STT models) */
  readonly sampleRate: number;
  /** Preferred framework for transcription (WhisperKit, ONNX, etc.) */
  readonly preferredFramework: string | null;
}

/**
 * Input for Speech-to-Text (conforms to ComponentInput protocol)
 */
export interface STTInput extends ComponentInput {
  /** Audio data to transcribe */
  readonly audioData: Buffer | Uint8Array;
  /** Audio format information */
  readonly format: string;
  /** Language code override (e.g., "en-US") */
  readonly language: string | null;
  /** Custom options override */
  readonly options: STTOptions | null;
}

/**
 * Output from Speech-to-Text (conforms to ComponentOutput protocol)
 */
export interface STTOutput extends ComponentOutput {
  /** Transcribed text */
  readonly text: string;
  /** Confidence score (0.0 to 1.0) */
  readonly confidence: number;
  /** Word-level timestamps if available */
  readonly wordTimestamps: WordTimestamp[] | null;
  /** Detected language if auto-detected */
  readonly detectedLanguage: string | null;
  /** Alternative transcriptions if available */
  readonly alternatives: TranscriptionAlternative[] | null;
  /** Processing metadata */
  readonly metadata: TranscriptionMetadata;
}

/**
 * Word timestamp information
 */
export interface WordTimestamp {
  readonly word: string;
  readonly startTime: number; // seconds
  readonly endTime: number; // seconds
  readonly confidence: number;
}

/**
 * Alternative transcription
 */
export interface TranscriptionAlternative {
  readonly text: string;
  readonly confidence: number;
}

/**
 * Transcription metadata
 */
export interface TranscriptionMetadata {
  readonly modelId: string;
  readonly processingTime: number; // seconds
  readonly audioLength: number; // seconds
  readonly realTimeFactor: number; // Processing time / audio length
}

/**
 * Transcription result from service
 */
export interface STTTranscriptionResult {
  readonly transcript: string;
  readonly confidence: number | null;
  readonly timestamps: TimestampInfo[] | null;
  readonly language: string | null;
  readonly alternatives: AlternativeTranscription[] | null;
}

/**
 * Timestamp information
 */
export interface TimestampInfo {
  readonly word: string;
  readonly startTime: number; // seconds
  readonly endTime: number; // seconds
  readonly confidence: number | null;
}

/**
 * Alternative transcription result
 */
export interface AlternativeTranscription {
  readonly transcript: string;
  readonly confidence: number;
}

/**
 * Streaming transcription result
 * Represents partial or final transcription results during streaming
 */
export interface STTStreamResult {
  /** Transcribed text (partial or final) */
  readonly text: string;
  /** Whether this is the final result */
  readonly isFinal: boolean;
  /** Confidence score (0.0 to 1.0) */
  readonly confidence?: number;
  /** Timestamp when this result was generated */
  readonly timestamp: Date;
}

