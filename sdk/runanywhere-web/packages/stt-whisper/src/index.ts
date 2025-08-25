/**
 * Whisper STT Adapter Implementation
 * Uses @huggingface/transformers with proper worker isolation to prevent bundle size issues
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

export interface WhisperSTTConfig extends STTConfig {
  model?: 'whisper-tiny' | 'whisper-base' | 'whisper-small';
  device?: 'wasm' | 'webgpu';
  dtype?: {
    encoder_model?: string;
    decoder_model_merged?: string;
  };
  language?: string;
  task?: 'transcribe' | 'translate';
}

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
  private config?: WhisperSTTConfig;
  private isInitialized = false;
  private modelLoaded = false;
  private workerReady = false;
  private metrics: STTMetrics = {
    totalTranscriptions: 0,
    avgProcessingTime: 0,
    modelLoadTime: 0,
    lastTranscriptionTime: undefined
  };

  async initialize(config?: WhisperSTTConfig): Promise<Result<void, Error>> {
    try {
      this.config = config;

      // Create worker from public URL that Next.js can serve
      // In production, this would need to be configured based on the app's public path
      const workerUrl = '/stt-worker.js';
      this.worker = new Worker(workerUrl, {
        type: 'module',
        name: 'whisper-worker'
      });

      // Set up worker message handler
      this.worker.onmessage = (event) => {
        this.handleWorkerMessage(event.data);
      };

      this.worker.onerror = (error) => {
        logger.error('Worker error', 'WhisperSTTAdapter', { error });
        this.emit('error', error as any);
      };

      // Wait for worker to be ready
      await this.waitForWorkerReady();

      this.isInitialized = true;
      logger.info('Whisper STT adapter initialized', 'WhisperSTTAdapter');

      // Load the default model if specified
      if (config?.model) {
        const loadResult = await this.loadModel(config.model);
        if (Result.isErr(loadResult)) {
          logger.warn(`Failed to load default model ${config.model}`, 'WhisperSTTAdapter', { error: loadResult.error.message });
        }
      }

      return Result.ok(undefined);
    } catch (error) {
      logger.error('Failed to initialize Whisper STT', 'WhisperSTTAdapter', { error });
      return Result.err(error as Error);
    }
  }

  private async waitForWorkerReady(): Promise<void> {
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        reject(new Error('Worker initialization timeout'));
      }, 30000); // 30 second timeout

      const handler = (event: MessageEvent) => {
        if (event.data.status === 'worker_ready') {
          clearTimeout(timeout);
          this.worker!.removeEventListener('message', handler);
          this.workerReady = true;
          resolve();
        }
      };

      this.worker!.addEventListener('message', handler);
    });
  }

  private handleWorkerMessage(message: any): void {
    const { status, data, error } = message;

    switch (status) {
      case 'loading':
      case 'progress':
        this.emit('model_loading', {
          progress: message.progress || 0,
          message: message.message || 'Loading model...'
        });
        break;

      case 'ready':
        this.modelLoaded = true;
        this.emit('model_loading', {
          progress: 100,
          message: 'Model loaded successfully'
        });
        break;

      case 'complete':
        // Transcription completed
        break;

      case 'error':
        logger.error('Worker reported error', 'WhisperSTTAdapter', { error });
        this.emit('error', new Error(message.message));
        break;

      default:
        logger.debug('Unknown worker message', 'WhisperSTTAdapter', { message });
        break;
    }
  }

  private getModelId(model: string): string {
    switch (model) {
      case 'whisper-tiny':
        return 'onnx-community/whisper-tiny';
      case 'whisper-base':
        return 'onnx-community/whisper-base';
      case 'whisper-small':
        return 'onnx-community/whisper-small';
      default:
        return 'onnx-community/whisper-tiny';
    }
  }

  async loadModel(modelId: string): Promise<Result<void, Error>> {
    const startTime = Date.now();
    try {
      if (!this.worker || !this.workerReady) {
        return Result.err(new Error('Worker not ready'));
      }

      const modelInfo = this.supportedModels.find(m => m.id === modelId);
      if (!modelInfo) {
        return Result.err(new Error(`Unsupported model: ${modelId}`));
      }

      this.currentModel = modelInfo;
      this.modelLoaded = false;

      const fullModelId = this.getModelId(modelId);

      // Send load command to worker
      // Use simple dtype string like whisper-web does
      this.worker.postMessage({
        type: 'load',
        data: {
          model_id: fullModelId,
          dtype: this.config?.dtype || 'q8',  // Use simple string dtype
          device: this.config?.device || 'wasm'
        }
      });

      // Wait for model to be loaded
      await this.waitForModelLoad();

      this.metrics.modelLoadTime = Date.now() - startTime;

      logger.info(`Whisper model ${modelId} loaded successfully`, 'WhisperSTTAdapter');
      return Result.ok(undefined);
    } catch (error) {
      logger.error(`Failed to load Whisper model ${modelId}`, 'WhisperSTTAdapter', { error });
      return Result.err(error as Error);
    }
  }

  private async waitForModelLoad(): Promise<void> {
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        reject(new Error('Model load timeout'));
      }, 300000); // 5 minute timeout

      const handler = (event: MessageEvent) => {
        if (event.data.status === 'ready') {
          clearTimeout(timeout);
          this.worker!.removeEventListener('message', handler);
          resolve();
        } else if (event.data.status === 'error') {
          clearTimeout(timeout);
          this.worker!.removeEventListener('message', handler);
          reject(new Error(event.data.message));
        }
      };

      this.worker!.addEventListener('message', handler);
    });
  }

  async transcribe(
    audio: Float32Array,
    options?: TranscribeOptions
  ): Promise<Result<TranscriptionResult, Error>> {
    if (!this.worker || !this.workerReady || !this.modelLoaded || !this.currentModel) {
      return Result.err(new Error('Worker or model not ready'));
    }

    try {
      const startTime = Date.now();
      logger.debug('Starting transcription', 'WhisperSTTAdapter', { audioLength: audio.length });

      const fullModelId = this.getModelId(this.currentModel.id);

      // Send transcription request to worker
      // Pass Float32Array directly - it will be cloned automatically
      this.worker.postMessage({
        type: 'transcribe',
        data: {
          audio: audio,
          model_id: fullModelId,
          language: options?.language || this.config?.language,
          task: options?.task || this.config?.task || 'transcribe'
        }
      });

      // Wait for transcription result
      const result = await this.waitForTranscription();

      // Update metrics
      const processingTime = Date.now() - startTime;
      this.metrics.totalTranscriptions++;
      this.metrics.avgProcessingTime =
        (this.metrics.avgProcessingTime * (this.metrics.totalTranscriptions - 1) + processingTime) /
        this.metrics.totalTranscriptions;
      this.metrics.lastTranscriptionTime = Date.now();

      // Add processing time to result
      const finalResult = {
        ...result,
        processingTime
      };

      return Result.ok(finalResult);

    } catch (error) {
      logger.error('Transcription failed', 'WhisperSTTAdapter', { error });
      this.emit('error', error as Error);
      return Result.err(error as Error);
    }
  }

  private async waitForTranscription(): Promise<TranscriptionResult> {
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        reject(new Error('Transcription timeout'));
      }, 60000); // 1 minute timeout

      const handler = (event: MessageEvent) => {
        if (event.data.status === 'complete') {
          clearTimeout(timeout);
          this.worker!.removeEventListener('message', handler);
          resolve(event.data.data);
        } else if (event.data.status === 'error') {
          clearTimeout(timeout);
          this.worker!.removeEventListener('message', handler);
          reject(new Error(event.data.message));
        }
      };

      this.worker!.addEventListener('message', handler);
    });
  }


  async destroy(): Promise<void> {
    if (this.worker) {
      // Send dispose command to worker
      this.worker.postMessage({ type: 'dispose' });

      // Terminate the worker
      this.worker.terminate();
      this.worker = undefined;
    }

    this.currentModel = undefined;
    this.isInitialized = false;
    this.modelLoaded = false;
    this.workerReady = false;
    this.removeAllListeners();
    logger.info('Whisper STT adapter destroyed', 'WhisperSTTAdapter');
  }

  isModelLoaded(): boolean {
    return this.modelLoaded && !!this.currentModel;
  }

  getLoadedModel(): ModelInfo | null {
    return this.currentModel || null;
  }

  isHealthy(): boolean {
    return this.isInitialized && this.modelLoaded;
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
