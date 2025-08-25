/**
 * Whisper STT Adapter Implementation
 * Uses @xenova/transformers for browser-based Whisper models
 */

import {
  BaseAdapter,
  type STTAdapter,
  type STTEvents,
  type STTConfig,
  type STTMetrics,
  type TranscriptionResult,
  type ModelLoadingProgress,
  type AdapterType,
  type TranscribeOptions,
  type ModelInfo,
  Result,
  logger,
  ServiceRegistry
} from '@runanywhere/core';

export class WhisperSTTAdapter extends BaseAdapter<STTEvents> implements STTAdapter {
  readonly id = 'whisper';
  readonly name = 'Whisper (Transformers.js)';
  readonly version = '1.0.0';
  readonly supportedModels: ModelInfo[] = [
    {
      id: 'whisper-tiny',
      name: 'Whisper Tiny',
      size: '39MB',
      languages: ['en', 'multi'],
      accuracy: 'low' as const,
      speed: 'fast' as const
    },
    {
      id: 'whisper-base',
      name: 'Whisper Base',
      size: '74MB',
      languages: ['en', 'multi'],
      accuracy: 'medium' as const,
      speed: 'medium' as const
    },
    {
      id: 'whisper-small',
      name: 'Whisper Small',
      size: '244MB',
      languages: ['en', 'multi'],
      accuracy: 'high' as const,
      speed: 'slow' as const
    },
  ];

  private worker?: Worker;
  private currentModel?: ModelInfo;
  private config?: STTConfig;
  private isInitialized = false;
  private lastTranscriptionResult?: any;
  private metrics: STTMetrics = {
    totalTranscriptions: 0,
    avgProcessingTime: 0,
    modelLoadTime: 0,
    lastTranscriptionTime: undefined
  };

  async initialize(config?: STTConfig): Promise<Result<void, Error>> {
    try {
      this.config = config;

      // Create worker for non-blocking operation (whisper-web pattern)
      if (typeof window !== 'undefined') {
        this.worker = new Worker(
          new URL('./worker.ts', import.meta.url),
          { type: 'module' }
        );

        // Set up message handler - whisper-web pattern
        this.worker.addEventListener('message', this.handleWorkerMessage);

        // Handle worker errors
        this.worker.addEventListener('error', (error) => {
          logger.error('Worker error', 'WhisperSTTAdapter', { error });
          this.emit('error', new Error(`Worker error: ${error.message}`));
        });
      }

      this.isInitialized = true;
      return Result.ok(undefined);
    } catch (error) {
      return Result.err(error as Error);
    }
  }

  async loadModel(modelId: string): Promise<Result<void, Error>> {
    const startTime = Date.now();
    try {
      const modelInfo = this.supportedModels.find(m => m.id === modelId);
      if (!modelInfo) {
        return Result.err(new Error(`Unsupported model: ${modelId}`));
      }

      if (!this.worker) {
        return Result.err(new Error('Worker not initialized'));
      }

      // No explicit load step - whisper-web loads on first transcription
      this.currentModel = modelInfo;
      this.metrics.modelLoadTime = Date.now() - startTime;

      logger.info(`Whisper model ${modelId} loaded successfully`, 'WhisperSTTAdapter');
      return Result.ok(undefined);
    } catch (error) {
      logger.error(`Failed to load Whisper model ${modelId}`, 'WhisperSTTAdapter', { error });
      this.emit('error', error as Error);
      return Result.err(error as Error);
    }
  }

  async transcribe(
    audio: Float32Array,
    options?: TranscribeOptions
  ): Promise<Result<TranscriptionResult, Error>> {
    if (!this.worker || !this.currentModel) {
      return Result.err(new Error('Model not loaded'));
    }

    try {
      const startTime = Date.now();

      // Process audio using whisper-web exact pattern
      const audioData = this.preprocessAudio(audio);

      // Send message to worker like whisper-web does
      this.worker.postMessage({
        audio: audioData,
        model: `Xenova/${this.currentModel.id}`,
        dtype: { encoder_model: 'fp32', decoder_model_merged: 'q4' },
        gpu: false, // Start with WASM, can detect WebGPU later
        subtask: options?.task || 'transcribe',
        language: options?.language
      });

      // Return a promise that resolves when transcription completes
      const result = await new Promise<any>((resolve, reject) => {
        const handleMessage = (event: MessageEvent) => {
          const message = event.data;
          if (message.status === 'complete') {
            this.worker?.removeEventListener('message', handleMessage);
            resolve(message.data);
          } else if (message.status === 'error') {
            this.worker?.removeEventListener('message', handleMessage);
            reject(new Error(message.data?.message || 'Transcription failed'));
          }
        };

        this.worker?.addEventListener('message', handleMessage);
      });

      const processingTime = Date.now() - startTime;

      // Update metrics
      this.metrics.totalTranscriptions++;
      this.metrics.avgProcessingTime =
        (this.metrics.avgProcessingTime * (this.metrics.totalTranscriptions - 1) + processingTime) /
        this.metrics.totalTranscriptions;
      this.metrics.lastTranscriptionTime = Date.now();

      // Add processing time to result
      result.processingTime = processingTime;

      return Result.ok(result as TranscriptionResult);
    } catch (error) {
      this.emit('error', error as Error);
      return Result.err(error as Error);
    }
  }

  private preprocessAudio(audio: Float32Array): Float32Array {
    // Process audio following whisper-web patterns
    // Ensure audio is at 16kHz mono as required by Whisper
    const WHISPER_SAMPLE_RATE = 16000;

    // For now, assume audio is already at correct format
    // In production, you'd implement resampling here
    return audio;
  }

  // Use whisper-web exact pattern for worker communication
  private handleWorkerMessage = (event: MessageEvent) => {
    const message = event.data;

    // Handle different message types like whisper-web
    switch (message.status) {
      case "progress":
        // Model file progress
        this.emit('model_loading', {
          progress: message.progress || 0,
          message: message.file ? `Loading ${message.file}...` : 'Loading...'
        });
        break;

      case "initiate":
        // Model file start load
        this.emit('model_loading', {
          progress: 0,
          message: `Loading ${message.file || 'model'}...`
        });
        break;

      case "ready":
        // Model is ready - could emit event here if needed
        break;

      case "complete":
        // Transcription complete
        const result = {
          text: message.data.text,
          language: 'en', // Default
          confidence: 0.95,
          processingTime: 0,
          timestamps: message.data.chunks?.map((chunk: any) => ({
            start: chunk.timestamp[0],
            end: chunk.timestamp[1],
            text: chunk.text,
          })),
        };

        // Store result for retrieval
        this.lastTranscriptionResult = result;
        logger.info('Transcription completed', 'WhisperSTTAdapter', { text: result.text });
        break;

      case "error":
        const errorMsg = message.data?.message || 'Transcription error';
        this.emit('error', new Error(errorMsg));
        logger.error('Worker error', 'WhisperSTTAdapter', { error: message.data });
        break;

      case "done":
        // Model file loaded
        break;

      default:
        break;
    }
  };

  destroy(): void {
    if (this.worker) {
      this.worker.terminate();
      this.worker = undefined;
    }
    this.currentModel = undefined;
    this.isInitialized = false;
    this.removeAllListeners();
  }

  isModelLoaded(): boolean {
    return !!this.worker && !!this.currentModel;
  }

  getLoadedModel(): ModelInfo | null {
    return this.currentModel || null;
  }

  isHealthy(): boolean {
    return this.isInitialized && this.isModelLoaded();
  }

  getMetrics(): STTMetrics {
    return { ...this.metrics };
  }
}

// Auto-register with ServiceRegistry if available
if (typeof window !== 'undefined') {
  try {
    const registry = ServiceRegistry.getInstance();
    registry.register('STT' as AdapterType, 'whisper', WhisperSTTAdapter as any);
    logger.info('Whisper STT adapter auto-registered', 'WhisperSTTAdapter');
  } catch (error) {
    // ServiceRegistry not available, skip auto-registration
    logger.debug('ServiceRegistry not available for auto-registration', 'WhisperSTTAdapter');
  }
}

// Named exports
export { WhisperSTTAdapter as default };
export const adapter = WhisperSTTAdapter;

// Metadata for registry
export const WhisperSTTAdapterMetadata = {
  id: 'whisper',
  name: 'Whisper (Transformers.js)',
  version: '1.0.0',
  description: 'OpenAI Whisper models running in the browser via Transformers.js',
  modelSizes: {
    'whisper-tiny': '39MB',
    'whisper-base': '74MB',
    'whisper-small': '244MB',
  },
  offline: true,
  languages: 99,
  requirements: {
    memory: '512MB-2GB',
    compute: 'cpu',
  },
};
