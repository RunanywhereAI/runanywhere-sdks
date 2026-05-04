/**
 * Model Registry for RunAnywhere React Native SDK
 *
 * Thin wrapper over native model registry.
 * All logic (caching, filtering, discovery) is in native commons.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+ModelRegistry.swift
 */

import {
  InferenceFramework,
  ModelInfo as ProtoModelInfoCodec,
  ModelInfoList as ProtoModelInfoListCodec,
  ModelQuery as ProtoModelQueryCodec,
  ModelSource,
} from '@runanywhere/proto-ts/model_types';
import type {
  ModelInfo as ProtoModelInfo,
  ModelQuery as ProtoModelQuery,
} from '@runanywhere/proto-ts/model_types';
import { requireNativeModule, isNativeModuleAvailable } from '../native';
import {
  ConfigurationSource,
  LLMFramework,
  ModelCategory,
  ModelFormat,
} from '../types';
import type { ModelInfo, ModelCompatibilityResult } from '../types';
import { SDKLogger } from '../Foundation/Logging/Logger/SDKLogger';
import { arrayBufferToBytes, bytesToArrayBuffer } from './ProtoBytes';

const logger = new SDKLogger('ModelRegistry');

type RegistryModelInfo = ModelInfo & {
  framework?: InferenceFramework;
  downloadUrl?: string;
  downloadSizeBytes?: number;
  supportsLora?: boolean;
  description?: string;
  createdAtUnixMs?: number;
  updatedAtUnixMs?: number;
};

const frameworkToProto: Record<LLMFramework, InferenceFramework> = {
  [LLMFramework.CoreML]: InferenceFramework.INFERENCE_FRAMEWORK_COREML,
  [LLMFramework.TensorFlowLite]: InferenceFramework.INFERENCE_FRAMEWORK_TFLITE,
  [LLMFramework.MLX]: InferenceFramework.INFERENCE_FRAMEWORK_MLX,
  [LLMFramework.SwiftTransformers]: InferenceFramework.INFERENCE_FRAMEWORK_SWIFT_TRANSFORMERS,
  [LLMFramework.ONNX]: InferenceFramework.INFERENCE_FRAMEWORK_ONNX,
  [LLMFramework.Sherpa]: InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
  [LLMFramework.ExecuTorch]: InferenceFramework.INFERENCE_FRAMEWORK_EXECUTORCH,
  [LLMFramework.LlamaCpp]: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
  [LLMFramework.FoundationModels]: InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS,
  [LLMFramework.PicoLLM]: InferenceFramework.INFERENCE_FRAMEWORK_PICO_LLM,
  [LLMFramework.MLC]: InferenceFramework.INFERENCE_FRAMEWORK_MLC,
  [LLMFramework.MediaPipe]: InferenceFramework.INFERENCE_FRAMEWORK_MEDIAPIPE,
  [LLMFramework.WhisperKit]: InferenceFramework.INFERENCE_FRAMEWORK_WHISPERKIT,
  [LLMFramework.OpenAIWhisper]: InferenceFramework.INFERENCE_FRAMEWORK_OPENAI_WHISPER,
  [LLMFramework.SystemTTS]: InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS,
  [LLMFramework.PiperTTS]: InferenceFramework.INFERENCE_FRAMEWORK_PIPER_TTS,
  [LLMFramework.Genie]: InferenceFramework.INFERENCE_FRAMEWORK_GENIE,
};

const protoToFramework = new Map<InferenceFramework, LLMFramework>(
  Object.entries(frameworkToProto).map(([framework, proto]) => [
    proto,
    framework as LLMFramework,
  ])
);

function decodeModelInfoList(bytes: Uint8Array): ProtoModelInfo[] {
  if (bytes.byteLength === 0) return [];
  return ProtoModelInfoListCodec.decode(bytes).models;
}

function protoFrameworkToLegacy(
  framework: InferenceFramework
): LLMFramework | undefined {
  return protoToFramework.get(framework);
}

function legacyFrameworkToProto(
  framework: LLMFramework | undefined
): InferenceFramework {
  if (!framework) return InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED;
  return frameworkToProto[framework] ?? InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED;
}

function legacySourceToProto(
  source: ModelInfo['source'] | ModelSource | undefined,
  downloadUrl: string
): ModelSource {
  if (typeof source === 'number') return source;
  if (source === ConfigurationSource.Remote) return ModelSource.MODEL_SOURCE_REMOTE;
  if (source === ConfigurationSource.Local) return ModelSource.MODEL_SOURCE_LOCAL;
  return downloadUrl ? ModelSource.MODEL_SOURCE_REMOTE : ModelSource.MODEL_SOURCE_LOCAL;
}

function protoSourceToLegacy(source: ModelSource): ConfigurationSource {
  if (source === ModelSource.MODEL_SOURCE_REMOTE) return ConfigurationSource.Remote;
  if (source === ModelSource.MODEL_SOURCE_LOCAL) return ConfigurationSource.Local;
  return ConfigurationSource.Local;
}

function unixMsToIso(unixMs: number): string {
  if (!Number.isFinite(unixMs) || unixMs <= 0) {
    return new Date(0).toISOString();
  }
  return new Date(unixMs).toISOString();
}

function isoToUnixMs(value: string | undefined, fallback = 0): number {
  if (!value) return fallback;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function normalizeCategory(category: unknown): ModelCategory {
  if (typeof category === 'number') return category as ModelCategory;
  if (typeof category !== 'string') return ModelCategory.MODEL_CATEGORY_UNSPECIFIED;

  switch (category.toLowerCase()) {
    case 'language':
      return ModelCategory.MODEL_CATEGORY_LANGUAGE;
    case 'speech-recognition':
    case 'speech_recognition':
      return ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION;
    case 'speech-synthesis':
    case 'speech_synthesis':
      return ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS;
    case 'vision':
      return ModelCategory.MODEL_CATEGORY_VISION;
    case 'image-generation':
    case 'image_generation':
      return ModelCategory.MODEL_CATEGORY_IMAGE_GENERATION;
    case 'multimodal':
      return ModelCategory.MODEL_CATEGORY_MULTIMODAL;
    case 'audio':
      return ModelCategory.MODEL_CATEGORY_AUDIO;
    case 'embedding':
      return ModelCategory.MODEL_CATEGORY_EMBEDDING;
    case 'voice-activity-detection':
    case 'voice_activity_detection':
      return ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION;
    default:
      return ModelCategory.MODEL_CATEGORY_UNSPECIFIED;
  }
}

function normalizeFormat(format: unknown): ModelFormat {
  if (typeof format === 'number') return format as ModelFormat;
  if (typeof format !== 'string') return ModelFormat.MODEL_FORMAT_UNSPECIFIED;

  switch (format.toLowerCase()) {
    case 'gguf':
      return ModelFormat.MODEL_FORMAT_GGUF;
    case 'ggml':
      return ModelFormat.MODEL_FORMAT_GGML;
    case 'onnx':
      return ModelFormat.MODEL_FORMAT_ONNX;
    case 'ort':
      return ModelFormat.MODEL_FORMAT_ORT;
    case 'bin':
      return ModelFormat.MODEL_FORMAT_BIN;
    case 'zip':
      return ModelFormat.MODEL_FORMAT_ZIP;
    case 'folder':
      return ModelFormat.MODEL_FORMAT_FOLDER;
    case 'system':
    case 'proprietary':
      return ModelFormat.MODEL_FORMAT_PROPRIETARY;
    default:
      return ModelFormat.MODEL_FORMAT_UNSPECIFIED;
  }
}

function protoToLegacyModelInfo(proto: ProtoModelInfo): ModelInfo {
  const framework = protoFrameworkToLegacy(proto.framework);
  const compatibleFrameworks = framework ? [framework] : [];

  return {
    id: proto.id,
    name: proto.name,
    category: proto.category,
    format: proto.format,
    framework: proto.framework,
    downloadURL: proto.downloadUrl || undefined,
    downloadUrl: proto.downloadUrl,
    localPath: proto.localPath || undefined,
    downloadSize: proto.downloadSizeBytes || undefined,
    downloadSizeBytes: proto.downloadSizeBytes,
    memoryRequired: 0,
    compatibleFrameworks,
    preferredFramework: framework,
    contextLength: proto.contextLength || undefined,
    supportsThinking: proto.supportsThinking,
    supportsLora: proto.supportsLora,
    thinkingPattern: undefined,
    metadata: {
      description: proto.description || undefined,
      tags: [],
    },
    description: proto.description,
    source: protoSourceToLegacy(proto.source),
    createdAt: unixMsToIso(proto.createdAtUnixMs),
    updatedAt: unixMsToIso(proto.updatedAtUnixMs),
    createdAtUnixMs: proto.createdAtUnixMs,
    updatedAtUnixMs: proto.updatedAtUnixMs,
    syncPending: false,
    lastUsed: undefined,
    usageCount: 0,
    isDownloaded: Boolean(proto.localPath),
    isAvailable: true,
  } as ModelInfo;
}

function legacyToProtoModelInfo(model: ModelInfo): ProtoModelInfo {
  const registryModel = model as RegistryModelInfo;
  const framework =
    model.preferredFramework ??
    model.compatibleFrameworks?.[0] ??
    protoFrameworkToLegacy(registryModel.framework ?? InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED);
  const downloadUrl = model.downloadURL ?? registryModel.downloadUrl ?? '';
  const now = Date.now();

  return ProtoModelInfoCodec.fromPartial({
    id: model.id,
    name: model.name,
    category: normalizeCategory(model.category),
    format: normalizeFormat(model.format),
    framework: legacyFrameworkToProto(framework),
    downloadUrl,
    localPath: model.localPath ?? '',
    downloadSizeBytes:
      model.downloadSize ??
      registryModel.downloadSizeBytes ??
      0,
    contextLength: model.contextLength ?? 0,
    supportsThinking: model.supportsThinking ?? false,
    supportsLora: registryModel.supportsLora ?? false,
    description:
      registryModel.description ??
      model.metadata?.description ??
      '',
    source: legacySourceToProto(model.source, downloadUrl),
    createdAtUnixMs:
      registryModel.createdAtUnixMs ??
      isoToUnixMs(model.createdAt, now),
    updatedAtUnixMs:
      registryModel.updatedAtUnixMs ??
      isoToUnixMs(model.updatedAt, now),
    artifactType: (model as { artifactType?: ProtoModelInfo['artifactType'] }).artifactType,
  });
}

function encodeModelInfo(model: ModelInfo): ArrayBuffer {
  const bytes = ProtoModelInfoCodec.encode(legacyToProtoModelInfo(model)).finish();
  return bytesToArrayBuffer(bytes);
}

function encodeProtoModelInfo(model: ProtoModelInfo): ArrayBuffer {
  return bytesToArrayBuffer(ProtoModelInfoCodec.encode(model).finish());
}

function encodeModelQuery(query: ProtoModelQuery): ArrayBuffer {
  return bytesToArrayBuffer(ProtoModelQueryCodec.encode(query).finish());
}

/**
 * Criteria for filtering models (passed to native)
 */
export interface ModelCriteria {
  framework?: LLMFramework;
  category?: ModelCategory;
  downloadedOnly?: boolean;
  availableOnly?: boolean;
}

/**
 * Options for adding a model from URL
 */
export interface AddModelFromURLOptions {
  name: string;
  url: string;
  framework: LLMFramework;
  estimatedSize?: number;
  supportsThinking?: boolean;
}

/**
 * Model Registry - wrapper over the native commons registry.
 *
 * C++ owns registry state. RN deliberately does not keep a JS-side mirror:
 * if native commons is unavailable or returns an error, callers see an empty
 * result/null and the error is logged.
 */
class ModelRegistryImpl {
  private initialized = false;

  /**
   * Initialize the registry (calls native)
   */
  async initialize(): Promise<void> {
    if (this.initialized) return;

    if (!isNativeModuleAvailable()) {
      logger.warning('Native module not available; model registry is unavailable');
      this.initialized = true;
      return;
    }

    try {
      await this.getAllModels();
      this.initialized = true;
      logger.info('Model registry initialized via native');
    } catch (error) {
      logger.warning('Failed to initialize native model registry:', { error });
      this.initialized = true;
    }
  }

  /**
   * Get all models from native commons.
   */
  async getAllModels(): Promise<ModelInfo[]> {
    const protos = await this.getAllModelProtos();
    return protos.map(protoToLegacyModelInfo);
  }

  /**
   * Get all models as generated proto-ts ModelInfo values.
   */
  async getAllModelProtos(): Promise<ProtoModelInfo[]> {
    if (!isNativeModuleAvailable()) {
      return [];
    }

    try {
      const native = requireNativeModule();
      const buffer = await native.getAvailableModelsProto();
      return decodeModelInfoList(arrayBufferToBytes(buffer));
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      logger.warning(`Native getAvailableModelsProto failed (${msg})`);
      return [];
    }
  }

  /**
   * Query models using the generated ModelQuery proto.
   */
  async queryModelProtos(query: ProtoModelQuery): Promise<ProtoModelInfo[]> {
    if (!isNativeModuleAvailable()) {
      return [];
    }

    try {
      const native = requireNativeModule();
      const buffer = await native.queryModelsProto(encodeModelQuery(query));
      return decodeModelInfoList(arrayBufferToBytes(buffer));
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      logger.warning(`Native queryModelsProto failed (${msg})`);
      return [];
    }
  }

  /**
   * Get a model by ID from native commons.
   */
  async getModel(id: string): Promise<ModelInfo | null> {
    if (!isNativeModuleAvailable()) {
      return null;
    }

    try {
      const native = requireNativeModule();
      const buffer = await native.getModelInfoProto(id);
      const bytes = arrayBufferToBytes(buffer);
      if (bytes.byteLength === 0) {
        return null;
      }
      return protoToLegacyModelInfo(ProtoModelInfoCodec.decode(bytes));
    } catch (error) {
      logger.debug(`Failed to get model info proto from native for ${id}`);
      return null;
    }
  }

  /**
   * Filter models by criteria
   */
  async filterModels(criteria: ModelCriteria): Promise<ModelInfo[]> {
    const protos = await this.queryModelProtos(
      ProtoModelQueryCodec.fromPartial({
        framework: criteria.framework
          ? legacyFrameworkToProto(criteria.framework)
          : undefined,
        category: criteria.category,
        downloadedOnly: criteria.downloadedOnly,
        availableOnly: criteria.availableOnly,
        searchQuery: '',
      })
    );
    return protos.map(protoToLegacyModelInfo);
  }

  /** Register a model in native commons. */
  async registerModel(model: ModelInfo): Promise<void> {
    if (!isNativeModuleAvailable()) {
      throw new Error('Native module not available');
    }

    const native = requireNativeModule();
    const ok = await native.registerModelProto(encodeModelInfo(model));
    if (!ok) {
      throw new Error(`Native registerModelProto failed for ${model.id}`);
    }
  }

  /** Register a generated proto-ts ModelInfo in native commons. */
  async registerModelProto(model: ProtoModelInfo): Promise<void> {
    if (!isNativeModuleAvailable()) {
      throw new Error('Native module not available');
    }

    const native = requireNativeModule();
    const ok = await native.registerModelProto(encodeProtoModelInfo(model));
    if (!ok) {
      throw new Error(`Native registerModelProto failed for ${model.id}`);
    }
  }

  /**
   * Update model info in native commons.
   */
  async updateModel(model: ModelInfo): Promise<void> {
    if (!isNativeModuleAvailable()) {
      throw new Error('Native module not available');
    }

    const native = requireNativeModule();
    const encoded = encodeModelInfo(model);
    const updated = await native.updateModelProto(encoded);
    if (!updated) {
      const registered = await native.registerModelProto(encoded);
      if (!registered) {
        throw new Error(`Native updateModelProto failed for ${model.id}`);
      }
    }
  }

  /** Update a generated proto-ts ModelInfo in native commons. */
  async updateModelProto(model: ProtoModelInfo): Promise<void> {
    if (!isNativeModuleAvailable()) {
      throw new Error('Native module not available');
    }

    const native = requireNativeModule();
    const encoded = encodeProtoModelInfo(model);
    const updated = await native.updateModelProto(encoded);
    if (!updated) {
      const registered = await native.registerModelProto(encoded);
      if (!registered) {
        throw new Error(`Native updateModelProto failed for ${model.id}`);
      }
    }
  }

  /** Remove a model from native commons. */
  async removeModel(id: string): Promise<void> {
    if (!isNativeModuleAvailable()) return;

    try {
      const native = requireNativeModule();
      await native.removeModelProto(id);
    } catch (error) {
      logger.debug(`Native removeModelProto failed for ${id}`);
    }
  }

  /**
   * Add model from URL - registers a model with a download URL
   */
  async addModelFromURL(options: AddModelFromURLOptions): Promise<ModelInfo> {
    if (!isNativeModuleAvailable()) {
      throw new Error('Native module not available');
    }

    // Create a ModelInfo from the options and register it
    const model: Partial<ModelInfo> = {
      id: options.name.toLowerCase().replace(/\s+/g, '-'),
      name: options.name,
      downloadURL: options.url,
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      compatibleFrameworks: [options.framework] as any,
      downloadSize: options.estimatedSize ?? 0,
      supportsThinking: options.supportsThinking ?? false,
      isDownloaded: false,
      isAvailable: true,
    };

    await this.registerModel(model as ModelInfo);
    return model as ModelInfo;
  }

  /**
   * Get downloaded models
   */
  async getDownloadedModels(): Promise<ModelInfo[]> {
    const protos = await this.getDownloadedModelProtos();
    return protos.map(protoToLegacyModelInfo);
  }

  /** Get downloaded models as generated proto-ts ModelInfo values. */
  async getDownloadedModelProtos(): Promise<ProtoModelInfo[]> {
    if (!isNativeModuleAvailable()) {
      return [];
    }

    try {
      const native = requireNativeModule();
      const buffer = await native.getDownloadedModelsProto();
      return decodeModelInfoList(arrayBufferToBytes(buffer));
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      logger.warning(`Native getDownloadedModelsProto failed (${msg})`);
      return [];
    }
  }

  /**
   * Get available models
   */
  async getAvailableModels(): Promise<ModelInfo[]> {
    return this.filterModels({ availableOnly: true });
  }

  /**
   * Get models by framework
   */
  async getModelsByFramework(framework: LLMFramework): Promise<ModelInfo[]> {
    return this.filterModels({ framework });
  }

  /**
   * Get models by category
   */
  async getModelsByCategory(category: ModelCategory): Promise<ModelInfo[]> {
    return this.filterModels({ category });
  }

  /**
   * Check if model is downloaded (native, falls back to cache)
   */
  async isModelDownloaded(modelId: string): Promise<boolean> {
    if (!isNativeModuleAvailable()) {
      return false;
    }

    try {
      const native = requireNativeModule();
      return native.isModelDownloaded(modelId);
    } catch {
      return false;
    }
  }

  /**
   * Check if a model is compatible with the current device
   * Checks RAM and storage requirements against device capabilities
   * All logic runs in native C++ (runanywhere-commons)
   */
  async checkCompatibility(modelId: string): Promise<ModelCompatibilityResult> {
    const defaultResult: ModelCompatibilityResult = {
      isCompatible: false,
      canRun: false,
      canFit: false,
      requiredMemory: 0,
      availableMemory: 0,
      requiredStorage: 0,
      availableStorage: 0,
    };

    if (!isNativeModuleAvailable()) {
      logger.warning('Native module not available for compatibility check');
      return defaultResult;
    }

    try {
      const native = requireNativeModule();
      const json = await native.checkCompatibility(modelId);
      const result = JSON.parse(json);

      // Convert string booleans to actual booleans if needed
      return {
        isCompatible: result.isCompatible === true || result.isCompatible === 'true',
        canRun: result.canRun === true || result.canRun === 'true',
        canFit: result.canFit === true || result.canFit === 'true',
        requiredMemory: Number(result.requiredMemory),
        availableMemory: Number(result.availableMemory),
        requiredStorage: Number(result.requiredStorage),
        availableStorage: Number(result.availableStorage),
      };
    } catch (error) {
      logger.error('Failed to check model compatibility:', { error });
      return defaultResult;
    }
  }
  /**
   * Check if model is available
   */
  async isModelAvailable(modelId: string): Promise<boolean> {
    const model = await this.getModel(modelId);
    return model?.isAvailable ?? false;
  }

  /**
   * Check if initialized
   */
  isInitialized(): boolean {
    return this.initialized;
  }

  /**
   * Reset (for testing)
   */
  reset(): void {
    this.initialized = false;
  }
}

/**
 * Singleton instance
 */
export const ModelRegistry = new ModelRegistryImpl();
