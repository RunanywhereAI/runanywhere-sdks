/**
 * RunAnywhere Web SDK - TTS Types (Backend-Agnostic)
 *
 * Generic type definitions for Text-to-Speech synthesis results and options.
 * Backend-specific voice configurations live in the respective backend packages.
 */

export interface TTSSynthesisResult {
  [key: string]: unknown;
  /** Raw PCM audio data */
  audioData: Float32Array;
  /** Audio sample rate */
  sampleRate: number;
  /** Duration in milliseconds */
  durationMs: number;
  /** Processing time in milliseconds */
  processingTimeMs: number;
}

export interface TTSSynthesizeOptions {
  /** Speaker ID for multi-speaker models (default: 0) */
  speakerId?: number;
  /** Speed factor (default: 1.0, >1 = faster, <1 = slower) */
  speed?: number;
}
