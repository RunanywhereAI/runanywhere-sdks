/**
 * SpeakerDiarizationModels.ts
 *
 * Input/Output models for Speaker Diarization component
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Components/SpeakerDiarization/SpeakerDiarizationComponent.swift
 */

import type { ComponentInput, ComponentOutput } from '../../Core/Components/BaseComponent';
import type { STTOutput } from '../STT/STTModels';

/**
 * Options for speaker diarization
 */
export interface SpeakerDiarizationOptions {
  readonly maxSpeakers: number;
  readonly minSpeechDuration: number; // seconds
  readonly speakerChangeThreshold: number; // 0.0 to 1.0
}

/**
 * Information about a detected speaker
 */
export interface SpeakerInfo {
  readonly id: string;
  readonly name: string | null;
  readonly confidence: number | null;
  readonly embedding: number[] | null; // Float array
}

/**
 * Input for Speaker Diarization (conforms to ComponentInput protocol)
 */
export interface SpeakerDiarizationInput extends ComponentInput {
  /** Audio data to diarize */
  readonly audioData: Buffer | Uint8Array;
  /** Audio format */
  readonly format: string;
  /** Optional transcription for labeled output */
  readonly transcription: STTOutput | null;
  /** Expected number of speakers (if known) */
  readonly expectedSpeakers: number | null;
  /** Custom options */
  readonly options: SpeakerDiarizationOptions | null;
}

/**
 * Output from Speaker Diarization (conforms to ComponentOutput protocol)
 */
export interface SpeakerDiarizationOutput extends ComponentOutput {
  /** Speaker segments */
  readonly segments: SpeakerSegment[];
  /** Speaker profiles */
  readonly speakers: SpeakerProfile[];
  /** Labeled transcription (if STT output was provided) */
  readonly labeledTranscription: LabeledTranscription | null;
  /** Processing metadata */
  readonly metadata: DiarizationMetadata;
}

/**
 * Speaker segment
 */
export interface SpeakerSegment {
  readonly speakerId: string;
  readonly startTime: number; // seconds
  readonly endTime: number; // seconds
  readonly confidence: number;
}

/**
 * Speaker profile
 */
export interface SpeakerProfile {
  readonly id: string;
  readonly embedding: number[] | null; // Float array
  readonly totalSpeakingTime: number; // seconds
  readonly segmentCount: number;
  readonly name: string | null;
}

/**
 * Labeled transcription with speaker information
 */
export interface LabeledTranscription {
  readonly segments: LabeledSegment[];
}

/**
 * Labeled segment
 */
export interface LabeledSegment {
  readonly speakerId: string;
  readonly text: string;
  readonly startTime: number; // seconds
  readonly endTime: number; // seconds
}

/**
 * Diarization metadata
 */
export interface DiarizationMetadata {
  readonly processingTime: number; // seconds
  readonly audioLength: number; // seconds
  readonly speakerCount: number;
  readonly method: string; // "energy", "ml", "hybrid"
}
