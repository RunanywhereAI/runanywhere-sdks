/**
 * Whisper STT Adapter Implementation
 * Uses @xenova/transformers for browser-based Whisper models
 */

import type { Pipeline } from '@xenova/transformers';
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

  private pipeline?: Pipeline;
  private processor?: any;
  private currentModel?: ModelInfo;
  private config?: STTConfig;
  private isInitialized = false;
  private metrics: STTMetrics = {
    totalTranscriptions: 0,
    avgProcessingTime: 0,
    modelLoadTime: 0,
    lastTranscriptionTime: undefined
  };

  async initialize(config?: STTConfig): Promise<Result<void, Error>> {
    try {
      this.config = config;
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

      // Emit loading progress
      this.emit('model_loading', { progress: 0, message: 'Importing transformers...' });

      // Dynamic import to avoid bundling
      const transformers = await import('@xenova/transformers');

      this.emit('model_loading', { progress: 10, message: 'Creating pipeline...' });

      // Create the pipeline with progress callback
      this.pipeline = await transformers.pipeline(
        'automatic-speech-recognition',
        `Xenova/${modelId}`,
        {
          progress_callback: (progress: any) => {
            if (progress.status === 'downloading') {
              const percent = (progress.loaded / progress.total) * 90 + 10;
              this.emit('model_loading', {
                progress: percent,
                message: `Downloading model... ${Math.round(percent)}%`
              });
            }
          }
        }
      );

      // Also create processor for audio preprocessing
      const AutoProcessor = transformers.AutoProcessor;
      this.processor = await AutoProcessor.from_pretrained(`Xenova/${modelId}`);

      this.currentModel = modelInfo;
      this.emit('model_loading', { progress: 100, message: 'Model loaded successfully' });

      // Update metrics
      this.metrics.modelLoadTime = Date.now() - startTime;

      return Result.ok(undefined);
    } catch (error) {
      this.emit('error', error as Error);
      return Result.err(error as Error);
    }
  }

  async transcribe(
    audio: Float32Array,
    options?: TranscribeOptions
  ): Promise<Result<TranscriptionResult, Error>> {
    if (!this.pipeline || !this.processor) {
      return Result.err(new Error('Model not loaded'));
    }

    try {
      const startTime = Date.now();

      // Process audio for Whisper
      const inputs = await this.preprocessAudio(audio);

      // Run inference
      const output = await this.pipeline(inputs, {
        language: options?.language,
        task: options?.task || 'transcribe',
        return_timestamps: options?.timestamps !== false,
        chunk_length_s: 30,
        stride_length_s: 5,
      });

      const processingTime = Date.now() - startTime;

      // Update metrics
      this.metrics.totalTranscriptions++;
      this.metrics.avgProcessingTime =
        (this.metrics.avgProcessingTime * (this.metrics.totalTranscriptions - 1) + processingTime) /
        this.metrics.totalTranscriptions;
      this.metrics.lastTranscriptionTime = Date.now();

      // Format result
      const result: TranscriptionResult = {
        text: output.text,
        language: output.language || options?.language || 'en',
        confidence: 0.95, // Whisper doesn't provide confidence scores
        processingTime,
        timestamps: output.chunks?.map((chunk: any) => ({
          start: chunk.timestamp[0],
          end: chunk.timestamp[1],
          text: chunk.text,
        })),
      };

      return Result.ok(result);
    } catch (error) {
      this.emit('error', error as Error);
      return Result.err(error as Error);
    }
  }

  private async preprocessAudio(audio: Float32Array): Promise<any> {
    // Ensure audio is at 16kHz (Whisper requirement)
    const WHISPER_SAMPLE_RATE = 16000;

    // In a real implementation, you'd resample if needed
    // For now, assume audio is already at 16kHz

    return {
      raw: audio,
      sampling_rate: WHISPER_SAMPLE_RATE,
    };
  }

  destroy(): void {
    this.pipeline = undefined;
    this.processor = undefined;
    this.currentModel = undefined;
    this.isInitialized = false;
    this.removeAllListeners();
  }

  isModelLoaded(): boolean {
    return !!this.pipeline && !!this.currentModel;
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
