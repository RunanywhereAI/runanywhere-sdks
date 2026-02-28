/**
 * RunAnywhere Web SDK - VAD Types (Backend-Agnostic)
 *
 * Generic type definitions for Voice Activity Detection events and segments.
 * Backend-specific model configurations live in the respective backend packages.
 */

export enum SpeechActivity {
  Started = 'started',
  Ended = 'ended',
  Ongoing = 'ongoing',
}

export type SpeechActivityCallback = (activity: SpeechActivity) => void;

export interface SpeechSegment {
  /** Start time in seconds */
  startTime: number;
  /** Audio samples of the speech segment */
  samples: Float32Array;
}
