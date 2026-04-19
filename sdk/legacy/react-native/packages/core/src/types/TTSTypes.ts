/**
 * TTSTypes.ts
 *
 * Type definitions for Text-to-Speech functionality.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/TTS/TTSTypes.swift
 */

/**
 * TTS synthesis options
 */
export interface TTSOptions {
  /** Voice ID to use */
  voice?: string;

  /** Speech rate multiplier (default: 1.0) */
  rate?: number;

  /** Pitch adjustment (default: 1.0) */
  pitch?: number;

  /** Volume (0.0 - 1.0, default: 1.0) */
  volume?: number;

  /** Sample rate in Hz (default: 22050) */
  sampleRate?: number;

  /** Language code (e.g., 'en-US') */
  language?: string;

  /** Audio format */
  audioFormat?: AudioFormat;
}

/**
 * Audio format enum
 */
export type AudioFormat = 'pcm' | 'wav' | 'mp3';

/**
 * TTS synthesis output
 */
export interface TTSOutput {
  /** Audio data (base64 encoded or raw PCM) */
  audioData: string;

  /** Audio format */
  format: AudioFormat;

  /** Duration in seconds */
  duration: number;

  /** Phoneme timestamps (if available) */
  phonemeTimestamps?: PhonemeTimestamp[];

  /** Synthesis metadata */
  metadata: TTSSynthesisMetadata;
}

/**
 * Phoneme timestamp
 */
export interface PhonemeTimestamp {
  phoneme: string;
  startTime: number;
  endTime: number;
}

/**
 * TTS synthesis metadata
 */
export interface TTSSynthesisMetadata {
  /** Voice used */
  voice: string;

  /** Language */
  language?: string;

  /** Processing time in seconds */
  processingTime: number;

  /** Character count of input text */
  characterCount: number;
}

/**
 * TTS speak result (simple playback API)
 */
export interface TTSSpeakResult {
  /** Duration of audio in seconds */
  duration: number;

  /** Voice used */
  voice: string;

  /** Processing time in seconds */
  processingTime: number;

  /** Character count */
  characterCount: number;
}

/**
 * TTS voice info
 */
export interface TTSVoiceInfo {
  /** Voice ID */
  id: string;

  /** Display name */
  name: string;

  /** Language code */
  language: string;

  /** Gender */
  gender?: 'male' | 'female' | 'neutral';

  /** Whether this voice is downloaded */
  isDownloaded: boolean;
}

/**
 * TTS stream chunk callback
 */
export type TTSStreamChunkCallback = (audioChunk: ArrayBuffer) => void;
