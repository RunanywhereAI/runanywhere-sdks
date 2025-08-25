/**
 * Transformers.js Model Service
 * Bridges RunAnywhere model management with transformers.js
 * Inspired by iOS WhisperKitDownloadStrategy patterns
 */

import type { ModelInfo, TranscriptionResult } from '@runanywhere/core';
import { Result, logger } from '@runanywhere/core';

export interface TransformersModelConfig {
  model_id: string;
  dtype?: {
    encoder_model?: string;
    decoder_model_merged?: string;
  };
  device?: 'wasm' | 'webgpu' | 'cpu';
  cache_dir?: string;
  local_files_only?: boolean;
  revision?: string;
}

export interface ModelLoadingProgress {
  status: 'initiate' | 'progress' | 'done' | 'ready' | 'loading' | 'error';
  name?: string;
  file?: string;
  progress?: number;
  loaded?: number;
  total?: number;
  message?: string;
}

export interface TransformersModelInstance {
  tokenizer: any;
  processor: any;
  model: any;
  modelId: string;
  isLoaded: boolean;
}

/**
 * Manages transformers.js model loading with progress tracking
 * Follows iOS SDK patterns for model lifecycle management
 */
export class TransformersModelService {
  private static instance: TransformersModelService;
  private loadedModels = new Map<string, TransformersModelInstance>();
  private loadingPromises = new Map<string, Promise<TransformersModelInstance>>();
  private progressHandlers = new Map<string, Array<(progress: ModelLoadingProgress) => void>>();

  private constructor() {}

  static getInstance(): TransformersModelService {
    if (!TransformersModelService.instance) {
      TransformersModelService.instance = new TransformersModelService();
    }
    return TransformersModelService.instance;
  }

  /**
   * Load a model with progress tracking
   * Similar to iOS ModelRegistry.loadModel patterns
   */
  async loadModel(
    config: TransformersModelConfig,
    onProgress?: (progress: ModelLoadingProgress) => void
  ): Promise<Result<TransformersModelInstance, Error>> {
    const { model_id } = config;

    try {
      // Check if already loaded
      const existing = this.loadedModels.get(model_id);
      if (existing?.isLoaded) {
        logger.info(`Model ${model_id} already loaded`, 'TransformersModelService');
        onProgress?.({
          status: 'ready',
          name: model_id,
          progress: 100,
          message: 'Model already loaded'
        });
        return Result.ok(existing);
      }

      // Check if already loading
      const existingPromise = this.loadingPromises.get(model_id);
      if (existingPromise) {
        logger.debug(`Model ${model_id} already loading, waiting...`, 'TransformersModelService');
        if (onProgress) {
          this.addProgressHandler(model_id, onProgress);
        }
        const instance = await existingPromise;
        return Result.ok(instance);
      }

      // Start new loading process
      logger.info(`Loading model ${model_id}`, 'TransformersModelService');

      if (onProgress) {
        this.addProgressHandler(model_id, onProgress);
      }

      const loadPromise = this.performModelLoad(config);
      this.loadingPromises.set(model_id, loadPromise);

      try {
        const instance = await loadPromise;
        this.loadedModels.set(model_id, instance);

        // Notify completion
        this.notifyProgress(model_id, {
          status: 'ready',
          name: model_id,
          progress: 100,
          message: 'Model loaded successfully'
        });

        return Result.ok(instance);
      } finally {
        this.loadingPromises.delete(model_id);
        this.progressHandlers.delete(model_id);
      }

    } catch (error) {
      logger.error(`Failed to load model ${model_id}`, 'TransformersModelService', { error });

      this.notifyProgress(model_id, {
        status: 'error',
        name: model_id,
        message: `Failed to load model: ${error}`
      });

      return Result.err(error instanceof Error ? error : new Error(String(error)));
    }
  }

  /**
   * Perform the actual model loading with transformers.js
   * Follows the singleton pattern from transformers.js examples
   */
  private async performModelLoad(config: TransformersModelConfig): Promise<TransformersModelInstance> {
    const { model_id, dtype, device = 'wasm' } = config;

    // Notify start
    this.notifyProgress(model_id, {
      status: 'initiate',
      name: model_id,
      progress: 0,
      message: 'Initializing model loading...'
    });

    // Dynamic import to avoid bundle issues
    const { AutoTokenizer, AutoProcessor, WhisperForConditionalGeneration } = await import('@huggingface/transformers');

    // Create progress callback
    const progressCallback = (data: any) => {
      this.notifyProgress(model_id, {
        status: data.status || 'progress',
        name: model_id,
        file: data.file,
        progress: data.progress,
        loaded: data.loaded,
        total: data.total,
        message: data.file ? `Loading ${data.file}...` : 'Loading model files...'
      });
    };

    this.notifyProgress(model_id, {
      status: 'loading',
      name: model_id,
      progress: 10,
      message: 'Loading tokenizer...'
    });

    // Load components in parallel with progress tracking
    const [tokenizer, processor, model] = await Promise.all([
      AutoTokenizer.from_pretrained(model_id, {
        progress_callback: progressCallback,
      }),
      AutoProcessor.from_pretrained(model_id, {
        progress_callback: progressCallback,
      }),
      WhisperForConditionalGeneration.from_pretrained(model_id, {
        dtype: dtype as any || {
          encoder_model: 'fp32',
          decoder_model_merged: 'q4',
        },
        device: device as any,
        progress_callback: progressCallback,
      })
    ]);

    this.notifyProgress(model_id, {
      status: 'loading',
      name: model_id,
      progress: 95,
      message: 'Warming up model...'
    });

    // Warm up the model with a dummy input (following transformers.js patterns)
    const dummyInput = new Float32Array(16000).fill(0);
    const inputs = await processor(dummyInput);
    await model.generate({
      ...inputs,
      max_new_tokens: 1,
    });

    logger.info(`Model ${model_id} loaded successfully`, 'TransformersModelService');

    return {
      tokenizer,
      processor,
      model,
      modelId: model_id,
      isLoaded: true
    };
  }

  /**
   * Transcribe audio using a loaded model
   */
  async transcribe(
    modelId: string,
    audio: Float32Array,
    options?: {
      language?: string;
      task?: 'transcribe' | 'translate';
      return_timestamps?: boolean;
    }
  ): Promise<Result<TranscriptionResult, Error>> {
    try {
      const modelInstance = this.loadedModels.get(modelId);
      if (!modelInstance?.isLoaded) {
        return Result.err(new Error(`Model ${modelId} not loaded`));
      }

      const { tokenizer, processor, model } = modelInstance;

      // Process audio input
      const inputs = await processor(audio);

      // Generate transcription
      const generated_ids = await model.generate({
        ...inputs,
        max_new_tokens: 448,
        language: options?.language,
        task: options?.task || 'transcribe',
        return_timestamps: options?.return_timestamps || false,
      });

      // Decode the result
      const transcription = tokenizer.batch_decode(generated_ids, {
        skip_special_tokens: true
      });

      const result: TranscriptionResult = {
        text: transcription[0] || '',
        language: options?.language || 'en',
        confidence: 0.95, // Whisper doesn't provide confidence scores
      };

      return Result.ok(result);

    } catch (error) {
      logger.error(`Transcription failed for model ${modelId}`, 'TransformersModelService', { error });
      return Result.err(error instanceof Error ? error : new Error(String(error)));
    }
  }

  /**
   * Check if a model is loaded
   */
  isModelLoaded(modelId: string): boolean {
    const instance = this.loadedModels.get(modelId);
    return instance?.isLoaded || false;
  }

  /**
   * Get loaded model instance
   */
  getLoadedModel(modelId: string): TransformersModelInstance | null {
    return this.loadedModels.get(modelId) || null;
  }

  /**
   * Unload a model and free resources
   */
  async unloadModel(modelId: string): Promise<void> {
    const instance = this.loadedModels.get(modelId);
    if (instance) {
      try {
        // Dispose of the model if it has a dispose method
        if (instance.model && typeof instance.model.dispose === 'function') {
          await instance.model.dispose();
        }

        this.loadedModels.delete(modelId);
        logger.info(`Model ${modelId} unloaded`, 'TransformersModelService');
      } catch (error) {
        logger.error(`Failed to unload model ${modelId}`, 'TransformersModelService', { error });
      }
    }
  }

  /**
   * Get all loaded models
   */
  getLoadedModels(): string[] {
    return Array.from(this.loadedModels.keys()).filter(id =>
      this.loadedModels.get(id)?.isLoaded
    );
  }

  /**
   * Clear all loaded models
   */
  async clearAll(): Promise<void> {
    const modelIds = Array.from(this.loadedModels.keys());
    await Promise.all(modelIds.map(id => this.unloadModel(id)));

    // Clear any pending loads
    this.loadingPromises.clear();
    this.progressHandlers.clear();

    logger.info('All models cleared', 'TransformersModelService');
  }

  private addProgressHandler(modelId: string, handler: (progress: ModelLoadingProgress) => void): void {
    if (!this.progressHandlers.has(modelId)) {
      this.progressHandlers.set(modelId, []);
    }
    this.progressHandlers.get(modelId)!.push(handler);
  }

  private notifyProgress(modelId: string, progress: ModelLoadingProgress): void {
    const handlers = this.progressHandlers.get(modelId) || [];
    handlers.forEach(handler => {
      try {
        handler(progress);
      } catch (error) {
        logger.error('Progress handler error', 'TransformersModelService', { error });
      }
    });
  }

  /**
   * Get memory usage information
   */
  getMemoryInfo(): {
    loadedModels: number;
    modelIds: string[];
  } {
    return {
      loadedModels: this.loadedModels.size,
      modelIds: Array.from(this.loadedModels.keys())
    };
  }
}
