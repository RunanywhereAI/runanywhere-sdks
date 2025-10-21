/**
 * VAD (Voice Activity Detection) types
 */

export interface VADConfig {
  /** Positive speech probability threshold (0-1) */
  positiveSpeechThreshold: number;
  /** Negative speech probability threshold (0-1) */
  negativeSpeechThreshold: number;
  /** Number of frames to pad before speech */
  preSpeechPadFrames: number;
  /** Minimum number of speech frames to trigger detection */
  minSpeechFrames: number;
  /** Whether to submit speech when user pauses */
  submitUserSpeechOnPause: boolean;
  /** Frame size in samples (512, 1024, or 1536) */
  frameSamples: 512 | 1024 | 1536;
  /** Sample rate (default 16000 Hz) */
  sampleRate?: number;
  /** Speech timeout in milliseconds */
  speechEndTimeout?: number;
}

export interface VADEvent {
  type: 'speech_start' | 'speech_end' | 'speech_segment' | 'audio_level';
  timestamp: number;
  data?: Float32Array;
  energy?: number;
  duration?: number;
}

export interface VADMetrics {
  totalSpeechSegments: number;
  totalSpeechDuration: number;
  averageEnergy: number;
  lastActivityTime: number;
}

export interface VADService {
  initialize(config?: Partial<VADConfig>): Promise<void>;
  start(): Promise<void>;
  stop(): void;
  pause(): void;
  resume(): void;
  process(audio: Float32Array): Promise<VADEvent | null>;
  onSpeechStart(callback: () => void): void;
  onSpeechEnd(callback: (audio: Float32Array) => void): void;
  onAudioLevel(callback: (level: number) => void): void;
  getMetrics(): VADMetrics;
  isHealthy(): boolean;
  destroy(): void;
}

export const DEFAULT_VAD_CONFIG: VADConfig = {
  positiveSpeechThreshold: 0.9,
  negativeSpeechThreshold: 0.75,
  preSpeechPadFrames: 10,
  minSpeechFrames: 5,
  submitUserSpeechOnPause: true,
  frameSamples: 1536,
  sampleRate: 16000,
  speechEndTimeout: 1500
};
