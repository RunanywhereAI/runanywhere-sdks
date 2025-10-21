import type { VADConfig } from '../services/vad/types';

/**
 * Pipeline component types
 */
export type PipelineComponent = 'vad' | 'stt' | 'llm' | 'tts';

/**
 * Pipeline configuration
 */
export interface PipelineConfig {
  /** VAD configuration */
  vad?: {
    enabled: boolean;
    config?: Partial<VADConfig>;
  };

  /** STT configuration (Phase 2) */
  stt?: {
    enabled: boolean;
    modelId?: string;
    language?: string;
  };

  /** LLM configuration (Phase 2) */
  llm?: {
    enabled: boolean;
    modelId?: string;
    systemPrompt?: string;
    temperature?: number;
  };

  /** TTS configuration (Phase 2) */
  tts?: {
    enabled: boolean;
    modelId?: string;
    voice?: string;
    speed?: number;
  };

  /** Performance settings */
  performance?: {
    useWebWorkers?: boolean;
    bufferSize?: number;
    maxConcurrentOperations?: number;
  };
}

/**
 * Pipeline state
 */
export enum PipelineState {
  IDLE = 'idle',
  INITIALIZING = 'initializing',
  READY = 'ready',
  RUNNING = 'running',
  PAUSED = 'paused',
  ERROR = 'error',
  DESTROYED = 'destroyed'
}

/**
 * Pipeline event types with modern discriminated unions
 */
export type PipelineEvent =
  // Lifecycle events
  | { type: 'initialized'; components: PipelineComponent[] }
  | { type: 'started'; timestamp: number }
  | { type: 'stopped'; timestamp: number }
  | { type: 'paused'; timestamp: number }
  | { type: 'resumed'; timestamp: number }
  | { type: 'error'; error: Error; component?: PipelineComponent }
  | { type: 'destroyed' }

  // VAD events
  | { type: 'vad:speech_start'; timestamp: number }
  | { type: 'vad:speech_end'; audio: Float32Array; duration: number }
  | { type: 'vad:audio_level'; level: number }

  // STT events (Phase 2)
  | { type: 'stt:partial'; text: string; confidence?: number }
  | { type: 'stt:final'; text: string; confidence?: number }

  // LLM events (Phase 2)
  | { type: 'llm:thinking' }
  | { type: 'llm:streaming'; token: string }
  | { type: 'llm:complete'; response: string }

  // TTS events (Phase 2)
  | { type: 'tts:started' }
  | { type: 'tts:audio_chunk'; chunk: ArrayBuffer }
  | { type: 'tts:complete' }

  // Processing events
  | { type: 'processing:start'; stage: PipelineComponent }
  | { type: 'processing:complete'; stage: PipelineComponent; duration: number };

/**
 * Pipeline metrics
 */
export interface PipelineMetrics {
  sessionsProcessed: number;
  totalProcessingTime: number;
  averageLatency: number;
  componentMetrics: Map<PipelineComponent, {
    invocations: number;
    totalTime: number;
    errors: number;
  }>;
}

/**
 * Pipeline health status
 */
export interface PipelineHealth {
  overall: boolean;
  components: Map<PipelineComponent, {
    healthy: boolean;
    message?: string;
  }>;
  lastCheck: Date;
}
