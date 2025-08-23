import type { EnhancedPipelineConfig } from '@runanywhere/voice';

export interface VoicePipelineConfig extends EnhancedPipelineConfig {
  autoInitialize?: boolean;
  autoStart?: boolean;
}

export interface ConversationEntry {
  id: string;
  type: 'user' | 'assistant';
  text: string;
  timestamp: Date;
}

export interface VoicePipelineState {
  isInitialized: boolean;
  isListening: boolean;
  isProcessing: boolean;
  isPlaying: boolean;
  error: Error | null;
}

export interface VoiceMetrics {
  vadLatency: number;
  sttLatency: number;
  llmLatency: number;
  ttsLatency: number;
  totalLatency: number;
}
