import { Result } from '../types/result'

export interface LLMConfig {
  model?: string
  defaultModel?: string
  apiKey?: string
  endpoint?: string
  temperature?: number
  maxTokens?: number
  topP?: number
  topK?: number
  systemPrompt?: string
  timeout?: number
}

export interface Message {
  role: 'system' | 'user' | 'assistant'
  content: string
  timestamp?: number
}

export interface CompletionOptions {
  model?: string
  temperature?: number
  maxTokens?: number
  topP?: number
  topK?: number
  stopSequences?: string[]
  stream?: boolean
  frequencyPenalty?: number
  presencePenalty?: number
  saveToHistory?: boolean
  useHistory?: boolean
  historyLimit?: number
}

export interface CompletionResult {
  text: string
  finishReason?: 'stop' | 'length' | 'error'
  usage?: {
    promptTokens: number
    completionTokens: number
    totalTokens: number
  }
  model?: string
  latency?: number
}

export interface TokenResult {
  token: string
  isComplete: boolean
  finishReason?: 'stop' | 'length' | 'error'
  tokenIndex?: number
  timestamp?: number
}

export interface LLMMetrics {
  totalCompletions: number
  totalTokens: number
  avgResponseTime: number
  errorRate: number
  averageLatency?: number
  totalCost?: number
}

export type LLMEvents = {
  token: (token: string) => void
  error: (error: Error) => void
}

export interface LLMAdapter {
  readonly id: string
  readonly name: string
  readonly version: string
  readonly supportedModels: string[]

  initialize(config?: LLMConfig): Promise<Result<void, Error>>
  complete(prompt: string, options?: CompletionOptions): Promise<Result<CompletionResult, Error>>
  completeStream(prompt: string, options?: CompletionOptions): AsyncGenerator<TokenResult>
  destroy(): void

  setSystemPrompt(prompt: string): void
  clearHistory(): void
  getHistory(): Message[]
  addMessage(message: Message): void

  on<K extends keyof LLMEvents>(event: K, handler: LLMEvents[K]): void
  off<K extends keyof LLMEvents>(event: K, handler?: LLMEvents[K]): void

  isHealthy(): boolean
  getMetrics(): LLMMetrics
}
