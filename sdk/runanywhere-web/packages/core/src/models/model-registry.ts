/**
 * Model Registry for centralized model management
 * Handles model metadata, downloading, and validation
 */

import { Result } from '../types/result';
import { logger } from '../utils/logger';
import { ModelCache } from './model-cache';

export interface ModelMetadata {
  id: string;
  name: string;
  type: 'vad' | 'stt' | 'llm' | 'tts';
  provider: string;
  size: number;
  format: 'onnx' | 'tensorflow' | 'pytorch' | 'custom';
  url: string;
  hash?: string;
  version: string;
  description?: string;
  requirements?: {
    memory: number;
    compute: 'cpu' | 'gpu' | 'webgpu';
  };
  supportedLanguages?: string[];
  performance?: {
    latency: string;
    throughput: string;
  };
}

export interface ModelLoadOptions {
  onProgress?: (progress: number, message?: string) => void;
  preferCache?: boolean;
  validateHash?: boolean;
}

export class ModelRegistry {
  private static instance: ModelRegistry;
  private models = new Map<string, ModelMetadata>();
  private cache: ModelCache;
  private loadingModels = new Map<string, Promise<ArrayBuffer>>();

  private constructor() {
    this.cache = new ModelCache();
    this.initializeBuiltInModels();
  }

  static getInstance(): ModelRegistry {
    if (!ModelRegistry.instance) {
      ModelRegistry.instance = new ModelRegistry();
    }
    return ModelRegistry.instance;
  }

  private initializeBuiltInModels(): void {
    // Register built-in models
    this.registerModel({
      id: 'silero-vad',
      name: 'Silero VAD',
      type: 'vad',
      provider: 'silero',
      size: 4.3 * 1024 * 1024, // 4.3MB
      format: 'onnx',
      url: 'https://cdn.jsdelivr.net/npm/@ricky0123/vad-web@0.0.24/dist/silero_vad.onnx',
      version: '4.0',
      description: 'High-quality voice activity detection model',
      requirements: {
        memory: 50 * 1024 * 1024, // 50MB
        compute: 'cpu'
      }
    });

    this.registerModel({
      id: 'whisper-tiny',
      name: 'Whisper Tiny',
      type: 'stt',
      provider: 'openai',
      size: 39 * 1024 * 1024, // 39MB
      format: 'onnx',
      url: 'https://huggingface.co/Xenova/whisper-tiny/resolve/main/onnx/encoder_model.onnx',
      version: '1.0',
      description: 'Fastest Whisper model, lower accuracy',
      supportedLanguages: ['en', 'multi'],
      requirements: {
        memory: 200 * 1024 * 1024, // 200MB
        compute: 'cpu'
      },
      performance: {
        latency: '200ms',
        throughput: '5x realtime'
      }
    });

    this.registerModel({
      id: 'whisper-base',
      name: 'Whisper Base',
      type: 'stt',
      provider: 'openai',
      size: 74 * 1024 * 1024, // 74MB
      format: 'onnx',
      url: 'https://huggingface.co/Xenova/whisper-base/resolve/main/onnx/encoder_model.onnx',
      version: '1.0',
      description: 'Balanced Whisper model',
      supportedLanguages: ['en', 'multi'],
      requirements: {
        memory: 400 * 1024 * 1024, // 400MB
        compute: 'cpu'
      },
      performance: {
        latency: '400ms',
        throughput: '3x realtime'
      }
    });

    this.registerModel({
      id: 'whisper-small',
      name: 'Whisper Small',
      type: 'stt',
      provider: 'openai',
      size: 244 * 1024 * 1024, // 244MB
      format: 'onnx',
      url: 'https://huggingface.co/Xenova/whisper-small/resolve/main/onnx/encoder_model.onnx',
      version: '1.0',
      description: 'High accuracy Whisper model',
      supportedLanguages: ['en', 'multi'],
      requirements: {
        memory: 1024 * 1024 * 1024, // 1GB
        compute: 'cpu'
      },
      performance: {
        latency: '800ms',
        throughput: '1.5x realtime'
      }
    });

    this.registerModel({
      id: 'speecht5-tts',
      name: 'SpeechT5 TTS',
      type: 'tts',
      provider: 'microsoft',
      size: 150 * 1024 * 1024, // 150MB
      format: 'onnx',
      url: 'https://huggingface.co/Xenova/speecht5_tts/resolve/main/onnx/model.onnx',
      version: '1.0',
      description: 'High-quality neural TTS model',
      supportedLanguages: ['en'],
      requirements: {
        memory: 500 * 1024 * 1024, // 500MB
        compute: 'cpu'
      },
      performance: {
        latency: '300ms',
        throughput: '2x realtime'
      }
    });
  }

  async initialize(): Promise<Result<void, Error>> {
    try {
      await this.cache.initialize();
      logger.info('Model registry initialized', 'ModelRegistry');
      return Result.ok(undefined);
    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error));
      logger.error(`Failed to initialize model registry: ${err.message}`, 'ModelRegistry');
      return Result.err(err);
    }
  }

  registerModel(metadata: ModelMetadata): void {
    this.models.set(metadata.id, metadata);
    logger.debug(`Registered model: ${metadata.id}`, 'ModelRegistry', { metadata });
  }

  getModel(modelId: string): ModelMetadata | undefined {
    return this.models.get(modelId);
  }

  getAvailableModels(type?: ModelMetadata['type']): ModelMetadata[] {
    const models = Array.from(this.models.values());
    if (type) {
      return models.filter(m => m.type === type);
    }
    return models;
  }

  async downloadModel(
    modelId: string,
    options?: ModelLoadOptions
  ): Promise<Result<ArrayBuffer, Error>> {
    try {
      // Check if already loading
      const existingLoad = this.loadingModels.get(modelId);
      if (existingLoad) {
        logger.debug(`Model ${modelId} already loading, waiting...`, 'ModelRegistry');
        const buffer = await existingLoad;
        return Result.ok(buffer);
      }

      // Check cache first if preferred
      if (options?.preferCache !== false) {
        const cached = await this.cache.get(modelId);
        if (cached) {
          logger.info(`Model ${modelId} loaded from cache`, 'ModelRegistry');
          options?.onProgress?.(100, 'Loaded from cache');
          return Result.ok(cached);
        }
      }

      // Get model metadata
      const metadata = this.models.get(modelId);
      if (!metadata) {
        return Result.err(new Error(`Model ${modelId} not found in registry`));
      }

      // Create loading promise
      const loadPromise = this.performDownload(metadata, options);
      this.loadingModels.set(modelId, loadPromise);

      try {
        const buffer = await loadPromise;
        return Result.ok(buffer);
      } finally {
        this.loadingModels.delete(modelId);
      }

    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error));
      logger.error(`Failed to download model ${modelId}: ${err.message}`, 'ModelRegistry');
      return Result.err(err);
    }
  }

  private async performDownload(
    metadata: ModelMetadata,
    options?: ModelLoadOptions
  ): Promise<ArrayBuffer> {
    logger.info(`Downloading model ${metadata.id} from ${metadata.url}`, 'ModelRegistry');

    options?.onProgress?.(0, 'Starting download...');

    const response = await fetch(metadata.url);

    if (!response.ok) {
      throw new Error(`Failed to download model: ${response.statusText}`);
    }

    // Get content length for progress tracking
    const contentLength = response.headers.get('content-length');
    const total = contentLength ? parseInt(contentLength, 10) : metadata.size;

    // Read the response with progress tracking
    const reader = response.body?.getReader();
    if (!reader) {
      throw new Error('Response body is not readable');
    }

    const chunks: Uint8Array[] = [];
    let receivedBytes = 0;

    while (true) {
      const { done, value } = await reader.read();

      if (done) break;

      chunks.push(value);
      receivedBytes += value.length;

      const progress = Math.round((receivedBytes / total) * 100);
      options?.onProgress?.(progress, `Downloading... ${progress}%`);
    }

    // Combine chunks into single ArrayBuffer
    const buffer = new Uint8Array(receivedBytes);
    let position = 0;
    for (const chunk of chunks) {
      buffer.set(chunk, position);
      position += chunk.length;
    }

    const arrayBuffer = buffer.buffer;

    // Validate hash if provided and requested
    if (metadata.hash && options?.validateHash !== false) {
      const valid = await this.validateHash(arrayBuffer, metadata.hash);
      if (!valid) {
        throw new Error('Model hash validation failed');
      }
    }

    // Cache for future use
    options?.onProgress?.(95, 'Caching model...');
    await this.cache.set(metadata.id, arrayBuffer);

    options?.onProgress?.(100, 'Model loaded successfully');
    logger.info(`Model ${metadata.id} downloaded successfully`, 'ModelRegistry', {
      size: receivedBytes,
      cached: true
    });

    return arrayBuffer;
  }

  private async validateHash(buffer: ArrayBuffer, expectedHash: string): Promise<boolean> {
    try {
      const hashBuffer = await crypto.subtle.digest('SHA-256', buffer);
      const hashArray = Array.from(new Uint8Array(hashBuffer));
      const actualHash = hashArray.map(b => b.toString(16).padStart(2, '0')).join('');

      const valid = actualHash === expectedHash;
      if (!valid) {
        logger.warn('Hash validation failed', 'ModelRegistry', {
          expected: expectedHash,
          actual: actualHash
        });
      }

      return valid;
    } catch (error) {
      logger.error('Failed to validate hash', 'ModelRegistry', { error });
      return false;
    }
  }

  async loadModel(
    modelId: string,
    runtime: 'onnx' | 'tfjs',
    options?: ModelLoadOptions
  ): Promise<Result<any, Error>> {
    try {
      const downloadResult = await this.downloadModel(modelId, options);
      if (!downloadResult.success) {
        return downloadResult;
      }

      const buffer = downloadResult.value;

      switch (runtime) {
        case 'onnx': {
          try {
            // Use eval to avoid TypeScript checking the import
            const importOnnx = new Function('return import("onnxruntime-web")');
            const ort = await importOnnx();
            const session = await ort.InferenceSession.create(buffer);
            return Result.ok(session);
          } catch (error) {
            return Result.err(new Error('ONNX runtime not available. Install onnxruntime-web package.'));
          }
        }

        case 'tfjs': {
          try {
            // Use eval to avoid TypeScript checking the import
            const importTf = new Function('return import("@tensorflow/tfjs")');
            const tf = await importTf();
            // For TensorFlow.js, we need to convert ArrayBuffer to a model
            // This is a simplified example - actual implementation would depend on model format
            const model = await tf.loadLayersModel(tf.io.browserHTTPRequest('', {
              fetch: async () => new Response(buffer)
            }));
            return Result.ok(model);
          } catch (error) {
            return Result.err(new Error('TensorFlow.js not available. Install @tensorflow/tfjs package.'));
          }
        }

        default:
          return Result.err(new Error(`Unsupported runtime: ${runtime}`));
      }
    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error));
      logger.error(`Failed to load model ${modelId}: ${err.message}`, 'ModelRegistry');
      return Result.err(err);
    }
  }

  async clearCache(modelId?: string): Promise<void> {
    if (modelId) {
      await this.cache.delete(modelId);
      logger.info(`Cleared cache for model ${modelId}`, 'ModelRegistry');
    } else {
      await this.cache.clear();
      logger.info('Cleared all model cache', 'ModelRegistry');
    }
  }

  async getCacheSize(): Promise<number> {
    return this.cache.getSize();
  }

  async getCachedModels(): Promise<string[]> {
    return this.cache.getKeys();
  }
}
