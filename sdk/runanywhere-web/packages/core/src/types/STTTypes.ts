/**
 * RunAnywhere Web SDK - STT Types (Backend-Agnostic)
 *
 * Generic type definitions for Speech-to-Text transcription results,
 * options, and streaming interfaces. Backend-specific model configs
 * (file paths, architecture types) live in the respective backend packages.
 */

export interface STTTranscriptionResult {
  [key: string]: unknown;
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

export interface STTTranscribeOptions {
  language?: string;
  sampleRate?: number;
}

/** Callback for streaming STT partial results. */
export type STTStreamCallback = (text: string, isFinal: boolean) => void;

/** Backend-agnostic streaming STT session interface. */
export interface STTStreamingSession {
  /** Feed audio samples to the recognizer */
  acceptWaveform(samples: Float32Array, sampleRate?: number): void;
  /** Signal end of audio input */
  inputFinished(): void;
  /** Get current partial/final result */
  getResult(): { text: string; isEndpoint: boolean };
  /** Reset after endpoint */
  reset(): void;
  /** Destroy the streaming session */
  destroy(): void;
}
