/**
 * TTSResult.ts
 * Matches iOS: Features/TTS/Models/TTSOutput.swift
 */

import type { AudioFormat } from '../../../types/enums';

/**
 * Phoneme timestamp information
 * Matches iOS TTSPhonemeTimestamp
 */
export interface TTSPhonemeTimestamp {
  /** The phoneme */
  phoneme: string;
  /** Start time in seconds */
  startTime: number;
  /** End time in seconds */
  endTime: number;
}

/**
 * Synthesis metadata
 * Matches iOS TTSSynthesisMetadata
 */
export interface TTSSynthesisMetadata {
  /** Voice used for synthesis */
  voice: string;
  /** Language used for synthesis */
  language: string;
  /** Processing time in seconds */
  processingTime: number;
  /** Number of characters synthesized */
  characterCount: number;
}

/**
 * Output from Text-to-Speech synthesis
 * Matches iOS TTSOutput struct
 *
 * Note: In RN, audioData is base64 encoded for serialization across the bridge.
 */
export interface TTSResult {
  /** Synthesized audio data (base64 encoded) */
  audioData: string;
  /** Audio format of the output */
  format: AudioFormat;
  /** Duration of the audio in seconds */
  duration: number;
  /** Phoneme timestamps if available */
  phonemeTimestamps?: TTSPhonemeTimestamp[];
  /** Processing metadata */
  metadata: TTSSynthesisMetadata;
  /** Timestamp of when the result was created */
  timestamp: Date;
}

/**
 * Computed property helpers for TTSResult
 */
export function getTTSResultAudioSizeBytes(result: TTSResult): number {
  // Base64 to raw bytes: base64 length * 3/4
  return Math.floor(result.audioData.length * 0.75);
}

export function hasTTSPhonemeTimestamps(result: TTSResult): boolean {
  return (
    result.phonemeTimestamps != null && result.phonemeTimestamps.length > 0
  );
}

export function getCharactersPerSecond(metadata: TTSSynthesisMetadata): number {
  return metadata.processingTime > 0
    ? metadata.characterCount / metadata.processingTime
    : 0;
}
