import { Result } from '../types/result'

export interface TTSConfig {
  voice?: string
  defaultVoice?: string
  rate?: number
  pitch?: number
  volume?: number
  language?: string
  modelUrl?: string
  apiKey?: string
  endpoint?: string
  enableSSML?: boolean
  timeout?: number
}

export interface VoiceInfo {
  id: string
  name: string
  language: string
  gender?: 'male' | 'female' | 'neutral'
  quality?: 'low' | 'medium' | 'high'
  isDefault?: boolean
  isLocal?: boolean
  localService?: boolean
}

export interface SynthesizeOptions {
  voice?: string
  rate?: number
  pitch?: number
  volume?: number
  language?: string
  speakerEmbedding?: Float32Array
  enableSSML?: boolean
}

export interface TTSMetrics {
  totalSyntheses: number
  avgProcessingTime: number
  totalCharacters: number
  lastSynthesisTime?: number
  totalSynthesisTime?: number
  totalPlaybackTime?: number
  synthesisCount?: number
}

export type TTSEvents = {
  synthesis_start: () => void
  synthesis_progress: (progress: number) => void
  synthesis_complete: () => void
  synthesis_end: () => void
  playback_start: () => void
  playback_end: () => void
  error: (error: Error) => void
}

export interface TTSAdapter {
  readonly id: string
  readonly name: string
  readonly version: string
  readonly supportedVoices: VoiceInfo[]

  initialize(config?: TTSConfig): Promise<Result<void, Error>>
  loadModel?(modelId: string): Promise<Result<void, Error>>
  synthesize(text: string, options?: SynthesizeOptions): Promise<Result<AudioBuffer, Error>>
  play(audio?: AudioBuffer): Promise<Result<void, Error>>
  synthesizeAndPlay?(text: string, options?: SynthesizeOptions): Promise<Result<void, Error>>
  stop(): void
  pause?(): void
  resume?(): void
  destroy(): void

  on<K extends keyof TTSEvents>(event: K, handler: TTSEvents[K]): void
  off<K extends keyof TTSEvents>(event: K, handler?: TTSEvents[K]): void

  isHealthy(): boolean
  getMetrics(): TTSMetrics
}
