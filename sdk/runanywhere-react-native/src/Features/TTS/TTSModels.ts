/**
 * TTSModels.ts
 *
 * Input/Output models for TTS component
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Components/TTS/TTSComponent.swift
 */

import type { ComponentInput, ComponentOutput } from '../../Core/Components/BaseComponent';

/**
 * Options for text-to-speech synthesis
 */
export interface TTSOptions {
  /** Voice to use for synthesis */
  readonly voice: string | null;
  /** Language for synthesis */
  readonly language: string;
  /** Speech rate (0.0 to 2.0, 1.0 is normal) */
  readonly rate: number;
  /** Speech pitch (0.0 to 2.0, 1.0 is normal) */
  readonly pitch: number;
  /** Speech volume (0.0 to 1.0) */
  readonly volume: number;
  /** Audio format for output */
  readonly audioFormat: string;
  /** Sample rate for output audio */
  readonly sampleRate: number;
  /** Whether to use SSML markup */
  readonly useSSML: boolean;
}

/**
 * Input for Text-to-Speech (conforms to ComponentInput protocol)
 */
export interface TTSInput extends ComponentInput {
  /** Text to synthesize */
  readonly text: string;
  /** Optional SSML markup (overrides text if provided) */
  readonly ssml: string | null;
  /** Voice ID override */
  readonly voiceId: string | null;
  /** Language override */
  readonly language: string | null;
  /** Custom options override */
  readonly options: TTSOptions | null;
}

/**
 * Output from Text-to-Speech (conforms to ComponentOutput protocol)
 */
export interface TTSOutput extends ComponentOutput {
  /** Synthesized audio data */
  readonly audioData: Buffer | Uint8Array;
  /** Audio format of the output */
  readonly format: string;
  /** Duration of the audio in seconds */
  readonly duration: number;
  /** Phoneme timestamps if available */
  readonly phonemeTimestamps: PhonemeTimestamp[] | null;
  /** Processing metadata */
  readonly metadata: SynthesisMetadata;
}

/**
 * Phoneme timestamp information
 */
export interface PhonemeTimestamp {
  readonly phoneme: string;
  readonly startTime: number; // seconds
  readonly endTime: number; // seconds
}

/**
 * Synthesis metadata
 */
export interface SynthesisMetadata {
  readonly voice: string;
  readonly language: string;
  readonly processingTime: number; // seconds
  readonly characterCount: number;
  readonly charactersPerSecond: number;
}
