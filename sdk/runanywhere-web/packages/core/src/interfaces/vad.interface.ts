import { Result } from '../types/result'

export interface VADConfig {
  positiveSpeechThreshold?: number
  negativeSpeechThreshold?: number
  minSpeechFrames?: number
  redemptionFrames?: number
  preSpeechPadFrames?: number
  frameSamples?: number
  sampleRate?: number
  minSpeechDuration?: number
  preSpeechPadding?: number
}

export interface VADMetrics {
  totalDetections: number
  avgSpeechDuration: number
  lastDetectionTime?: number
  noiseLevel: number
  totalSpeechSegments?: number
  totalSilenceMs?: number
  totalSpeechMs?: number
  lastActivityTime?: number | null
}

export type VADEvents = {
  speech_start: () => void
  speech_end: (audio: Float32Array) => void
  audio_level: (level: number) => void
  error: (error: Error) => void
  vad_misfire: () => void
}

export interface VADAdapter {
  readonly id: string
  readonly name: string
  readonly version: string

  initialize(config?: VADConfig): Promise<Result<void, Error>>
  start(): Promise<Result<void, Error>>
  stop(): void
  pause(): void
  resume(): void
  destroy(): void

  on<K extends keyof VADEvents>(event: K, handler: VADEvents[K]): void
  off<K extends keyof VADEvents>(event: K, handler?: VADEvents[K]): void

  isHealthy(): boolean
  getMetrics(): VADMetrics
}
