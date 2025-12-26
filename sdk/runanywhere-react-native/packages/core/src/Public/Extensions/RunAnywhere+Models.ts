/**
 * RunAnywhere+Models.ts
 *
 * Model registry and download extension for RunAnywhere SDK.
 * Matches iOS: RunAnywhere+ModelManagement.swift and RunAnywhere+ModelAssignments.swift
 */

import {
  requireNativeModule,
  isNativeModuleAvailable,
  requireFileSystemModule,
} from '@runanywhere/native';
import { ModelRegistry } from '../../services/ModelRegistry';
import { ServiceContainer } from '../../Foundation/DependencyInjection/ServiceContainer';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import type { ModelInfo, LLMFramework } from '../../types';
import { ModelCategory } from '../../types';

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
  const { JSDownloadService } = require('../../services/JSDownloadService');
  return JSDownloadService.isModelDownloaded(modelId);
}

/**
 * Get local path for a downloaded model
 */
export async function getModelPath(modelId: string): Promise<string | null> {
  const { JSDownloadService } = require('../../services/JSDownloadService');
  return JSDownloadService.getModelPath(modelId);
}

/**
 * Get list of downloaded models
 */
export async function getDownloadedModels(): Promise<ModelInfo[]> {
  if (!isNativeModuleAvailable()) {
    return [];
  }
  const native = requireNativeModule();
  const modelsJson = await native.getDownloadedModels();
  try {
    return JSON.parse(modelsJson);
  } catch {
    return [];
  }
}

// ============================================================================
// Model Assignments Extension
// ============================================================================

/**
 * Fetch model assignments for the current device from the backend
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

  const modelAssignmentService =
    ServiceContainer.shared.modelAssignmentService;
  if (!modelAssignmentService) {
    throw new Error('ModelAssignmentService not available');
  }

  const models =
    await modelAssignmentService.fetchModelAssignments(forceRefresh);
  logger.info(`Successfully fetched ${models.length} model assignments`);
  return models;
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

  const modelAssignmentService =
    ServiceContainer.shared.modelAssignmentService;
  if (!modelAssignmentService) {
    const allModels = await ModelRegistry.getAvailableModels();
    return allModels.filter((m) => m.category === category);
  }

  return modelAssignmentService.getModelsForCategory(category);
}

/**
 * Clear cached model assignments
 */
export async function clearModelAssignmentsCache(
  initState: { isCoreInitialized: boolean }
): Promise<void> {
  if (!initState.isCoreInitialized) {
    return;
  }

  const modelAssignmentService =
    ServiceContainer.shared.modelAssignmentService;
  if (modelAssignmentService) {
    modelAssignmentService.clearCache();
  }
}

/**
 * Register a model from a download URL
 */
export async function registerModel(options: {
  id?: string;
  name: string;
  url: string;
  framework: LLMFramework;
  category?: ModelCategory;
  memoryRequirement?: number;
  supportsThinking?: boolean;
}): Promise<ModelInfo> {
  const { ModelFormat, ConfigurationSource } = await import('../../types/enums');
  const now = new Date().toISOString();

  const modelInfo: ModelInfo = {
    id: options.id ?? generateModelId(options.url),
    name: options.name,
    category: options.category ?? ModelCategory.Language,
    format: options.url.includes('.gguf')
      ? ModelFormat.GGUF
      : ModelFormat.GGUF,
    downloadURL: options.url,
    localPath: undefined,
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
    isDownloaded: false,
    isAvailable: true,
  };

  await ModelRegistry.registerModel(modelInfo);
  return modelInfo;
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

  const fs = requireFileSystemModule();

  let extension = '';
  if (modelInfo.downloadURL.includes('.gguf')) {
    extension = '.gguf';
  } else if (modelInfo.downloadURL.includes('.tar.bz2')) {
    extension = '.tar.bz2';
  } else if (modelInfo.downloadURL.includes('.tar.gz')) {
    extension = '.tar.gz';
  } else if (modelInfo.downloadURL.includes('.zip')) {
    extension = '.zip';
  }
  const fileName = `${modelId}${extension}`;

  logger.info(' Starting native download (OkHttp/URLSession):', {
    modelId,
    url: modelInfo.downloadURL,
  });

  activeDownloads.set(modelId, 1);
  let lastLoggedProgress = -1;

  try {
    await fs.downloadModel(
      fileName,
      modelInfo.downloadURL,
      (progress: number) => {
        const progressPct = Math.round(progress * 100);
        if (progressPct - lastLoggedProgress >= 10) {
          logger.debug(`Download progress: ${progressPct}%`);
          lastLoggedProgress = progressPct;
        }

        if (onProgress) {
          onProgress({
            modelId,
            bytesDownloaded: Math.round(
              progress * (modelInfo.downloadSize || 0)
            ),
            totalBytes: modelInfo.downloadSize || 0,
            progress,
          });
        }
      }
    );

    const destPath = await fs.getModelPath(fileName);

    logger.info(' Download completed:', {
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
    const fs = requireFileSystemModule();

    const modelInfo = await ModelRegistry.getModel(modelId);
    const extension = modelInfo?.downloadURL?.includes('.gguf')
      ? '.gguf'
      : '';
    const fileName = `${modelId}${extension}`;

    const exists = await fs.modelExists(fileName);
    if (exists) {
      await fs.deleteModel(fileName);
      logger.info(`Deleted model: ${modelId}`);
    }

    const existsPlain = await fs.modelExists(modelId);
    if (existsPlain) {
      await fs.deleteModel(modelId);
    }

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
