/**
 * STTTranscriptionResult.ts
 * Matches iOS: Features/STT/Models/STTTranscriptionResult.swift
 */

/**
 * Timestamp information for individual words in transcription
 */
export interface TimestampInfo {
  /** The word */
  word: string;
  /** Start time in seconds */
  startTime: number;
  /** End time in seconds */
  endTime: number;
  /** Confidence score for this word (optional) */
  confidence?: number;
}

/**
 * Alternative transcription with confidence score
 */
export interface AlternativeTranscription {
  /** The alternative transcript text */
  transcript: string;
  /** Confidence score for this alternative */
  confidence: number;
}

/**
 * Transcription result from STT service
 * Matches iOS STTTranscriptionResult struct
 */
export interface STTTranscriptionResult {
  /** The transcribed text */
  transcript: string;
  /** Confidence score for the transcription (optional) */
  confidence?: number;
  /** Word-level timestamp information (optional) */
  timestamps?: TimestampInfo[];
  /** Detected language (optional) */
  language?: string;
  /** Alternative transcriptions (optional) */
  alternatives?: AlternativeTranscription[];
}
