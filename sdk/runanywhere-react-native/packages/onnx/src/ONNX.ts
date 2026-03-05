/**
 * @runanywhere/onnx - ONNX Runtime Module
 *
 * ONNX Runtime module wrapper for RunAnywhere React Native SDK.
 * Provides public API for module registration and model declaration.
 *
 * This mirrors the Swift SDK's ONNX module pattern:
 * - ONNX.register() - Register the module with ServiceRegistry
 * - ONNX.addModel() - Declare a model for this module
 *
 * Reference: sdk/runanywhere-swift/Sources/ONNXRuntime/ONNXServiceProvider.swift
 */

import { ONNXProvider } from './ONNXProvider';
import {
  ModelRegistry,
  FileSystem,
  LLMFramework,
  ModelCategory,
  ModelFormat,
  ConfigurationSource,
  SDKLogger,
  type ModelInfo,
} from '@runanywhere/core';

// Use SDKLogger with ONNX category
const logger = new SDKLogger('ONNX');

/**
 * Model artifact type for ONNX models
 *
 * Matches iOS: ModelArtifactType enum
 */
export enum ModelArtifactType {
  /** Single file model */
  SingleFile = 'singleFile',
  /** Tar.gz archive with nested directory structure */
  TarGzArchive = 'tarGzArchive',
  /** Tar.bz2 archive with nested directory structure */
  TarBz2Archive = 'tarBz2Archive',
  /** ZIP archive */
  ZipArchive = 'zipArchive',
}

/**
 * Model registration options for ONNX models
 *
 * Matches iOS: ONNX.addModel() parameter structure
 */
export interface ONNXModelOptions {
  /** Unique model ID. If not provided, generated from URL filename */
  id?: string;
  /** Display name for the model */
  name: string;
  /** Download URL for the model */
  url: string;
  /** Model category (STT or TTS) */
  modality: ModelCategory;
  /** How the model is packaged (inferred from URL if not specified) */
  artifactType?: ModelArtifactType;
  /** Memory requirement in bytes */
  memoryRequirement?: number;
}

/**
 * ONNX Runtime Module
 *
 * Public API for registering ONNX module and declaring STT/TTS models.
 * This provides the same developer experience as the iOS SDK.
 *
 * ## Usage
 *
 * ```typescript
 * import { ONNX, ModelArtifactType } from '@runanywhere/onnx';
 * import { ModelCategory } from '@runanywhere/core';
 *
 * // Register module
 * ONNX.register();
 *
 * // Add STT model
 * ONNX.addModel({
 *   id: 'sherpa-onnx-whisper-tiny.en',
 *   name: 'Sherpa Whisper Tiny (ONNX)',
 *   url: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/.../sherpa-onnx-whisper-tiny.en.tar.gz',
 *   modality: ModelCategory.SpeechRecognition,
 *   artifactType: ModelArtifactType.TarGzArchive,
 *   memoryRequirement: 75_000_000
 * });
 *
 * // Add TTS model
 * ONNX.addModel({
 *   id: 'vits-piper-en_US-lessac-medium',
 *   name: 'Piper TTS (US English - Medium)',
 *   url: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/.../vits-piper-en_US-lessac-medium.tar.gz',
 *   modality: ModelCategory.SpeechSynthesis,
 *   memoryRequirement: 65_000_000
 * });
 * ```
 *
 * Matches iOS: public enum ONNX: RunAnywhereModule
 */
export const ONNX = {
  /**
   * Module metadata
   * Matches iOS: static let moduleId, moduleName, inferenceFramework
   */
  moduleId: 'onnx',
  moduleName: 'ONNX Runtime',
  inferenceFramework: LLMFramework.ONNX,
  capabilities: ['stt', 'tts'] as const,
  defaultPriority: 100,

  /**
   * Register ONNX module with the SDK
   *
   * This registers both ONNX STT and TTS providers with ServiceRegistry,
   * enabling them to handle Sherpa-ONNX and Piper models.
   *
   * Matches iOS: static func register(priority: Int = defaultPriority)
   *
   * @example
   * ```typescript
   * ONNX.register();
   * ```
   */
  register(): void {
    logger.info('Registering ONNX module (STT + TTS)');
    ONNXProvider.register();
    logger.info('ONNX module registered (STT + TTS)');
  },

  /**
   * Add a model to this module
   *
   * Registers an ONNX model (STT or TTS) with the ModelRegistry.
   * The model will use ONNX framework automatically.
   *
   * Matches iOS: static func addModel(id:name:url:modality:artifactType:memoryRequirement:)
   *
   * @param options - Model registration options
   * @returns Promise resolving to the created ModelInfo
   *
   * @example
   * ```typescript
   * // STT Model
   * await ONNX.addModel({
   *   id: 'sherpa-onnx-whisper-small.en',
   *   name: 'Sherpa Whisper Small (ONNX)',
   *   url: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-small.en.tar.gz',
   *   modality: ModelCategory.SpeechRecognition,
   *   artifactType: ModelArtifactType.TarGzArchive,
   *   memoryRequirement: 250_000_000
   * });
   * ```
   */
  async addModel(options: ONNXModelOptions): Promise<ModelInfo> {
    // Generate stable ID from URL if not provided
    const modelId = options.id ?? this._generateModelId(options.url);

    // Format is always ONNX for this module
    const format = ModelFormat.ONNX;

    const now = new Date().toISOString();

    // Check if model already exists on disk (persistence across sessions)
    let isDownloaded = false;
    let localPath: string | undefined;

    if (FileSystem.isAvailable()) {
      try {
        const exists = await FileSystem.modelExists(modelId, 'ONNX');
        if (exists) {
          localPath = await FileSystem.getModelPath(modelId, 'ONNX');
          isDownloaded = true;
          logger.info(`Model ${modelId} found on disk: ${localPath}`);
        }
      } catch (error) {
        // Ignore errors checking for existing model
        logger.debug(`Could not check for existing model ${modelId}: ${error}`);
      }
    }

    const modelInfo: ModelInfo = {
      id: modelId,
      name: options.name,
      category: options.modality,
      format,
      downloadURL: options.url,
      localPath,
      downloadSize: undefined,
      memoryRequired: options.memoryRequirement,
      compatibleFrameworks: [LLMFramework.ONNX],
      preferredFramework: LLMFramework.ONNX,
      supportsThinking: false, // ONNX STT/TTS models don't support thinking
      metadata: {
        tags: [],
      },
      source: ConfigurationSource.Local,
      createdAt: now,
      updatedAt: now,
      syncPending: false,
      usageCount: 0,
      isDownloaded,
      isAvailable: true,
    };

    // Register with ModelRegistry and wait for completion
    await ModelRegistry.registerModel(modelInfo);

    logger.info(`Added model: ${modelId} (${options.name})${isDownloaded ? ' [already downloaded]' : ''}`);

    return modelInfo;
  },

  /**
   * Generate a stable model ID from URL
   * @internal
   */
  _generateModelId(url: string): string {
    try {
      const urlObj = new URL(url);
      const pathname = urlObj.pathname;
      const filename = pathname.split('/').pop() ?? 'model';
      // Remove common archive extensions
      return filename.replace(/\.(tar\.gz|tar\.bz2|zip|onnx)$/i, '');
    } catch {
      // Fallback for invalid URLs
      return `model-${Date.now()}`;
    }
  },

  /**
   * Infer artifact type from URL
   * @internal
   */
  _inferArtifactType(url: string): ModelArtifactType {
    const lowercased = url.toLowerCase();

    if (lowercased.includes('.tar.gz')) {
      return ModelArtifactType.TarGzArchive;
    } else if (lowercased.includes('.tar.bz2')) {
      return ModelArtifactType.TarBz2Archive;
    } else if (lowercased.includes('.zip')) {
      return ModelArtifactType.ZipArchive;
    }

    // Default to single file
    return ModelArtifactType.SingleFile;
  },
};
