export interface LLMConfig {
  apiKey?: string;
  baseUrl?: string;
  model?: string;
  temperature?: number;
  maxTokens?: number;
  topP?: number;
  frequencyPenalty?: number;
  presencePenalty?: number;
  systemPrompt?: string;
  streamingEnabled?: boolean;
  timeout?: number;
}

export interface Message {
  role: 'system' | 'user' | 'assistant';
  content: string;
  timestamp?: number;
}

export interface CompletionResult {
  text: string;
  finishReason?: 'stop' | 'length' | 'error';
  usage?: {
    promptTokens: number;
    completionTokens: number;
    totalTokens: number;
  };
  latency?: {
    firstTokenMs: number;
    totalMs: number;
  };
}

export interface TokenEvent {
  token: string;
  position: number;
}

export interface FirstTokenEvent {
  token: string;
  latency: number;
}
