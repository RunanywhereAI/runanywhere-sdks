export * from './vad.interface'
export * from './stt.interface'
export * from './llm.interface'
export * from './tts.interface'

export enum AdapterType {
  VAD = 'vad',
  STT = 'stt',
  LLM = 'llm',
  TTS = 'tts'
}

export interface AdapterMetadata {
  name: string
  version: string
  description?: string
  author?: string
  license?: string
}

export interface AdapterConstructor<T = any> {
  new (config?: any): T
  metadata: AdapterMetadata
}

export interface AdapterInfo {
  id: string
  name: string
  version: string
  description?: string
}
