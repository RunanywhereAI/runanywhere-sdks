import { Result } from '../types/result'

export interface STTConfig {
  model?: string
  language?: string
  sampleRate?: number
  chunkLength?: number
  stride?: number
  returnTimestamps?: boolean
  forceFullSequences?: boolean
  apiKey?: string
  endpoint?: string
}

export interface ModelInfo {
  id: string
  name: string
  size: string
  speed: 'fast' | 'balanced' | 'quality' | 'medium' | 'slow'
  languages?: string[]
  accuracy?: 'low' | 'medium' | 'high'
}

export interface TranscribeOptions {
  language?: string
  returnTimestamps?: boolean
  maxNewTokens?: number
  task?: 'transcribe' | 'translate'
  timestamps?: boolean
}

export interface TranscriptionResult {
  text: string
  language?: string
  confidence?: number
  timestamps?: Array<{
    text: string
    start: number
    end: number
  }>
  duration?: number
  processingTime?: number
}

export interface STTMetrics {
  totalTranscriptions: number
  avgProcessingTime: number
  modelLoadTime?: number
  lastTranscriptionTime?: number
}

export type ModelLoadingProgress = {
  progress: number
  message?: string
}

export type STTEvents = {
  model_loading: (progress: ModelLoadingProgress) => void
  partial_transcript: (text: string) => void
  error: (error: Error) => void
}

export interface STTAdapter {
  readonly id: string
  readonly name: string
  readonly version: string
  readonly supportedModels: ModelInfo[]

  initialize(config?: STTConfig): Promise<Result<void, Error>>
  loadModel(modelId: string): Promise<Result<void, Error>>
  transcribe(audio: Float32Array, options?: TranscribeOptions): Promise<Result<TranscriptionResult, Error>>
  destroy(): void

  on<K extends keyof STTEvents>(event: K, handler: STTEvents[K]): void
  off<K extends keyof STTEvents>(event: K, handler?: STTEvents[K]): void

  isModelLoaded(): boolean
  getLoadedModel(): ModelInfo | null
  isHealthy(): boolean
  getMetrics(): STTMetrics
}
