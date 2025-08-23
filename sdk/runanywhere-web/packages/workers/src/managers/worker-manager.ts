// Worker Manager for orchestrating audio and LLM workers
import type { Result } from '@runanywhere/core';
import type {
  InitializeMessage as AudioInitializeMessage,
  ProcessAudioMessage,
  WorkerResponse as AudioWorkerResponse,
  InitializedResponse as AudioInitializedResponse,
  VADResultResponse,
  TranscriptionResponse,
  ErrorResponse as AudioErrorResponse
} from '../workers/audio-processor.worker';

import type {
  LLMInitializeMessage,
  LLMProcessMessage,
  LLMWorkerResponse,
  LLMInitializedResponse,
  LLMTextResponse,
  LLMStreamResponse,
  LLMErrorResponse
} from '../workers/llm-processor.worker';

export interface WorkerManagerConfig {
  // Audio Worker Config
  vadModelUrl?: string;
  whisperModelUrl?: string;
  sampleRate?: number;

  // LLM Worker Config
  llmApiKey?: string;
  llmBaseUrl?: string;
  llmModelName?: string;
  systemPrompt?: string;
  maxTokens?: number;
  temperature?: number;

  // General Config
  enableFallback?: boolean;
  workerTimeout?: number;
}

export interface WorkerManagerEvents {
  initialized: void;
  vadResult: {
    speechDetected: boolean;
    confidence: number;
    timestamp: number;
  };
  transcription: {
    text: string;
    confidence: number;
    timestamp: number;
    duration: number;
  };
  llmResponse: {
    text: string;
    isComplete: boolean;
    metadata?: any;
  };
  llmStream: {
    delta: string;
    text: string;
    isComplete: boolean;
  };
  error: Error;
}

export class WorkerManager {
  private audioWorker: Worker | null = null;
  private llmWorker: Worker | null = null;
  private config: WorkerManagerConfig;
  private isInitialized = false;
  private messageId = 0;
  private pendingRequests = new Map<string, {
    resolve: (value: any) => void;
    reject: (error: Error) => void;
    timeout: number;
  }>();
  private eventHandlers = new Map<keyof WorkerManagerEvents, Function[]>();
  private supportsWorkers: boolean;

  constructor(config: WorkerManagerConfig = {}) {
    this.config = config;
    this.supportsWorkers = typeof Worker !== 'undefined';

    if (!this.supportsWorkers && !config.enableFallback) {
      throw new Error('Web Workers not supported and fallback disabled');
    }
  }

  async initialize(): Promise<Result<void, Error>> {
    try {
      if (this.supportsWorkers) {
        await this.initializeWorkers();
      } else if (this.config.enableFallback) {
        console.warn('[WorkerManager] Web Workers not supported, running in fallback mode');
        // Fallback implementation would go here
      }

      this.isInitialized = true;
      this.emit('initialized', undefined);

      return { success: true, value: undefined };
    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error));
      this.emit('error', err);
      return { success: false, error: err };
    }
  }

  private async initializeWorkers(): Promise<void> {
    // Initialize Audio Worker
    this.audioWorker = new Worker(
      new URL('../workers/audio-processor.worker.ts', import.meta.url),
      { type: 'module' }
    );

    this.audioWorker.addEventListener('message', this.handleAudioWorkerMessage.bind(this));
    this.audioWorker.addEventListener('error', (error) => {
      this.emit('error', new Error(`Audio worker error: ${error.message}`));
    });

    // Initialize LLM Worker
    this.llmWorker = new Worker(
      new URL('../workers/llm-processor.worker.ts', import.meta.url),
      { type: 'module' }
    );

    this.llmWorker.addEventListener('message', this.handleLLMWorkerMessage.bind(this));
    this.llmWorker.addEventListener('error', (error) => {
      this.emit('error', new Error(`LLM worker error: ${error.message}`));
    });

    // Initialize both workers
    const audioInitPromise = this.sendAudioWorkerMessage<AudioInitializedResponse>({
      id: this.generateMessageId(),
      type: 'initialize',
      data: {
        vadModelUrl: this.config.vadModelUrl,
        whisperModelUrl: this.config.whisperModelUrl,
        sampleRate: this.config.sampleRate
      }
    });

    const llmInitPromise = this.sendLLMWorkerMessage<LLMInitializedResponse>({
      id: this.generateMessageId(),
      type: 'initialize',
      data: {
        apiKey: this.config.llmApiKey,
        baseUrl: this.config.llmBaseUrl,
        modelName: this.config.llmModelName,
        systemPrompt: this.config.systemPrompt,
        maxTokens: this.config.maxTokens,
        temperature: this.config.temperature
      }
    });

    await Promise.all([audioInitPromise, llmInitPromise]);
  }

  async processAudio(audioData: Float32Array): Promise<Result<void, Error>> {
    if (!this.isInitialized) {
      return { success: false, error: new Error('Worker manager not initialized') };
    }

    if (!this.audioWorker) {
      return { success: false, error: new Error('Audio worker not available') };
    }

    try {
      // Send audio to audio worker for VAD and potential STT processing
      await this.sendAudioWorkerMessage({
        id: this.generateMessageId(),
        type: 'processAudio',
        data: {
          audioData,
          timestamp: Date.now()
        }
      });

      return { success: true, value: undefined };
    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error));
      return { success: false, error: err };
    }
  }

  async processLLM(
    prompt: string,
    context: Array<{ role: 'user' | 'assistant'; content: string }> = [],
    stream = false
  ): Promise<Result<void, Error>> {
    if (!this.isInitialized) {
      return { success: false, error: new Error('Worker manager not initialized') };
    }

    if (!this.llmWorker) {
      return { success: false, error: new Error('LLM worker not available') };
    }

    try {
      await this.sendLLMWorkerMessage({
        id: this.generateMessageId(),
        type: 'process',
        data: {
          prompt,
          context,
          stream
        }
      });

      return { success: true, value: undefined };
    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error));
      return { success: false, error: err };
    }
  }

  private handleAudioWorkerMessage(event: MessageEvent<AudioWorkerResponse>): void {
    const response = event.data;

    // Handle pending request resolution
    if (this.pendingRequests.has(response.id)) {
      const pending = this.pendingRequests.get(response.id)!;
      clearTimeout(pending.timeout);
      this.pendingRequests.delete(response.id);

      if (response.success) {
        pending.resolve(response);
      } else {
        pending.reject(new Error(response.error || 'Audio worker request failed'));
      }
    }

    // Handle events
    switch (response.type) {
      case 'vadResult': {
        const vadResponse = response as VADResultResponse;
        this.emit('vadResult', vadResponse.data);
        break;
      }
      case 'transcription': {
        const transcriptionResponse = response as TranscriptionResponse;
        this.emit('transcription', transcriptionResponse.data);
        break;
      }
      case 'error': {
        const errorResponse = response as AudioErrorResponse;
        this.emit('error', new Error(errorResponse.error));
        break;
      }
    }
  }

  private handleLLMWorkerMessage(event: MessageEvent<LLMWorkerResponse>): void {
    const response = event.data;

    // Handle pending request resolution
    if (this.pendingRequests.has(response.id)) {
      const pending = this.pendingRequests.get(response.id)!;

      // Don't resolve streaming responses until complete
      if (response.type !== 'textStream' || (response as LLMStreamResponse).data.isComplete) {
        clearTimeout(pending.timeout);
        this.pendingRequests.delete(response.id);

        if (response.success) {
          pending.resolve(response);
        } else {
          pending.reject(new Error(response.error || 'LLM worker request failed'));
        }
      }
    }

    // Handle events
    switch (response.type) {
      case 'textGenerated': {
        const textResponse = response as LLMTextResponse;
        this.emit('llmResponse', textResponse.data);
        break;
      }
      case 'textStream': {
        const streamResponse = response as LLMStreamResponse;
        this.emit('llmStream', streamResponse.data);
        break;
      }
      case 'error': {
        const errorResponse = response as LLMErrorResponse;
        this.emit('error', new Error(errorResponse.error));
        break;
      }
    }
  }

  private sendAudioWorkerMessage<T = AudioWorkerResponse>(
    message: any
  ): Promise<T> {
    return this.sendWorkerMessage(this.audioWorker, message);
  }

  private sendLLMWorkerMessage<T = LLMWorkerResponse>(
    message: any
  ): Promise<T> {
    return this.sendWorkerMessage(this.llmWorker, message);
  }

  private sendWorkerMessage<T>(
    worker: Worker | null,
    message: any
  ): Promise<T> {
    return new Promise((resolve, reject) => {
      if (!worker) {
        reject(new Error('Worker not available'));
        return;
      }

      const timeout = setTimeout(() => {
        this.pendingRequests.delete(message.id);
        reject(new Error('Worker request timeout'));
      }, this.config.workerTimeout || 30000) as any;

      this.pendingRequests.set(message.id, {
        resolve,
        reject,
        timeout
      });

      worker.postMessage(message);
    });
  }

  private generateMessageId(): string {
    return `msg-${++this.messageId}-${Date.now()}`;
  }

  // Event handling
  on<K extends keyof WorkerManagerEvents>(
    event: K,
    handler: (data: WorkerManagerEvents[K]) => void
  ): void {
    if (!this.eventHandlers.has(event)) {
      this.eventHandlers.set(event, []);
    }
    this.eventHandlers.get(event)!.push(handler);
  }

  off<K extends keyof WorkerManagerEvents>(
    event: K,
    handler: (data: WorkerManagerEvents[K]) => void
  ): void {
    const handlers = this.eventHandlers.get(event);
    if (handlers) {
      const index = handlers.indexOf(handler);
      if (index > -1) {
        handlers.splice(index, 1);
      }
    }
  }

  private emit<K extends keyof WorkerManagerEvents>(
    event: K,
    data: WorkerManagerEvents[K]
  ): void {
    const handlers = this.eventHandlers.get(event);
    if (handlers) {
      handlers.forEach(handler => {
        try {
          handler(data);
        } catch (error) {
          console.error(`[WorkerManager] Error in event handler for ${event}:`, error);
        }
      });
    }
  }

  async destroy(): Promise<void> {
    // Clear pending requests
    this.pendingRequests.forEach(pending => {
      clearTimeout(pending.timeout);
      pending.reject(new Error('Worker manager destroyed'));
    });
    this.pendingRequests.clear();

    // Terminate workers
    if (this.audioWorker) {
      this.audioWorker.postMessage({ id: 'destroy', type: 'destroy' });
      this.audioWorker.terminate();
      this.audioWorker = null;
    }

    if (this.llmWorker) {
      this.llmWorker.postMessage({ id: 'destroy', type: 'destroy' });
      this.llmWorker.terminate();
      this.llmWorker = null;
    }

    // Clear event handlers
    this.eventHandlers.clear();

    this.isInitialized = false;
  }
}
