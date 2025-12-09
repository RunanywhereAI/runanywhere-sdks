/**
 * WakeWordModels.ts
 *
 * Input/Output models for Wake Word component
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Components/WakeWord/WakeWordComponent.swift
 */

import type { ComponentInput, ComponentOutput } from '../../Core/Components/BaseComponent';

/**
 * Input for Wake Word Detection
 */
export interface WakeWordInput extends ComponentInput {
  /** Audio buffer to process */
  readonly audioBuffer: number[]; // Float array
  /** Optional audio timestamp in seconds (distinct from ComponentInput.timestamp) */
  readonly audioTimestamp?: number;
}

/**
 * Output from Wake Word Detection
 */
export interface WakeWordOutput extends ComponentOutput {
  /** Whether a wake word was detected */
  readonly detected: boolean;
  /** Detected wake word (if any) */
  readonly wakeWord: string | null;
  /** Confidence score (0.0 to 1.0) */
  readonly confidence: number;
  /** Detection metadata */
  readonly metadata: WakeWordMetadata;
}

/**
 * Wake word detection metadata
 */
export interface WakeWordMetadata {
  readonly processingTime: number; // seconds
  readonly bufferSize: number;
  readonly sampleRate: number;
}
