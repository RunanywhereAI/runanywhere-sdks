/**
 * ONNX.ts
 *
 * ONNX Runtime module wrapper for RunAnywhere React Native SDK.
 * Provides public API for module registration and model declaration.
 *
 * This mirrors the Swift SDK's ONNX module pattern:
 * - ONNX.register() - Register the module with ServiceRegistry
 * - ONNX.addModel() - Declare a model for this module
 *
 * Reference: sdk/runanywhere-swift/Sources/ONNXRuntime/ONNXServiceProvider.swift
 *           sdk/runanywhere-swift/Sources/RunAnywhere/Core/Module/RunAnywhereModule.swift
 */

import { registerONNXProviders } from '../Providers/ONNXProvider';
import { ModelRegistry } from '../services/ModelRegistry';
import {
  LLMFramework,
  ModelCategory,
  ModelFormat,
  ConfigurationSource,
} from '../types/enums';
import type { ModelInfo } from '../types/models';
import { SDKLogger } from '../Foundation/Logging/Logger/SDKLogger';

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
 * import { ONNX, ModelCategory } from 'runanywhere-react-native';
 *
 * // Register module
 * ONNX.register();
 *
 * // Add STT model
 * ONNX.addModel({
 *   id: 'sherpa-onnx-whisper-tiny.en',
 *   name: 'Sherpa Whisper Tiny (ONNX)',
 *   url: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-tiny.en.tar.gz',
 *   modality: ModelCategory.SpeechRecognition,
 *   artifactType: ModelArtifactType.TarGzArchive,
 *   memoryRequirement: 75_000_000
 * });
 *
 * // Add TTS model
 * ONNX.addModel({
 *   id: 'vits-piper-en_US-lessac-medium',
 *   name: 'Piper TTS (US English - Medium)',
 *   url: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_US-lessac-medium.tar.gz',
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
    registerONNXProviders();
    logger.info('✅ ONNX module registered (STT + TTS)');
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
   * @returns The created ModelInfo
   *
   * @example
   * ```typescript
   * // STT Model
   * ONNX.addModel({
   *   id: 'sherpa-onnx-whisper-small.en',
   *   name: 'Sherpa Whisper Small (ONNX)',
   *   url: 'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-small.en.tar.bz2',
   *   modality: ModelCategory.SpeechRecognition,
   *   artifactType: ModelArtifactType.TarBz2Archive,
   *   memoryRequirement: 250_000_000
   * });
   *
   * // TTS Model
   * ONNX.addModel({
   *   id: 'vits-piper-en_GB-alba-medium',
   *   name: 'Piper TTS (British English)',
   *   url: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_GB-alba-medium.tar.gz',
   *   modality: ModelCategory.SpeechSynthesis,
   *   memoryRequirement: 65_000_000
   * });
   * ```
   */
  addModel(options: ONNXModelOptions): ModelInfo {
    // Generate stable ID from URL if not provided
    const modelId = options.id ?? this._generateModelId(options.url);

    // Infer artifact type from URL if not specified
    const artifactType =
      options.artifactType ?? this._inferArtifactType(options.url);

    // Format is always ONNX for this module
    const format = ModelFormat.ONNX;

    const now = new Date().toISOString();

    const modelInfo: ModelInfo = {
      id: modelId,
      name: options.name,
      category: options.modality,
      format,
      downloadURL: options.url,
      localPath: undefined,
      downloadSize: undefined,
      memoryRequired: options.memoryRequirement,
      compatibleFrameworks: [LLMFramework.ONNX],
      preferredFramework: LLMFramework.ONNX,
      supportsThinking: false, // ONNX STT/TTS models don't support thinking
      metadata: {
        tags: [],
        // artifactType stored separately, not in metadata
      },
      source: ConfigurationSource.Local,
      createdAt: now,
      updatedAt: now,
      syncPending: false,
      usageCount: 0,
      isDownloaded: false,
      isAvailable: true,
    };

    // Register with ModelRegistry (synchronous - queues async registration)
    ModelRegistry.registerModel(modelInfo);

    logger.info(`Added model: ${modelId} (${options.name})`);

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
