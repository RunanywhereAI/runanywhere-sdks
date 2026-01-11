/**
 * VADTypes.ts
 *
 * Type definitions for Voice Activity Detection functionality.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/VAD/VADTypes.swift
 */

/**
 * VAD configuration options
 */
export interface VADConfiguration {
  /** Sample rate in Hz (default: 16000) */
  sampleRate?: number;

  /** Frame length in seconds (default: 0.1) */
  frameLength?: number;

  /** Energy threshold for speech detection (default: 0.005) */
  energyThreshold?: number;
}

/**
 * VAD processing result
 */
export interface VADResult {
  /** Whether speech was detected */
  isSpeech: boolean;

  /** Speech probability (0.0 - 1.0) */
  probability: number;

  /** Start time of speech segment (seconds) */
  startTime?: number;

  /** End time of speech segment (seconds) */
  endTime?: number;
}

/**
 * Speech activity event types
 */
export type SpeechActivityEvent = 'started' | 'ended';

/**
 * VAD speech activity callback
 */
export type VADSpeechActivityCallback = (event: SpeechActivityEvent) => void;

/**
 * VAD audio buffer callback
 */
export type VADAudioBufferCallback = (samples: Float32Array) => void;

/**
 * VAD state
 */
export interface VADState {
  /** Whether VAD is initialized */
  isInitialized: boolean;

  /** Whether VAD is currently running */
  isRunning: boolean;

  /** Whether speech is currently active */
  isSpeechActive: boolean;

  /** Current speech probability */
  currentProbability: number;
}
