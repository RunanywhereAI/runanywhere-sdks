/**
 * RunAnywhere+Models.ts
 *
 * Model registry and download extension for RunAnywhere SDK.
 * Matches iOS: RunAnywhere+ModelManagement.swift and RunAnywhere+ModelAssignments.swift
 */

import {
  requireNativeModule,
  isNativeModuleAvailable,
} from '../../native';
import { ModelRegistry } from '../../services/ModelRegistry';
import { FileSystem, MultiFileModelCache } from '../../services/FileSystem';
import type { ModelFileDescriptor } from '../../services/FileSystem';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import type { ModelInfo, LLMFramework, ModelCompatibilityResult } from '../../types';
import { ModelCategory, ModelArtifactType } from '../../types';

const logger = new SDKLogger('RunAnywhere.Models');

// Track active downloads for cancellation
const activeDownloads = new Map<string, number>();

// ============================================================================
// Model Registry Extension
// ============================================================================

/**
 * Get available models from the catalog
 */
export async function getAvailableModels(): Promise<ModelInfo[]> {
  return ModelRegistry.getAvailableModels();
}

/**
 * Get available frameworks
 */
export function getAvailableFrameworks(): LLMFramework[] {
  const {
    ServiceRegistry,
  } = require('../../Foundation/DependencyInjection/ServiceRegistry');

  const llmProviders = ServiceRegistry.shared.allLLMProviders();
  const frameworksSet = new Set<LLMFramework>();

  for (const provider of llmProviders) {
    if (provider.getProvidedModels) {
      const models = provider.getProvidedModels();
      for (const model of models) {
        for (const framework of model.compatibleFrameworks) {
          frameworksSet.add(framework);
        }
        if (model.preferredFramework) {
          frameworksSet.add(model.preferredFramework);
        }
      }
    }
  }

  return Array.from(frameworksSet);
}

/**
 * Get models for a specific framework
 */
export async function getModelsForFramework(
  framework: LLMFramework
): Promise<ModelInfo[]> {
  const allModels = await ModelRegistry.getAvailableModels();
  return allModels.filter(
    (model) =>
      model.compatibleFrameworks.includes(framework) ||
      model.preferredFramework === framework
  );
}

/**
 * Get info for a specific model
 */
export async function getModelInfo(modelId: string): Promise<ModelInfo | null> {
  if (!isNativeModuleAvailable()) {
    return null;
  }
  const native = requireNativeModule();
  const infoJson = await native.getModelInfo(modelId);
  try {
    const result = JSON.parse(infoJson);
    return result === 'null' ? null : result;
  } catch {
    return null;
  }
}

/**
 * Check if a model is downloaded
 */
export async function isModelDownloaded(modelId: string): Promise<boolean> {
  if (!isNativeModuleAvailable()) {
    return false;
  }
  const native = requireNativeModule();
  return native.isModelDownloaded(modelId);
}

/**
 * Get local path for a downloaded model
 */
export async function getModelPath(modelId: string): Promise<string | null> {
  if (!isNativeModuleAvailable()) {
    return null;
  }
  const native = requireNativeModule();
  return native.getModelPath(modelId);
}

/**
 * Get mmproj path for a VLM model
 * Searches for mmproj file in the same directory as the main model
 * Returns undefined if not found (backend will auto-detect)
 */
export async function getMmprojPath(modelId: string): Promise<string | undefined> {
  const modelPath = await getModelPath(modelId);
  if (!modelPath) {
    return undefined;
  }
  return FileSystem.findMmprojForModel(modelPath);
}

/**
 * Get list of downloaded models
 */
export async function getDownloadedModels(): Promise<ModelInfo[]> {
  if (!isNativeModuleAvailable()) {
    return [];
  }
  // Get all models and filter for downloaded ones
  const native = requireNativeModule();
  const modelsJson = await native.getAvailableModels();
  try {
    const allModels: ModelInfo[] = JSON.parse(modelsJson);
    return allModels.filter(m => m.isDownloaded);
  } catch {
    return [];
  }
}

// ============================================================================
// Model Assignments Extension
// ============================================================================

/**
 * Fetch model assignments for the current device from the backend.
 *
 * Note: Model assignments are automatically fetched during SDK initialization
 * (auto-fetch is enabled in the C++ layer). This method retrieves the cached
 * models from the registry.
 */
export async function fetchModelAssignments(
  forceRefresh = false,
  initState: { isCoreInitialized: boolean },
  ensureServicesReady: () => Promise<void>
): Promise<ModelInfo[]> {
  if (!initState.isCoreInitialized) {
    throw new Error('SDK not initialized. Call initialize() first.');
  }

  await ensureServicesReady();

  logger.info('Fetching model assignments...');

  // Models are auto-fetched at SDK initialization and saved to the registry
  try {
    const models = await ModelRegistry.getAllModels();
    logger.info(`Successfully fetched ${models.length} model assignments`);
    return models;
  } catch (error) {
    logger.warning('Failed to fetch model assignments:', { error });
    return [];
  }
}

/**
 * Get available models for a specific category
 */
export async function getModelsForCategory(
  category: ModelCategory,
  initState: { isCoreInitialized: boolean },
  ensureServicesReady: () => Promise<void>
): Promise<ModelInfo[]> {
  if (!initState.isCoreInitialized) {
    throw new Error('SDK not initialized. Call initialize() first.');
  }

  await ensureServicesReady();

  // Get models by category via ModelRegistry (delegates to native)
  const allModels = await ModelRegistry.getModelsByCategory(category);
  return allModels;
}

/**
 * Clear cached model assignments.
 * Resets local state; next fetch will get fresh data from the registry.
 */
export async function clearModelAssignmentsCache(
  initState: { isCoreInitialized: boolean }
): Promise<void> {
  if (!initState.isCoreInitialized) {
    return;
  }

  ModelRegistry.reset();
}

/**
 * Register a model from a download URL.
 *
 * Matches iOS: RunAnywhere.registerModel(id:name:url:framework:modality:artifactType:memoryRequirement:supportsThinking:)
 */
export async function registerModel(options: {
  id?: string;
  name: string;
  url: string;
  framework: LLMFramework;
  modality?: ModelCategory;
  artifactType?: ModelArtifactType;
  memoryRequirement?: number;
  supportsThinking?: boolean;
}): Promise<ModelInfo> {
  const { ModelFormat, ConfigurationSource } = await import('../../types/enums');
  const now = new Date().toISOString();
  const modelId = options.id ?? generateModelId(options.url);

  let isDownloaded = false;
  let localPath: string | undefined;

  if (FileSystem.isAvailable()) {
    try {
      const frameworkDir = inferFrameworkDir(options.framework);
      const exists = await FileSystem.modelExists(modelId, frameworkDir);
      if (exists) {
        localPath = await FileSystem.getModelPath(modelId, frameworkDir);
        isDownloaded = true;
        logger.info(`Model ${modelId} found on disk: ${localPath}`);
      }
    } catch (error) {
      logger.debug(`Could not check for existing model ${modelId}: ${error}`);
    }
  }

  const modelInfo: ModelInfo = {
    id: modelId,
    name: options.name,
    category: options.modality ?? ModelCategory.Language,
    format: inferFormat(options.url, options.framework),
    downloadURL: options.url,
    localPath,
    downloadSize: undefined,
    memoryRequired: options.memoryRequirement,
    compatibleFrameworks: [options.framework],
    preferredFramework: options.framework,
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

  await ModelRegistry.registerModel(modelInfo);

  logger.info(`Registered model: ${modelId} (${options.name})${isDownloaded ? ' [already downloaded]' : ''}`);

  return modelInfo;
}

/**
 * Register a multi-file model (e.g., ONNX embedding model with vocab.txt, or VLM with mmproj).
 * All files are downloaded into the same directory so companion files are co-located.
 *
 * Matches iOS: RunAnywhere.registerMultiFileModel(id:name:files:framework:modality:memoryRequirement:)
 */
export async function registerMultiFileModel(options: {
  id: string;
  name: string;
  files: ModelFileDescriptor[];
  framework: LLMFramework;
  modality?: ModelCategory;
  memoryRequirement?: number;
}): Promise<ModelInfo> {
  const { ModelFormat, ConfigurationSource } = await import('../../types/enums');
  const now = new Date().toISOString();

  MultiFileModelCache.set(options.id, options.files);

  let isDownloaded = false;
  let localPath: string | undefined;

  if (FileSystem.isAvailable()) {
    try {
      const frameworkDir = inferFrameworkDir(options.framework);
      const exists = await FileSystem.modelExists(options.id, frameworkDir);
      if (exists) {
        localPath = FileSystem.getModelFolder(options.id, frameworkDir);
        isDownloaded = true;
        logger.info(`Multi-file model ${options.id} found on disk: ${localPath}`);
      }
    } catch (error) {
      logger.debug(`Could not check for existing model ${options.id}: ${error}`);
    }
  }

  const modelInfo: ModelInfo = {
    id: options.id,
    name: options.name,
    category: options.modality ?? ModelCategory.Language,
    format: ModelFormat.ONNX,
    downloadURL: options.files[0]?.url,
    localPath,
    downloadSize: undefined,
    memoryRequired: options.memoryRequirement,
    compatibleFrameworks: [options.framework],
    preferredFramework: options.framework,
    supportsThinking: false,
    metadata: {
      tags: [],
      description: `Multi-file model (${options.files.length} files)`,
    },
    source: ConfigurationSource.Local,
    createdAt: now,
    updatedAt: now,
    syncPending: false,
    usageCount: 0,
    isDownloaded,
    isAvailable: true,
  };

  await ModelRegistry.registerModel(modelInfo);

  logger.info(
    `Registered multi-file model: ${options.id} (${options.name}, ${options.files.length} files)` +
    `${isDownloaded ? ' [already downloaded]' : ''}`
  );

  return modelInfo;
}

function inferFrameworkDir(framework: LLMFramework): string {
  switch (framework) {
    case 'ONNX': return 'ONNX';
    case 'LlamaCpp': return 'LlamaCpp';
    default: return framework;
  }
}

function inferFormat(url: string, framework?: LLMFramework): import('../../types/enums').ModelFormat {
  const { ModelFormat } = require('../../types/enums');
  const lower = url.toLowerCase();
  if (lower.includes('.gguf')) return ModelFormat.GGUF;
  if (lower.includes('.onnx')) return ModelFormat.ONNX;
  if (lower.includes('.zip')) return ModelFormat.Zip;
  // Archives (.tar.gz, .tar.bz2) are packaging, not format.
  // Derive format from framework: ONNX archives contain ONNX models.
  if (lower.includes('.tar.gz') || lower.includes('.tar.bz2')) {
    if (framework === 'ONNX') return ModelFormat.ONNX;
    return ModelFormat.GGUF;
  }
  if (framework === 'ONNX') return ModelFormat.ONNX;
  return ModelFormat.GGUF;
}

function generateModelId(url: string): string {
  const urlObj = new URL(url);
  const pathname = urlObj.pathname;
  const filename = pathname.split('/').pop() ?? 'model';
  return filename.replace(/\.(gguf|bin|safetensors|tar\.gz|zip)$/i, '');
}

// ============================================================================
// Model Download Extension
// ============================================================================

/**
 * Download progress information
 */
export interface DownloadProgress {
  modelId: string;
  bytesDownloaded: number;
  totalBytes: number;
  progress: number;
}

/**
 * Download a model
 * Uses react-native-fs for cross-platform downloads with progress tracking
 */
export async function downloadModel(
  modelId: string,
  onProgress?: (progress: DownloadProgress) => void
): Promise<string> {
  const modelInfo = await ModelRegistry.getModel(modelId);
  if (!modelInfo) {
    throw new Error(`Model not found: ${modelId}`);
  }

  if (!modelInfo.downloadURL) {
    throw new Error(`Model has no download URL: ${modelId}`);
  }

  if (!FileSystem.isAvailable()) {
    throw new Error('react-native-fs not installed - cannot download models');
  }

  // Use preferredFramework from modelInfo to ensure correct directory structure
  const framework = modelInfo.preferredFramework;

  activeDownloads.set(modelId, 1);
  let lastLoggedProgress = -1;

  const progressHandler = (progress: { bytesWritten: number; contentLength: number; progress: number }) => {
    const progressPct = Math.round(progress.progress * 100);
    if (progressPct - lastLoggedProgress >= 10) {
      logger.debug(`Download progress: ${progressPct}%`);
      lastLoggedProgress = progressPct;
    }
    if (onProgress) {
      onProgress({
        modelId,
        bytesDownloaded: progress.bytesWritten,
        totalBytes: progress.contentLength || modelInfo.downloadSize || 0,
        progress: progress.progress,
      });
    }
  };

  try {
    // Multi-file model: download all files into the same directory
    const multiFileDescriptors = MultiFileModelCache.get(modelId);
    if (multiFileDescriptors && multiFileDescriptors.length > 0) {
      logger.info('Starting multi-file download:', { modelId, fileCount: multiFileDescriptors.length });

      const destFolder = await FileSystem.downloadMultiFileModel(
        modelId,
        multiFileDescriptors,
        progressHandler,
        framework
      );

      logger.info('Multi-file download completed:', { modelId, destFolder });

      const updatedModel: ModelInfo = {
        ...modelInfo,
        localPath: destFolder,
        isDownloaded: true,
      };
      await ModelRegistry.registerModel(updatedModel);

      return destFolder;
    }

    // Single-file model: existing download logic
    let extension = '';
    if (modelInfo.downloadURL.includes('.gguf')) {
      extension = '.gguf';
    } else if (modelInfo.downloadURL.includes('.onnx')) {
      extension = '.onnx';
    } else if (modelInfo.downloadURL.includes('.tar.bz2')) {
      extension = '.tar.bz2';
    } else if (modelInfo.downloadURL.includes('.tar.gz')) {
      extension = '.tar.gz';
    } else if (modelInfo.downloadURL.includes('.zip')) {
      extension = '.zip';
    }
    const fileName = `${modelId}${extension}`;

    logger.info('Starting download (react-native-fs):', {
      modelId,
      url: modelInfo.downloadURL,
    });

    const destPath = await FileSystem.downloadModel(
      fileName,
      modelInfo.downloadURL,
      progressHandler,
      framework
    );

    logger.info('Download completed:', {
      modelId,
      destPath,
    });

    const updatedModel: ModelInfo = {
      ...modelInfo,
      localPath: destPath,
      isDownloaded: true,
    };
    await ModelRegistry.registerModel(updatedModel);

    return destPath;
  } finally {
    activeDownloads.delete(modelId);
  }
}

/**
 * Cancel an ongoing download
 */
export async function cancelDownload(modelId: string): Promise<boolean> {
  if (activeDownloads.has(modelId)) {
    activeDownloads.delete(modelId);
    logger.info(`Marked download as cancelled: ${modelId}`);
    return true;
  }
  return false;
}

/**
 * Delete a downloaded model
 */
export async function deleteModel(modelId: string): Promise<boolean> {
  try {
    const modelInfo = await ModelRegistry.getModel(modelId);
    const extension = modelInfo?.downloadURL?.includes('.gguf')
      ? '.gguf'
      : '';
    const fileName = `${modelId}${extension}`;

    // Delete using FileSystem service
    const deleted = await FileSystem.deleteModel(fileName);
    if (deleted) {
      logger.info(`Deleted model: ${modelId}`);
    }

    // Also try plain model ID in case of different naming
    await FileSystem.deleteModel(modelId);

    // Update model in registry
    if (modelInfo) {
      const updatedModel: ModelInfo = {
        ...modelInfo,
        localPath: undefined,
        isDownloaded: false,
      };
      await ModelRegistry.registerModel(updatedModel);
    }

    return true;
  } catch (error) {
    logger.error('Delete model error:', { error });
    return false;
  }
}

/**
 * Check if a model is compatible with the current device
 * Returns RAM and storage compatibility info
 */
export async function checkCompatibility(modelId: string): Promise<ModelCompatibilityResult> {
  return ModelRegistry.checkCompatibility(modelId);
}
