/** RunAnywhere Web SDK - VAD Types */

export enum SpeechActivity {
  Started = 'started',
  Ended = 'ended',
  Ongoing = 'ongoing',
}

export type SpeechActivityCallback = (activity: SpeechActivity) => void;

export interface VADModelConfig {
  /** Path to Silero VAD ONNX model in sherpa-onnx virtual FS */
  modelPath: string;
  /** Detection threshold (default: 0.5, range 0-1) */
  threshold?: number;
  /** Minimum silence duration in seconds to split segments (default: 0.5) */
  minSilenceDuration?: number;
  /** Minimum speech duration in seconds (default: 0.25) */
  minSpeechDuration?: number;
  /** Maximum speech duration in seconds (default: 5.0 for streaming) */
  maxSpeechDuration?: number;
  /** Sample rate (default: 16000) */
  sampleRate?: number;
  /** Window size in samples (default: 512 for Silero) */
  windowSize?: number;
}

export interface SpeechSegment {
  /** Start time in seconds */
  startTime: number;
  /** Audio samples of the speech segment */
  samples: Float32Array;
}
