/**
 * @runanywhere/llamacpp - LlamaCPP Module
 *
 * LlamaCPP module wrapper for RunAnywhere React Native SDK.
 * Provides public API for module registration and model declaration.
 *
 * This mirrors the Swift SDK's LlamaCPP module pattern:
 * - LlamaCPP.register() - Register the module with ServiceRegistry
 * - LlamaCPP.addModel() - Declare a model for this module
 *
 * Reference: sdk/runanywhere-swift/Sources/LlamaCPPRuntime/LlamaCPPServiceProvider.swift
 */

import { LlamaCppProvider } from './LlamaCppProvider';
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

// SDKLogger instance for this module
const log = new SDKLogger('LLM.LlamaCpp');

/**
 * Model registration options for LlamaCPP models
 *
 * Matches iOS: LlamaCPP.addModel() parameter structure
 */
export interface LlamaCPPModelOptions {
  /** Unique model ID. If not provided, generated from URL filename */
  id?: string;
  /** Display name for the model */
  name: string;
  /** Download URL for the model */
  url: string;
  /** Model category (defaults to Language for LLM models) */
  modality?: ModelCategory;
  /** Memory requirement in bytes */
  memoryRequirement?: number;
  /** Whether model supports reasoning/thinking tokens */
  supportsThinking?: boolean;
}

/**
 * VLM model registration options for LlamaCPP VLM models
 *
 * Matches iOS: LlamaCPP.addVLMModel() parameter structure
 */
export interface LlamaCPPVLMModelOptions {
  /** Unique model ID */
  id?: string;
  /** Display name */
  name: string;
  /** Download URL for main model */
  url: string;
  /** Download URL for mmproj vision projector (optional - auto-detected if in same directory) */
  mmprojUrl?: string;
  /** Memory requirement in bytes */
  memoryRequirement?: number;
}

/**
 * LlamaCPP Module
 *
 * Public API for registering LlamaCPP module and declaring GGUF models.
 * This provides the same developer experience as the iOS SDK.
 *
 * ## Usage
 *
 * ```typescript
 * import { LlamaCPP } from '@runanywhere/llamacpp';
 *
 * // Register module
 * LlamaCPP.register();
 *
 * // Add models
 * LlamaCPP.addModel({
 *   id: 'smollm2-360m-q8_0',
 *   name: 'SmolLM2 360M Q8_0',
 *   url: 'https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf',
 *   memoryRequirement: 500_000_000
 * });
 * ```
 *
 * Matches iOS: public enum LlamaCPP: RunAnywhereModule
 */
export const LlamaCPP = {
  /**
   * Module metadata
   * Matches iOS: static let moduleId, moduleName, inferenceFramework
   */
  moduleId: 'llamacpp',
  moduleName: 'LlamaCPP',
  inferenceFramework: LLMFramework.LlamaCpp,
  capabilities: ['llm', 'vlm'] as const,
  defaultPriority: 100,

  /**
   * Register LlamaCPP module with the SDK
   *
   * This registers the LlamaCPP provider with ServiceRegistry,
   * enabling it to handle GGUF models.
   *
   * Matches iOS: static func register(priority: Int = defaultPriority)
   *
   * @example
   * ```typescript
   * LlamaCPP.register();
   * ```
   */
  register(): void {
    log.debug('Registering LlamaCPP module');
    LlamaCppProvider.register();
    log.info('LlamaCPP module registered');
  },

  /**
   * Add a model to this module
   *
   * Registers a GGUF model with the ModelRegistry.
   * The model will use LlamaCPP framework automatically.
   *
   * Matches iOS: static func addModel(id:name:url:modality:memoryRequirement:supportsThinking:)
   *
   * @param options - Model registration options
   * @returns Promise resolving to the created ModelInfo
   *
   * @example
   * ```typescript
   * await LlamaCPP.addModel({
   *   id: 'llama-2-7b-chat-q4_k_m',
   *   name: 'Llama 2 7B Chat Q4_K_M',
   *   url: 'https://huggingface.co/TheBloke/Llama-2-7B-Chat-GGUF/resolve/main/llama-2-7b-chat.Q4_K_M.gguf',
   *   memoryRequirement: 4_000_000_000
   * });
   * ```
   */
  async addModel(options: LlamaCPPModelOptions): Promise<ModelInfo> {
    // Generate stable ID from URL if not provided
    const modelId = options.id ?? this._generateModelId(options.url);

    // Determine modality (default to Language for LLM)
    const category = options.modality ?? ModelCategory.Language;

    // Infer format from URL
    const format = options.url.toLowerCase().includes('.gguf')
      ? ModelFormat.GGUF
      : ModelFormat.GGML;

    const now = new Date().toISOString();

    // Check if model already exists on disk (persistence across sessions)
    let isDownloaded = false;
    let localPath: string | undefined;

    if (FileSystem.isAvailable()) {
      try {
        const exists = await FileSystem.modelExists(modelId, 'LlamaCpp');
        if (exists) {
          localPath = await FileSystem.getModelPath(modelId, 'LlamaCpp');
          isDownloaded = true;
          log.debug(`Model ${modelId} found on disk: ${localPath}`);
        }
      } catch (error) {
        // Ignore errors checking for existing model
        log.debug(`Could not check for existing model ${modelId}: ${error}`);
      }
    }

    const modelInfo: ModelInfo = {
      id: modelId,
      name: options.name,
      category,
      format,
      downloadURL: options.url,
      localPath,
      downloadSize: undefined,
      memoryRequired: options.memoryRequirement,
      compatibleFrameworks: [LLMFramework.LlamaCpp],
      preferredFramework: LLMFramework.LlamaCpp,
      supportsThinking: options.supportsThinking ?? false,
      metadata: { tags: [] },
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

    log.info(`Added model: ${modelId} (${options.name})`, {
      modelId,
      isDownloaded,
    });

    return modelInfo;
  },

  /**
   * Add a VLM model to this module
   *
   * Registers a VLM GGUF model with the ModelRegistry.
   * The model will use LlamaCPP framework automatically.
   *
   * Matches iOS: static func addVLMModel(id:name:url:mmprojUrl:memoryRequirement:)
   *
   * @param options - VLM model registration options
   * @returns Promise resolving to the created ModelInfo
   *
   * @example
   * ```typescript
   * await LlamaCPP.addVLMModel({
   *   id: 'llava-1.5-7b-q4_k_m',
   *   name: 'LLaVA 1.5 7B Q4_K_M',
   *   url: 'https://huggingface.co/mys/ggml_llava-v1.5-7b/resolve/main/ggml-model-q4_k.gguf',
   *   mmprojUrl: 'https://huggingface.co/mys/ggml_llava-v1.5-7b/resolve/main/mmproj-model-f16.gguf',
   *   memoryRequirement: 5_000_000_000
   * });
   * ```
   */
  async addVLMModel(options: LlamaCPPVLMModelOptions): Promise<ModelInfo> {
    // Generate stable ID from URL if not provided
    const modelId = options.id ?? this._generateModelId(options.url);

    // VLM models are Multimodal category (matches iOS: modality: .multimodal)
    const category = ModelCategory.Multimodal;

    // Infer format from URL
    const format = options.url.toLowerCase().includes('.gguf')
      ? ModelFormat.GGUF
      : ModelFormat.GGML;

    const now = new Date().toISOString();

    // Check if model already exists on disk (persistence across sessions)
    let isDownloaded = false;
    let localPath: string | undefined;

    if (FileSystem.isAvailable()) {
      try {
        const exists = await FileSystem.modelExists(modelId, 'LlamaCpp');
        if (exists) {
          localPath = await FileSystem.getModelPath(modelId, 'LlamaCpp');
          isDownloaded = true;
          log.debug(`VLM model ${modelId} found on disk: ${localPath}`);
        }
      } catch (error) {
        // Ignore errors checking for existing model
        log.debug(`Could not check for existing VLM model ${modelId}: ${error}`);
      }
    }

    const modelInfo: ModelInfo = {
      id: modelId,
      name: options.name,
      category,
      format,
      downloadURL: options.url,
      localPath,
      downloadSize: undefined,
      memoryRequired: options.memoryRequirement,
      compatibleFrameworks: [LLMFramework.LlamaCpp],
      preferredFramework: LLMFramework.LlamaCpp,
      supportsThinking: false,
      metadata: {
        tags: [],
        mmprojUrl: options.mmprojUrl,  // Store mmproj URL in metadata for download
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

    log.info(`Added VLM model: ${modelId} (${options.name})`, {
      modelId,
      isDownloaded,
      hasMmproj: !!options.mmprojUrl,
    });

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
      // Remove common extensions
      return filename.replace(/\.(gguf|ggml|bin)$/i, '');
    } catch {
      // Fallback for invalid URLs
      return `model-${Date.now()}`;
    }
  },
};
